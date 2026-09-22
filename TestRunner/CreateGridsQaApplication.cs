using System.IO;
using System.Text.Json;
using Autodesk.Revit.UI;
using Autodesk.Revit.UI.Events;

namespace Repato.Revit.TestRunner;

/// <summary>QA-only startup application; it consumes one disposable request and never edits production files.</summary>
public sealed class CreateGridsQaApplication : IExternalApplication
{
    public const string RequestEnvironmentVariable = "REPATO_QA_CREATE_GRIDS_REQUEST";
    private string? requestPath;

    public Result OnStartup(UIControlledApplication application)
    {
        requestPath = Environment.GetEnvironmentVariable(RequestEnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(requestPath)) application.Idling += RunOnce;
        return Result.Succeeded;
    }

    public Result OnShutdown(UIControlledApplication application)
    {
        application.Idling -= RunOnce;
        return Result.Succeeded;
    }

    private void RunOnce(object? sender, IdlingEventArgs args)
    {
        if (sender is not UIApplication app) return;
        app.Idling -= RunOnce;
        string? receiptPath = null;
        string requestId = "";
        var report = new TestRunReport { TestId = CreateGridsTestCommand.SupportedTestId, Inputs = new { } };
        try
        {
            string path = QAPathPolicy.ValidatePath(requestPath!, QAPathPolicy.RunsRoot, false);
            receiptPath = QAPathPolicy.ValidatePath(path + ".result.json", QAPathPolicy.RunsRoot, false);
            if (File.Exists(receiptPath)) throw new InvalidOperationException("This QA request already has a result; prepare a new run.");
            using var request = JsonDocument.Parse(File.ReadAllText(path));
            var root = request.RootElement;
            requestId = root.GetProperty("requestId").GetString() ?? "";
            if (!Guid.TryParseExact(requestId, "N", out _)) throw new InvalidOperationException("Invalid QA request ID.");
            if (root.GetProperty("testId").GetString() != CreateGridsTestCommand.SupportedTestId) throw new InvalidOperationException("Unknown test ID.");
            if (DateTimeOffset.UtcNow >= root.GetProperty("expiresUtc").GetDateTimeOffset()) throw new InvalidOperationException("QA request expired before execution.");
            if (!string.Equals(Environment.UserName, "RepatoQA", StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Automated startup is restricted to the RepatoQA Windows account.");
            if (app.Application.VersionNumber != "2025" || app.Application.Documents.Size != 0) throw new InvalidOperationException("Start a fresh Revit 2025 QA session with no open documents.");
            report.IdentifyAssembly();
            AddinIsolationPolicy.RequireAllowed(report);
            string model = QAPathPolicy.ValidatePath(root.GetProperty("modelPath").GetString() ?? "", QAPathPolicy.RunsRoot, true);
            string fixture = QAPathPolicy.ValidatePath(QAPathPolicy.RepositoryRoot + @"\QA\Fixtures\CreateGridsEmptyPlan.rvt", QAPathPolicy.RepositoryRoot + @"\QA\Fixtures", true);
            string sidecar = QAPathPolicy.ValidatePath(model + ".fixture.json", QAPathPolicy.RunsRoot, false);
            using var provenance = JsonDocument.Parse(File.ReadAllText(sidecar));
            if (provenance.RootElement.GetProperty("fixtureId").GetString() != "CreateGridsEmptyPlan" ||
                !string.Equals(provenance.RootElement.GetProperty("sourceSha256").GetString(), TestRunReport.Hash(fixture), StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(provenance.RootElement.GetProperty("sourceSha256").GetString(), TestRunReport.Hash(model), StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Fixture provenance failed before opening the model.");
            app.OpenAndActivateDocument(model);
            report = RepatoTestCommand.Run(app, CreateGridsTestCommand.SupportedTestId);
        }
        catch (Exception ex) { report.Status = "Failed"; report.Errors.Add(ex.ToString()); }
        try
        {
            string reportPath = report.Write();
            if (receiptPath is not null) File.WriteAllText(receiptPath, JsonSerializer.Serialize(new { RequestId = requestId, report.RunId, ReportPath = reportPath, report.Status }));
        }
        catch (Exception ex) { app.Application.WriteJournalComment("Repato Create Grids QA evidence failure: " + ex, false); }
    }
}
