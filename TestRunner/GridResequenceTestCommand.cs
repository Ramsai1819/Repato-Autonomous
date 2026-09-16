using System.Diagnostics;
using Autodesk.Revit.Attributes;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;

namespace Repato.Revit.TestRunner;

[Transaction(TransactionMode.Manual)]
public sealed class GridResequenceTestCommand : IExternalCommand
{
    public const string SupportedTestId = "grid-resequence-all-directions-v1";
    private static readonly string[] VerticalNames = ["A", "A.1", "B", "C"];
    private static readonly string[] HorizontalNames = ["1", "2", "3", "3.2", "4"];

    public Result Execute(ExternalCommandData data, ref string message, ElementSet elements)
    {
        TestRunReport report = Run(data.Application,
            data.JournalData.TryGetValue("testId", out string? id) ? id : SupportedTestId);
        try
        {
            string path = report.Write();
            message = $"{report.Status}: {path}";
            return report.Status == "Passed" ? Result.Succeeded : Result.Failed;
        }
        catch (Exception ex) { message = ex.ToString(); return Result.Failed; }
    }

    public static TestRunReport Run(UIApplication app, string testId)
    {
        var report = new TestRunReport
        {
            TestId = testId,
            FixtureId = "GridResequenceEmpty",
            Inputs = new
            {
                VerticalStart = "A", HorizontalStart = 1,
                VerticalDirections = new[] { "Left to Right", "Right to Left" },
                HorizontalDirections = new[] { "Bottom to Top", "Top to Bottom" },
                ApprovedNames = FixtureContentPolicy.ApprovedGridResequenceNames
            }
        };
        var timer = Stopwatch.StartNew();
        try
        {
            report.RevitVersion = $"{app.Application.VersionName}; {app.Application.VersionNumber}; {app.Application.VersionBuild}";
            report.IdentifyAssembly();
            AddinIsolationPolicy.RequireAllowed(report);
            if (testId != SupportedTestId) throw new InvalidOperationException("Unknown test ID.");
            Document document = app.ActiveUIDocument?.Document ?? throw new InvalidOperationException("No active document.");
            report.DocumentPath = document.PathName;
            if (app.Application.VersionNumber != "2025") throw new InvalidOperationException("Only Revit 2025 is supported.");
            TestSafetyGate.Verify(document, report, "GridResequenceEmpty");
            ExecuteCases(document, report);
        }
        catch (Exception ex) { report.Errors.Add(ex.ToString()); }
        finally
        {
            report.FinishedUtc = DateTimeOffset.UtcNow;
            report.DurationMilliseconds = timer.Elapsed.TotalMilliseconds;
            report.Status = report.Errors.Count == 0 && report.Assertions.Count > 0 &&
                report.Assertions.All(a => a.Passed) && report.RollbackStatus == "RolledBack" ? "Passed" : "Failed";
        }
        return report;
    }

    private static void ExecuteCases(Document document, TestRunReport report)
    {
        List<Grid> grids = new FilteredElementCollector(document).OfClass(typeof(Grid)).Cast<Grid>().ToList();
        var baseline = grids.ToDictionary(g => g.Id.Value, g => new State(g.Name, Geometry(g, document.ActiveView)));
        var verticals = grids.Where(g => !IsHorizontal(g, document.ActiveView)).ToList();
        var horizontals = grids.Where(g => IsHorizontal(g, document.ActiveView)).ToList();
        report.Assert("fixture-orientation-counts", verticals.Count == 4 && horizontals.Count == 5,
            new { Vertical = 4, Horizontal = 5 }, new { Vertical = verticals.Count, Horizontal = horizontals.Count });

        RunCase(document, report, baseline, verticals, horizontals, "vertical-left-to-right", "Left to Right", "Bottom to Top", VerticalNames);
        RunCase(document, report, baseline, verticals, horizontals, "vertical-right-to-left", "Right to Left", "Bottom to Top", VerticalNames);
        RunCase(document, report, baseline, horizontals, verticals, "horizontal-bottom-to-top", "Left to Right", "Bottom to Top", HorizontalNames);
        RunCase(document, report, baseline, horizontals, verticals, "horizontal-top-to-bottom", "Left to Right", "Top to Bottom", HorizontalNames);
        report.RollbackStatus = "RolledBack";
        report.Assert("all-cases-rolled-back", MatchesBaseline(grids, baseline, document.ActiveView), true,
            grids.Select(g => new { Id = g.Id.Value, g.Name }).ToArray());
    }

