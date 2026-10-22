using System.Security.Cryptography;
using System.Text.Json;
using System.Xml;
using Repato.ToolQaFramework;

namespace Repato.RcpQaRunner;

public sealed record RcpQaRequest(
    int SchemaVersion, string Operation, string RequestId, string RequestSha256, string TaskId, string WorkflowId,
    string QaWorkflowId, string TestId, string AttemptId, string RunId, string ClaimId,
    string RequestPath, string ModelPath, string ModelSha256, string FixtureId, string FixtureSha256,
    string ManifestPath, string ManifestSha256, string ArtifactSha256, string SupportArtifactSha256, DateTimeOffset ExpiresUtc,
    string[] LevelNames, string ViewTypeName, string NameSuffix)
{
    public const string Test = "create-rcp-views-v1";
    public const string RunnerIdentity = "Repato.RcpQaRunner.RcpQaApplication";

    public static RcpQaRequest Parse(string json, string actualPath, DateTimeOffset? now = null)
    {
        var request = JsonSerializer.Deserialize<RcpQaRequest>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
            ?? throw new InvalidDataException("RCP QA request is empty.");
        if (request.SchemaVersion != 1 || request.Operation != "create-rcp-views-qa" ||
            request.QaWorkflowId != Test || request.TestId != Test ||
            !Guid.TryParseExact(request.RequestId, "N", out _) || !Guid.TryParseExact(request.AttemptId, "N", out _) ||
            !Guid.TryParseExact(request.RunId, "N", out _) || !Guid.TryParseExact(request.ClaimId, "N", out _) ||
            string.IsNullOrWhiteSpace(request.TaskId) || !Guid.TryParseExact(request.WorkflowId, "N", out _) ||
            !Path.IsPathFullyQualified(actualPath) || !Path.GetFullPath(actualPath).Equals(Path.GetFullPath(request.RequestPath), StringComparison.OrdinalIgnoreCase) ||
            !Path.IsPathFullyQualified(request.ModelPath) ||
            !Path.GetExtension(request.ModelPath).Equals(".rvt", StringComparison.OrdinalIgnoreCase) ||
            !Path.IsPathFullyQualified(request.ManifestPath) || request.LevelNames.Length is < 1 or > 20 ||
            request.LevelNames.Any(string.IsNullOrWhiteSpace) || request.LevelNames.Distinct(StringComparer.Ordinal).Count() != request.LevelNames.Length ||
            request.ViewTypeName != "Ceiling Plan" || request.NameSuffix != "RCP" ||
            !Hash(request.RequestSha256) || !CanonicalSha256(json).Equals(request.RequestSha256, StringComparison.OrdinalIgnoreCase) ||
            !Hash(request.ModelSha256) || !Hash(request.FixtureSha256) || !Hash(request.ManifestSha256) || !Hash(request.ArtifactSha256) || !Hash(request.SupportArtifactSha256) ||
            request.ExpiresUtc <= (now ?? DateTimeOffset.UtcNow))
            throw new InvalidDataException("RCP QA request identity, expiry, paths, inputs, or hashes are invalid.");
        ToolQaRegistry.LoadBuiltIn().ValidateRunner(Test, RunnerIdentity);
        return request;
    }

    private static bool Hash(string value) => value.Length == 64 && value.All(Uri.IsHexDigit);

    public static string CanonicalSha256(string json)
    {
        using var document = JsonDocument.Parse(json);
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            foreach (JsonProperty property in document.RootElement.EnumerateObject().OrderBy(item => item.Name, StringComparer.Ordinal))
            {
                writer.WritePropertyName(property.Name);
                if (property.Name.Equals("requestSha256", StringComparison.OrdinalIgnoreCase)) writer.WriteStringValue(new string('0', 64));
                else property.Value.WriteTo(writer);
            }
            writer.WriteEndObject();
        }
        return Convert.ToHexString(SHA256.HashData(stream.ToArray()));
    }
}

public sealed record RcpQaReport(
    int SchemaVersion, string RequestId, string RequestSha256, string TaskId, string WorkflowId, string QaWorkflowId,
    string TestId, string AttemptId, string RunId, string ClaimId, string Status,
    string FixtureId, string FixtureSha256, string ModelSha256, string ArtifactSha256, string SupportArtifactSha256,
    string ViewTypeName, string[] ExpectedViewNames, string[] CreatedViewNames, RcpCreatedViewEvidence[] CreatedViews,
    string RollbackStatus, bool BaselineRestored, string CleanupStatus, string[] Errors, string[] Assertions,
    DateTimeOffset FinishedUtc);

public sealed record RcpCreatedViewEvidence(string ElementId, string Name, string ViewFamily, string ViewFamilyType, string LevelName, string LevelId);

public sealed record RcpQaReceipt(
    int SchemaVersion, string RequestId, string RequestSha256, string TaskId, string WorkflowId, string QaWorkflowId,
    string TestId, string AttemptId, string RunId, string ClaimId, string Status,
    string ReportPath, string ReportSha256, string ArtifactSha256, string SupportArtifactSha256);

