using System.Diagnostics;
using System.Globalization;
using Autodesk.Revit.Attributes;
using Autodesk.Revit.DB;
using Autodesk.Revit.DB.Events;
using Autodesk.Revit.UI;

namespace Repato.Revit.TestRunner;

[Transaction(TransactionMode.Manual)]
public sealed class CreateLevelsTestCommand : IExternalCommand
{
    public const string SupportedTestId = "create-levels-elevations-v1";

    public Result Execute(
        ExternalCommandData commandData,
        ref string message,
        ElementSet elements)
    {
        string testId = commandData.JournalData.TryGetValue(
            "testId",
            out string? requested)
            ? requested
            : SupportedTestId;

        TestRunReport report = Run(commandData.Application, testId);

        try
        {
            string path = report.Write();
            message = $"{report.Status}: {path}";

            return report.Status == "Passed"
                ? Result.Succeeded
                : Result.Failed;
        }
        catch (Exception ex)
        {
            message =
                $"QA FAILED: evidence could not be saved. Run {report.RunId}; "
                + $"rollback={report.RollbackStatus}; {ex}";

            return Result.Failed;
        }
    }

    public static TestRunReport Run(UIApplication application, string testId)
    {
        var report = new TestRunReport { TestId = testId };
        string[] inputNames = Names(report);
        report.Inputs = new { Names = inputNames, ElevationsMm = new double[] { -1200, 3450, 7800 }, ElevationReference = "Project", ToleranceMm = 0.1 };
        var timer = Stopwatch.StartNew();

        try
        {
            report.RevitVersion =
                $"{application.Application.VersionName}; "
                + $"{application.Application.VersionNumber}; "
                + application.Application.VersionBuild;

            report.IdentifyAssembly();
            AddinIsolationPolicy.RequireAllowed(report);

            if (!string.Equals(
                testId,
                SupportedTestId,
                StringComparison.Ordinal))
            {
                throw new InvalidOperationException(
                    "Unknown test ID. Only " + SupportedTestId + " is supported."
                );
            }

            Document document = application.ActiveUIDocument?.Document
                ?? throw new InvalidOperationException("No saved active document.");

            report.DocumentPath = document.PathName;

            if (application.Application.VersionNumber != "2025")
            {
                throw new InvalidOperationException(
                    "Only Revit 2025 is supported."
                );
            }

            if (application.Application.Documents
                .Cast<Document>()
                .Count(d => !d.IsLinked) != 1)
            {
                throw new InvalidOperationException(
                    "The QA session must contain only the test document."
                );
            }

            TestSafetyGate.Verify(document, report, "CreateLevelsEmpty");
            ExecuteTest(application, document, report);
        }
        catch (Exception ex)
        {
            report.Errors.Add(ex.ToString());
        }
        finally
        {
            report.FinishedUtc = DateTimeOffset.UtcNow;
            report.DurationMilliseconds = timer.Elapsed.TotalMilliseconds;

            report.Status =
                report.Errors.Count == 0
                && report.Assertions.Count > 0
                && report.Assertions.All(a => a.Passed)
                && report.RollbackStatus == "RolledBack"
                    ? "Passed"
                    : "Failed";
        }

        return report;
    }

