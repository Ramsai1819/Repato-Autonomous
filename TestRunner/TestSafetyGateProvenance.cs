using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Repato.Revit.TestRunner;

/// <summary>
/// Encapsulates the fixture-sidecar provenance validation for both the live Verify path
/// (inside Revit) and synthetic contract tests (outside Revit). This is the testable
/// core of the preparation-aware safety gate.
/// </summary>
internal static class TestSafetyGateProvenance
{
    /// <summary>
    /// Validates fixture provenance from a parsed sidecar JSON against the actual file hashes.
    /// Throws InvalidOperationException on any mismatch.
    /// </summary>
    /// <param name="sidecarJson">Parsed sidecar JSON root element.</param>
    /// <param name="fixtureHash">Actual SHA-256 of the authoritative source fixture file.</param>
    /// <param name="runtimeModelHash">Actual SHA-256 of the runtime model file.</param>
    internal static void Verify(JsonElement sidecarJson, string fixtureHash, string runtimeModelHash,
        CreatePlanViewsRequest? request = null)
    {
        if (sidecarJson.ValueKind != JsonValueKind.Object)
            throw new InvalidOperationException("Fixture provenance sidecar must be a JSON object.");
        string sourceSha256 = sidecarJson.GetProperty("sourceSha256").GetString() ?? "";
        if (!Regex.IsMatch(sourceSha256, @"\A[0-9A-Fa-f]{64}\z"))
            throw new InvalidOperationException("Invalid source SHA-256 in fixture provenance sidecar.");

        bool hasPreparation = sidecarJson.TryGetProperty("preparedModelSha256", out JsonElement preparedElement);
        string preparedModelHash = hasPreparation ? (preparedElement.GetString() ?? "") : "";

        if (hasPreparation)
        {
            if (!Regex.IsMatch(preparedModelHash, @"\A[0-9A-Fa-f]{64}\z"))
                throw new InvalidOperationException("Invalid prepared model hash in fixture provenance sidecar.");
            if (string.Equals(preparedModelHash, sourceSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Prepared model hash must differ from the original source fixture hash.");
            if (!sidecarJson.TryGetProperty("fixturePreparationRequestPath", out JsonElement prepReqPath) ||
                prepReqPath.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(prepReqPath.GetString()) ||
                !sidecarJson.TryGetProperty("fixturePreparationRequestSha256", out JsonElement prepReqHash) ||
                prepReqHash.ValueKind != JsonValueKind.String || !Regex.IsMatch(prepReqHash.GetString() ?? "", @"\A[0-9A-Fa-f]{64}\z") ||
                !sidecarJson.TryGetProperty("fixturePreparationResultPath", out JsonElement prepResPath) ||
                prepResPath.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(prepResPath.GetString()) ||
                !sidecarJson.TryGetProperty("fixturePreparationResultSha256", out JsonElement prepResHash) ||
                prepResHash.ValueKind != JsonValueKind.String || !Regex.IsMatch(prepResHash.GetString() ?? "", @"\A[0-9A-Fa-f]{64}\z") ||
                !sidecarJson.TryGetProperty("fixturePreparationAttemptId", out JsonElement prepAttemptId) ||
                prepAttemptId.ValueKind != JsonValueKind.String || !Guid.TryParseExact(prepAttemptId.GetString(), "N", out _) ||
                !sidecarJson.TryGetProperty("fixturePreparationRunId", out JsonElement prepRunId) ||
                prepRunId.ValueKind != JsonValueKind.String || !Guid.TryParseExact(prepRunId.GetString(), "N", out _))
                throw new InvalidOperationException("Preparation-aware sidecar is missing required correlated evidence fields.");

            if (request is null || request.QaWorkflowId != CreatePlanViewsRequest.Test ||
                request.TestId != CreatePlanViewsRequest.Test ||
                !string.Equals(sourceSha256, request.FixtureSha256, StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(preparedModelHash, request.ModelSha256, StringComparison.OrdinalIgnoreCase) ||
                !Path.GetFullPath(prepReqPath.GetString()!).Equals(Path.GetFullPath(request.FixturePreparationRequestPath), StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(prepReqHash.GetString(), request.FixturePreparationRequestSha256, StringComparison.OrdinalIgnoreCase) ||
                !Path.GetFullPath(prepResPath.GetString()!).Equals(Path.GetFullPath(request.FixturePreparationResultPath), StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(prepResHash.GetString(), request.FixturePreparationResultSha256, StringComparison.OrdinalIgnoreCase) ||
                (request.RecoveredProvenancePath.Length == 0 &&
                 (!string.Equals(prepAttemptId.GetString(), request.AttemptId, StringComparison.Ordinal) ||
                  !string.Equals(prepRunId.GetString(), request.RunId, StringComparison.Ordinal))) ||
                !string.Equals(prepAttemptId.GetString(), request.FixturePreparationAttemptId, StringComparison.Ordinal) ||
                !string.Equals(prepRunId.GetString(), request.FixturePreparationRunId, StringComparison.Ordinal))
                throw new InvalidOperationException("Preparation sidecar provenance does not match the authenticated QA request identity and evidence.");

            if (!string.Equals(fixtureHash, sourceSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Authoritative source fixture does not match its expected SHA-256.");
            if (!string.Equals(runtimeModelHash, preparedModelHash, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Prepared run copy must exactly match the authenticated prepared model SHA-256.");
        }
        else
        {
            if (request is not null)
                throw new InvalidOperationException("Create Plan Views QA requires authenticated fixture-preparation provenance.");
            if (!string.Equals(fixtureHash, sourceSha256, StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(runtimeModelHash, sourceSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Run copy must exactly match the approved controlled fixture and its SHA-256.");
        }
    }
}
