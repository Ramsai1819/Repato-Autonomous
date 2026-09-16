using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;
using Autodesk.Revit.DB;

namespace Repato.Revit.TestRunner;

internal static class TestSafetyGate
{
    internal const string RepositoryRoot = QAPathPolicy.RepositoryRoot;
    internal const string RunsRoot = RepositoryRoot + @"\QA\TestRuns";
    internal const string ReportsRoot = RepositoryRoot + @"\QA\Reports";
    private const string FixturesRoot = RepositoryRoot + @"\QA\Fixtures";

    internal static void Verify(Document document, TestRunReport report, string? requiredFixtureId = null)
    {
        if (document.IsFamilyDocument || document.IsLinked || document.IsReadOnly || document.IsModified || document.IsModifiable ||
            document.IsWorkshared || document.IsModelInCloud || document.IsDetached)
            throw new InvalidOperationException("Reject family, linked, read-only, modified, modifiable, workshared, cloud or detached documents.");
        string path = QAPathPolicy.ValidatePath(document.PathName, RunsRoot, true);
        report.DocumentPath = path;
        using (BasicFileInfo info = BasicFileInfo.Extract(path))
            if (info.IsWorkshared || info.IsCentral || info.IsLocal)
                throw new InvalidOperationException("The saved file has worksharing/central metadata.");
        var grids = new FilteredElementCollector(document).OfClass(typeof(Grid)).Cast<Grid>().ToList();
        if (new FilteredElementCollector(document).OfClass(typeof(RevitLinkType)).Any())
            throw new InvalidOperationException("Fixture must have zero Revit links.");
        if (string.Equals(requiredFixtureId, "GridBubbleVisibilityEmpty", StringComparison.Ordinal))
        {
            string[] approved = ["A", "B", "C", "D", "1", "2", "3", "4"];
            if (grids.Count != approved.Length || !grids.Select(g => g.Name).Order(StringComparer.Ordinal).SequenceEqual(approved.Order(StringComparer.Ordinal)))
                throw new InvalidOperationException("Grid Bubble fixture must contain exactly grids A, B, C, D, 1, 2, 3, 4.");
        }
        else if (grids.Count != 0)
            throw new InvalidOperationException("Fixture must have no grids and no Revit links.");

        string sidecarPath = QAPathPolicy.ValidatePath(path + ".fixture.json", RunsRoot, false);
        using var json = JsonDocument.Parse(File.ReadAllText(sidecarPath));
        string fixtureId = json.RootElement.GetProperty("fixtureId").GetString() ?? "";
        string expectedHash = json.RootElement.GetProperty("sourceSha256").GetString() ?? "";
        if (requiredFixtureId is not null && !string.Equals(fixtureId, requiredFixtureId, StringComparison.Ordinal))
            throw new InvalidOperationException("This test requires fixture " + requiredFixtureId + ".");
        if (!Regex.IsMatch(fixtureId, @"\A[A-Za-z0-9][A-Za-z0-9_-]{0,79}\z") ||
            !Regex.IsMatch(expectedHash, @"\A[0-9A-Fa-f]{64}\z"))
            throw new InvalidOperationException("Invalid fixture provenance sidecar.");
        string fixturePath = QAPathPolicy.ValidatePath(Path.Combine(FixturesRoot, fixtureId + ".rvt"), FixturesRoot, true);
        if (!string.Equals(TestRunReport.Hash(fixturePath), expectedHash, StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(TestRunReport.Hash(path), expectedHash, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Run copy must exactly match the approved controlled fixture and its SHA-256.");
        report.FixtureId = fixtureId;
        report.FixtureSha256 = expectedHash;
        report.Assert("safety-gate", true, "Controlled local disposable fixture", path);
    }

}