public static class RcpQaResultContract
{
    public static bool IsPassing(RcpQaRequest request, RcpQaReceipt receipt, RcpQaReport report, string expectedArtifactSha256)
    {
        try { return receipt.SchemaVersion == 1 && report.SchemaVersion == 1 &&
            Same(request, receipt.RequestId, receipt.RequestSha256, receipt.TaskId, receipt.WorkflowId, receipt.QaWorkflowId, receipt.TestId, receipt.AttemptId, receipt.RunId, receipt.ClaimId) &&
            Same(request, report.RequestId, report.RequestSha256, report.TaskId, report.WorkflowId, report.QaWorkflowId, report.TestId, report.AttemptId, report.RunId, report.ClaimId) &&
            receipt.Status == "Passed" && report.Status == "Passed" && report.RollbackStatus == "RolledBack" && report.BaselineRestored && report.CleanupStatus == "Closed" &&
            report.Errors.Length == 0 && report.Assertions.Length > 0 && report.Assertions.All(value => value.StartsWith("PASS:", StringComparison.Ordinal)) &&
            report.FixtureId == request.FixtureId && report.FixtureSha256.Equals(request.FixtureSha256, StringComparison.OrdinalIgnoreCase) &&
            report.ModelSha256.Equals(request.ModelSha256, StringComparison.OrdinalIgnoreCase) &&
            report.ArtifactSha256.Equals(expectedArtifactSha256, StringComparison.OrdinalIgnoreCase) &&
            receipt.ArtifactSha256.Equals(expectedArtifactSha256, StringComparison.OrdinalIgnoreCase) &&
            report.SupportArtifactSha256.Equals(request.SupportArtifactSha256, StringComparison.OrdinalIgnoreCase) &&
            receipt.SupportArtifactSha256.Equals(request.SupportArtifactSha256, StringComparison.OrdinalIgnoreCase) &&
            report.ViewTypeName == request.ViewTypeName &&
            report.CreatedViews.Length == request.LevelNames.Length &&
            report.CreatedViews.Select(view => view.ElementId).Distinct(StringComparer.Ordinal).Count() == request.LevelNames.Length &&
            report.CreatedViews.Select(view => view.LevelId).Distinct(StringComparer.Ordinal).Count() == request.LevelNames.Length &&
            report.CreatedViews.Select((view, index) => view.Name == request.LevelNames[index] + " - RCP" &&
                view.LevelName == request.LevelNames[index] && view.ViewFamily == "CeilingPlan" &&
                view.ViewFamilyType == request.ViewTypeName && !string.IsNullOrWhiteSpace(view.ElementId) &&
                !string.IsNullOrWhiteSpace(view.LevelId)).All(valid => valid) &&
            receipt.ReportSha256.Equals(SHA256.HashData(File.ReadAllBytes(receipt.ReportPath)).ToHex(), StringComparison.OrdinalIgnoreCase) &&
            report.ExpectedViewNames.SequenceEqual(request.LevelNames.Select(name => name + " - RCP"), StringComparer.Ordinal) &&
            report.CreatedViewNames.SequenceEqual(report.ExpectedViewNames, StringComparer.Ordinal);
        } catch { return false; }
    }

    private static bool Same(RcpQaRequest request, string requestId, string requestSha256, string taskId, string workflowId, string qaWorkflowId,
        string testId, string attemptId, string runId, string claimId) =>
        request.RequestId == requestId && request.RequestSha256.Equals(requestSha256, StringComparison.OrdinalIgnoreCase) && request.TaskId == taskId && request.WorkflowId == workflowId &&
        request.QaWorkflowId == qaWorkflowId && request.TestId == testId && request.AttemptId == attemptId &&
        request.RunId == runId && request.ClaimId == claimId;

    private static string ToHex(this byte[] bytes) => Convert.ToHexString(bytes);
}

public static class RcpQaStartupContract
{
    public static void Validate(string revitVersion, string windowsUser, int openDocumentCount, string requestPath)
    {
        if (revitVersion != "2025" || !windowsUser.Equals("RepatoQA", StringComparison.OrdinalIgnoreCase) ||
            openDocumentCount != 0 || string.IsNullOrWhiteSpace(requestPath))
            throw new InvalidOperationException("RCP runner startup identity/session/document/request preconditions failed.");
    }
}

public static class RcpQaManifestContract
{
    public static void Verify(string manifestPath, string expectedSha256, string loadedAssemblyPath)
    {
        if (!File.Exists(manifestPath) || !Hash(File.ReadAllBytes(manifestPath)).Equals(expectedSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("RCP QA manifest is missing or its hash mismatches.");
        var xml = new XmlDocument { XmlResolver = null };
        xml.Load(manifestPath);
        XmlElement application = xml.SelectSingleNode("/RevitAddIns/AddIn[@Type='Application']") as XmlElement
            ?? throw new InvalidDataException("RCP manifest has no application entry.");
        if (application.SelectSingleNode("FullClassName")?.InnerText != "Repato.RcpQaRunner.RcpQaApplication")
            throw new InvalidDataException("RCP manifest runner class binding mismatch.");
        string assemblyPath = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(manifestPath)!, application.SelectSingleNode("Assembly")?.InnerText ?? ""));
        if (!assemblyPath.Equals(Path.GetFullPath(loadedAssemblyPath), StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("RCP manifest does not bind the loaded candidate assembly.");
    }

    private static string Hash(byte[] value) => Convert.ToHexString(SHA256.HashData(value));
}
