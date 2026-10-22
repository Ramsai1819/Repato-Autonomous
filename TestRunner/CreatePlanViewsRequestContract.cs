using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using Repato.ToolQaFramework;

namespace Repato.Revit.TestRunner;

internal sealed record CreatePlanViewsRequest(
    string RequestId, string TaskId, string WorkflowId, string QaWorkflowId,
    string TestId, string AttemptId, string RunId, string ClaimId,
    string RequestPath, string RequestSha256, string ModelPath, string ModelSha256,
    string FixtureSha256, string FixturePreparationRequestPath, string FixturePreparationRequestSha256,
    string FixturePreparationResultPath, string FixturePreparationResultSha256,
    string FixturePreparationAttemptId, string FixturePreparationRunId,
    string ManifestPath, string ManifestSha256, DateTimeOffset ExpiresUtc,
    string RecoveredProvenancePath = "", string RecoveredProvenanceSha256 = "")
{
    internal const string Test = "create-plan-views-v1";
    internal const string RunnerIdentity = "Repato.Revit.TestRunner.CreatePlanViewsQaApplication";

    internal static CreatePlanViewsRequest Parse(string json, string actualPath)
    {
        using var document = JsonDocument.Parse(json);
        JsonElement root = document.RootElement;
        string Text(string name) => root.TryGetProperty(name, out JsonElement value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? "" : throw new InvalidDataException("Request field is missing or malformed: " + name);
        int version = root.TryGetProperty("schemaVersion", out JsonElement schema) && schema.TryGetInt32(out int parsed) ? parsed : 0;
        DateTimeOffset expires = root.TryGetProperty("expiresUtc", out JsonElement expiry) && expiry.TryGetDateTimeOffset(out DateTimeOffset parsedExpiry)
            ? parsedExpiry : throw new InvalidDataException("Request field is missing or malformed: expiresUtc");
        var request = new CreatePlanViewsRequest(Text("requestId"), Text("taskId"), Text("workflowId"), Text("qaWorkflowId"),
            Text("testId"), Text("attemptId"), Text("runId"), Text("claimId"), Text("requestPath"), Text("requestSha256"),
            Text("modelPath"), Text("modelSha256"), Text("fixtureSha256"),
            Text("fixturePreparationRequestPath"), Text("fixturePreparationRequestSha256"),
            Text("fixturePreparationResultPath"), Text("fixturePreparationResultSha256"),
            Text("fixturePreparationAttemptId"), Text("fixturePreparationRunId"),
            Text("manifestPath"), Text("manifestSha256"), expires,
            root.TryGetProperty("recoveredProvenancePath", out _) ? Text("recoveredProvenancePath") : "",
            root.TryGetProperty("recoveredProvenanceSha256", out _) ? Text("recoveredProvenanceSha256") : "");
        if ((request.RecoveredProvenancePath.Length != 0 || request.RecoveredProvenanceSha256.Length != 0) &&
            (!Path.IsPathFullyQualified(request.RecoveredProvenancePath) || !IsHash(request.RecoveredProvenanceSha256)))
            throw new InvalidDataException("Recovered provenance requires a fully qualified path and bound SHA-256.");
        if (version != 2 || root.GetProperty("operation").GetString() != "launch-revit-qa" ||
            !Guid.TryParseExact(request.RequestId, "N", out _) || !Guid.TryParseExact(request.AttemptId, "N", out _) ||
            !Guid.TryParseExact(request.RunId, "N", out _) || !Guid.TryParseExact(request.ClaimId, "N", out _) ||
            request.QaWorkflowId != Test || request.TestId != Test || string.IsNullOrWhiteSpace(request.TaskId) ||
            string.IsNullOrWhiteSpace(request.WorkflowId) || !IsHash(request.RequestSha256) || !IsHash(request.ModelSha256) ||
            !IsHash(request.FixtureSha256) || !IsHash(request.FixturePreparationRequestSha256) || !IsHash(request.FixturePreparationResultSha256) ||
            !Guid.TryParseExact(request.FixturePreparationAttemptId, "N", out _) || !Guid.TryParseExact(request.FixturePreparationRunId, "N", out _) ||
            !Path.IsPathFullyQualified(request.FixturePreparationRequestPath) || !Path.IsPathFullyQualified(request.FixturePreparationResultPath) ||
            !IsHash(request.ManifestSha256) || !Path.GetFullPath(request.RequestPath).Equals(Path.GetFullPath(actualPath), StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Canonical Create Plan Views launch request is invalid or not bound to this file.");
        if (!CanonicalSha256(json).Equals(request.RequestSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Canonical request SHA-256 mismatch.");
        ToolQaRegistry.LoadBuiltIn().ValidateRunner(Test, RunnerIdentity);
        return request;
    }

    internal static string CanonicalSha256(string json)
    {
        using var document = JsonDocument.Parse(json);
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            foreach (JsonProperty property in document.RootElement.EnumerateObject().OrderBy(item => item.Name, StringComparer.Ordinal))
            {
                writer.WritePropertyName(property.Name);
                if (property.Name.Equals("requestSha256", StringComparison.OrdinalIgnoreCase))
                    writer.WriteStringValue(new string('0', 64));
                else property.Value.WriteTo(writer);
            }
            writer.WriteEndObject();
        }
        return Convert.ToHexString(SHA256.HashData(stream.ToArray()));
    }

    private static bool IsHash(string value) => value.Length == 64 && value.All(Uri.IsHexDigit);
}
