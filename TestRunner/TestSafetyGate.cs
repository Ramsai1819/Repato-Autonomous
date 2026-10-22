using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;
using Autodesk.Revit.DB;

namespace Repato.Revit.TestRunner;

internal static class TestSafetyGate
{
    internal static readonly string[] ApprovedGridBubbleFixtureNames = FixtureContentPolicy.ApprovedGridNames;
    internal static string RepositoryRoot => QAPathPolicy.RepositoryRoot;
    internal static string RunsRoot => RepositoryRoot + @"\QA\TestRuns";
    internal static string ReportsRoot => RepositoryRoot + @"\QA\Reports";
    private static string FixturesRoot => RepositoryRoot + @"\QA\Fixtures";

    internal static void Verify(Document document, TestRunReport report, string? requiredFixtureId = null,
        CreatePlanViewsRequest? request = null, bool allowControlledFixtureSource = false)
    {
        if (document.IsFamilyDocument || document.IsLinked || document.IsReadOnly || document.IsModified || document.IsModifiable ||
            document.IsWorkshared || document.IsModelInCloud || document.IsDetached)
            throw new InvalidOperationException("Reject family, linked, read-only, modified, modifiable, workshared, cloud or detached documents.");
        string activePath = document.PathName;
        if (string.IsNullOrWhiteSpace(activePath))
            throw new InvalidOperationException("The active Revit document has no saved PathName; cannot validate the QA fixture.");
        report.DocumentPath = activePath;
        string path = QAPathPolicy.ValidatePath(activePath, allowControlledFixtureSource ? FixturesRoot : RunsRoot, true);
        report.DocumentPath = path;
        using (BasicFileInfo info = BasicFileInfo.Extract(path))
            if (info.IsWorkshared || info.IsCentral || info.IsLocal)
                throw new InvalidOperationException("The saved file has worksharing/central metadata.");
        string[] gridNames = new FilteredElementCollector(document).OfClass(typeof(Grid)).Cast<Grid>().Select(g => g.Name).ToArray();
        int linkCount = new FilteredElementCollector(document).OfClass(typeof(RevitLinkType)).Count();
        FixtureContentPolicy.Validate(requiredFixtureId, gridNames, linkCount);
        report.Assert(
            "fixture-content-policy",
            true,
            new { GridNames = FixtureContentPolicy.ApprovedNames(requiredFixtureId) ?? Array.Empty<string>(), RevitLinkCount = 0 },
            new { GridNames = gridNames.Order(StringComparer.Ordinal).ToArray(), RevitLinkCount = linkCount }
        );

        string fixtureId;
        string expectedHash;
        JsonDocument? json = null;
        if (allowControlledFixtureSource)
        {
            fixtureId = requiredFixtureId ?? "";
            expectedHash = TestRunReport.Hash(path);
        }
        else
        {
            string sidecarPath = QAPathPolicy.ValidatePath(path + ".fixture.json", RunsRoot, false);
            json = JsonDocument.Parse(RecoveredFixtureProvenance.Resolve(path, request).GetRawText());
            fixtureId = json.RootElement.GetProperty("fixtureId").GetString() ?? "";
            expectedHash = json.RootElement.GetProperty("sourceSha256").GetString() ?? "";
        }
        if (requiredFixtureId is not null && !string.Equals(fixtureId, requiredFixtureId, StringComparison.Ordinal))
            throw new InvalidOperationException("This test requires fixture " + requiredFixtureId + ".");
        if (!Regex.IsMatch(fixtureId, @"\A[A-Za-z0-9][A-Za-z0-9_-]{0,79}\z") ||
            !Regex.IsMatch(expectedHash, @"\A[0-9A-Fa-f]{64}\z"))
            throw new InvalidOperationException("Invalid fixture provenance sidecar.");
        string[]? approvedNames = FixtureContentPolicy.ApprovedNames(fixtureId);
        if (approvedNames is not null)
        {
            string[] declared = json is not null && json.RootElement.TryGetProperty("requiredGridNames", out JsonElement names)
                ? names.EnumerateArray().Select(item => item.GetString() ?? "").ToArray()
                : [];
            if (json is not null && !FixtureContentPolicy.SameNames(declared, approvedNames))
                throw new InvalidOperationException("Fixture sidecar does not declare the exact approved grid set.");
        }
        string fixturePath = QAPathPolicy.ValidatePath(Path.Combine(FixturesRoot, fixtureId + ".rvt"), FixturesRoot, true);

        if (json is not null)
            TestSafetyGateProvenance.Verify(json.RootElement, TestRunReport.Hash(fixturePath), TestRunReport.Hash(path), request);

        report.FixtureId = fixtureId;
        report.FixtureSha256 = expectedHash;
        report.Assert("safety-gate", true, "Controlled local disposable fixture", path);
        json?.Dispose();
    }

}

