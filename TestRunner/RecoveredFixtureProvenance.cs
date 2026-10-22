using System.IO;
using System.Security.Cryptography;
using System.Text.Json;

namespace Repato.Revit.TestRunner;

/// <summary>Read-only selection of explicitly request-bound recovered evidence.</summary>
internal static class RecoveredFixtureProvenance
{
    internal static JsonElement Resolve(string modelPath, CreatePlanViewsRequest? request)
    {
        string historicalPath = modelPath + ".fixture.json";
        using var original = JsonDocument.Parse(File.ReadAllText(historicalPath));
        JsonElement historical = original.RootElement;
        if (request is null || request.RecoveredProvenancePath.Length == 0)
            return historical.Clone();
        if (request.ExpiresUtc <= DateTimeOffset.UtcNow)
            throw new InvalidDataException("Recovered evidence cannot authorize an expired native request.");
        if (historical.ValueKind != JsonValueKind.Object || historical.EnumerateObject().Count() != 2 ||
            historical.GetProperty("fixtureId").GetString() != "CreatePlanViewsEmpty" ||
            !Same(historical.GetProperty("sourceSha256").GetString(), request.FixtureSha256))
            throw new InvalidDataException("Companion selection requires the exact historical source-only CPV schema.");
        var preparation = CreatePlanViewsFixturePreparationRequest.Parse(File.ReadAllText(request.FixturePreparationRequestPath),
            request.FixturePreparationRequestPath, allowExpiredEvidence: true);
        string expectedHistorical = preparation.ModelPath + ".fixture.json";
        string expectedCompanion = preparation.ModelPath + ".recovered.fixture.json";
        if (!PathEquals(request.RecoveredProvenancePath, expectedCompanion) ||
            !Same(Hash(expectedHistorical), Hash(historicalPath)) ||
            !Same(Hash(expectedCompanion), request.RecoveredProvenanceSha256))
            throw new InvalidDataException("Recovered companion or copied historical evidence hash/path mismatch.");
        using var recovered = JsonDocument.Parse(File.ReadAllText(expectedCompanion));
        JsonElement root = recovered.RootElement;
        string Text(string name) => root.GetProperty(name).GetString() ?? "";
        if (root.GetProperty("schemaVersion").GetInt32() != 1 || !root.GetProperty("recoveredFromOutcomeUnknown").GetBoolean() ||
            Text("taskId") != request.TaskId || Text("workflowId") != request.WorkflowId ||
            Text("fixtureId") != "CreatePlanViewsEmpty" ||
            !PathEquals(Text("historicalSidecarPath"), expectedHistorical) || !Same(Text("historicalSidecarSha256"), Hash(expectedHistorical)) ||
            !Same(Text("sourceSha256"), request.FixtureSha256) || !Same(Text("preparedModelSha256"), request.ModelSha256) ||
            !PathEquals(Text("fixturePreparationRequestPath"), request.FixturePreparationRequestPath) ||
            !PathEquals(Text("fixturePreparationResultPath"), request.FixturePreparationResultPath) ||
            !Same(Text("fixturePreparationRequestSha256"), request.FixturePreparationRequestSha256) ||
            !Same(Text("fixturePreparationResultSha256"), request.FixturePreparationResultSha256) ||
            Text("fixturePreparationAttemptId") != request.FixturePreparationAttemptId ||
            Text("fixturePreparationRunId") != request.FixturePreparationRunId ||
            preparation.TaskId != request.TaskId || preparation.WorkflowId != request.WorkflowId ||
            preparation.AttemptId != request.FixturePreparationAttemptId || preparation.RunId != request.FixturePreparationRunId ||
            !Same(Hash(request.FixturePreparationRequestPath), request.FixturePreparationRequestSha256) ||
            !Same(Hash(request.FixturePreparationResultPath), request.FixturePreparationResultSha256))
            throw new InvalidDataException("Recovered provenance does not match authenticated native request evidence.");
        foreach (string key in new[] { "requestId", "recoveryApprovalId" })
            if (!Guid.TryParseExact(Text(key), "N", out _)) throw new InvalidDataException("Missing recovered identity: " + key);
        foreach (string key in new[] { "requestSha256", "approvalBindingHash", "originalReceiptSha256", "originalFailureReceiptSha256", "activeMarkerSha256", "failureEvidenceSha256" })
            if (Text(key).Length != 64 || !Text(key).All(Uri.IsHexDigit)) throw new InvalidDataException("Invalid recovered evidence hash: " + key);
        if (!Same(Text("originalReceiptSha256"), Text("originalFailureReceiptSha256")))
            throw new InvalidDataException("Original recovery receipt bindings disagree.");
        return root.Clone();
    }

    internal static bool PathEquals(string a, string b) => Path.GetFullPath(a).Equals(Path.GetFullPath(b), StringComparison.OrdinalIgnoreCase);
    private static bool Same(string? a, string? b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    private static string Hash(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
}
