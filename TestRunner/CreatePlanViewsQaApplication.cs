using System.IO;
using System.Text.Json;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;
using Autodesk.Revit.UI.Events;

namespace Repato.Revit.TestRunner;

public sealed class CreatePlanViewsQaApplication : IExternalApplication
{
    public const string RequestEnvironmentVariable = "REPATO_QA_CREATE_PLAN_VIEWS_REQUEST";
    public const string SupportedTestId = "create-plan-views-v1";
    private string? requestPath;

    public Result OnStartup(UIControlledApplication application)
    {
        requestPath = Environment.GetEnvironmentVariable(RequestEnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(requestPath)) application.Idling += RunOnce;
        return Result.Succeeded;
    }

    public Result OnShutdown(UIControlledApplication application) { application.Idling -= RunOnce; return Result.Succeeded; }

    private void RunOnce(object? sender, IdlingEventArgs args)
    {
        if (sender is not UIApplication app) return;
        app.Idling -= RunOnce;
        string? receiptPath = null; string requestId = "";
        var report = new TestRunReport { TestId = SupportedTestId, FixtureId = "CreatePlanViewsEmpty", Inputs = new { Levels = new[] { 0, 1, 2 }, ViewType = "floor-plan", Scale = "1:100", Template = "architectural", Naming = "by-level" } };
        try
        {
            string path = QAPathPolicy.ValidatePath(requestPath!, QAPathPolicy.RunsRoot, false);
            receiptPath = QAPathPolicy.ValidatePath(path + ".result.json", QAPathPolicy.RunsRoot, false);
            if (File.Exists(receiptPath)) throw new InvalidOperationException("This QA request already has a result; prepare a new run.");
            using var request = JsonDocument.Parse(File.ReadAllText(path)); var root = request.RootElement;
            requestId = root.GetProperty("requestId").GetString() ?? "";
            if (!Guid.TryParseExact(requestId, "N", out _)) throw new InvalidOperationException("Invalid QA request ID.");
            if (root.GetProperty("testId").GetString() != SupportedTestId) throw new InvalidOperationException("Unknown test ID.");
            if (DateTimeOffset.UtcNow >= root.GetProperty("expiresUtc").GetDateTimeOffset()) throw new InvalidOperationException("QA request expired before execution.");
            if (!string.Equals(Environment.UserName, "RepatoQA", StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Automated startup is restricted to the RepatoQA Windows account.");
            if (app.Application.VersionNumber != "2025" || app.Application.Documents.Size != 0) throw new InvalidOperationException("Start a fresh Revit 2025 QA session with no open documents.");
            report.IdentifyAssembly();
            string selectedManifestPath = root.GetProperty("selectedManifestPath").GetString() ?? "";
            string selectedManifestSha256 = root.GetProperty("selectedManifestSha256").GetString() ?? "";
            AddinIsolationPolicy.RequireAllowed(report, selectedManifestPath, selectedManifestSha256);
            string model = QAPathPolicy.ValidatePath(root.GetProperty("modelPath").GetString() ?? "", QAPathPolicy.RunsRoot, true);
            string fixture = QAPathPolicy.ValidatePath(QAPathPolicy.RepositoryRoot + @"\QA\Fixtures\CreatePlanViewsEmpty.rvt", QAPathPolicy.RepositoryRoot + @"\QA\Fixtures", true);
            string sidecar = QAPathPolicy.ValidatePath(model + ".fixture.json", QAPathPolicy.RunsRoot, false);
            using var provenance = JsonDocument.Parse(File.ReadAllText(sidecar)); string sourceHash = provenance.RootElement.GetProperty("sourceSha256").GetString() ?? "";
            if (provenance.RootElement.GetProperty("fixtureId").GetString() != "CreatePlanViewsEmpty" || !string.Equals(sourceHash, TestRunReport.Hash(fixture), StringComparison.OrdinalIgnoreCase) || !string.Equals(sourceHash, TestRunReport.Hash(model), StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Fixture provenance failed before opening the model.");
            app.OpenAndActivateDocument(model); report.DocumentPath = model; EnsureRequiredLevels(app.ActiveUIDocument!.Document); app.ActiveUIDocument.Document.Save(); report.RuntimeModelSha256 = TestRunReport.Hash(model); Execute(app, report);
        }
        catch (Exception ex) { report.Status = "Failed"; report.Errors.Add("Create Plan Views isolation/execution failure: " + ex); }
        try { string reportPath = report.Write(); if (receiptPath is not null) File.WriteAllText(receiptPath, JsonSerializer.Serialize(new { RequestId = requestId, report.RunId, ReportPath = reportPath, report.Status })); }
        catch (Exception ex) { app.Application.WriteJournalComment("Repato Create Plan Views QA evidence failure: " + ex, false); }
    }

    private static void EnsureRequiredLevels(Document document)
    {
        var required = new[] { (Name: "0", Millimeters: 0.0), (Name: "1", Millimeters: 3000.0), (Name: "2", Millimeters: 6000.0) };
        using var transaction = new Transaction(document, "Repato QA prepare Create Plan Views levels");
        transaction.Start();
        foreach (var item in required)
        {
            if (new FilteredElementCollector(document).OfClass(typeof(Level)).Cast<Level>().Any(level => level.Name.Equals(item.Name, StringComparison.OrdinalIgnoreCase))) continue;
            Level.Create(document, UnitUtils.ConvertToInternalUnits(item.Millimeters, UnitTypeId.Millimeters)).Name = item.Name;
        }
        transaction.Commit();
    }

    private static void Execute(UIApplication app, TestRunReport report)
    {
        Document document = app.ActiveUIDocument?.Document ?? throw new InvalidOperationException("No active QA document.");
        Level?[] levels = new[] { "0", "1", "2" }.Select(name => new FilteredElementCollector(document).OfClass(typeof(Level)).Cast<Level>().FirstOrDefault(l => l.Name.Equals(name, StringComparison.OrdinalIgnoreCase))).ToArray();
        report.Assert("requested-levels-present", levels.All(l => l is not null), new[] { "0", "1", "2" }, levels.Select(l => l?.Name).ToArray());
        if (levels.Any(l => l is null)) throw new InvalidOperationException("Requested levels 0, 1, and 2 were not found.");
        ViewFamilyType floorPlan = new FilteredElementCollector(document).OfClass(typeof(ViewFamilyType)).Cast<ViewFamilyType>().FirstOrDefault(v => v.ViewFamily == ViewFamily.FloorPlan) ?? throw new InvalidOperationException("Floor-plan view type is unavailable.");
        ViewPlan? template = new FilteredElementCollector(document).OfClass(typeof(ViewPlan)).Cast<ViewPlan>().FirstOrDefault(v => v.IsTemplate && v.Name.Contains("Architectural", StringComparison.OrdinalIgnoreCase));
        report.Assert("architectural-template-intent", template is not null, "Architectural", template?.Name ?? "Missing");
        if (template is null) throw new InvalidOperationException("Architectural template intent could not be satisfied.");
        using var group = new TransactionGroup(document, "Repato QA Create Plan Views - always rollback"); group.Start(); report.RollbackStatus = "Required";
        try
        {
            using var tx = new Transaction(document, "Create Plan Views QA"); tx.Start();
            foreach (Level level in levels!) { ViewPlan view = ViewPlan.Create(document, floorPlan.Id, level.Id); view.Scale = 100; view.Name = "Floor Plan - Level " + level.Name; view.ViewTemplateId = template.Id; report.CreatedIds.Add(view.Id.Value.ToString()); report.Assert("floor-plan-view-" + level.Name, view.ViewType == ViewType.FloorPlan && view.Scale == 100 && view.Name.Contains(level.Name, StringComparison.Ordinal), true, new { view.ViewType, view.Scale, view.Name }); }
            tx.Commit();
        }
        finally { report.RollbackStatus = group.RollBack().ToString(); }
        report.Assert("rollback-status", report.RollbackStatus == "RolledBack", "RolledBack", report.RollbackStatus); report.Status = report.Errors.Count == 0 && report.Assertions.All(a => a.Passed) ? "Passed" : "Failed";
    }
}
