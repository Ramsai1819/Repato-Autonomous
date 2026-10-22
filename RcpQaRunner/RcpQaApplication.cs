using System.Security.Cryptography;
using System.Text.Json;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;
using Autodesk.Revit.UI.Events;
using Repato.Revit.TestRunner;
using Repato.ToolQaFramework;

namespace Repato.RcpQaRunner;

public sealed class RcpQaApplication : IExternalApplication
{
    public const string RequestEnvironmentVariable = "REPATO_QA_CREATE_RCP_VIEWS_REQUEST";
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
        Run(app);
    }

    private void Run(UIApplication app)
    {
        RcpQaRequest? request = null;
        string? reportPath = null;
        string requestId = "";
        string taskId = "";
        string workflowId = "";
        string attemptId = "";
        string runId = "";
        string claimId = "";
        string status = "Failed";
        string rollbackStatus = "NotStarted";
        string cleanupStatus = "NotStarted";
        bool baselineRestored = false;
        string[] expectedNames = [];
        string[] createdNames = [];
        RcpCreatedViewEvidence[] createdViews = [];
        var errors = new List<string>();
        var assertions = new List<string>();
        string fixtureId = "";
        string fixtureSha = "";
        string modelSha = "";
        string artifactSha = "";
        string supportArtifactSha = "";
        string viewTypeName = "";
        Document? document = null;
        try
        {
            string fullRequestPath = ValidateLocalPath(requestPath!, requireExisting: true);
            ToolQaRegistry.LoadBuiltIn().ValidateRunner(RcpQaRequest.Test, typeof(RcpQaApplication).FullName!);
            request = RcpQaRequest.Parse(File.ReadAllText(fullRequestPath), fullRequestPath);
            requestId = request.RequestId; taskId = request.TaskId; workflowId = request.WorkflowId;
            attemptId = request.AttemptId; runId = request.RunId; claimId = request.ClaimId;
            reportPath = Path.Combine(Path.GetDirectoryName(fullRequestPath)!, request.RequestId + ".report.json");
            ValidateLocalPath(request.ModelPath, requireExisting: true);
            fixtureId = request.FixtureId; fixtureSha = request.FixtureSha256; modelSha = request.ModelSha256; artifactSha = request.ArtifactSha256; supportArtifactSha = request.SupportArtifactSha256;
            expectedNames = request.LevelNames.Select(name => name + " - " + request.NameSuffix).ToArray();
            RcpQaStartupContract.Validate(app.Application.VersionNumber, Environment.UserName, app.Application.Documents.Size, fullRequestPath);
            RcpQaManifestContract.Verify(request.ManifestPath, request.ManifestSha256, typeof(RcpQaApplication).Assembly.Location);
            var isolation = AddinIsolationPolicy.Inspect(request.ManifestPath, request.ManifestSha256);
            if (!isolation.Allowed) throw new InvalidOperationException("RCP QA add-in isolation failed: " + string.Join(";", isolation.Errors));
            if (!Hash(typeof(RcpQaApplication).Assembly.Location).Equals(request.ArtifactSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Loaded RCP QA runner artifact hash mismatch.");
            if (!Hash(typeof(AddinIsolationPolicy).Assembly.Location).Equals(request.SupportArtifactSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Loaded shared Repato QA support artifact hash mismatch.");
            if (!File.Exists(request.ModelPath) || !Hash(request.ModelPath).Equals(request.ModelSha256, StringComparison.OrdinalIgnoreCase) ||
                !request.ModelSha256.Equals(request.FixtureSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Disposable RCP fixture copy hash mismatch.");
            string sidecarPath = request.ModelPath + ".fixture.json";
            using (JsonDocument sidecar = JsonDocument.Parse(File.ReadAllText(sidecarPath)))
            {
                JsonElement root = sidecar.RootElement;
                string expectedFixtureSpec = ToolQaRegistry.LoadBuiltIn().Get(RcpQaRequest.Test).FixtureSpecId;
                if (root.GetProperty("fixtureId").GetString() != request.FixtureId ||
                    !root.GetProperty("sourceSha256").GetString()!.Equals(request.FixtureSha256, StringComparison.OrdinalIgnoreCase) ||
                    !root.GetProperty("fixtureSpecId").GetString()!.Equals(expectedFixtureSpec, StringComparison.Ordinal))
                    throw new InvalidOperationException("RCP disposable fixture provenance mismatch.");
            }
            using (BasicFileInfo info = BasicFileInfo.Extract(request.ModelPath))
                if (info.IsWorkshared || info.IsCentral || info.IsLocal || info.Format != "2025")
                    throw new InvalidOperationException("RCP QA target must be a local, non-workshared Revit 2025 model.");
            if (request.ExpiresUtc <= DateTimeOffset.UtcNow) throw new InvalidOperationException("RCP QA request expired before model open.");
            app.OpenAndActivateDocument(request.ModelPath);
            document = app.ActiveUIDocument?.Document ?? throw new InvalidOperationException("RCP model did not become active.");
            if (!Path.GetFullPath(document.PathName).Equals(Path.GetFullPath(request.ModelPath), StringComparison.OrdinalIgnoreCase) ||
                document.IsFamilyDocument || document.IsLinked || document.IsReadOnly || document.IsModified || document.IsModifiable ||
                document.IsWorkshared || document.IsModelInCloud || document.IsDetached)
                throw new InvalidOperationException("RCP model identity or safety state is invalid.");
            var levels = new FilteredElementCollector(document).OfClass(typeof(Level)).Cast<Level>().ToArray();
            Level[] selected = request.LevelNames.Select(name => levels.SingleOrDefault(level => level.Name.Equals(name, StringComparison.Ordinal))
                ?? throw new InvalidOperationException("Required RCP fixture level missing or duplicated: " + name)).ToArray();
            ViewFamilyType[] ceilingTypes = new FilteredElementCollector(document).OfClass(typeof(ViewFamilyType)).Cast<ViewFamilyType>()
                .Where(type => type.ViewFamily == ViewFamily.CeilingPlan && type.Name == request.ViewTypeName).ToArray();
            if (ceilingTypes.Length != 1) throw new InvalidOperationException("Expected exactly one requested CeilingPlan family type.");
            viewTypeName = ceilingTypes[0].Name;
            if (new FilteredElementCollector(document).OfClass(typeof(ViewPlan)).Cast<ViewPlan>().Any(view => expectedNames.Contains(view.Name, StringComparer.OrdinalIgnoreCase)))
                throw new InvalidOperationException("RCP fixture already contains a requested target view name.");
            long[] before = ViewIds(document);
            using (var group = new TransactionGroup(document, "Repato QA Create RCP Views - rollback required"))
            {
                if (group.Start() != TransactionStatus.Started) throw new InvalidOperationException("Could not start RCP QA transaction group.");
                rollbackStatus = "Required";
                try
                {
                    using var transaction = new Transaction(document, "Create RCP Views QA");
                    if (transaction.Start() != TransactionStatus.Started) throw new InvalidOperationException("Could not start RCP QA transaction.");
                    var observed = new List<string>();
                    var observedViews = new List<RcpCreatedViewEvidence>();
                    foreach (Level level in selected)
                    {
                        ViewPlan view = ViewPlan.Create(document, ceilingTypes[0].Id, level.Id);
                        view.Name = level.Name + " - " + request.NameSuffix;
                        if (view.ViewType != ViewType.CeilingPlan || view.GenLevel?.Id != level.Id || view.GetTypeId() != ceilingTypes[0].Id || view.Name != level.Name + " - RCP")
                            throw new InvalidOperationException("Created view did not match the RCP type/level/name contract.");
                        observed.Add(view.Name);
                        observedViews.Add(new RcpCreatedViewEvidence(view.Id.Value.ToString(), view.Name, view.ViewType.ToString(),
                            ceilingTypes[0].Name, view.GenLevel!.Name, view.GenLevel.Id.Value.ToString()));
                        assertions.Add("PASS:created:" + view.Name);
                    }
                    createdNames = observed.ToArray();
                    createdViews = observedViews.ToArray();
                    if (transaction.Commit() != TransactionStatus.Committed) throw new InvalidOperationException("RCP QA transaction did not commit for inspection.");
                }
                finally { rollbackStatus = group.RollBack().ToString(); }
            }
            baselineRestored = before.SequenceEqual(ViewIds(document));
            if (rollbackStatus != "RolledBack" || !baselineRestored) throw new InvalidOperationException("RCP transaction rollback did not restore the baseline view IDs.");
            if (!Hash(request.ModelPath).Equals(request.ModelSha256, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("RCP model bytes changed during QA.");
            if (request.ExpiresUtc <= DateTimeOffset.UtcNow) throw new InvalidOperationException("RCP QA request expired during execution.");
            assertions.Add("PASS:rollback-restored-baseline");
            assertions.Add("PASS:model-file-hash-unchanged");
            status = "Passed";
        }
        catch (Exception ex) { errors.Add(ex.ToString()); status = "Failed"; }
        finally
        {
            if (document is not null)
            {
                try { document.Close(false); cleanupStatus = "Closed"; }
                catch (Exception ex) { cleanupStatus = "Failed"; errors.Add("Cleanup failed: " + ex); status = "Failed"; }
            }
            else cleanupStatus = "NotRequired";
            if (request is not null && reportPath is not null)
            {
                try
                {
                    var report = new RcpQaReport(1, requestId, request.RequestSha256, taskId, workflowId, RcpQaRequest.Test, RcpQaRequest.Test,
                        attemptId, runId, claimId, status, fixtureId, fixtureSha, modelSha, artifactSha, supportArtifactSha, viewTypeName,
                        expectedNames, createdNames, createdViews, rollbackStatus, baselineRestored, cleanupStatus, errors.ToArray(), assertions.ToArray(), DateTimeOffset.UtcNow);
                    WriteNew(reportPath, report);
                    string resultPath = requestPath! + ".result.json";
                    var receipt = new RcpQaReceipt(1, requestId, request.RequestSha256, taskId, workflowId, RcpQaRequest.Test, RcpQaRequest.Test,
                        attemptId, runId, claimId, status, reportPath, Hash(reportPath), artifactSha, supportArtifactSha);
                    WriteNew(resultPath, receipt);
                }
                catch (Exception ex) { app.Application.WriteJournalComment("RCP QA evidence publication failed: " + ex, false); }
            }
        }
    }

    private static long[] ViewIds(Document document) => new FilteredElementCollector(document).OfClass(typeof(ViewPlan)).Cast<ViewPlan>()
        .Select(view => view.Id.Value).Order().ToArray();

    private static string ValidateLocalPath(string path, bool requireExisting)
    {
        if (!Path.IsPathFullyQualified(path) || path.StartsWith("\\\\", StringComparison.Ordinal) || path.IndexOf(':', 2) >= 0) throw new InvalidDataException("Only absolute local paths are accepted.");
        string full = Path.GetFullPath(path);
        string root = Path.GetFullPath(@"C:\Repato-Autonomous\Source\QA\TestRuns") + Path.DirectorySeparatorChar;
        if (!full.StartsWith(root, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("RCP request must be under QA/TestRuns.");
        if (requireExisting && !File.Exists(full)) throw new FileNotFoundException("RCP request is missing.", full);
        for (string? item = full; item is not null; item = Path.GetDirectoryName(item))
            if ((File.Exists(item) || Directory.Exists(item)) && (File.GetAttributes(item) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("Reparse points are prohibited.");
        return full;
    }

    private static string Hash(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));

    private static void WriteNew<T>(string path, T value)
    {
        using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        JsonSerializer.Serialize(stream, value, new JsonSerializerOptions { WriteIndented = true });
        stream.Flush(true);
    }
}