    private static void ExecuteTest(
        UIApplication app,
        Document document,
        TestRunReport report)
    {
        HashSet<long> baseline = ElementIds(document);
        var baselineLevels = Levels(document).ToDictionary(level => level.Id.Value, level => (level.Name, level.ProjectElevation));
        string[] names = Names(report);
        double[] elevations = [-1200, 3450, 7800];
        string levelData = string.Join("\n", names.Zip(elevations).Select(definition => definition.First + " | " + definition.Second.ToString(CultureInfo.InvariantCulture)));
        report.Inputs = new { Names = names, ElevationsMm = elevations, ElevationReference = "Project", ToleranceMm = 0.1, LevelData = levelData };
        if (baselineLevels.Values.Any(level => names.Contains(level.Name, StringComparer.OrdinalIgnoreCase)))
            throw new InvalidOperationException("Test level names already exist.");
        bool observedCommit = false;
        var modified = new HashSet<long>();
        var deleted = new HashSet<long>();

        void OnChanged(object? sender, DocumentChangedEventArgs args)
        {
            if (!args.GetDocument().Equals(document))
            {
                return;
            }

            if (args.Operation == UndoOperation.TransactionCommitted)
            {
                observedCommit = true;

                modified.UnionWith(
                    args.GetModifiedElementIds().Select(id => id.Value)
                );

                deleted.UnionWith(
                    args.GetDeletedElementIds().Select(id => id.Value)
                );
            }
        }

        void OnFailures(object? sender, FailuresProcessingEventArgs args)
        {
            FailuresAccessor accessor = args.GetFailuresAccessor();

            if (!accessor.GetDocument().Equals(document))
            {
                return;
            }

            var failures = accessor.GetFailureMessages();

            if (failures.Count == 0)
            {
                return;
            }

            foreach (FailureMessageAccessor failure in failures)
            {
                report.Errors.Add(
                    $"Revit {failure.GetSeverity()}: "
                    + failure.GetDescriptionText()
                );
            }

            var options = accessor.GetFailureHandlingOptions();
            options.SetClearAfterRollback(true);
            accessor.SetFailureHandlingOptions(options);
            args.SetProcessingResult(FailureProcessingResult.ProceedWithRollBack);
        }

        using var group = new TransactionGroup(
            document,
            "Repato QA Create Levels - always rollback"
        );

        app.Application.DocumentChanged += OnChanged;
        app.Application.FailuresProcessing += OnFailures;

        try
        {
            if (group.Start() != TransactionStatus.Started)
            {
                throw new InvalidOperationException(
                    "Could not start test transaction group."
                );
            }

            report.RollbackStatus = "Required";

            LevelScreenshotCapture.Capture(document, report, "before");
            observedCommit = false;
            object service = LevelCreator.Create(document, levelData);
            report.ChangedIds.AddRange(modified.Select(id => id.ToString(CultureInfo.InvariantCulture)));
            report.DeletedIds.AddRange(deleted.Select(id => id.ToString(CultureInfo.InvariantCulture)));
            report.Assert("service-commit-observed", observedCommit, true, observedCommit);
            var levels = Levels(document);
            var created = levels.Where(level => !baselineLevels.ContainsKey(level.Id.Value)).ToList();
            report.CreatedIds.AddRange(created.Select(level => level.Id.Value.ToString(CultureInfo.InvariantCulture)));
            report.Assert("created-level-count", created.Count == 3, 3, created.Count);
            report.Assert("total-level-count", levels.Count == baselineLevels.Count + 3, baselineLevels.Count + 3, levels.Count);
            report.Assert("exact-created-names", created.Select(level => level.Name).Order(StringComparer.Ordinal).SequenceEqual(names.Order(StringComparer.Ordinal)), names, created.Select(level => level.Name).ToArray());
            foreach (var definition in names.Zip(elevations))
            {
                Level? level = created.SingleOrDefault(item => item.Name == definition.First);
                double? actual = level is null ? null : UnitUtils.ConvertFromInternalUnits(level.ProjectElevation, UnitTypeId.Millimeters);
                report.Assert("elevation-" + definition.First, actual.HasValue && Math.Abs(actual.Value - definition.Second) <= 0.1,
                    new { ProjectElevationMm = definition.Second, ToleranceMm = 0.1 }, (object?)actual ?? "Missing level");
            }
            AssertBaselineLevels(document, baselineLevels, report, "during-test");
            report.Assert("no-preexisting-deletions-during-test", !deleted.Overlaps(baseline), "No preexisting elements deleted", deleted.Select(id => id.ToString()).ToArray());
            report.Assert("only-level-additions", ElementIds(document).Except(baseline).ToHashSet().SetEquals(created.Select(level => level.Id.Value)), "Only three level elements added", ElementIds(document).Except(baseline).Select(id => id.ToString()).ToArray());
            report.Assert("service-result", System.Text.Json.JsonSerializer.SerializeToElement(service).GetProperty("status").GetString() == "completed", "completed", service);
            LevelScreenshotCapture.Capture(document, report, "created");
        }
        finally
        {
            try
            {
                if (group.GetStatus() == TransactionStatus.Started)
                {
                    report.RollbackStatus = group.RollBack().ToString();
                }
                else if (report.RollbackStatus == "Required")
                {
                    report.RollbackStatus = group.GetStatus().ToString();
                }

                report.Assert(
                    "rollback-status",
                    report.RollbackStatus == "RolledBack",
                    "RolledBack",
                    report.RollbackStatus
                );

                report.Assert(
                    "baseline-element-ids-restored",
                    baseline.SetEquals(ElementIds(document)),
                    baseline.Count,
                    ElementIds(document).Count
                );

                report.Assert("no-test-levels-after-rollback", !Levels(document).Any(level => names.Contains(level.Name, StringComparer.Ordinal)), "No test levels remain", Levels(document).Where(level => names.Contains(level.Name, StringComparer.Ordinal)).Select(level => level.Name).ToArray());
                AssertBaselineLevels(document, baselineLevels, report, "after-rollback");
                string fixturePath = System.IO.Path.Combine(QAPathPolicy.RepositoryRoot, "QA", "Fixtures", report.FixtureId + ".rvt");
                string fixtureHash = TestRunReport.Hash(fixturePath);
                report.Assert("source-fixture-unchanged", string.Equals(fixtureHash, report.FixtureSha256, StringComparison.OrdinalIgnoreCase), report.FixtureSha256, fixtureHash);
                report.Assert(
                    "disk-copy-unchanged",
                    string.Equals(
                        TestRunReport.Hash(document.PathName),
                        report.FixtureSha256,
                        StringComparison.OrdinalIgnoreCase
                    ),
                    report.FixtureSha256,
                    TestRunReport.Hash(document.PathName)
                );
                if (report.RollbackStatus == "RolledBack")
                    LevelScreenshotCapture.Capture(document, report, "rolled-back");
            }
            finally
            {
                app.Application.DocumentChanged -= OnChanged;
                app.Application.FailuresProcessing -= OnFailures;
            }
        }
    }

