using System.IO;
using System.Text.Json;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;
using Autodesk.Revit.UI.Events;

namespace Repato.Revit.TestRunner;

// Installed only by the QA manifest. No ribbon changes and no listener/server.
public sealed class CreateLevelsQaApplication : IExternalApplication
{
    public const string RequestEnvironmentVariable = "REPATO_QA_LEVELS_REQUEST";
    private string? _requestPath;

    public Result OnStartup(UIControlledApplication application)
    {
        _requestPath = Environment.GetEnvironmentVariable(RequestEnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(_requestPath))
            application.Idling += RunOnce;
        return Result.Succeeded;
    }

    public Result OnShutdown(UIControlledApplication application)
    {
        application.Idling -= RunOnce;
        return Result.Succeeded;
    }

    private void RunOnce(object? sender, IdlingEventArgs args)
    {
        if (sender is not UIApplication app)
            return;
        app.Idling -= RunOnce;
        string? receiptPath = null;
        string requestId = "";
        var report = new TestRunReport { TestId = CreateLevelsTestCommand.SupportedTestId, Inputs = new { } };
        try
        {
            // Validate the request location before allowing even a completion file write.
            string requestPath = QAPathPolicy.ValidatePath(_requestPath!, QAPathPolicy.RunsRoot, false);
            receiptPath = QAPathPolicy.ValidatePath(requestPath + ".result.json", QAPathPolicy.RunsRoot, false);
            if (File.Exists(receiptPath))
                throw new InvalidOperationException("This QA request already has a result; prepare a new run.");
            using var request = JsonDocument.Parse(File.ReadAllText(requestPath));
            var root = request.RootElement;
            requestId = root.GetProperty("requestId").GetString() ?? "";
            if (!Guid.TryParseExact(requestId, "N", out _))
                throw new InvalidOperationException("Invalid QA request ID.");
            string testId = root.GetProperty("testId").GetString() ?? "";
            DateTimeOffset expires = root.GetProperty("expiresUtc").GetDateTimeOffset();
            if (DateTimeOffset.UtcNow >= expires)
                throw new InvalidOperationException("QA request expired before execution; prepare a fresh run.");
            report.TestId = testId;
            report.IdentifyAssembly();
            report.RevitVersion = app.Application.VersionName + "; " + app.Application.VersionBuild;
            if (testId != CreateLevelsTestCommand.SupportedTestId)
                throw new InvalidOperationException("Unknown test ID.");
            if (!string.Equals(Environment.UserName, "RepatoQA", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Automated startup is restricted to the RepatoQA Windows account.");
            if (app.Application.VersionNumber != "2025" || app.Application.Documents.Size != 0)
                throw new InvalidOperationException("Start a fresh Revit 2025 QA session with no open documents.");
            string expectedAssembly = root.GetProperty("assemblySha256").GetString() ?? "";
            if (!string.Equals(expectedAssembly, TestRunReport.Hash(typeof(CreateLevelsQaApplication).Assembly.Location), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Loaded add-in file does not match the requested build hash.");

            string model = QAPathPolicy.ValidatePath(root.GetProperty("modelPath").GetString() ?? "", QAPathPolicy.RunsRoot, true);
            if (!string.Equals(Path.GetDirectoryName(model), Path.GetDirectoryName(requestPath), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Request and disposable model must be in the same run directory.");
            string fixture = QAPathPolicy.ValidatePath(
                QAPathPolicy.RepositoryRoot + @"\QA\Fixtures\CreateLevelsEmpty.rvt",
                QAPathPolicy.RepositoryRoot + @"\QA\Fixtures", true);
            string sidecar = QAPathPolicy.ValidatePath(model + ".fixture.json", QAPathPolicy.RunsRoot, false);
            using var provenance = JsonDocument.Parse(File.ReadAllText(sidecar));
            string hash = provenance.RootElement.GetProperty("sourceSha256").GetString() ?? "";
            if (provenance.RootElement.GetProperty("fixtureId").GetString() != "CreateLevelsEmpty" ||
                !string.Equals(hash, TestRunReport.Hash(fixture), StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(hash, TestRunReport.Hash(model), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Fixture provenance failed before opening the model.");
            using (BasicFileInfo info = BasicFileInfo.Extract(model))
            {
                if (info.IsWorkshared || info.IsCentral || info.IsLocal || info.Format != "2025")
                    throw new InvalidOperationException("Only a local non-workshared Revit 2025 fixture may be opened.");
            }

            AddinIsolationPolicy.RequireAllowed(report);
            string expectedPolicyHash = root.GetProperty("addinIsolation").GetProperty("PolicySha256").GetString() ?? "";
            if (!string.Equals(expectedPolicyHash, report.AddinIsolation!.PolicySha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Add-in isolation policy changed since the QA request was prepared.");
            app.OpenAndActivateDocument(model);
            if (DateTimeOffset.UtcNow >= expires)
                throw new InvalidOperationException("QA request expired while opening the disposable model; no test mutations started.");
            report = CreateLevelsTestCommand.Run(app, testId);
        }
        catch (Exception ex)
        {
            report.Status = "Failed";
            report.Errors.Add(ex.ToString());
        }

        try
        {
            if (report.FinishedUtc == default)
            {
                report.FinishedUtc = DateTimeOffset.UtcNow;
                report.DurationMilliseconds = (report.FinishedUtc - report.StartedUtc).TotalMilliseconds;
            }
            string reportPath = report.Write();
            if (receiptPath is not null)
            {
                string temporary = receiptPath + ".partial";
                using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                {
                    JsonSerializer.Serialize(stream, new { RequestId = requestId, report.RunId, ReportPath = reportPath, report.Status });
                    stream.Flush(true);
                }
                File.Move(temporary, receiptPath);
            }
        }
        catch (Exception ex)
        {
            // The controller treats a missing receipt as failure, never a pass.
            app.Application.WriteJournalComment("Repato Create Levels QA evidence failure: " + ex, false);
        }
        // Keep the disposable document open for supervised inspection. Never save,
        // force-close a dialog, terminate Revit, or mutate any other document.
    }
}
