using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Repato.QaLaunchAgent;

public sealed record CpvPreparationRequest(int SchemaVersion, string Operation, string RequestId, string TaskId,
    string WorkflowId, string AttemptId, string RunId, DateTimeOffset ExpiresUtc, int TimeoutSeconds,
    QaCandidateEvidence CandidateEvidence);
public sealed record CpvPreparationQuery(int SchemaVersion, string Operation, string RequestId);
public sealed record CpvPreparationReconciliation(int SchemaVersion, string Operation, string RequestId, string TaskId,
    string WorkflowId, string AttemptId, string RunId);
public sealed record CpvPreparationCompletedRecovery(int SchemaVersion, string Operation, string RequestId, string TaskId,
    string WorkflowId, string AttemptId, string RunId, string RecoveryApprovalId, long ExpectedTaskRevision,
    string ApprovalBindingHash, DateTimeOffset AuthorizationExpiresUtc, string OriginalReceiptSha256,
    string ActiveMarkerSha256, string FailureEvidenceSha256, string RequestSha256, string ResultSha256, string ModelSha256);
public sealed record CpvPreparationCompletedRecoveryStatus(int SchemaVersion, string Operation, string RequestId);
public sealed record CpvPreparationCompletedRecoveryReconcile(int SchemaVersion, string Operation, string RequestId, string TaskId,
    string WorkflowId, string AttemptId, string RunId, string RecoveryApprovalId, string ApprovalBindingHash,
    string OriginalReceiptSha256, string ActiveMarkerSha256, string FailureEvidenceSha256, string RequestSha256);
public sealed record CpvPreparationRecoveryCommit(int SchemaVersion, CpvPreparationReceipt Receipt, string RecoveryApprovalId,
    long ExpectedTaskRevision, string ApprovalBindingHash, DateTimeOffset AuthorizationExpiresUtc,
    string OriginalReceiptSha256, string ActiveMarkerSha256, string FailureEvidenceSha256, string RequestSha256, string ResultSha256, string ModelSha256, DateTimeOffset VerifiedUtc,
    string? RecoveredProvenancePath = null, string? RecoveredProvenanceSha256 = null);
public sealed record CpvPreparationReceipt(int SchemaVersion, string Operation, string RequestId, string TaskId,
    string WorkflowId, string AttemptId, string RunId, string Status, string User, string Sid, int SessionId,
    string CandidateSha256, string ManifestSha256, string ModelPath, string ModelSha256, string RequestPath,
    string RequestSha256, string ResultPath, string ResultSha256, bool CleanupVerified, string RollbackStatus,
    string? FailureCode, DateTimeOffset ExpiresUtc);
public sealed record CpvPreparationOutcome(string ModelSha256, string ResultSha256, bool CleanupVerified, string RollbackStatus);
public interface ICpvPreparationBoundary : ICpvPreparationReconciliationBoundary
{
    void Validate(CpvPreparationRequest request);
    Task<CpvPreparationOutcome> Execute(CpvPreparationRequest request, string directory);
}
public interface ICpvPreparationReconciliationBoundary
{
    IDisposable ValidateReconciliation(CpvPreparationRequest request, CpvPreparationReceipt receipt, string expectedModelSha256);
}