    private static HashSet<long> ElementIds(Document document) =>
        new FilteredElementCollector(document)
            .WherePasses(
                new LogicalOrFilter(
                    new ElementIsElementTypeFilter(true),
                    new ElementIsElementTypeFilter(false)
                )
            )
            .ToElementIds()
            .Select(id => id.Value)
            .ToHashSet();

    private static List<Level> Levels(Document document) => new FilteredElementCollector(document).OfClass(typeof(Level)).Cast<Level>().ToList();

    private static string[] Names(TestRunReport report)
    {
        string prefix = "REPATO_QA_LEVEL_" + report.RunId[..12] + "_";
        return [prefix + "LOW", prefix + "MID", prefix + "HIGH"];
    }

    private static void AssertBaselineLevels(Document document, Dictionary<long, (string Name, double ProjectElevation)> expected, TestRunReport report, string phase)
    {
        var current = Levels(document).ToDictionary(level => level.Id.Value);
        bool unchanged = expected.All(item => current.TryGetValue(item.Key, out Level? level) && level.Name == item.Value.Name && Math.Abs(level.ProjectElevation - item.Value.ProjectElevation) < 1e-9);
        report.Assert("baseline-levels-unchanged-" + phase, unchanged,
            expected.Select(item => new { Id = item.Key.ToString(), item.Value.Name, item.Value.ProjectElevation }).ToArray(),
            current.Where(item => expected.ContainsKey(item.Key)).Select(item => new { Id = item.Key.ToString(), item.Value.Name, item.Value.ProjectElevation }).ToArray());
    }
}