    private static void RunCase(Document document, TestRunReport report, Dictionary<long, State> baseline,
        List<Grid> selected, List<Grid> unselected, string id, string verticalDirection,
        string horizontalDirection, string[] expectedNames)
    {
        using var group = new TransactionGroup(document, "Repato QA " + id + " - rollback");
        if (group.Start() != TransactionStatus.Started) throw new InvalidOperationException("Could not start " + id);
        try
        {
            IReadOnlyDictionary<long, string> changed = GridResequenceCommand.ApplyQaCase(
                document, document.ActiveView, selected, verticalDirection, horizontalDirection, 1, 1);
            report.ChangedIds.AddRange(changed.Keys.Select(value => value.ToString()));
            bool horizontal = selected.Count != 0 && IsHorizontal(selected[0], document.ActiveView);
            IEnumerable<Grid> ordered = horizontal
                ? (horizontalDirection == "Top to Bottom" ? selected.OrderByDescending(g => Position(g, document.ActiveView)) : selected.OrderBy(g => Position(g, document.ActiveView)))
                : (verticalDirection == "Right to Left" ? selected.OrderByDescending(g => Position(g, document.ActiveView)) : selected.OrderBy(g => Position(g, document.ActiveView)));
            string[] actual = ordered.Select(g => g.Name).ToArray();
            report.Assert(id + "-names", actual.SequenceEqual(expectedNames), expectedNames, actual);
            report.Assert(id + "-geometry", selected.All(g => Geometry(g, document.ActiveView) == baseline[g.Id.Value].Geometry), "unchanged", "checked");
            report.Assert(id + "-unselected", unselected.All(g => g.Name == baseline[g.Id.Value].Name && Geometry(g, document.ActiveView) == baseline[g.Id.Value].Geometry), "unchanged", "checked");
            report.Assert(id + "-decimal-3.2", !horizontal || actual.Contains("3.2"), true, actual);
            report.Assert(id + "-secondary-A.1", horizontal || actual.Contains("A.1"), true, actual);
            if (id == "horizontal-top-to-bottom")
            {
                Grid originalSecondary = selected.Single(g => baseline[g.Id.Value].Name == "3.2");
                report.Assert("special-3-3.2-family-order", originalSecondary.Name == "3.2" && Array.IndexOf(actual, "3.2") == Array.IndexOf(actual, "3") + 1,
                    "3 followed by 3.2", actual);
            }
        }
        finally
        {
            string status = group.GetStatus() == TransactionStatus.Started ? group.RollBack().ToString() : group.GetStatus().ToString();
            report.Assert(id + "-rollback", status == "RolledBack" && MatchesBaseline(baseline.Keys.Select(key => document.GetElement(new ElementId(key))).Cast<Grid>(), baseline, document.ActiveView),
                "RolledBack and baseline restored", status);
        }
    }

    private static bool IsHorizontal(Grid grid, View view)
    {
        Line line = grid.GetCurvesInView(DatumExtentType.ViewSpecific, view).OfType<Line>().First();
        XYZ a = line.GetEndPoint(0); XYZ b = line.GetEndPoint(1);
        return Math.Abs(b.X - a.X) >= Math.Abs(b.Y - a.Y);
    }
    private static double Position(Grid grid, View view)
    {
        Line line = grid.GetCurvesInView(DatumExtentType.ViewSpecific, view).OfType<Line>().First();
        XYZ a = line.GetEndPoint(0); XYZ b = line.GetEndPoint(1);
        return IsHorizontal(grid, view) ? (a.Y + b.Y) / 2 : (a.X + b.X) / 2;
    }
    private static string Geometry(Grid grid, View view)
    {
        Curve curve = grid.GetCurvesInView(DatumExtentType.ViewSpecific, view).First();
        XYZ a = curve.GetEndPoint(0); XYZ b = curve.GetEndPoint(1);
        return $"{a.X:R},{a.Y:R},{a.Z:R}|{b.X:R},{b.Y:R},{b.Z:R}";
    }
    private static bool MatchesBaseline(IEnumerable<Grid> grids, Dictionary<long, State> baseline, View view) =>
        grids.All(g => baseline.TryGetValue(g.Id.Value, out State? state) && g.Name == state.Name && Geometry(g, view) == state.Geometry);
    private sealed record State(string Name, string Geometry);
}
