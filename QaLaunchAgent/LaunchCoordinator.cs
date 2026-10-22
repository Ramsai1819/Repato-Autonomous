using System.Text.Json;
using System.Security.Principal;

namespace Repato.QaLaunchAgent;

public sealed class LaunchCoordinator(QaAgentOptions options, IIdentitySessionProvider identity, IReplayLedger ledger, IChildProcessLauncher launcher, IChildProcessVerifier verifier, IRcpChildProcessLauncher? rcpLauncher = null, IRcpChildProcessVerifier? rcpVerifier = null)
{
    private readonly CpvPreparationService preparation = new(options, identity, ledger, new RevitCpvPreparationBoundary(options));
    public object PreparationCapabilities() => preparation.Capabilities();
    public object HandlePreparation(string json, DateTimeOffset now) => preparation.Handle(json, now);
    public RcpQaLaunchResponse HandleRcp(RcpQaLaunchRequest? request, DateTimeOffset now, string rawJson)
    {
        RcpQaLaunchResponse Reject(string code, bool? accepted = false, string disposition = "rejected") => new(1,
            RcpQaLaunchPolicy.Operation, request?.RequestId ?? "", request?.TaskId ?? "", request?.WorkflowId ?? "",
            request?.QaWorkflowId ?? "", request?.TestId ?? "", request?.AttemptId ?? "", request?.RunId ?? "",
            request?.ClaimId ?? "", accepted, disposition, null, identity.User, identity.Sid, identity.SessionId, null, code);

        if (preparation.HasUnresolvedExecution) return Reject("cpv-preparation-unresolved");
        if (!identity.User.Equals(options.ExpectedUser, StringComparison.OrdinalIgnoreCase) || identity.Sid != options.ExpectedUserSid || !identity.Interactive)
            return Reject("wrong-agent-identity");
        if (request is null) return Reject("request-invalid");
        if (string.IsNullOrWhiteSpace(options.RcpCandidateRoot) || string.IsNullOrWhiteSpace(options.RcpManifestRoot) || string.IsNullOrWhiteSpace(options.RcpIsolationRoot))
            return Reject("rcp-deployment-not-authorized");
        try
        {
            var binding = new RcpQaLaunchPolicy.ToolQaDescriptorBinding(RcpQaLaunchPolicy.ToolId, RcpQaLaunchPolicy.ToolId,
                "Repato.RcpQaRunner.RcpQaApplication", "Repato.CreateRcpViews.TestRunner.addin", 1, RcpQaLaunchPolicy.RunnerRequestOperation);
            RcpQaLaunchPolicy.Validate(request, rawJson, new RcpQaLaunchRoots(options.RuntimeRoot, options.RcpCandidateRoot,
                options.RcpManifestRoot, options.RcpIsolationRoot, options.ExpectedUser, options.ExpectedUserSid), binding, now,
                identity.User, identity.Sid, identity.Interactive);
        }
        catch { return Reject("request-or-artifact-validation-failed"); }
        if (!ledger.TryReserve(request.RequestId, now)) return Reject("request-replayed");
        if (rcpLauncher is null || rcpVerifier is null) return Reject("rcp-native-dispatch-unavailable");
        try
        {
            var child = rcpLauncher.Launch(request, options.RevitExe);
            if (!rcpVerifier.Verify(child, request, options.RevitExe, options.ExpectedUser, options.ExpectedUserSid, identity.SessionId))
                return Reject("process-correlation-failed", null, "unknown");
            return new(1, RcpQaLaunchPolicy.Operation, request.RequestId, request.TaskId, request.WorkflowId, request.QaWorkflowId,
                request.TestId, request.AttemptId, request.RunId, request.ClaimId, true, "accepted", child.Pid, child.User,
                options.ExpectedUserSid, child.SessionId, child.LaunchUtc, null);
        }
        catch { return Reject("native-disposition-unknown", null, "unknown"); }
    }

