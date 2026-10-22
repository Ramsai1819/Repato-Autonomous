using System.Security.Cryptography;
using System.Text.Json;
using System.Xml;

namespace Repato.QaLaunchAgent;

/// <summary>Independent native envelope for the RCP runner. CPV schema 2 is intentionally unchanged.</summary>
public sealed record RcpQaLaunchRequest(
    int SchemaVersion, string Operation, string RequestId, string RequestSha256,
    string TaskId, string WorkflowId, string QaWorkflowId, string TestId,
    string AttemptId, string RunId, string ClaimId, string RequestPath,
    string RunnerRequestFileSha256, string ModelPath, string ModelSha256,
    string FixtureId, string FixtureSha256, string FixtureEvidencePath, string FixtureEvidenceSha256,
    string CandidatePath, string CandidateSha256, string SupportArtifactPath, string SupportArtifactSha256,
    string ManifestPath, string ManifestSha256, string IsolationPolicyPath, string IsolationPolicySha256,
    DateTimeOffset ExpiresUtc);

public sealed record RcpQaLaunchResponse(int SchemaVersion, string Operation, string RequestId,
    string TaskId, string WorkflowId, string QaWorkflowId, string TestId, string AttemptId,
    string RunId, string ClaimId, bool? Accepted, string Disposition, int? Pid, string? User, string? Sid,
    int? SessionId, DateTimeOffset? LaunchUtc, string? FailureCode);

public sealed record RcpQaLaunchRoots(string RuntimeRoot, string CandidateRoot, string ManifestRoot,
    string IsolationRoot, string ExpectedUser, string ExpectedSid);
public sealed record RcpChildLaunchResult(int Pid, string User, string Sid, int SessionId, string ImagePath, DateTimeOffset LaunchUtc);
public interface IRcpChildProcessLauncher { RcpChildLaunchResult Launch(RcpQaLaunchRequest request, string revitExe); }
public interface IRcpChildProcessVerifier { bool Verify(RcpChildLaunchResult result, RcpQaLaunchRequest request, string revitExe, string expectedUser, string expectedSid, int currentSession); }

public sealed class RevitRcpChildProcessLauncher : IRcpChildProcessLauncher
{
    public RcpChildLaunchResult Launch(RcpQaLaunchRequest request, string revitExe)
    {
        if (!File.Exists(revitExe)) throw new FileNotFoundException("Configured Revit executable is unavailable.", revitExe);
        var start = new System.Diagnostics.ProcessStartInfo(revitExe) { UseShellExecute = false, WorkingDirectory = Path.GetDirectoryName(revitExe)! };
        foreach (string key in start.Environment.Keys.Where(key => key.StartsWith("REPATO_QA_", StringComparison.OrdinalIgnoreCase)).ToArray()) start.Environment.Remove(key);
        start.Environment[RcpQaLaunchPolicy.RequestEnvironmentVariable] = request.RequestPath;
        using var process = System.Diagnostics.Process.Start(start) ?? throw new InvalidOperationException("Revit process creation failed.");
        var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
        return new(process.Id, identity.Name, identity.User?.Value ?? "", process.SessionId, revitExe, DateTimeOffset.UtcNow);
    }
}

public sealed class StrictRcpChildProcessVerifier : IRcpChildProcessVerifier
{
    public bool Verify(RcpChildLaunchResult result, RcpQaLaunchRequest request, string revitExe, string expectedUser, string expectedSid, int currentSession) =>
        result.Pid > 0 && result.User.Equals(expectedUser, StringComparison.OrdinalIgnoreCase) &&
        result.Sid.Equals(expectedSid, StringComparison.OrdinalIgnoreCase) && result.SessionId == currentSession &&
        Path.GetFullPath(result.ImagePath).Equals(Path.GetFullPath(revitExe), StringComparison.OrdinalIgnoreCase);
}

public static class RcpQaLaunchPolicy
{
    public const int SchemaVersion = 1;
    public const string Operation = "launch-revit-rcp-qa-v1";
    public const string ToolId = "create-rcp-views-v1";
    public const string RunnerRequestOperation = "create-rcp-views-qa";
    public const string RequestEnvironmentVariable = "REPATO_QA_CREATE_RCP_VIEWS_REQUEST";

