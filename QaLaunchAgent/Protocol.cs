using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Repato.QaLaunchAgent;

public sealed record QaLaunchRequest(
    int SchemaVersion, string Operation, string RequestId, string TaskId,
    string WorkflowId, string QaWorkflowId, string TestId, string AttemptId,
    string RunId, string ClaimId, string RequestPath, string RequestSha256,
    string ModelPath, string ModelSha256, string ManifestPath,
    string ManifestSha256, DateTimeOffset ExpiresUtc, string? RecoveredProvenancePath = null, string? RecoveredProvenanceSha256 = null);

public sealed record QaLaunchResponse(
    int SchemaVersion, string RequestId, bool Accepted, int? Pid, string? User,
    int? SessionId, DateTimeOffset? LaunchUtc, string? ImagePath,
    string? RequestPath, string? RunId, string? FailureCode);

public sealed record QaLaunchResponseV2(
    int SchemaVersion, string Operation, string RequestId, string CorrelationId,
    bool Accepted, int? Pid, string? User, string? Sid, int? SessionId,
    DateTimeOffset? LaunchUtc, string? ImagePath, string? RequestPath,
    string? TaskId, string? WorkflowId, string? QaWorkflowId, string? TestId,
    string? AttemptId, string? RunId, string? FailureCode);

public sealed record QaHealthRequest(int SchemaVersion, string Operation);
public sealed record QaHealthResponse(int SchemaVersion, string Operation, bool Ready, string User, string Sid, int SessionId, bool Interactive, string? FailureCode);
public sealed record QaPreflightRequest(int SchemaVersion, string Operation, string? TaskId = null, string? WorkflowId = null,
    string? QaWorkflowId = null, string? TestId = null, string? CandidateCommit = null,
    string? ExpectedCandidateSha256 = null, QaCandidateEvidence? CandidateEvidence = null);
public sealed record QaPreflightCheck(string Name, bool Passed, string Status, string? Path, string? Detail);
public sealed record QaPreflightResponse(int SchemaVersion, string Operation, bool Succeeded, string ExecutionIdentity, string QaAddinRoot, string RunnerManifestPath, string ExpectedRunnerManifestSha256, IReadOnlyList<QaPreflightCheck> Checks, string? FailureCode);
public sealed record QaCandidateEvidence(
    int SchemaVersion, string TaskId, string WorkflowId, string QaWorkflowId, string TestId,
    string CandidateSourceCommit, string CandidateDirectory, string CandidateDllPath,
    string CandidateDllSha256, string NeilBuildArtifactSha256, string RunnerManifestPath,
    string RunnerManifestSha256, string CandidateProvenancePath);
public sealed record QaStageRequest(int SchemaVersion, string Operation, string RequestId, string CandidateCommit, string ExpectedCandidateSha256, string QaWorkflowId, string TestId, string? TaskId = null, string? WorkflowId = null, QaCandidateEvidence? CandidateEvidence = null);
public sealed record QaStageResponse(int SchemaVersion, string Operation, string RequestId, bool Succeeded, string? CandidateCommit, string? CandidateSha256, string? QaWorkflowId, string? TestId, string? StagingIdentity, string? QaAddinRoot, bool IsolationPassed, string? ReceiptPath, string? ErrorCode, string? ErrorMessage);
public sealed record QaDeploymentValidationRequest(int SchemaVersion, string Operation, string RequestId, string CandidateCommit, string ExpectedCandidateSha256, string QaWorkflowId, string TestId, string? TaskId = null, string? WorkflowId = null, QaCandidateEvidence? CandidateEvidence = null);
public sealed record QaDeploymentValidationResponse(int SchemaVersion, string Operation, string RequestId, bool Succeeded, string? CandidateCommit, string? CandidateSha256, string? QaWorkflowId, string? TestId, string? ValidationIdentity, string? QaAddinRoot, bool IsolationPassed, string? ErrorCode, string? ErrorMessage, string? RunnerManifestPath = null, string? RunnerManifestSha256 = null, bool? ManifestIntegrityPassed = null);