    public QaStageResponse HandleStage(QaStageRequest? request, DateTimeOffset now)
    {
        if (preparation.HasUnresolvedExecution) return StageReject(request, "cpv-preparation-unresolved");
        if (!identity.User.Equals(options.ExpectedUser, StringComparison.OrdinalIgnoreCase) || identity.Sid != options.ExpectedUserSid || !identity.Interactive) return StageReject(request, "wrong-agent-identity");
        if (request is null || request.SchemaVersion != 1 || request.Operation != QaLaunchPolicy.StageOperation || !Guid.TryParse(request.RequestId, out _) || request.QaWorkflowId != "create-plan-views-v1" || request.TestId != request.QaWorkflowId || (request.CandidateEvidence is null && (request.CandidateCommit != QaLaunchPolicy.FrozenCandidateCommit || request.ExpectedCandidateSha256 != QaLaunchPolicy.FrozenCandidateSha256)) || (request.CandidateEvidence is not null && !QaLaunchPolicy.IsValidCandidateEvidence(request.CandidateEvidence, request.TaskId ?? "", request.WorkflowId ?? "", request.QaWorkflowId, request.TestId))) return StageReject(request, "staging-request-invalid");
        if (!ledger.TryReserve(request.RequestId, now)) return StageReject(request, "staging-request-replayed");
        try
        {
            var result = StagingAdapter.Run(request);
            return result;
        }
        catch (Exception ex) { return StageReject(request, "staging-adapter-failed", ex.Message); }
    }
    public QaDeploymentValidationResponse HandleDeploymentValidation(QaDeploymentValidationRequest? request, DateTimeOffset now)
    {
        if (!identity.User.Equals(options.ExpectedUser, StringComparison.OrdinalIgnoreCase) || identity.Sid != options.ExpectedUserSid || !identity.Interactive) return new(1, QaLaunchPolicy.ValidateDeploymentOperation, request?.RequestId ?? "", false, request?.CandidateCommit, request?.ExpectedCandidateSha256, request?.QaWorkflowId, request?.TestId, null, null, false, "wrong-agent-identity", null);
        if (request is null || request.SchemaVersion != 1 || request.Operation != QaLaunchPolicy.ValidateDeploymentOperation || !Guid.TryParse(request.RequestId, out _) || request.QaWorkflowId != "create-plan-views-v1" || request.TestId != request.QaWorkflowId || (request.CandidateEvidence is null && (request.CandidateCommit != QaLaunchPolicy.FrozenCandidateCommit || request.ExpectedCandidateSha256 != QaLaunchPolicy.FrozenCandidateSha256)) || (request.CandidateEvidence is not null && !QaLaunchPolicy.IsValidCandidateEvidence(request.CandidateEvidence, request.TaskId ?? "", request.WorkflowId ?? "", request.QaWorkflowId, request.TestId))) return new(1, QaLaunchPolicy.ValidateDeploymentOperation, request?.RequestId ?? "", false, request?.CandidateCommit, request?.ExpectedCandidateSha256, request?.QaWorkflowId, request?.TestId, null, null, false, "validation-request-invalid", null);
        if (!ledger.TryReserve(request.RequestId, now)) return new(1, QaLaunchPolicy.ValidateDeploymentOperation, request.RequestId, false, request.CandidateCommit, request.ExpectedCandidateSha256, request.QaWorkflowId, request.TestId, null, null, false, "validation-request-replayed", null);
        try
        {
            var response = StagingAdapter.ValidateDeployment(request);
            if (response.Succeeded && !QaLaunchPolicy.CanPassDeploymentValidation(response))
                return response with { Succeeded = false, ErrorCode = "manifest-integrity-evidence-rejected", ErrorMessage = response.ManifestIntegrityPassed == false ? "Runtime manifest integrity evidence rejected deployment." : "Runtime manifest integrity evidence is missing or malformed." };
            return response;
        }
        catch (Exception ex) { return new(1, QaLaunchPolicy.ValidateDeploymentOperation, request.RequestId, false, request.CandidateCommit, request.ExpectedCandidateSha256, request.QaWorkflowId, request.TestId, null, null, false, "deployment-validation-failed", ex.Message); }
    }