/// <summary>One fixed operation; no caller-selected executable, model, environment, or command.</summary>
public sealed class CpvPreparationService(QaAgentOptions options, IIdentitySessionProvider identity,
    IReplayLedger ledger, ICpvPreparationBoundary boundary)
{
    public const string Operation = "prepare-cpv-fixture";
    public const string StatusOperation = "cpv-preparation-status";
    public const string ReconcileOperation = "cpv-preparation-reconcile-failed";
    public const string RecoverCompletedOperation = "cpv-preparation-recover-completed";
    public const string RecoverCompletedStatusOperation = "cpv-preparation-recover-completed-status";
    public const string RecoverCompletedReconcileOperation = "cpv-preparation-recover-completed-reconcile";
    public const string CapabilitiesOperation = "cpv-preparation-capabilities";
    public const string RunnerOperation = "prepare-disposable-create-plan-views-fixture";
    public const string FixtureSha256 = "92CC9E434E2C4DD6720A2AA564E19F4E1A30EB3DA63CEA73CF737F875B9EDD45";
    public static readonly JsonSerializerOptions StrictJson = new(QaLaunchPolicy.JsonOptions) {
        PropertyNameCaseInsensitive = true, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };
    private readonly object gate = new();
    private readonly HashSet<string> running = new(StringComparer.Ordinal);
    private string Store => Path.Combine(options.LogRoot, "CpvPreparation");
    public bool HasUnresolvedExecution => File.Exists(Path.Combine(Store, "active.json"));
    private bool IdentityValid => identity.User.Equals(options.ExpectedUser, StringComparison.OrdinalIgnoreCase) &&
        identity.Sid == options.ExpectedUserSid && identity.Interactive && identity.SessionId > 0;
    public static bool Id(string? id) => Guid.TryParseExact(id, "N", out var value) && value != Guid.Empty;
    public object Capabilities() => new { schemaVersion = 1, operation = CapabilitiesOperation, supported = IdentityValid,
        preparationOperation = Operation, reconciliationOperation = ReconcileOperation, recoveryOperation = RecoverCompletedOperation,
        recoveryStatusOperation = RecoverCompletedStatusOperation,
        recoveryReconcileOperation = RecoverCompletedReconcileOperation,
        runtimeVersion = FileVersionInfo.GetVersionInfo(Process.GetCurrentProcess().MainModule!.FileName!).ProductVersion,
        user = identity.User, sid = identity.Sid, sessionId = identity.SessionId };
    public object Handle(string json, DateTimeOffset now)
    {
        if (!IdentityValid) throw new InvalidDataException("wrong-agent-identity");
        using var doc = JsonDocument.Parse(json);
        RejectDuplicateProperties(doc.RootElement);
        string operation = doc.RootElement.GetProperty("operation").GetString() ?? "";
        if (operation == StatusOperation)
        {
            var query = JsonSerializer.Deserialize<CpvPreparationQuery>(json, StrictJson)!;
            if (query.SchemaVersion != 1 || !Id(query.RequestId)) throw new InvalidDataException("query-invalid");
            lock (gate) return Read(query.RequestId);
        }
        if (operation == ReconcileOperation)
        {
            var q = JsonSerializer.Deserialize<CpvPreparationReconciliation>(json, StrictJson)!;
            if (q.SchemaVersion != 1 || q.Operation != ReconcileOperation || !Id(q.RequestId) || !Id(q.AttemptId) ||
                !Id(q.RunId) || !Id(q.WorkflowId) || !q.TaskId.StartsWith("task-", StringComparison.Ordinal) || !Id(q.TaskId[5..]))
                throw new InvalidDataException("reconciliation-request-invalid");
            lock (gate) return Reconcile(q);
        }
        if (operation == RecoverCompletedOperation)
        {
            var q = JsonSerializer.Deserialize<CpvPreparationCompletedRecovery>(json, StrictJson)!;
            if (q.SchemaVersion != 1 || q.Operation != RecoverCompletedOperation || !Id(q.RequestId) || !Id(q.AttemptId) ||
                !Id(q.RunId) || !Id(q.WorkflowId) || !q.TaskId.StartsWith("task-", StringComparison.Ordinal) || !Id(q.TaskId[5..]) ||
                !Id(q.RecoveryApprovalId) || q.ExpectedTaskRevision < 1 || q.AuthorizationExpiresUtc <= now ||
                q.AuthorizationExpiresUtc > now.AddHours(4) || !Sha256(q.ApprovalBindingHash) || !Sha256(q.OriginalReceiptSha256) || !Sha256(q.ActiveMarkerSha256) || !Sha256(q.FailureEvidenceSha256) ||
                !Sha256(q.RequestSha256) || !Sha256(q.ResultSha256) || !Sha256(q.ModelSha256))
                throw new InvalidDataException("completed-recovery-request-invalid-or-expired");
            lock (gate) return RecoverCompleted(q, now);
        }
        if (operation == RecoverCompletedStatusOperation)
        {
            var q = JsonSerializer.Deserialize<CpvPreparationCompletedRecoveryStatus>(json, StrictJson)!;
            if (q.SchemaVersion != 1 || q.Operation != RecoverCompletedStatusOperation || !Id(q.RequestId))
                throw new InvalidDataException("completed-recovery-status-query-invalid");
            lock (gate)
            {
                string path = Path.Combine(Store, q.RequestId + ".recovered.json");
                return File.Exists(path) ? ReadRecoveryCommit(path) :
                    new { schemaVersion = 1, operation = RecoverCompletedStatusOperation, requestId = q.RequestId, status = "NotFound" };
            }
        }
        if (operation == RecoverCompletedReconcileOperation)
        {
            var q = JsonSerializer.Deserialize<CpvPreparationCompletedRecoveryReconcile>(json, StrictJson)!;
            if (q.SchemaVersion != 1 || q.Operation != RecoverCompletedReconcileOperation || !Id(q.RequestId) || !Id(q.AttemptId) ||
                !Id(q.RunId) || !Id(q.WorkflowId) || !q.TaskId.StartsWith("task-", StringComparison.Ordinal) || !Id(q.TaskId[5..]) ||
                !Id(q.RecoveryApprovalId) || !Sha256(q.ApprovalBindingHash) || !Sha256(q.OriginalReceiptSha256) ||
                !Sha256(q.ActiveMarkerSha256) || !Sha256(q.FailureEvidenceSha256) || !Sha256(q.RequestSha256))
                throw new InvalidDataException("completed-recovery-reconcile-request-invalid");
            lock (gate) return ReconcileCompletedRecovery(q, now);
        }
        var r = JsonSerializer.Deserialize<CpvPreparationRequest>(json, StrictJson)!;
        if (r.SchemaVersion != 1 || r.Operation != Operation || !Id(r.RequestId) || !Id(r.AttemptId) || !Id(r.RunId) ||
            !Id(r.WorkflowId) || !r.TaskId.StartsWith("task-", StringComparison.Ordinal) || !Id(r.TaskId[5..]) ||
            r.ExpiresUtc <= now || r.ExpiresUtc > now.AddHours(4) || r.TimeoutSeconds < 60 || r.TimeoutSeconds > 7200 ||
            r.ExpiresUtc < now.AddSeconds(r.TimeoutSeconds) || r.CandidateEvidence is null ||
            r.CandidateEvidence.TaskId != r.TaskId || r.CandidateEvidence.WorkflowId != r.WorkflowId ||
            r.CandidateEvidence.QaWorkflowId != "create-plan-views-v1" || r.CandidateEvidence.TestId != "create-plan-views-v1")
            throw new InvalidDataException("preparation-request-invalid-or-expired");
        lock (gate)
        {
            Directory.CreateDirectory(Store);
            if (File.Exists(Path.Combine(Store, r.RequestId + ".json"))) return Read(r.RequestId) is CpvPreparationReceipt old &&
                old.TaskId == r.TaskId && old.WorkflowId == r.WorkflowId && old.AttemptId == r.AttemptId && old.RunId == r.RunId &&
                File.ReadAllText(Path.Combine(Store, r.RequestId + ".request.json")) == json ? old : throw new InvalidDataException("request-id-collision");
            // Durable marker intentionally survives agent termination. Never guess whether a child launched.
            string active = Path.Combine(Store, "active.json");
            if (File.Exists(active)) throw new InvalidOperationException("preparation-busy-or-interrupted-reconcile-required");
            boundary.Validate(r);
            if (!ledger.TryReserve("cpv-preparation-attempt-" + r.AttemptId, now) ||
                !ledger.TryReserve("cpv-preparation-run-" + r.RunId, now) || !ledger.TryReserve(r.RequestId, now))
                throw new InvalidOperationException("preparation-replayed");
            foreach (string key in new[] { "attempt-" + r.AttemptId, "run-" + r.RunId })
                using (var reserved = File.Open(Path.Combine(Store, key + ".reserved"), FileMode.CreateNew, FileAccess.Write, FileShare.None)) { reserved.Flush(true); }
            using (var file = new FileStream(active, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { JsonSerializer.Serialize(file, r, StrictJson); file.Flush(true); }
            WriteDurable(Path.Combine(Store, r.RequestId + ".request.json"), json);
            string directory = Path.Combine(options.RuntimeRoot, "cpv-preparation-" + r.RunId);
            if (Directory.Exists(directory)) throw new InvalidDataException("preparation-runtime-already-exists");
            var pending = new CpvPreparationReceipt(1, Operation, r.RequestId, r.TaskId, r.WorkflowId, r.AttemptId, r.RunId,
                "Executing", identity.User, identity.Sid, identity.SessionId, r.CandidateEvidence.CandidateDllSha256,
                r.CandidateEvidence.RunnerManifestSha256, Path.Combine(directory, "model.rvt"), "",
                Path.Combine(directory, "tara-" + r.AttemptId + ".request.json"), "", "", "", false, "Unknown", null, r.ExpiresUtc);
            Write(pending);
            running.Add(r.RequestId);
            _ = Task.Run(async () => {
                CpvPreparationReceipt terminal;
                try {
                    var outcome = await boundary.Execute(r, directory);
                    terminal = pending with { Status = outcome.CleanupVerified ? "Passed" : "Failed", ModelSha256 = outcome.ModelSha256,
                        RequestSha256 = Hash(pending.RequestPath), ResultPath = pending.RequestPath + ".preparation.json",
                        ResultSha256 = outcome.ResultSha256, CleanupVerified = outcome.CleanupVerified,
                        RollbackStatus = outcome.RollbackStatus, FailureCode = outcome.CleanupVerified ? null : "cleanup-failed" };
                } catch (Exception ex) {
                    File.WriteAllText(Path.Combine(Store, r.RequestId + ".failure.txt"), ex.ToString());
                    // A failed/ambiguous preparation never authorizes final QA. Preserve its marker and model.
                    terminal = pending with { Status = "OutcomeUnknown", FailureCode = ex is TimeoutException ? "preparation-timeout" : "preparation-failed-reconcile-required" };
                }
                lock (gate) { Write(terminal); running.Remove(r.RequestId); if (terminal.Status == "Passed") File.Delete(active); }
            });
            return pending;
        }
    }
    private object Reconcile(CpvPreparationReconciliation q)
    {
        Directory.CreateDirectory(Store);
        string activePath = Path.Combine(Store, "active.json"), receiptPath = Path.Combine(Store, q.RequestId + ".json");
        if (!File.Exists(receiptPath)) throw new InvalidDataException("reconciliation-receipt-missing");
        var receipt = JsonSerializer.Deserialize<CpvPreparationReceipt>(File.ReadAllText(receiptPath), StrictJson)
            ?? throw new InvalidDataException("reconciliation-receipt-invalid");
        Match(q, receipt);
        if (receipt.Status == "FailedReconciled")
        {
            if (receipt.FailureCode != "preparation-exited-without-result") throw new InvalidDataException("reconciliation-terminal-evidence-mismatch");
            if (File.Exists(activePath))
            {
                var active = ReadActive(activePath); Match(q, active);
                string terminalRequestPath = Path.Combine(Store, q.RequestId + ".request.json");
                if (!File.Exists(terminalRequestPath) || JsonSerializer.Serialize(active, StrictJson) !=
                    JsonSerializer.Serialize(JsonSerializer.Deserialize<CpvPreparationRequest>(File.ReadAllText(terminalRequestPath), StrictJson), StrictJson))
                    throw new InvalidDataException("reconciliation-active-request-mismatch");
            }
            File.Delete(activePath);
            return receipt;
        }
        if (receipt.Status != "OutcomeUnknown" || receipt.FailureCode != "preparation-failed-reconcile-required" ||
            receipt.CleanupVerified || receipt.ModelSha256 != "" || receipt.ResultPath != "" || receipt.ResultSha256 != "" ||
            receipt.RollbackStatus != "Unknown" || !File.Exists(activePath))
            throw new InvalidDataException("reconciliation-state-invalid");
        var request = ReadActive(activePath);
        Match(q, request);
        string requestPath = Path.Combine(Store, q.RequestId + ".request.json");
        string failurePath = Path.Combine(Store, q.RequestId + ".failure.txt");
        if (!File.Exists(requestPath) || !File.Exists(failurePath) ||
            !File.ReadAllText(failurePath).Contains("InvalidDataException: preparation-exited-without-result", StringComparison.Ordinal))
            throw new InvalidDataException("reconciliation-failure-evidence-invalid");
        var persisted = JsonSerializer.Deserialize<CpvPreparationRequest>(File.ReadAllText(requestPath), StrictJson)
            ?? throw new InvalidDataException("reconciliation-request-evidence-invalid");
        Match(q, persisted);
        if (JsonSerializer.Serialize(request, StrictJson) != JsonSerializer.Serialize(persisted, StrictJson))
            throw new InvalidDataException("reconciliation-active-request-mismatch");
        if (persisted.CandidateEvidence is null || receipt.CandidateSha256 != persisted.CandidateEvidence.CandidateDllSha256 ||
            receipt.ManifestSha256 != persisted.CandidateEvidence.RunnerManifestSha256 || receipt.ExpiresUtc != persisted.ExpiresUtc ||
            !Path.GetFullPath(receipt.ModelPath).Equals(Path.GetFullPath(Path.Combine(options.RuntimeRoot, "cpv-preparation-" + q.RunId, "model.rvt")), StringComparison.OrdinalIgnoreCase) ||
            !Path.GetFullPath(receipt.RequestPath).Equals(Path.GetFullPath(Path.Combine(options.RuntimeRoot, "cpv-preparation-" + q.RunId, "tara-" + q.AttemptId + ".request.json")), StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("reconciliation-path-binding-invalid");
        string runnerPath = receipt.RequestPath, resultPath = runnerPath + ".preparation.json", modelPath = receipt.ModelPath;
        if (!File.Exists(runnerPath) || File.Exists(resultPath) || File.Exists(modelPath + ".slog") || File.Exists(modelPath + ".lck"))
            throw new InvalidDataException("reconciliation-result-or-lock-evidence-present");
        var runner = JsonDocument.Parse(File.ReadAllText(runnerPath));
        using (runner)
        {
            var root = runner.RootElement;
            RejectDuplicateProperties(root);
            string[] expectedProperties = ["schemaVersion", "operation", "requestId", "taskId", "workflowId", "attemptId", "runId", "requestPath", "modelPath", "modelSha256", "selectedManifestPath", "selectedManifestSha256", "outputPath", "expiresUtc"];
            if (root.ValueKind != JsonValueKind.Object || root.EnumerateObject().Count() != expectedProperties.Length ||
                expectedProperties.Any(name => !root.TryGetProperty(name, out _)))
                throw new InvalidDataException("reconciliation-runner-request-schema-mismatch");
            if (root.GetProperty("operation").GetString() != RunnerOperation || root.GetProperty("requestId").GetString() != q.AttemptId ||
                root.GetProperty("taskId").GetString() != q.TaskId || root.GetProperty("workflowId").GetString() != q.WorkflowId ||
                root.GetProperty("attemptId").GetString() != q.AttemptId || root.GetProperty("runId").GetString() != q.RunId ||
                root.GetProperty("schemaVersion").GetInt32() != 1 ||
                !Path.GetFullPath(root.GetProperty("requestPath").GetString()!).Equals(Path.GetFullPath(runnerPath), StringComparison.OrdinalIgnoreCase) ||
                !Path.GetFullPath(root.GetProperty("modelPath").GetString()!).Equals(Path.GetFullPath(modelPath), StringComparison.OrdinalIgnoreCase) ||
                root.GetProperty("modelSha256").GetString() != FixtureSha256 ||
                root.GetProperty("selectedManifestPath").GetString() != QaLaunchPolicy.ExpectedRunnerManifestPath ||
                root.GetProperty("selectedManifestSha256").GetString() != persisted.CandidateEvidence.RunnerManifestSha256 ||
                !Path.GetFullPath(root.GetProperty("outputPath").GetString()!).Equals(Path.GetFullPath(resultPath), StringComparison.OrdinalIgnoreCase) ||
                DateTimeOffset.Parse(root.GetProperty("expiresUtc").GetString()!) != persisted.ExpiresUtc)
                throw new InvalidDataException("reconciliation-runner-request-mismatch");
        }
        if (!Hash(modelPath).Equals(FixtureSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("reconciliation-model-hash-mismatch");
        using var evidenceLease = boundary.ValidateReconciliation(persisted, receipt, CpvPreparationService.FixtureSha256);
        var terminal = receipt with { Status = "FailedReconciled", RequestSha256 = Hash(runnerPath), FailureCode = "preparation-exited-without-result", CleanupVerified = false, RollbackStatus = "NotRequired-NoPreparationResult" };
        WriteReconciled(terminal); // Receipt is durable before the sole matching marker is removed.
        File.Delete(activePath);
        return terminal;
    }
    private object RecoverCompleted(CpvPreparationCompletedRecovery q, DateTimeOffset now)
    {
        Directory.CreateDirectory(Store);
        string activePath = Path.Combine(Store, "active.json"), originalPath = Path.Combine(Store, q.RequestId + ".json");
        string recoveryPath = Path.Combine(Store, q.RequestId + ".recovered.json");
        string failurePath = Path.Combine(Store, q.RequestId + ".failure.txt");
        if (running.Contains(q.RequestId)) throw new InvalidOperationException("completed-recovery-execution-still-running");
        if (!File.Exists(originalPath)) throw new InvalidDataException("completed-recovery-original-receipt-missing");
        string originalJson = File.ReadAllText(originalPath);
        if (!Hash(originalPath).Equals(q.OriginalReceiptSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("completed-recovery-original-receipt-changed");
        var original = JsonSerializer.Deserialize<CpvPreparationReceipt>(originalJson, StrictJson)
            ?? throw new InvalidDataException("completed-recovery-original-receipt-invalid");
        Match(q, original);
        if (original.Status != "OutcomeUnknown" || original.FailureCode != "preparation-failed-reconcile-required" ||
            original.CleanupVerified || original.RollbackStatus != "Unknown" || original.ModelSha256 != "" ||
            original.ResultPath != "" || original.ResultSha256 != "")
            throw new InvalidDataException("completed-recovery-original-state-invalid");
        if (!File.Exists(activePath)) throw new InvalidDataException("completed-recovery-active-marker-missing");
        if (!Hash(activePath).Equals(q.ActiveMarkerSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("completed-recovery-active-marker-changed");
        if (!File.Exists(failurePath) || !Hash(failurePath).Equals(q.FailureEvidenceSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("completed-recovery-failure-evidence-changed");
        var active = ReadActive(activePath); Match(q, active);
        string requestPath = Path.Combine(Store, q.RequestId + ".request.json");
        if (!File.Exists(requestPath) || !Hash(requestPath).Equals(q.RequestSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("completed-recovery-request-evidence-changed");
        string requestJson = File.ReadAllText(requestPath);
        var persisted = JsonSerializer.Deserialize<CpvPreparationRequest>(requestJson, StrictJson)
            ?? throw new InvalidDataException("completed-recovery-request-evidence-invalid");
        Match(q, persisted);
        if (JsonSerializer.Serialize(active, StrictJson) != JsonSerializer.Serialize(persisted, StrictJson) ||
            persisted.CandidateEvidence is null || original.CandidateSha256 != persisted.CandidateEvidence.CandidateDllSha256 ||
            original.ManifestSha256 != persisted.CandidateEvidence.RunnerManifestSha256 || original.ExpiresUtc != persisted.ExpiresUtc)
            throw new InvalidDataException("completed-recovery-active-request-mismatch");
        string runDirectory = Path.GetFullPath(Path.Combine(options.RuntimeRoot, "cpv-preparation-" + q.RunId));
        string modelPath = Path.Combine(runDirectory, "model.rvt");
        string runnerPath = Path.Combine(runDirectory, "tara-" + q.AttemptId + ".request.json");
        string resultPath = runnerPath + ".preparation.json";
        if (!Path.GetFullPath(original.ModelPath).Equals(Path.GetFullPath(modelPath), StringComparison.OrdinalIgnoreCase) ||
            !Path.GetFullPath(original.RequestPath).Equals(Path.GetFullPath(runnerPath), StringComparison.OrdinalIgnoreCase) ||
            original.User != identity.User || original.Sid != identity.Sid || original.SessionId <= 0 ||
            !File.Exists(resultPath) || !File.Exists(modelPath) || File.Exists(modelPath + ".slog") || File.Exists(modelPath + ".lck"))
            throw new InvalidDataException("completed-recovery-path-or-process-evidence-invalid");
        if (!Hash(modelPath).Equals(q.ModelSha256, StringComparison.OrdinalIgnoreCase) ||
            !Hash(resultPath).Equals(q.ResultSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("completed-recovery-model-or-result-hash-mismatch");
        boundary.Validate(persisted); // Revalidate pinned candidate, fixture provenance, deployment, identity, and no-Revit policy.
        ValidateRunnerRequest(runnerPath, resultPath, modelPath, persisted);
        RevitCpvPreparationBoundary.VerifyResult(File.ReadAllText(resultPath), persisted, modelPath);
        using var modelLease = boundary.ValidateReconciliation(persisted, original, q.ModelSha256);
        if (modelLease is not Stream lockedModel) throw new InvalidDataException("completed-recovery-model-lease-invalid");
        lockedModel.Position = 0;
        string lockedHash = Convert.ToHexString(SHA256.HashData(lockedModel));
        if (!lockedHash.Equals(q.ModelSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("completed-recovery-model-changed-during-validation");
        string sidecarPath = modelPath + ".fixture.json";
        if (!File.Exists(sidecarPath)) throw new InvalidDataException("completed-recovery-historical-sidecar-missing");
        RevitCpvPreparationBoundary.NoLinks(sidecarPath);
        string historicalSidecarSha256 = Hash(sidecarPath);
        var sidecar = new { fixtureId = "CreatePlanViewsEmpty", sourceSha256 = FixtureSha256, preparedModelSha256 = q.ModelSha256,
            fixturePreparationRequestPath = runnerPath, fixturePreparationRequestSha256 = Hash(runnerPath),
            fixturePreparationResultPath = resultPath, fixturePreparationResultSha256 = q.ResultSha256,
            fixturePreparationAttemptId = q.AttemptId, fixturePreparationRunId = q.RunId,
            recoveredFromOutcomeUnknown = true, recoveryApprovalId = q.RecoveryApprovalId,
            originalFailureReceiptSha256 = q.OriginalReceiptSha256,
            schemaVersion = 1, requestId = q.RequestId, taskId = q.TaskId, workflowId = q.WorkflowId,
            historicalSidecarPath = sidecarPath, historicalSidecarSha256,
            approvalBindingHash = q.ApprovalBindingHash, originalReceiptSha256 = q.OriginalReceiptSha256,
            activeMarkerSha256 = q.ActiveMarkerSha256, failureEvidenceSha256 = q.FailureEvidenceSha256,
            requestSha256 = q.RequestSha256 };
        string sidecarJson = JsonSerializer.Serialize(sidecar, StrictJson);
        if (File.Exists(sidecarPath))
        {
            using var existing = JsonDocument.Parse(File.ReadAllText(sidecarPath));
            var side = existing.RootElement;
            RejectDuplicateProperties(side);
            string[] requiredSidecarFields = ["fixtureId", "sourceSha256", "preparedModelSha256",
                "fixturePreparationRequestPath", "fixturePreparationRequestSha256", "fixturePreparationResultPath",
                "fixturePreparationResultSha256", "fixturePreparationAttemptId", "fixturePreparationRunId"];
            bool sourceOnly = side.ValueKind == JsonValueKind.Object && side.EnumerateObject().Count() == 2 &&
                side.TryGetProperty("fixtureId", out var fixture) && fixture.ValueKind == JsonValueKind.String && fixture.GetString() == "CreatePlanViewsEmpty" &&
                side.TryGetProperty("sourceSha256", out var source) && source.ValueKind == JsonValueKind.String && source.GetString() == FixtureSha256;
            if (!sourceOnly && (side.ValueKind != JsonValueKind.Object || side.EnumerateObject().Count() != requiredSidecarFields.Length || requiredSidecarFields.Any(name =>
                !side.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.String))
                ) throw new InvalidDataException("completed-recovery-existing-sidecar-mismatch");
            if (!sourceOnly && (side.GetProperty("fixtureId").GetString() != "CreatePlanViewsEmpty" ||
                side.GetProperty("sourceSha256").GetString() != FixtureSha256 ||
                side.GetProperty("preparedModelSha256").GetString() != q.ModelSha256 ||
                side.GetProperty("fixturePreparationRequestPath").GetString() != runnerPath ||
                side.GetProperty("fixturePreparationRequestSha256").GetString() != Hash(runnerPath) ||
                side.GetProperty("fixturePreparationResultPath").GetString() != resultPath ||
                side.GetProperty("fixturePreparationResultSha256").GetString() != q.ResultSha256 ||
                side.GetProperty("fixturePreparationAttemptId").GetString() != q.AttemptId ||
                side.GetProperty("fixturePreparationRunId").GetString() != q.RunId))
                throw new InvalidDataException("completed-recovery-existing-sidecar-mismatch");
        }
        string provenancePath = modelPath + ".recovered.fixture.json";
        if (File.Exists(provenancePath))
        {
            RevitCpvPreparationBoundary.NoLinks(provenancePath);
            if (File.ReadAllText(provenancePath) != sidecarJson)
                throw new InvalidDataException("completed-recovery-provenance-replay-mismatch");
        }
        else WriteDurable(provenancePath, sidecarJson);
        if (Hash(sidecarPath) != historicalSidecarSha256)
            throw new InvalidDataException("completed-recovery-historical-sidecar-changed");
        var recovered = original with { Status = "Passed", ModelSha256 = q.ModelSha256, RequestSha256 = Hash(runnerPath),
            ResultPath = resultPath, ResultSha256 = q.ResultSha256, CleanupVerified = true,
            RollbackStatus = "CommittedDisposableFixtureOnly", FailureCode = null };
        var commit = new CpvPreparationRecoveryCommit(1, recovered, q.RecoveryApprovalId, q.ExpectedTaskRevision,
            q.ApprovalBindingHash, q.AuthorizationExpiresUtc, q.OriginalReceiptSha256, q.ActiveMarkerSha256, q.FailureEvidenceSha256, q.RequestSha256,
            q.ResultSha256, q.ModelSha256, now, provenancePath, Hash(provenancePath));
        if (File.Exists(recoveryPath))
        {
            var existing = JsonSerializer.Deserialize<CpvPreparationRecoveryCommit>(File.ReadAllText(recoveryPath), StrictJson)
                ?? throw new InvalidDataException("completed-recovery-receipt-invalid");
            if (existing.SchemaVersion != 1 || existing.Receipt != recovered || existing.RecoveryApprovalId != q.RecoveryApprovalId ||
                existing.ExpectedTaskRevision != q.ExpectedTaskRevision || existing.ApprovalBindingHash != q.ApprovalBindingHash ||
                existing.AuthorizationExpiresUtc != q.AuthorizationExpiresUtc || existing.OriginalReceiptSha256 != q.OriginalReceiptSha256 ||
                existing.ActiveMarkerSha256 != q.ActiveMarkerSha256 ||
                existing.FailureEvidenceSha256 != q.FailureEvidenceSha256 ||
                existing.RequestSha256 != q.RequestSha256 || existing.ResultSha256 != q.ResultSha256 || existing.ModelSha256 != q.ModelSha256 ||
                existing.RecoveredProvenancePath != commit.RecoveredProvenancePath || existing.RecoveredProvenanceSha256 != commit.RecoveredProvenanceSha256)
                throw new InvalidDataException("completed-recovery-replay-binding-mismatch");
            commit = existing;
        }
        else
        {
            if (File.Exists(recoveryPath + ".partial")) throw new InvalidDataException("completed-recovery-partial-receipt-present");
            WriteDurable(recoveryPath + ".partial", JsonSerializer.Serialize(commit, StrictJson));
            File.Move(recoveryPath + ".partial", recoveryPath, false);
        }
        // Persist the separate terminal receipt first; the original OutcomeUnknown receipt is never overwritten.
        if (!File.Exists(activePath) || JsonSerializer.Serialize(ReadActive(activePath), StrictJson) != JsonSerializer.Serialize(persisted, StrictJson))
            throw new InvalidDataException("completed-recovery-active-marker-changed");
        File.Delete(activePath);
        return commit;
    }
    private object ReconcileCompletedRecovery(CpvPreparationCompletedRecoveryReconcile q, DateTimeOffset now)
    {
        // Definitive, fail-closed disposition for one reserved completed-outcome recovery.
        // A committed recovery is proven terminal by its durable recovery receipt. Otherwise a
        // "NotExecuted" attestation requires positive, byte-exact evidence that no recovery ran:
        // the original OutcomeUnknown receipt is unchanged, the active preparation marker is
        // present and byte-equal to the persisted request, and the failure/request evidence still
        // hashes to the approved snapshot. Absence of a commit is never sufficient on its own.
        Directory.CreateDirectory(Store);
        string recoveryPath = Path.Combine(Store, q.RequestId + ".recovered.json");
        if (File.Exists(recoveryPath))
        {
            var commit = ReadRecoveryCommit(recoveryPath);
            Match(q, commit.Receipt);
            if (commit.RecoveryApprovalId != q.RecoveryApprovalId || commit.ApprovalBindingHash != q.ApprovalBindingHash ||
                commit.OriginalReceiptSha256 != q.OriginalReceiptSha256 || commit.ActiveMarkerSha256 != q.ActiveMarkerSha256 ||
                commit.FailureEvidenceSha256 != q.FailureEvidenceSha256 || commit.RequestSha256 != q.RequestSha256)
                throw new InvalidDataException("completed-recovery-reconcile-commit-binding-mismatch");
            return new { schemaVersion = 1, operation = RecoverCompletedReconcileOperation, requestId = q.RequestId, status = "Executed",
                recoveryApprovalId = commit.RecoveryApprovalId, approvalBindingHash = commit.ApprovalBindingHash,
                modelSha256 = commit.ModelSha256, resultSha256 = commit.ResultSha256 };
        }
        if (File.Exists(recoveryPath + ".partial")) throw new InvalidDataException("completed-recovery-reconcile-partial-present");
        string activePath = Path.Combine(Store, "active.json"), originalPath = Path.Combine(Store, q.RequestId + ".json");
        string failurePath = Path.Combine(Store, q.RequestId + ".failure.txt"), requestPath = Path.Combine(Store, q.RequestId + ".request.json");
        if (!File.Exists(originalPath) || !Hash(originalPath).Equals(q.OriginalReceiptSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("completed-recovery-reconcile-original-receipt-changed");
        var original = JsonSerializer.Deserialize<CpvPreparationReceipt>(File.ReadAllText(originalPath), StrictJson)
            ?? throw new InvalidDataException("completed-recovery-reconcile-original-receipt-invalid");
        Match(q, original);
        if (File.Exists(original.ModelPath + ".recovered.fixture.json"))
            throw new InvalidDataException("completed-recovery-reconcile-uncommitted-provenance-present");
        if (original.Status != "OutcomeUnknown" || original.FailureCode != "preparation-failed-reconcile-required" ||
            original.CleanupVerified || original.RollbackStatus != "Unknown" || original.ModelSha256 != "" ||
            original.ResultPath != "" || original.ResultSha256 != "")
            throw new InvalidDataException("completed-recovery-reconcile-original-state-invalid");
        if (!File.Exists(activePath) || !Hash(activePath).Equals(q.ActiveMarkerSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("completed-recovery-reconcile-active-marker-changed");
        var active = ReadActive(activePath); Match(q, active);
        if (!File.Exists(failurePath) || !Hash(failurePath).Equals(q.FailureEvidenceSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("completed-recovery-reconcile-failure-evidence-changed");
        if (!File.Exists(requestPath) || !Hash(requestPath).Equals(q.RequestSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("completed-recovery-reconcile-request-evidence-changed");
        var persisted = JsonSerializer.Deserialize<CpvPreparationRequest>(File.ReadAllText(requestPath), StrictJson)
            ?? throw new InvalidDataException("completed-recovery-reconcile-request-evidence-invalid");
        Match(q, persisted);
        if (JsonSerializer.Serialize(active, StrictJson) != JsonSerializer.Serialize(persisted, StrictJson))
            throw new InvalidDataException("completed-recovery-reconcile-active-request-mismatch");
        return new { schemaVersion = 1, operation = RecoverCompletedReconcileOperation, requestId = q.RequestId, status = "NotExecuted",
            recoveryApprovalId = q.RecoveryApprovalId, approvalBindingHash = q.ApprovalBindingHash,
            originalReceiptSha256 = q.OriginalReceiptSha256, activeMarkerSha256 = q.ActiveMarkerSha256,
            failureEvidenceSha256 = q.FailureEvidenceSha256, requestSha256 = q.RequestSha256, verifiedUtc = now };
    }
    private static void ValidateRunnerRequest(string runnerPath, string resultPath, string modelPath, CpvPreparationRequest request)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(runnerPath));
        var root = document.RootElement; RejectDuplicateProperties(root);
        string[] names = ["schemaVersion", "operation", "requestId", "taskId", "workflowId", "attemptId", "runId", "requestPath", "modelPath", "modelSha256", "selectedManifestPath", "selectedManifestSha256", "outputPath", "expiresUtc"];
        if (root.ValueKind != JsonValueKind.Object || root.EnumerateObject().Count() != names.Length || names.Any(n => !root.TryGetProperty(n, out _)) ||
            root.GetProperty("schemaVersion").GetInt32() != 1 || root.GetProperty("operation").GetString() != RunnerOperation ||
            root.GetProperty("requestId").GetString() != request.AttemptId || root.GetProperty("taskId").GetString() != request.TaskId ||
            root.GetProperty("workflowId").GetString() != request.WorkflowId || root.GetProperty("attemptId").GetString() != request.AttemptId ||
            root.GetProperty("runId").GetString() != request.RunId ||
            !Path.GetFullPath(root.GetProperty("requestPath").GetString()!).Equals(Path.GetFullPath(runnerPath), StringComparison.OrdinalIgnoreCase) ||
            !Path.GetFullPath(root.GetProperty("modelPath").GetString()!).Equals(Path.GetFullPath(modelPath), StringComparison.OrdinalIgnoreCase) ||
            root.GetProperty("modelSha256").GetString() != FixtureSha256 ||
            root.GetProperty("selectedManifestPath").GetString() != QaLaunchPolicy.ExpectedRunnerManifestPath ||
            root.GetProperty("selectedManifestSha256").GetString() != request.CandidateEvidence.RunnerManifestSha256 ||
            !Path.GetFullPath(root.GetProperty("outputPath").GetString()!).Equals(Path.GetFullPath(resultPath), StringComparison.OrdinalIgnoreCase) ||
            DateTimeOffset.Parse(root.GetProperty("expiresUtc").GetString()!) != request.ExpiresUtc)
            throw new InvalidDataException("completed-recovery-runner-request-mismatch");
    }
    private static CpvPreparationRequest ReadActive(string path) => JsonSerializer.Deserialize<CpvPreparationRequest>(File.ReadAllText(path), StrictJson)
        ?? throw new InvalidDataException("reconciliation-active-marker-invalid");
    private static void Match(CpvPreparationReconciliation q, CpvPreparationRequest r)
    {
        if (q.RequestId != r.RequestId || q.TaskId != r.TaskId || q.WorkflowId != r.WorkflowId || q.AttemptId != r.AttemptId || q.RunId != r.RunId)
            throw new InvalidDataException("reconciliation-identity-mismatch");
    }
    private static void Match(CpvPreparationReconciliation q, CpvPreparationReceipt r)
    {
        if (q.RequestId != r.RequestId || q.TaskId != r.TaskId || q.WorkflowId != r.WorkflowId || q.AttemptId != r.AttemptId || q.RunId != r.RunId)
            throw new InvalidDataException("reconciliation-identity-mismatch");
    }
    private static void Match(CpvPreparationCompletedRecovery q, CpvPreparationRequest r)
    {
        if (q.RequestId != r.RequestId || q.TaskId != r.TaskId || q.WorkflowId != r.WorkflowId || q.AttemptId != r.AttemptId || q.RunId != r.RunId)
            throw new InvalidDataException("completed-recovery-identity-mismatch");
    }
    private static void Match(CpvPreparationCompletedRecovery q, CpvPreparationReceipt r)
    {
        if (q.RequestId != r.RequestId || q.TaskId != r.TaskId || q.WorkflowId != r.WorkflowId || q.AttemptId != r.AttemptId || q.RunId != r.RunId)
            throw new InvalidDataException("completed-recovery-identity-mismatch");
    }
    private static void Match(CpvPreparationCompletedRecoveryReconcile q, CpvPreparationRequest r)
    {
        if (q.RequestId != r.RequestId || q.TaskId != r.TaskId || q.WorkflowId != r.WorkflowId || q.AttemptId != r.AttemptId || q.RunId != r.RunId)
            throw new InvalidDataException("completed-recovery-reconcile-identity-mismatch");
    }
    private static void Match(CpvPreparationCompletedRecoveryReconcile q, CpvPreparationReceipt r)
    {
        if (q.RequestId != r.RequestId || q.TaskId != r.TaskId || q.WorkflowId != r.WorkflowId || q.AttemptId != r.AttemptId || q.RunId != r.RunId)
            throw new InvalidDataException("completed-recovery-reconcile-identity-mismatch");
    }
    private static CpvPreparationRecoveryCommit ReadRecoveryCommit(string path)
    {
        var commit = JsonSerializer.Deserialize<CpvPreparationRecoveryCommit>(File.ReadAllText(path), StrictJson)
            ?? throw new InvalidDataException("completed-recovery-commit-invalid");
        string expectedPath = commit.Receipt.ModelPath + ".recovered.fixture.json";
        if (File.Exists(expectedPath)) RevitCpvPreparationBoundary.NoLinks(expectedPath);
        if (File.Exists(commit.Receipt.ModelPath + ".fixture.json")) RevitCpvPreparationBoundary.NoLinks(commit.Receipt.ModelPath + ".fixture.json");
        if (commit.SchemaVersion != 1 || commit.RecoveredProvenancePath != expectedPath ||
            commit.RecoveredProvenanceSha256 is null || !Sha256(commit.RecoveredProvenanceSha256) ||
            !File.Exists(expectedPath) || Hash(expectedPath) != commit.RecoveredProvenanceSha256)
            throw new InvalidDataException("completed-recovery-provenance-integrity-invalid");
        using var doc = JsonDocument.Parse(File.ReadAllText(expectedPath));
        var p = doc.RootElement; RejectDuplicateProperties(p);
        var fields = new Dictionary<string, string> {
            ["fixtureId"] = "CreatePlanViewsEmpty", ["sourceSha256"] = FixtureSha256,
            ["preparedModelSha256"] = commit.ModelSha256, ["fixturePreparationRequestPath"] = commit.Receipt.RequestPath,
            ["fixturePreparationRequestSha256"] = commit.Receipt.RequestSha256,
            ["fixturePreparationResultPath"] = commit.Receipt.ResultPath, ["fixturePreparationResultSha256"] = commit.ResultSha256,
            ["fixturePreparationAttemptId"] = commit.Receipt.AttemptId, ["fixturePreparationRunId"] = commit.Receipt.RunId,
            ["requestId"] = commit.Receipt.RequestId, ["taskId"] = commit.Receipt.TaskId, ["workflowId"] = commit.Receipt.WorkflowId,
            ["recoveryApprovalId"] = commit.RecoveryApprovalId, ["approvalBindingHash"] = commit.ApprovalBindingHash,
            ["originalReceiptSha256"] = commit.OriginalReceiptSha256, ["originalFailureReceiptSha256"] = commit.OriginalReceiptSha256,
            ["activeMarkerSha256"] = commit.ActiveMarkerSha256,
            ["failureEvidenceSha256"] = commit.FailureEvidenceSha256, ["requestSha256"] = commit.RequestSha256,
            ["historicalSidecarPath"] = commit.Receipt.ModelPath + ".fixture.json" };
        if (p.ValueKind != JsonValueKind.Object || fields.Any(f => !p.TryGetProperty(f.Key, out var v) ||
                v.ValueKind != JsonValueKind.String || v.GetString() != f.Value) ||
            !p.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number || schema.GetInt32() != 1 ||
            !p.TryGetProperty("recoveredFromOutcomeUnknown", out var recovered) || recovered.ValueKind != JsonValueKind.True ||
            !p.TryGetProperty("historicalSidecarSha256", out var historical) || historical.ValueKind != JsonValueKind.String ||
            !File.Exists(fields["historicalSidecarPath"]) || Hash(fields["historicalSidecarPath"]) != historical.GetString())
            throw new InvalidDataException("completed-recovery-provenance-binding-invalid");
        return commit;
    }
    private object Read(string id) {
        if (!File.Exists(Path.Combine(Store, id + ".json"))) return new { schemaVersion = 1, operation = StatusOperation, requestId = id, status = "NotFound" };
        var receipt = JsonSerializer.Deserialize<CpvPreparationReceipt>(File.ReadAllText(Path.Combine(Store, id + ".json")), StrictJson)!;
        string recoveredPath = Path.Combine(Store, id + ".recovered.json");
        if (!File.Exists(Path.Combine(Store, "active.json")) && File.Exists(recoveredPath))
            return ReadRecoveryCommit(recoveredPath).Receipt;
        return receipt.Status == "Executing" && !running.Contains(id) ? receipt with { Status = "OutcomeUnknown", FailureCode = "agent-interrupted-reconcile-required" } : receipt;
    }
    private void Write(CpvPreparationReceipt receipt) {
        string path = Path.Combine(Store, receipt.RequestId + ".json"), temporary = path + ".partial";
        WriteDurable(temporary, JsonSerializer.Serialize(receipt, StrictJson)); File.Move(temporary, path, true);
    }
    private void WriteReconciled(CpvPreparationReceipt receipt)
    {
        string path = Path.Combine(Store, receipt.RequestId + ".json"), temporary = path + "." + Guid.NewGuid().ToString("N") + ".reconcile.partial";
        string json = JsonSerializer.Serialize(receipt, StrictJson);
        WriteDurable(temporary, json);
        File.Move(temporary, path, true);
    }
    private static void WriteDurable(string path, string text) { using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None); using var writer = new StreamWriter(stream, leaveOpen: true); writer.Write(text); writer.Flush(); stream.Flush(true); }
    public static string Hash(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
    private static bool Sha256(string value) => value.Length == 64 && value.All(Uri.IsHexDigit);
    private static void RejectDuplicateProperties(JsonElement element) {
        if (element.ValueKind != JsonValueKind.Object) return;
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in element.EnumerateObject()) { if (!names.Add(p.Name)) throw new InvalidDataException("duplicate-json-property"); RejectDuplicateProperties(p.Value); }
    }
}

public sealed class RevitCpvPreparationBoundary(QaAgentOptions options) : ICpvPreparationBoundary
{
    private const string Source = @"C:\Repato-Autonomous\Source\QA\Fixtures\CreatePlanViewsEmpty.rvt";
    public void Validate(CpvPreparationRequest r)
    {
        var e = r.CandidateEvidence;
        if (!QaLaunchPolicy.IsValidCandidateEvidence(e, r.TaskId, r.WorkflowId, "create-plan-views-v1", "create-plan-views-v1"))
            throw new InvalidDataException("candidate-invalid");
        NoLinks(e.CandidateDllPath); NoLinks(e.RunnerManifestPath); NoLinks(e.CandidateProvenancePath);
        NoLinks(options.RuntimeRoot); NoLinks(Source); NoLinks(Source.Replace(".rvt", ".provenance.json"));
        if (Process.GetProcessesByName("Revit").Length != 0) throw new InvalidDataException("revit-already-running");
        if (CpvPreparationService.Hash(Source) != CpvPreparationService.FixtureSha256) throw new InvalidDataException("source-fixture-integrity");
        using var provenance = JsonDocument.Parse(File.ReadAllText(Source.Replace(".rvt", ".provenance.json")));
        if (provenance.RootElement.GetProperty("fixtureId").GetString() != "CreatePlanViewsEmpty" ||
            provenance.RootElement.GetProperty("sourceSha256").GetString() != CpvPreparationService.FixtureSha256)
            throw new InvalidDataException("source-fixture-provenance");
        using var sourceLock = File.Open(Source, FileMode.Open, FileAccess.Read, FileShare.Read);
        var validated = StagingAdapter.ValidateDeployment(new(1, QaLaunchPolicy.ValidateDeploymentOperation, r.RequestId,
            e.CandidateSourceCommit, e.CandidateDllSha256, e.QaWorkflowId, e.TestId, r.TaskId, r.WorkflowId, e));
        if (!QaLaunchPolicy.CanPassDeploymentValidation(validated) || !validated.IsolationPassed ||
            !string.Equals(validated.ValidationIdentity, options.ExpectedUser, StringComparison.OrdinalIgnoreCase) ||
            validated.CandidateSha256 != e.CandidateDllSha256) throw new InvalidDataException("deployment-validation-failed");
    }
    public async Task<CpvPreparationOutcome> Execute(CpvPreparationRequest r, string directory)
    {
        Validate(r); // Recheck immediately before creating the sole disposable target.
        if (r.ExpiresUtc <= DateTimeOffset.UtcNow) throw new InvalidDataException("preparation-expired");
        Directory.CreateDirectory(directory); NoLinks(directory);
        string model = Path.Combine(directory, "model.rvt"), request = Path.Combine(directory, "tara-" + r.AttemptId + ".request.json"), result = request + ".preparation.json";
        File.Copy(Source, model, false);
        if (CpvPreparationService.Hash(model) != CpvPreparationService.FixtureSha256) throw new InvalidDataException("disposable-copy-integrity-failed");
        File.WriteAllText(model + ".fixture.json", JsonSerializer.Serialize(new { fixtureId = "CreatePlanViewsEmpty", sourceSha256 = CpvPreparationService.FixtureSha256 }));
        using (File.Open(model, FileMode.Open, FileAccess.Read, FileShare.None)) { }
        var runnerRequest = new { schemaVersion = 1, operation = CpvPreparationService.RunnerOperation, requestId = r.AttemptId,
            taskId = r.TaskId, workflowId = r.WorkflowId, attemptId = r.AttemptId, runId = r.RunId, requestPath = request,
            modelPath = model, modelSha256 = CpvPreparationService.FixtureSha256, selectedManifestPath = QaLaunchPolicy.ExpectedRunnerManifestPath,
            selectedManifestSha256 = r.CandidateEvidence.RunnerManifestSha256, outputPath = result, expiresUtc = r.ExpiresUtc };
        File.WriteAllText(request, JsonSerializer.Serialize(runnerRequest));
        var psi = new ProcessStartInfo(options.RevitExe) { UseShellExecute = false, WindowStyle = ProcessWindowStyle.Hidden };
        psi.ArgumentList.Add(model);
        foreach (var key in psi.Environment.Keys.ToArray()) if (key.StartsWith("REPATO_QA_", StringComparison.OrdinalIgnoreCase)) psi.Environment.Remove(key);
        psi.Environment["REPATO_QA_CREATE_PLAN_VIEWS_FIXTURE_PREPARATION"] = request;
        using var process = Process.Start(psi) ?? throw new InvalidOperationException("preparation-process-start-failed");
        string resultJson = "";
        try {
            if (process.SessionId != Process.GetCurrentProcess().SessionId || !Path.GetFullPath(process.MainModule!.FileName).Equals(Path.GetFullPath(options.RevitExe), StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("preparation-child-correlation-failed");
            var deadline = DateTimeOffset.UtcNow.AddSeconds(r.TimeoutSeconds);
            while (!File.Exists(result)) {
                if (process.HasExited) throw new InvalidDataException("preparation-exited-without-result");
                string? dialog = PreparationDialogs.FindOwnedDialog(process.Id);
                if (dialog is not null) throw new InvalidOperationException("Unattended preparation stopped at dialog: " + dialog);
                if (DateTimeOffset.UtcNow >= deadline || DateTimeOffset.UtcNow >= r.ExpiresUtc) throw new TimeoutException();
                await Task.Delay(250);
            }
            // The runner writes after Save, with exclusive file access. Wait for the writer to close.
            while (true) {
                try { using var file = File.Open(result, FileMode.Open, FileAccess.Read, FileShare.Read); using var reader = new StreamReader(file); resultJson = reader.ReadToEnd(); break; }
                catch (IOException) { if (DateTimeOffset.UtcNow >= deadline) throw new TimeoutException(); await Task.Delay(100); }
            }
        } finally {
            // Only this owned child is terminated; no global Revit close/kill and no dialog dismissal.
            if (!process.HasExited) process.Kill(true);
            if (!process.WaitForExit(15000)) throw new IOException("preparation-cleanup-failed");
        }
        using var modelLease = await OpenModelExclusivelyAfterChildExit(model, () => process.HasExited, TimeSpan.FromSeconds(15));
        string modelSha256 = Convert.ToHexString(SHA256.HashData(modelLease));
        VerifyResult(resultJson, r, model, modelSha256);
        if (Directory.EnumerateFiles(directory, "*.slog").Any() || Directory.EnumerateFiles(directory, "*.lck").Any()) throw new IOException("preparation-model-lock-remains");
        if (CpvPreparationService.Hash(Source) != CpvPreparationService.FixtureSha256) throw new InvalidDataException("source-mutated");
        File.WriteAllText(model + ".fixture.json", JsonSerializer.Serialize(new {
            fixtureId = "CreatePlanViewsEmpty", sourceSha256 = CpvPreparationService.FixtureSha256,
            preparedModelSha256 = modelSha256, fixturePreparationRequestPath = request,
            fixturePreparationRequestSha256 = CpvPreparationService.Hash(request), fixturePreparationResultPath = result,
            fixturePreparationResultSha256 = CpvPreparationService.Hash(result), fixturePreparationAttemptId = r.AttemptId,
            fixturePreparationRunId = r.RunId }));
        return new(modelSha256, CpvPreparationService.Hash(result), true, "CommittedDisposableFixtureOnly");
    }
    public IDisposable ValidateReconciliation(CpvPreparationRequest request, CpvPreparationReceipt receipt, string expectedModelSha256)
    {
        static void RequireNoRevitProcess()
        {
            // Any unreadable process snapshot makes absence unprovable; never treat errors as no process.
            foreach (var process in Process.GetProcessesByName("Revit"))
            {
                using (process) throw new InvalidDataException("reconciliation-revit-process-present");
            }
        }
        RequireNoRevitProcess();
        var model = File.Open(receipt.ModelPath, FileMode.Open, FileAccess.Read, FileShare.None);
        try
        {
            if (!Convert.ToHexString(SHA256.HashData(model)).Equals(expectedModelSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("reconciliation-model-hash-mismatch");
            RequireNoRevitProcess();
            return model;
        }
        catch { model.Dispose(); throw; }
    }
    public static void VerifyResult(string json, CpvPreparationRequest r, string model) => VerifyResult(json, r, model, CpvPreparationService.Hash(model));
    public static void VerifyResult(string json, CpvPreparationRequest r, string model, string modelSha256) {
        using var d = JsonDocument.Parse(json); var e = d.RootElement;
        string Text(string n) => e.GetProperty(n).GetString() ?? "";
        if (Text("Status") != "Passed" || Text("Operation") != CpvPreparationService.RunnerOperation || Text("TaskId") != r.TaskId ||
            Text("WorkflowId") != r.WorkflowId || Text("AttemptId") != r.AttemptId || Text("RunId") != r.RunId ||
            Text("ModelPath") != model || Text("SourceModelSha256") != CpvPreparationService.FixtureSha256 || Text("PreparedModelSha256") != modelSha256)
            throw new InvalidDataException("preparation-result-correlation-failed");
        var levels = e.GetProperty("Levels").EnumerateArray().ToArray();
        var expected = new[] { ("0", 0d), ("1", 4d), ("2", 7.8d) };
        if (levels.Length != 3 || levels.Select(l => l.GetProperty("ElementId").GetInt64()).Distinct().Count() != 3 || expected.Any(x => levels.Count(l => l.GetProperty("Name").GetString() == x.Item1 &&
            Math.Abs(l.GetProperty("ElevationMeters").GetDouble() - x.Item2) < 1e-7 && l.GetProperty("ElementId").GetInt64() > 0) != 1))
            throw new InvalidDataException("prepared-level-verification-failed");
    }
    public static void VerifyResultAfterChildExit(string json, CpvPreparationRequest r, string model, Func<bool> childHasExited) {
        ArgumentNullException.ThrowIfNull(childHasExited);
        if (!childHasExited()) throw new InvalidOperationException("preparation-child-still-running");
        VerifyResult(json, r, model);
    }
    public static async Task<FileStream> OpenModelExclusivelyAfterChildExit(string model, Func<bool> childHasExited, TimeSpan timeout, TimeSpan? retryDelay = null) {
        ArgumentNullException.ThrowIfNull(childHasExited);
        if (timeout <= TimeSpan.Zero) throw new ArgumentOutOfRangeException(nameof(timeout));
        var deadline = DateTimeOffset.UtcNow + timeout;
        var delay = retryDelay ?? TimeSpan.FromMilliseconds(100);
        while (true) {
            if (!childHasExited()) throw new InvalidOperationException("preparation-child-still-running");
            try { return File.Open(model, FileMode.Open, FileAccess.Read, FileShare.None); }
            catch (IOException ex) {
                if (DateTimeOffset.UtcNow >= deadline) throw new IOException("preparation-model-lock-remains-after-child-exit", ex);
                await Task.Delay(delay);
            }
        }
    }
    public static void NoLinks(string path) {
        for (var current = new FileInfo(Path.GetFullPath(path)) as FileSystemInfo; current is not null; current = Directory.GetParent(current.FullName))
            if ((current.Attributes & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("reparse-path-rejected");
    }
}

internal static class PreparationDialogs
{
    private delegate bool WindowCallback(IntPtr window, IntPtr parameter);
    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern bool EnumWindows(WindowCallback callback, IntPtr parameter);
    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)] private static extern int GetClassName(IntPtr window, System.Text.StringBuilder text, int count);
    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, System.Text.StringBuilder text, int count);
    public static string? FindOwnedDialog(int processId) {
        string? found = null;
        EnumWindows((window, _) => {
            GetWindowThreadProcessId(window, out uint owner); if (owner != processId) return true;
            var name = new System.Text.StringBuilder(256); GetClassName(window, name, name.Capacity);
            if (name.ToString() != "#32770") return true;
            var title = new System.Text.StringBuilder(1024); GetWindowText(window, title, title.Capacity);
            found = title.ToString(); return false;
        }, IntPtr.Zero);
        return found;
    }
}