public static class QaLaunchPolicy
{
    public const int SchemaVersion = 1;
    public const int LaunchSchemaVersion = 2;
    public const string Operation = "launch-revit-qa";
    public const string HealthOperation = "health";
    public const string PreflightOperation = "preflight-readonly";
    public const string StageOperation = "stage-frozen-candidate-for-qa";
    public const string ValidateDeploymentOperation = "validate-qa-deployment";
    public const string ExpectedRunnerManifestPath = @"C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin";
    public const string ExpectedRunnerManifestSha256 = "AF4DBFA78E61524DE7BD3B84178C6B70ED8D29D0A95BA17780826E09BE689D4F";
    public const string ApprovedCandidateRoot = @"C:\Repato-Autonomous\Source\DeploymentCandidates\AgentBuilds";
    public const string ApprovedRunnerManifestRoot = @"C:\Repato-Autonomous\Source\QA";
    public const string ExpectedUser = "RAMSAI\\RepatoQA";
    public const string ExpectedUserSid = "S-1-5-21-1031246752-3872016183-2454652381-1015";
    public const string ClientAccount = ExpectedUser;
    public const string ClientSid = ExpectedUserSid;
    public const string FrozenCandidateCommit = "4f2cbba22ba9f4d6d3176e2d36daf2890bd1849c";
    public const string FrozenCandidateSha256 = "8C3F6EF16790247B9949EADED8FF098B4D95598791011C418D003DAAC0680AB5";
    public const string StagingAdapterPath = @"C:\Repato-Autonomous\Source\AgentOrchestration\Invoke-RepatoQaFrozenCandidateStaging.ps1";
    public const string StagingCandidateDirectory = @"C:\Repato-Autonomous\Worktrees\create-plan-views-buildfix-4f2cbba22ba9\DeploymentCandidates\AgentBuilds\ReleaseCandidate-4f2cbba22ba9";
    public const string LogRoot = @"C:\Users\RepatoQA\AppData\Local\Repato\QaLaunchAgent\Logs";
    public const string RequestEnvironmentVariable = "REPATO_QA_CREATE_PLAN_VIEWS_REQUEST";
    public static readonly string[] AllowedQaWorkflows = ["create-plan-views-v1"];
    public const string RequestSha256Placeholder = "0000000000000000000000000000000000000000000000000000000000000000";
    public static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.General) { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true };
    public static string CanonicalRequestSha256(string json)
    {
        using var document = JsonDocument.Parse(json);
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = false }))
        {
            writer.WriteStartObject();
            foreach (var property in document.RootElement.EnumerateObject().OrderBy(p => p.Name, StringComparer.Ordinal))
            {
                writer.WritePropertyName(property.Name);
                if (property.Name.Equals("requestSha256", StringComparison.OrdinalIgnoreCase)) writer.WriteStringValue(RequestSha256Placeholder);
                else property.Value.WriteTo(writer);
            }
            writer.WriteEndObject();
        }
        return Convert.ToHexString(SHA256.HashData(stream.ToArray()));
    }
    public static bool IsValidCandidateEvidence(QaCandidateEvidence? e, string taskId, string workflowId, string qaWorkflowId, string testId)
    {
        if (e is null || e.SchemaVersion != 1 || string.IsNullOrWhiteSpace(e.TaskId) || string.IsNullOrWhiteSpace(e.WorkflowId) ||
            string.IsNullOrWhiteSpace(e.QaWorkflowId) || string.IsNullOrWhiteSpace(e.TestId) || e.TaskId != taskId || e.WorkflowId != workflowId ||
            e.QaWorkflowId != qaWorkflowId || e.TestId != testId || e.TestId != e.QaWorkflowId || !IsSha256(e.CandidateDllSha256) ||
            !IsSha256(e.NeilBuildArtifactSha256) || !IsSha256(e.RunnerManifestSha256) || !e.CandidateSourceCommit.All(Uri.IsHexDigit) || e.CandidateSourceCommit.Length != 40 ||
            string.IsNullOrWhiteSpace(e.CandidateDirectory) || string.IsNullOrWhiteSpace(e.CandidateDllPath) || string.IsNullOrWhiteSpace(e.RunnerManifestPath) || string.IsNullOrWhiteSpace(e.CandidateProvenancePath) ||
            !e.CandidateDllSha256.Equals(e.NeilBuildArtifactSha256, StringComparison.OrdinalIgnoreCase)) return false;
        try
        {
            var directory = Path.GetFullPath(e.CandidateDirectory); var dll = Path.GetFullPath(e.CandidateDllPath); var provenance = Path.GetFullPath(e.CandidateProvenancePath); var runner = Path.GetFullPath(e.RunnerManifestPath);
            if (!Under(directory, ApprovedCandidateRoot) || !Under(dll, directory) || !Under(provenance, directory) || !Under(runner, ApprovedRunnerManifestRoot) ||
                !File.Exists(dll) || !File.Exists(provenance) || !File.Exists(runner) || Hash(dll) != e.CandidateDllSha256 || Hash(runner) != e.RunnerManifestSha256) return false;
            using var json = JsonDocument.Parse(File.ReadAllText(provenance)); var root = json.RootElement;
            return root.TryGetProperty("SourceCommit", out var source) && source.GetString() == e.CandidateSourceCommit && root.TryGetProperty("FrozenArtifactSha256", out var artifact) && artifact.GetString()?.Equals(e.CandidateDllSha256, StringComparison.OrdinalIgnoreCase) == true;
        }
        catch { return false; }
    }
    public static bool IsValidPreflightRequest(QaPreflightRequest? request)
    {
        if (request is null || request.SchemaVersion != SchemaVersion || request.Operation != PreflightOperation) return false;
        if (request.CandidateEvidence is null)
            return request.TaskId is null && request.WorkflowId is null && request.QaWorkflowId is null && request.TestId is null && request.CandidateCommit is null && request.ExpectedCandidateSha256 is null;
        var evidence = request.CandidateEvidence;
        return request.QaWorkflowId == "create-plan-views-v1" && request.TestId == request.QaWorkflowId &&
            request.CandidateCommit == evidence.CandidateSourceCommit &&
            string.Equals(request.ExpectedCandidateSha256, evidence.CandidateDllSha256, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(evidence.RunnerManifestSha256, ExpectedRunnerManifestSha256, StringComparison.OrdinalIgnoreCase) &&
            IsValidCandidateEvidence(evidence, request.TaskId ?? "", request.WorkflowId ?? "", request.QaWorkflowId, request.TestId);
    }
    private static bool Under(string path, string root) => path.StartsWith(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    private static string Hash(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
    public static bool HasValidDeploymentManifestEvidence(QaDeploymentValidationResponse? response)
    {
        if (response is null || string.IsNullOrWhiteSpace(response.RunnerManifestPath) || response.RunnerManifestSha256 is not { Length: 64 } manifestHash || !IsSha256(manifestHash) || response.ManifestIntegrityPassed is null) return false;
        try { return Path.GetFullPath(response.RunnerManifestPath).Equals(ExpectedRunnerManifestPath, StringComparison.OrdinalIgnoreCase) && manifestHash.Equals(ExpectedRunnerManifestSha256, StringComparison.OrdinalIgnoreCase); }
        catch { return false; }
    }
    public static bool CanPassDeploymentValidation(QaDeploymentValidationResponse? response) =>
        response is { Succeeded: true, ManifestIntegrityPassed: true } && HasValidDeploymentManifestEvidence(response);
    public static bool IsValidRequest(QaLaunchRequest r, DateTimeOffset now) =>
        r is not null && r.SchemaVersion == LaunchSchemaVersion && r.Operation == Operation &&
        Guid.TryParse(r.RequestId, out _) &&
        !string.IsNullOrWhiteSpace(r.TaskId) && !string.IsNullOrWhiteSpace(r.WorkflowId) &&
        !string.IsNullOrWhiteSpace(r.QaWorkflowId) && !string.IsNullOrWhiteSpace(r.TestId) &&
        !string.IsNullOrWhiteSpace(r.AttemptId) && !string.IsNullOrWhiteSpace(r.RunId) &&
        !string.IsNullOrWhiteSpace(r.ClaimId) && !string.IsNullOrWhiteSpace(r.RequestPath) &&
        !string.IsNullOrWhiteSpace(r.ModelPath) && !string.IsNullOrWhiteSpace(r.ManifestPath) &&
        IsSha256(r.RequestSha256) && IsSha256(r.ModelSha256) && IsSha256(r.ManifestSha256) &&
        AllowedQaWorkflows.Contains(r.QaWorkflowId) && r.TestId == r.QaWorkflowId && r.ExpiresUtc > now &&
        IsValidRecoveredProvenanceBinding(r);

    public static bool IsValidRecoveredProvenanceBinding(QaLaunchRequest r)
    {
        if (r.RecoveredProvenancePath is null && r.RecoveredProvenanceSha256 is null) return true;
        if (r.RecoveredProvenancePath != r.ModelPath + ".recovered.fixture.json" || !IsSha256(r.RecoveredProvenanceSha256!)) return false;
        try
        {
            RevitCpvPreparationBoundary.NoLinks(r.RecoveredProvenancePath);
            return Hash(r.RecoveredProvenancePath).Equals(r.RecoveredProvenanceSha256, StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }

    private static bool IsSha256(string value) => value is not null && value.Length == 64 && value.All(Uri.IsHexDigit);
}
