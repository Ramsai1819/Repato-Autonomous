using System.Diagnostics;
using System.Globalization;
using Autodesk.Revit.Attributes;
using Autodesk.Revit.DB;
using Autodesk.Revit.DB.Events;
using Autodesk.Revit.UI;

namespace Repato.Revit.TestRunner;

[Transaction(TransactionMode.Manual)]
public sealed class RepatoTestCommand : IExternalCommand
{
    public const string SupportedTestId = "create-grids-world-axis-v1";

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
        var timer = Stopwatch.StartNew();

        try
        {
            report.RevitVersion =
                $"{application.Application.VersionName}; "
                + $"{application.Application.VersionNumber}; "
                + application.Application.VersionBuild;

            report.IdentifyAssembly();

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

            TestSafetyGate.Verify(document, report);
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
            "Repato QA Create Grids - always rollback"
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

            GridCreationResult service = GridCreator.Create(
                document,
                "A\t0\nB\t6000\nC\t12000\nD\t18000",
                "1\t0\n2\t6000\n3\t12000\n4\t18000",
                "48000"
            );

            report.Errors.AddRange(service.Errors);

            if (service.FailureMessage is not null)
            {
                report.Errors.Add(service.FailureMessage);
            }

            report.Assert(
                "service-outcome",
                service.Success
                    && service.Created.Count == 8
                    && service.Skipped.Count == 0
                    && service.Errors.Count == 0,
                "8 creations, no skips/errors",
                service
            );

            report.Assert(
                "service-commit-observed",
                observedCommit,
                true,
                observedCommit
            );

            var grids = new FilteredElementCollector(document)
                .OfClass(typeof(Grid))
                .Cast<Grid>()
                .ToList();

            report.CreatedIds.AddRange(
                grids.Select(
                    g => g.Id.Value.ToString(CultureInfo.InvariantCulture)
                )
            );

            report.Assert("grid-count", grids.Count == 8, 8, grids.Count);

            string[] names = ["A", "B", "C", "D", "1", "2", "3", "4"];

            string[] actualNames = grids
                .Select(g => g.Name)
                .Order(StringComparer.Ordinal)
                .ToArray();

            report.Assert(
                "exact-names",
                actualNames.SequenceEqual(names.Order(StringComparer.Ordinal)),
                names,
                actualNames
            );

            double tolerance = UnitUtils.ConvertToInternalUnits(
                0.1,
                UnitTypeId.Millimeters
            );

            foreach (string name in names)
            {
                Grid? grid = grids.SingleOrDefault(g => g.Name == name);
                bool vertical = char.IsLetter(name[0]);
                int index = vertical ? name[0] - 'A' : name[0] - '1';

                double offset = UnitUtils.ConvertToInternalUnits(
                    index * 6000,
                    UnitTypeId.Millimeters
                );

                double half = UnitUtils.ConvertToInternalUnits(
                    24000,
                    UnitTypeId.Millimeters
                );

                XYZ expectedA = vertical
                    ? new XYZ(offset, -half, 0)
                    : new XYZ(-half, offset, 0);

                XYZ expectedB = vertical
                    ? new XYZ(offset, half, 0)
                    : new XYZ(half, offset, 0);

                Curve? curve = grid?.Curve;
                XYZ? a = curve?.GetEndPoint(0);
                XYZ? b = curve?.GetEndPoint(1);

                bool matches =
                    curve is Line
                    && a is not null
                    && b is not null
                    && (
                        (
                            a.DistanceTo(expectedA) <= tolerance
                            && b.DistanceTo(expectedB) <= tolerance
                        )
                        || (
                            b.DistanceTo(expectedA) <= tolerance
                            && a.DistanceTo(expectedB) <= tolerance
                        )
                    );

                report.Assert(
                    "world-axis-position-" + name,
                    matches,
                    new
                    {
                        Name = name,
                        OffsetMm = index * 6000,
                        LengthMm = 48000,
                        ToleranceMm = 0.1
                    },
                    new
                    {
                        Start = Coordinates(a),
                        End = Coordinates(b)
                    }
                );
            }

            foreach (
                string[] family in new[]
                {
                    new[] { "A", "B", "C", "D" },
                    new[] { "1", "2", "3", "4" }
                }
            )
            {
                for (int i = 1; i < family.Length; i++)
                {
                    Grid? previous = grids.SingleOrDefault(
                        g => g.Name == family[i - 1]
                    );

                    Grid? current = grids.SingleOrDefault(
                        g => g.Name == family[i]
                    );

                    double? spacing =
                        previous is null || current is null
                            ? null
                            : char.IsLetter(family[i][0])
                                ? current.Curve.GetEndPoint(0).X
                                    - previous.Curve.GetEndPoint(0).X
                                : current.Curve.GetEndPoint(0).Y
                                    - previous.Curve.GetEndPoint(0).Y;

                    double? mm = spacing.HasValue
                        ? UnitUtils.ConvertFromInternalUnits(
                            spacing.Value,
                            UnitTypeId.Millimeters
                        )
                        : null;

                    report.Assert(
                        "spacing-" + family[i - 1] + "-" + family[i],
                        mm.HasValue && Math.Abs(mm.Value - 6000) <= 0.1,
                        6000,
                        (object?)mm ?? "Missing grid"
                    );
                }
            }

            report.Assert(
                "no-preexisting-deletions-during-test",
                !deleted.Overlaps(baseline),
                "No preexisting elements deleted during the temporary test transaction",
                new
                {
                    ModifiedIds = modified
                        .Select(x => x.ToString())
                        .ToArray(),

                    DeletedIds = deleted
                        .Select(x => x.ToString())
                        .ToArray()
                }
            );

            report.Assert(
                "only-grid-additions",
                ElementIds(document)
                    .Except(baseline)
                    .ToHashSet()
                    .SetEquals(grids.Select(g => g.Id.Value)),
                "Only eight grid IDs added",
                ElementIds(document)
                    .Except(baseline)
                    .Select(x => x.ToString())
                    .ToArray()
            );
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

                report.Assert(
                    "no-grids-after-rollback",
                    !new FilteredElementCollector(document)
                        .OfClass(typeof(Grid))
                        .Any(),
                    0,
                    new FilteredElementCollector(document)
                        .OfClass(typeof(Grid))
                        .Count()
                );

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

    private static double[]? Coordinates(XYZ? point) =>
        point is null
            ? null
            : new[]
            {
                point.X,
                point.Y,
                point.Z
            }
            .Select(
                value => UnitUtils.ConvertFromInternalUnits(
                    value,
                    UnitTypeId.Millimeters
                )
            )
            .ToArray();
}