    public QaPreflightResponse HandlePreflight(QaPreflightRequest? request)
    {
        var user = identity.User;
        var root = Path.Combine(options.QaProfileRoot, "RepatoQA");
        var manifest = Path.Combine(Directory.GetParent(root)!.FullName, "Repato.CreatePlanViews.TestRunner.addin");
        var dll = Path.Combine(root, "Repato.Revit.dll");
        var checks = new List<QaPreflightCheck>();
        var validRequest = QaLaunchPolicy.IsValidPreflightRequest(request);
        checks.Add(new("request-bindings", validRequest, validRequest ? "verified" : "rejected", null, null));
        var validIdentity = identity.User.Equals(options.ExpectedUser, StringComparison.OrdinalIgnoreCase) && identity.Sid == options.ExpectedUserSid && identity.Interactive;
        checks.Add(new("agent-identity", validIdentity, validIdentity ? "verified" : "rejected", null, null));
        // Only a fully validated task-bound candidate may replace the historical default pin.
        var evidence = validRequest ? request?.CandidateEvidence : null;
        var candidateHash = evidence?.CandidateDllSha256 ?? QaLaunchPolicy.FrozenCandidateSha256;
        var candidatePath = evidence?.CandidateDllPath ?? QaLaunchPolicy.StagingCandidateDirectory + "\\Repato.Revit.dll";
        checks.Add(CheckDirectory("qa-profile-root", root));
        checks.Add(CheckFile("runner-manifest-exists", manifest, null, false));
        checks.Add(CheckFile("runner-manifest-readable", manifest, null, false));
        checks.Add(CheckFile("runner-manifest-integrity", manifest, "AF4DBFA78E61524DE7BD3B84178C6B70ED8D29D0A95BA17780826E09BE689D4F", true));
        checks.Add(CheckFile("deployed-candidate-dll-exists", dll, null, false));
        checks.Add(CheckFile("deployed-candidate-dll-readable", dll, null, false));
        checks.Add(CheckFile("deployed-candidate-dll-integrity", dll, candidateHash, true));
        checks.Add(CheckDirectory("qa-test-runs", options.RuntimeRoot));
        checks.Add(CheckFile("revit-executable", options.RevitExe, null, false));
        checks.Add(CheckFile("frozen-candidate", candidatePath, candidateHash, true));
        checks.Add(CheckFile("authoritative-fixture", @"C:\Repato-Autonomous\Source\QA\Fixtures\CreatePlanViewsEmpty.rvt", "92CC9E434E2C4DD6720A2AA564E19F4E1A30EB3DA63CEA73CF737F875B9EDD45", true));
        checks.Add(CheckFile("isolation-policy", @"C:\Repato-Autonomous\Source\QA\MachineWideAddins.allowlist.json", null, false));
        checks.Add(CheckDirectory("qa-reports", @"C:\Repato-Autonomous\Source\QA\Reports"));
        checks.Add(CheckDirectory("qa-screenshots", @"C:\Repato-Autonomous\Source\QA\Screenshots"));
        var succeeded = request is not null && request.SchemaVersion == QaLaunchPolicy.SchemaVersion && request.Operation == QaLaunchPolicy.PreflightOperation && checks.All(c => c.Passed);
        return new(1, QaLaunchPolicy.PreflightOperation, succeeded, user, root, manifest, "AF4DBFA78E61524DE7BD3B84178C6B70ED8D29D0A95BA17780826E09BE689D4F", checks, succeeded ? null : "preflight-failed");
    }
    private static QaPreflightCheck CheckDirectory(string name, string path)
    {
        try { return new(name, Directory.Exists(path), Directory.Exists(path) ? "exists" : "missing", path, null); }
        catch (Exception ex) { return new(name, false, "io-failure", path, ex.GetType().Name); }
    }
    private static QaPreflightCheck CheckFile(string name, string path, string? expectedHash, bool hash)
    {
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            if (!hash) return new(name, true, "readable", path, null);
            var actual = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(stream));
            return new(name, actual.Equals(expectedHash, StringComparison.OrdinalIgnoreCase), actual.Equals(expectedHash, StringComparison.OrdinalIgnoreCase) ? "hash-match" : "hash-mismatch", path, $"actual={actual};expected={expectedHash}");
        }
        catch (UnauthorizedAccessException ex) { return new(name, false, "access-denied", path, ex.GetType().Name); }
        catch (FileNotFoundException ex) { return new(name, false, "missing", path, ex.GetType().Name); }
        catch (DirectoryNotFoundException ex) { return new(name, false, "directory-missing", path, ex.GetType().Name); }
        catch (IOException ex) { return new(name, false, "io-error", path, ex.GetType().Name); }
    }

    public QaLaunchResponseV2 Handle(QaLaunchRequest request, DateTimeOffset now, string? rawJson = null)
    {
        if (preparation.HasUnresolvedExecution) return Reject(request, "cpv-preparation-unresolved");
        if (!identity.User.Equals(options.ExpectedUser, StringComparison.OrdinalIgnoreCase) || identity.Sid != options.ExpectedUserSid) return Reject(request, "wrong-agent-identity");
        if (!identity.Interactive) return Reject(request, "non-interactive-session");
        if (!QaLaunchPolicy.IsValidRequest(request, now)) return Reject(request, "request-invalid");
        if (!ledger.TryReserve(request, now)) return Reject(request, "request-replayed");
        if (!QaLaunchPolicy.CanonicalRequestSha256(rawJson ?? JsonSerializer.Serialize(request, QaLaunchPolicy.JsonOptions)).Equals(request.RequestSha256, StringComparison.OrdinalIgnoreCase)) return Reject(request, "request-hash-mismatch");
        if (!IsUnder(request.RequestPath, options.RuntimeRoot) || !IsUnder(request.ModelPath, options.RuntimeRoot)) return Reject(request, "request-root-invalid");
        if (!IsUnder(request.ManifestPath, options.QaProfileRoot)) return Reject(request, "manifest-boundary-invalid");
        if (!File.Exists(request.ModelPath) || !File.Exists(request.ManifestPath)) return Reject(request, "artifact-unavailable");
        if (!Hash(request.ModelPath).Equals(request.ModelSha256, StringComparison.OrdinalIgnoreCase)) return Reject(request, "model-hash-mismatch");
        if (!Hash(request.ManifestPath).Equals(request.ManifestSha256, StringComparison.OrdinalIgnoreCase)) return Reject(request, "manifest-hash-mismatch");
        if (!File.Exists(options.RevitExe)) return Reject(request, "executable-unavailable");
        try
        {
            var child = launcher.Launch(request, options);
            if (!verifier.Verify(child, request, options)) return Reject(request, "process-correlation-failed");
            return new(2, request.Operation, request.RequestId, request.RequestId, true, child.Pid, child.User, child.Sid, child.SessionId, child.LaunchUtc, child.ImagePath, request.RequestPath, request.TaskId, request.WorkflowId, request.QaWorkflowId, request.TestId, request.AttemptId, request.RunId, null);
        }
        catch { return Reject(request, "launcher-failed"); }
    }
    private static bool IsUnder(string path, string root) => Path.GetFullPath(path).StartsWith(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    private static string Hash(string path) => Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(path)));
    private static QaLaunchResponseV2 Reject(QaLaunchRequest r, string code) => new(2, QaLaunchPolicy.Operation, r?.RequestId ?? "", r?.RequestId ?? "", false, null, null, null, null, null, null, r?.RequestPath, r?.TaskId, r?.WorkflowId, r?.QaWorkflowId, r?.TestId, r?.AttemptId, r?.RunId, code);
    private static QaStageResponse StageReject(QaStageRequest? r, string code, string? message = null) => new(1, QaLaunchPolicy.StageOperation, r?.RequestId ?? "", false, r?.CandidateCommit, r?.ExpectedCandidateSha256, r?.QaWorkflowId, r?.TestId, null, null, false, null, code, message);
}