    public static string CanonicalSha256(string json)
    {
        using var doc = JsonDocument.Parse(json);
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            foreach (var property in doc.RootElement.EnumerateObject().OrderBy(p => p.Name, StringComparer.Ordinal))
            {
                writer.WritePropertyName(property.Name);
                if (property.Name.Equals("requestSha256", StringComparison.OrdinalIgnoreCase)) writer.WriteStringValue(new string('0', 64));
                else property.Value.WriteTo(writer);
            }
            writer.WriteEndObject();
        }
        return Convert.ToHexString(SHA256.HashData(stream.ToArray()));
    }

    public static void Validate(RcpQaLaunchRequest request, string rawJson, RcpQaLaunchRoots roots,
        ToolQaDescriptorBinding descriptor, DateTimeOffset now, string currentUser, string currentSid, bool interactive)
    {
        if (request.SchemaVersion != SchemaVersion || request.Operation != Operation ||
            request.QaWorkflowId != ToolId || request.TestId != descriptor.TestId || descriptor.ToolId != ToolId ||
            descriptor.RequestSchemaVersion != 1 || descriptor.RequestOperation != RunnerRequestOperation ||
            !Guid.TryParseExact(request.RequestId, "N", out _) || !Guid.TryParseExact(request.AttemptId, "N", out _) ||
            !Guid.TryParseExact(request.RunId, "N", out _) || !Guid.TryParseExact(request.ClaimId, "N", out _) ||
            !Guid.TryParseExact(request.WorkflowId, "N", out _) || string.IsNullOrWhiteSpace(request.TaskId) ||
            request.ExpiresUtc <= now || !Hash(request.RequestSha256) || !interactive ||
            !currentUser.Equals(roots.ExpectedUser, StringComparison.OrdinalIgnoreCase) ||
            !currentSid.Equals(roots.ExpectedSid, StringComparison.OrdinalIgnoreCase) ||
            !CanonicalSha256(rawJson).Equals(request.RequestSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("RCP native request identity, schema, or expiry is invalid.");

        Check(request.RequestPath, roots.RuntimeRoot, request.RunnerRequestFileSha256, ".json");
        Check(request.ModelPath, roots.RuntimeRoot, request.ModelSha256, ".rvt");
        Check(request.FixtureEvidencePath, roots.RuntimeRoot, request.FixtureEvidenceSha256, ".json");
        Check(request.CandidatePath, roots.CandidateRoot, request.CandidateSha256);
        Check(request.SupportArtifactPath, roots.CandidateRoot, request.SupportArtifactSha256);
        if (!Path.GetFileName(request.CandidatePath).Equals("Repato.RcpQaRunner.dll", StringComparison.Ordinal) ||
            !Path.GetFileName(request.SupportArtifactPath).Equals("Repato.Revit.dll", StringComparison.Ordinal))
            throw new InvalidDataException("RCP runner/support artifacts are not the explicitly registered files.");
        Check(request.ManifestPath, roots.ManifestRoot, request.ManifestSha256);
        if (!Path.GetFileName(request.ManifestPath).Equals(descriptor.ManifestFile, StringComparison.Ordinal))
            throw new InvalidDataException("RCP manifest filename does not match the registered runner.");
        VerifyManifest(request.ManifestPath, request.CandidatePath, descriptor.RunnerIdentity);
        Check(request.IsolationPolicyPath, roots.IsolationRoot, request.IsolationPolicySha256);
        VerifyIsolationPolicy(request.IsolationPolicyPath);
        if (string.IsNullOrWhiteSpace(request.FixtureId) || !Hash(request.FixtureSha256))
            throw new InvalidDataException("RCP fixture identity or source hash is invalid.");
        ValidateRunnerRequestCorrelation(request);
    }

    private static void VerifyManifest(string manifestPath, string candidatePath, string runnerIdentity)
    {
        var xml = new XmlDocument { XmlResolver = null };
        xml.Load(manifestPath);
        var addin = xml.SelectSingleNode("/RevitAddIns/AddIn[@Type='Application']") as XmlElement
            ?? throw new InvalidDataException("RCP manifest has no application entry.");
        if (addin.SelectSingleNode("FullClassName")?.InnerText != runnerIdentity)
            throw new InvalidDataException("RCP manifest runner identity mismatch.");
        string assembly = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(manifestPath)!, addin.SelectSingleNode("Assembly")?.InnerText ?? ""));
        if (!assembly.Equals(Path.GetFullPath(candidatePath), StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("RCP manifest does not bind the validated candidate assembly.");
    }

    private static void VerifyIsolationPolicy(string policyPath)
    {
        using var policy = JsonDocument.Parse(File.ReadAllText(policyPath));
        var root = policy.RootElement;
        if (!root.TryGetProperty("schemaVersion", out var version) || version.GetInt32() != 1 ||
            !root.TryGetProperty("machineWideRoot", out var machineRoot) || string.IsNullOrWhiteSpace(machineRoot.GetString()) ||
            !root.TryGetProperty("approvedMachineWideManifests", out var manifests) || manifests.ValueKind != JsonValueKind.Array)
            throw new InvalidDataException("RCP isolation policy schema is invalid.");
        foreach (var item in manifests.EnumerateArray())
            if (!item.TryGetProperty("path", out var path) || path.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(path.GetString()) || !Path.IsPathFullyQualified(path.GetString()!) ||
                !item.TryGetProperty("sha256", out var hash) || !Hash(hash.GetString()) ||
                !item.TryGetProperty("reviewReason", out var reason) || string.IsNullOrWhiteSpace(reason.GetString()))
                throw new InvalidDataException("RCP isolation policy contains an invalid allowlist entry.");
    }

    private static void ValidateRunnerRequestCorrelation(RcpQaLaunchRequest outer)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(outer.RequestPath));
        var root = document.RootElement;
        string S(string name) => root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()! : throw new InvalidDataException("RCP runner request is missing " + name + ".");
        int I(string name) => root.TryGetProperty(name, out var value) && value.TryGetInt32(out int number)
            ? number : throw new InvalidDataException("RCP runner request is missing " + name + ".");
        if (I("schemaVersion") != 1 || S("operation") != RunnerRequestOperation || S("requestId") != outer.RequestId ||
            S("requestPath") != outer.RequestPath || S("taskId") != outer.TaskId || S("workflowId") != outer.WorkflowId ||
            S("qaWorkflowId") != outer.QaWorkflowId || S("testId") != outer.TestId || S("attemptId") != outer.AttemptId ||
            S("runId") != outer.RunId || S("claimId") != outer.ClaimId || S("modelPath") != outer.ModelPath ||
            !S("modelSha256").Equals(outer.ModelSha256, StringComparison.OrdinalIgnoreCase) ||
            S("fixtureId") != outer.FixtureId || !S("fixtureSha256").Equals(outer.FixtureSha256, StringComparison.OrdinalIgnoreCase) ||
            S("manifestPath") != outer.ManifestPath || !S("manifestSha256").Equals(outer.ManifestSha256, StringComparison.OrdinalIgnoreCase) ||
            !S("artifactSha256").Equals(outer.CandidateSha256, StringComparison.OrdinalIgnoreCase) ||
            !S("supportArtifactSha256").Equals(outer.SupportArtifactSha256, StringComparison.OrdinalIgnoreCase) ||
            DateTimeOffset.Parse(S("expiresUtc")) != outer.ExpiresUtc ||
            !S("requestSha256").Equals(RunnerRequestCanonicalSha256(document.RootElement), StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("RCP outer request does not correlate to the authenticated runner request.");
    }

    private static string RunnerRequestCanonicalSha256(JsonElement root)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            foreach (var property in root.EnumerateObject().OrderBy(p => p.Name, StringComparer.Ordinal))
            {
                writer.WritePropertyName(property.Name);
                if (property.Name.Equals("requestSha256", StringComparison.OrdinalIgnoreCase)) writer.WriteStringValue(new string('0', 64));
                else property.Value.WriteTo(writer);
            }
            writer.WriteEndObject();
        }
        return Convert.ToHexString(SHA256.HashData(stream.ToArray()));
    }

    /// <summary>Minimal immutable projection supplied only by the embedded, validated tool registry.</summary>
    public sealed record ToolQaDescriptorBinding(string ToolId, string TestId, string RunnerIdentity, string ManifestFile,
        int RequestSchemaVersion, string RequestOperation);

    private static void Check(string path, string root, string expectedHash, string? extension = null)
    {
        if (!Path.IsPathFullyQualified(path) || !Path.IsPathFullyQualified(root) ||
            !Under(Path.GetFullPath(path), Path.GetFullPath(root)) || !File.Exists(path) || !Hash(expectedHash) ||
            (extension is not null && !Path.GetExtension(path).Equals(extension, StringComparison.OrdinalIgnoreCase)) ||
            !Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))).Equals(expectedHash, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("RCP request path, root, extension, or artifact hash is invalid.");
    }

    private static bool Under(string path, string root) => path.StartsWith(root.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    private static bool Hash(string? value) => value is { Length: 64 } && value.All(Uri.IsHexDigit);
}
