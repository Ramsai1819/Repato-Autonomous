using System.IO;
using System.Text.Json;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;
using Autodesk.Revit.UI.Events;
using Repato.ToolQaFramework;

namespace Repato.Revit.TestRunner;

// QA-only application entry point selected by Repato.CreatePlanViews.TestRunner.addin.
public sealed class CreatePlanViewsQaApplication : IExternalApplication
{
    public const string RequestEnvironmentVariable = "REPATO_QA_CREATE_PLAN_VIEWS_REQUEST";
    public const string LevelInventoryEnvironmentVariable = "REPATO_QA_CREATE_PLAN_VIEWS_LEVEL_INVENTORY";
    public const string FixturePreparationEnvironmentVariable = "REPATO_QA_CREATE_PLAN_VIEWS_FIXTURE_PREPARATION";
    private string? requestPath;
    private string? levelInventoryRequestPath;
    private string? fixturePreparationRequestPath;

    public Result OnStartup(UIControlledApplication application)
    {
        levelInventoryRequestPath = Environment.GetEnvironmentVariable(LevelInventoryEnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(levelInventoryRequestPath))
        {
            application.Idling += InspectLevelsOnce;
            return Result.Succeeded;
        }

        fixturePreparationRequestPath = Environment.GetEnvironmentVariable(FixturePreparationEnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(fixturePreparationRequestPath))
        {
            application.Idling += PrepareFixtureOnce;
            return Result.Succeeded;
        }

        requestPath = Environment.GetEnvironmentVariable(RequestEnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(requestPath)) application.Idling += RunOnce;
        return Result.Succeeded;
    }

    public Result OnShutdown(UIControlledApplication application)
    {
        application.Idling -= RunOnce;
        application.Idling -= InspectLevelsOnce;
        application.Idling -= PrepareFixtureOnce;
        return Result.Succeeded;
    }

    private void PrepareFixtureOnce(object? sender, IdlingEventArgs args)
    {
        if (sender is not UIApplication app) return;
        app.Idling -= PrepareFixtureOnce;
        try
        {
            PrepareFixtureCore(app);
        }
        catch (Exception ex)
        {
            try
            {
                string requestPath = QAPathPolicy.ValidatePath(fixturePreparationRequestPath!, QAPathPolicy.RunsRoot, false);
                using JsonDocument requestDocument = JsonDocument.Parse(File.ReadAllText(requestPath));
                JsonElement request = requestDocument.RootElement;
                string outputPath = QAPathPolicy.ValidatePath(request.GetProperty("outputPath").GetString()!, QAPathPolicy.RunsRoot, false);
                if (!File.Exists(outputPath))
                {
                    using var stream = new FileStream(outputPath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                    JsonSerializer.Serialize(stream, new
                    {
                        SchemaVersion = 1,
                        Operation = "prepare-disposable-create-plan-views-fixture",
                        Status = "Failed",
                        TaskId = request.GetProperty("taskId").GetString(),
                        WorkflowId = request.GetProperty("workflowId").GetString(),
                        AttemptId = request.GetProperty("attemptId").GetString(),
                        RunId = request.GetProperty("runId").GetString(),
                        ModelPath = request.GetProperty("modelPath").GetString(),
                        Error = ex.ToString()
                    }, new JsonSerializerOptions { WriteIndented = true });
                    stream.Flush(true);
                }
            }
            catch (Exception evidenceError)
            {
                app.Application.WriteJournalComment("Repato Create Plan Views fixture preparation evidence failure: " + evidenceError, false);
            }
        }
    }

    private void PrepareFixtureCore(UIApplication app)
    {
        string requestPath = QAPathPolicy.ValidatePath(fixturePreparationRequestPath!, QAPathPolicy.RunsRoot, false);
        CreatePlanViewsFixturePreparationRequest parsed = CreatePlanViewsFixturePreparationRequest.Parse(File.ReadAllText(requestPath), requestPath);
        string modelPath = QAPathPolicy.ValidatePath(parsed.ModelPath, QAPathPolicy.RunsRoot, true);
        string expectedModelSha256 = parsed.ModelSha256;
        string outputPath = QAPathPolicy.ValidatePath(parsed.OutputPath, QAPathPolicy.RunsRoot, false);
        string taskId = parsed.TaskId, workflowId = parsed.WorkflowId, attemptId = parsed.AttemptId, runId = parsed.RunId;
        if (File.Exists(outputPath)) throw new InvalidOperationException("Fixture preparation output already exists.");
        if (app.Application.VersionNumber != "2025") throw new InvalidOperationException("Fixture preparation requires Revit 2025.");
        if (app.Application.Documents.Size != 1 || !string.Equals(Environment.UserName, "RepatoQA", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Fixture preparation requires one open document under the RepatoQA account.");
        string selectedManifestPath = Path.GetFullPath(parsed.SelectedManifestPath);
        string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        string expectedManifestPath = Path.Combine(appData, "Autodesk", "Revit", "Addins", "2025", "Repato.CreatePlanViews.TestRunner.addin");
        if (!selectedManifestPath.Equals(expectedManifestPath, StringComparison.OrdinalIgnoreCase) ||
            !File.Exists(selectedManifestPath) ||
            !TestRunReport.Hash(selectedManifestPath).Equals(parsed.SelectedManifestSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Fixture preparation selected runner manifest is missing or differs from its request-bound identity.");
        AddinIsolationPolicy.RequireAllowed(new TestRunReport(), selectedManifestPath, parsed.SelectedManifestSha256);
        Document document = app.ActiveUIDocument?.Document ?? throw new InvalidOperationException("No fixture document is open for preparation.");
        if (!Path.GetFullPath(document.PathName).Equals(modelPath, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Open document does not match the fixture preparation request.");
        using (BasicFileInfo info = BasicFileInfo.Extract(modelPath))
            if (info.IsWorkshared || info.IsCentral || info.IsLocal || info.Format != "2025")
                throw new InvalidOperationException("Fixture preparation target is not a local non-workshared Revit 2025 model.");
        if (!TestRunReport.Hash(modelPath).Equals(expectedModelSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Fixture preparation input hash does not match the request.");

        var levels = new FilteredElementCollector(document).OfClass(typeof(Level)).Cast<Level>().ToArray();
        Level level0 = levels.SingleOrDefault(level => level.Name.Equals("Level 0", StringComparison.Ordinal))
            ?? throw new InvalidOperationException("Expected source level 'Level 0' was not present exactly once.");
        Level level1 = levels.SingleOrDefault(level => level.Name.Equals("Level 1", StringComparison.Ordinal))
            ?? throw new InvalidOperationException("Expected source level 'Level 1' was not present exactly once.");
        if (levels.Length != 2 || levels.Any(level => level.Name is "0" or "1" or "2"))
            throw new InvalidOperationException("Fixture already contains one or more target level names.");

        const double level2ElevationMillimeters = 7800;
        using (var transaction = new Transaction(document, "Prepare disposable Create Plan Views fixture"))
        {
            transaction.Start();
            level0.Name = "0";
            level1.Name = "1";
            Level.Create(document, UnitUtils.ConvertToInternalUnits(level2ElevationMillimeters, UnitTypeId.Millimeters)).Name = "2";
            if (transaction.Commit() != TransactionStatus.Committed)
                throw new InvalidOperationException("Fixture preparation transaction did not commit.");
        }
        document.Save();
        var preparedLevels = new FilteredElementCollector(document).OfClass(typeof(Level)).Cast<Level>()
            .Where(level => level.Name is "0" or "1" or "2")
            .OrderBy(level => level.Name, StringComparer.Ordinal)
            .Select(level => new { ElementId = level.Id.Value, level.Name, ElevationMeters = UnitUtils.ConvertFromInternalUnits(level.Elevation, UnitTypeId.Meters) })
            .ToArray();
        if (preparedLevels.Length != 3 || !preparedLevels.Select(level => level.Name).SequenceEqual(new[] { "0", "1", "2" }))
            throw new InvalidOperationException("Prepared fixture did not contain exactly the required levels.");
        string resultHash = TestRunReport.Hash(modelPath);
        using (var stream = new FileStream(outputPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(stream, new
            {
                SchemaVersion = 1,
                Operation = "prepare-disposable-create-plan-views-fixture",
                Status = "Passed",
                TaskId = taskId,
                WorkflowId = workflowId,
                AttemptId = attemptId,
                RunId = runId,
                ModelPath = modelPath,
                SourceModelSha256 = expectedModelSha256,
                PreparedModelSha256 = resultHash,
                ElevationSource = "CreateLevelsTestCommand specification: 7800 mm",
                Levels = preparedLevels
            }, new JsonSerializerOptions { WriteIndented = true });
            stream.Flush(true);
        }
    }

    private void InspectLevelsOnce(object? sender, IdlingEventArgs args)
    {
        if (sender is not UIApplication app) return;
        app.Idling -= InspectLevelsOnce;

        string requestPath = QAPathPolicy.ValidatePath(levelInventoryRequestPath!, QAPathPolicy.RunsRoot, false);
        using JsonDocument requestDocument = JsonDocument.Parse(File.ReadAllText(requestPath));
        JsonElement request = requestDocument.RootElement;
        string modelPath = QAPathPolicy.ValidatePath(request.GetProperty("modelPath").GetString()!, QAPathPolicy.RunsRoot, true);
        string expectedModelSha256 = request.GetProperty("modelSha256").GetString() ?? "";
        string outputPath = QAPathPolicy.ValidatePath(request.GetProperty("outputPath").GetString()!, QAPathPolicy.RunsRoot, false);
        string taskId = request.GetProperty("taskId").GetString() ?? "";
        string attemptId = request.GetProperty("attemptId").GetString() ?? "";
        string runId = request.GetProperty("runId").GetString() ?? "";

        if (!Guid.TryParseExact(attemptId, "N", out _) || !Guid.TryParseExact(runId, "N", out _))
            throw new InvalidOperationException("Level inventory attempt/run identity is invalid.");
        if (!Path.GetDirectoryName(modelPath)!.Equals(Path.GetDirectoryName(requestPath), StringComparison.OrdinalIgnoreCase) ||
            !Path.GetDirectoryName(outputPath)!.Equals(Path.GetDirectoryName(requestPath), StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Inventory request, model, and output must share one attempt directory.");
        if (File.Exists(outputPath)) throw new InvalidOperationException("Level inventory output already exists.");
        if (app.Application.VersionNumber != "2025") throw new InvalidOperationException("Level inventory requires Revit 2025.");
        Document document = app.ActiveUIDocument?.Document ?? throw new InvalidOperationException("No fixture document is open for level inventory.");
        if (!Path.GetFullPath(document.PathName).Equals(modelPath, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Open document does not match the level inventory request.");
        string actualModelSha256 = TestRunReport.Hash(modelPath);
        if (!actualModelSha256.Equals(expectedModelSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Fixture hash does not match the level inventory request.");
        using (BasicFileInfo info = BasicFileInfo.Extract(modelPath))
            if (info.IsWorkshared || info.IsCentral || info.IsLocal || info.Format != "2025")
                throw new InvalidOperationException("Level inventory target is not a local non-workshared Revit 2025 fixture.");

        var levels = new FilteredElementCollector(document).OfClass(typeof(Level)).Cast<Level>()
            .OrderBy(level => level.Elevation)
            .ThenBy(level => level.Name, StringComparer.OrdinalIgnoreCase)
            .Select(level => new
            {
                ElementId = level.Id.Value,
                level.Name,
                ElevationInternalFeet = level.Elevation,
                ElevationFeet = UnitUtils.ConvertFromInternalUnits(level.Elevation, UnitTypeId.Feet),
                ElevationMeters = UnitUtils.ConvertFromInternalUnits(level.Elevation, UnitTypeId.Meters)
            }).ToArray();

        string temporaryPath = outputPath + ".partial";
        using (var stream = new FileStream(temporaryPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(stream, new
            {
                SchemaVersion = 1,
                Inspection = "read-only-revit-level-inventory",
                TaskId = taskId,
                AttemptId = attemptId,
                RunId = runId,
                ModelPath = modelPath,
                ModelSha256 = actualModelSha256,
                RevitVersion = $"{app.Application.VersionName}; {app.Application.VersionNumber}; {app.Application.VersionBuild}",
                Levels = levels
            }, new JsonSerializerOptions { WriteIndented = true });
            stream.Flush(true);
        }
        File.Move(temporaryPath, outputPath);
        if (!TestRunReport.Hash(modelPath).Equals(expectedModelSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Fixture hash changed during read-only level inventory.");
    }

    private void RunOnce(object? sender, IdlingEventArgs args)
    {
        if (sender is not UIApplication app) return;
        app.Idling -= RunOnce;
        CreatePlanViewsRequest? request = null;
        string? receiptPath = null;
        var report = new TestRunReport
        {
            TestId = CreatePlanViewsRequest.Test,
            FixtureId = "CreatePlanViewsEmpty",
            Inputs = new { Levels = new[] { "0", "1", "2" }, ViewType = "FloorPlan", Scale = 100, TemplateIntent = "Architectural" }
        };
        try
        {
            string path = QAPathPolicy.ValidatePath(requestPath!, QAPathPolicy.RunsRoot, false);
            receiptPath = QAPathPolicy.ValidatePath(path + ".result.json", QAPathPolicy.RunsRoot, false);
            if (File.Exists(receiptPath)) throw new InvalidOperationException("This QA request already has a result; prepare a new attempt.");
            string json = File.ReadAllText(path);
            ToolQaRegistry.LoadBuiltIn().ValidateRunner(CreatePlanViewsRequest.Test, typeof(CreatePlanViewsQaApplication).FullName!);
            request = CreatePlanViewsRequest.Parse(json, path);
            report.RunId = request.RunId;
            report.RequestId = request.RequestId;
            report.TaskId = request.TaskId;
            report.WorkflowId = request.WorkflowId;
            report.AttemptId = request.AttemptId;
            report.ClaimId = request.ClaimId;
            report.IdentifyAssembly();
            report.RevitVersion = $"{app.Application.VersionName}; {app.Application.VersionNumber}; {app.Application.VersionBuild}";
            report.Assert("request-identity", true, new { request.RequestId, request.TaskId, request.WorkflowId, request.AttemptId, request.RunId, request.ClaimId },
                new { request.RequestId, request.TaskId, request.WorkflowId, request.AttemptId, request.RunId, request.ClaimId });
            if (request.ExpiresUtc <= DateTimeOffset.UtcNow) throw new InvalidOperationException("QA request expired before execution.");
            if (!string.Equals(Environment.UserName, "RepatoQA", StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Automated startup is restricted to the RepatoQA Windows account.");
            if (app.Application.VersionNumber != "2025" || app.Application.Documents.Size != 0) throw new InvalidOperationException("Start a fresh Revit 2025 QA session with no open documents.");

            string manifestPath = Path.GetFullPath(request.ManifestPath);
            if (!File.Exists(manifestPath) || !TestRunReport.Hash(manifestPath).Equals(request.ManifestSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Selected runner manifest is missing or its request-bound SHA-256 changed.");
            VerifyManifestBinding(manifestPath);
            AddinIsolationPolicy.RequireAllowed(report, manifestPath, request.ManifestSha256);

            string model = QAPathPolicy.ValidatePath(request.ModelPath, QAPathPolicy.RunsRoot, true);
            if (!Path.GetDirectoryName(model)!.Equals(Path.GetDirectoryName(path), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Request and disposable model must be in the same attempt directory.");
            if (!TestRunReport.Hash(model).Equals(request.ModelSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Disposable model SHA-256 does not match the launch request.");
            string fixture = QAPathPolicy.ValidatePath(Path.Combine(QAPathPolicy.RepositoryRoot, "QA", "Fixtures", "CreatePlanViewsEmpty.rvt"),
                Path.Combine(QAPathPolicy.RepositoryRoot, "QA", "Fixtures"), true);
            string preparationRequestPath = QAPathPolicy.ValidatePreparationEvidencePath(request.FixturePreparationRequestPath, QAPathPolicy.RunsRoot);
            string preparationResultPath = QAPathPolicy.ValidatePreparationEvidencePath(request.FixturePreparationResultPath, QAPathPolicy.RunsRoot);
            CreatePlanViewsPreparationEvidenceContract.Verify(request, fixture, model);
            string sidecar = QAPathPolicy.ValidatePath(model + ".fixture.json", QAPathPolicy.RunsRoot, false);
            using (var provenance = JsonDocument.Parse(RecoveredFixtureProvenance.Resolve(model, request).GetRawText()))
            {
                JsonElement root = provenance.RootElement;
                string expectedFixture = ToolQaRegistry.LoadBuiltIn().Get(CreatePlanViewsRequest.Test).FixtureSpecId;
                string fixtureHash = root.GetProperty("sourceSha256").GetString() ?? "";
                if (root.GetProperty("fixtureId").GetString() != expectedFixture ||
                    !fixtureHash.Equals(request.FixtureSha256, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Controlled CreatePlanViewsEmpty fixture provenance failed.");
                report.FixtureSha256 = fixtureHash;
            }
            using (BasicFileInfo info = BasicFileInfo.Extract(model))
                if (info.IsWorkshared || info.IsCentral || info.IsLocal || info.Format != "2025")
                    throw new InvalidOperationException("Only the disposable local, non-workshared Revit 2025 fixture is allowed.");

            app.OpenAndActivateDocument(model);
            if (request.ExpiresUtc <= DateTimeOffset.UtcNow) throw new InvalidOperationException("QA request expired while opening the disposable model.");
            Document document = app.ActiveUIDocument?.Document ?? throw new InvalidOperationException("QA model did not become active.");
            TestSafetyGate.Verify(document, report, "CreatePlanViewsEmpty", request);
            Execute(document, report);
            report.RuntimeModelSha256 = TestRunReport.Hash(model);
            report.Assert("runtime-model-restored", report.RuntimeModelSha256.Equals(request.ModelSha256, StringComparison.OrdinalIgnoreCase), request.ModelSha256, report.RuntimeModelSha256);
        }
        catch (Exception ex)
        {
            report.Status = "Failed";
            report.Errors.Add("Create Plan Views runner failure: " + ex);
        }
        finally
        {
            report.FinishedUtc = DateTimeOffset.UtcNow;
            report.DurationMilliseconds = (report.FinishedUtc - report.StartedUtc).TotalMilliseconds;
            if (report.RollbackStatus != "RolledBack") report.Status = "Failed";
            try
            {
                string reportFile = report.Write();
                if (request is not null && receiptPath is not null)
                    QaRunnerFoundation.WriteReceiptAtomic(receiptPath, CreatePlanViewsResultContract.CreateReceipt(request,
                        report.RequestId, report.TaskId, report.WorkflowId, report.TestId, report.AttemptId, report.RunId,
                        report.ClaimId, report.Status, reportFile));
            }
            catch (Exception ex)
            {
                app.Application.WriteJournalComment("Repato Create Plan Views QA evidence failure: " + ex, false);
            }
        }
    }

    private static void VerifyManifestBinding(string manifestPath)
    {
        var xml = new System.Xml.XmlDocument { XmlResolver = null };
        xml.Load(manifestPath);
        var application = xml.SelectSingleNode("/RevitAddIns/AddIn[@Type='Application']") as System.Xml.XmlElement
            ?? throw new InvalidDataException("Selected manifest has no application entry.");
        if (application.SelectSingleNode("FullClassName")?.InnerText != typeof(CreatePlanViewsQaApplication).FullName)
            throw new InvalidDataException("Selected manifest does not bind this exact Create Plan Views runner class.");
        string assembly = application.SelectSingleNode("Assembly")?.InnerText ?? "";
        string assemblyPath = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(manifestPath)!, assembly));
        if (!File.Exists(assemblyPath) || !Path.GetFullPath(typeof(CreatePlanViewsQaApplication).Assembly.Location).Equals(assemblyPath, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Manifest assembly path does not resolve to the loaded candidate assembly.");
    }

    private static void Execute(Document document, TestRunReport report)
    {
        var levels = new[] { "0", "1", "2" }.Select(name =>
            new FilteredElementCollector(document).OfClass(typeof(Level)).Cast<Level>()
                .SingleOrDefault(level => level.Name.Equals(name, StringComparison.OrdinalIgnoreCase)))
            .ToArray();
        if (levels.Any(level => level is null)) throw new InvalidOperationException("Required levels 0, 1, and 2 are not present in the controlled fixture.");
        report.Assert("required-levels-present", true, new[] { "0", "1", "2" }, levels.Select(level => level!.Name).ToArray());
        ViewFamilyType[] floorPlanTypes = new FilteredElementCollector(document).OfClass(typeof(ViewFamilyType)).Cast<ViewFamilyType>()
            .Where(type => type.ViewFamily == ViewFamily.FloorPlan).ToArray();
        ElementId defaultFloorPlanTypeId = document.GetDefaultElementTypeId(ElementTypeGroup.ViewTypeFloorPlan);
        ViewFamilyType floorPlanType = ViewFamilyTypeSelection.SelectDefault(floorPlanTypes, type => type.Id == defaultFloorPlanTypeId);
        ViewPlan template = ArchitecturalTemplateSelection.SelectDefaultTemplate(
            new FilteredElementCollector(document).OfClass(typeof(ViewPlan)).Cast<ViewPlan>(),
            view => view.IsTemplate, view => view.Name, view => view.Id.Value);
        report.Assert("architectural-template-intent", true, "Architectural", template.Name);

        var baselinePlanIds = new FilteredElementCollector(document).OfClass(typeof(ViewPlan)).Cast<ViewPlan>()
            .Select(view => view.Id.Value).Order().ToArray();
        using var group = new TransactionGroup(document, "Repato QA Create Plan Views - rollback required");
        if (group.Start() != TransactionStatus.Started) throw new InvalidOperationException("Could not start QA transaction group.");
        report.RollbackStatus = "Required";
        try
        {
            using var transaction = new Transaction(document, "Create Plan Views QA");
            if (transaction.Start() != TransactionStatus.Started) throw new InvalidOperationException("Could not start Create Plan Views transaction.");
            foreach (Level level in levels!)
            {
                ViewPlan view = ViewPlan.Create(document, floorPlanType.Id, level.Id);
                view.Name = "Floor Plan - Level " + level.Name;
                view.Scale = 100;
                view.ViewTemplateId = template.Id;
                report.CreatedIds.Add(view.Id.Value.ToString());
                bool matches = view.ViewType == ViewType.FloorPlan && view.GenLevel?.Id == level.Id && view.Scale == 100 &&
                    view.Name == "Floor Plan - Level " + level.Name && view.ViewTemplateId == template.Id;
                report.Assert("created-floor-plan-level-" + level.Name, matches,
                    new { ViewType = "FloorPlan", Level = level.Name, Scale = 100, Template = template.Name },
                    new { ViewType = view.ViewType.ToString(), Level = view.GenLevel?.Name, view.Scale, view.Name, TemplateId = view.ViewTemplateId.Value });
                if (!matches) throw new InvalidOperationException("Created floor plan did not meet the requested view contract for level " + level.Name + ".");
            }
            if (transaction.Commit() != TransactionStatus.Committed) throw new InvalidOperationException("Create Plan Views transaction did not commit for inspection.");
        }
        finally
        {
            report.RollbackStatus = group.RollBack().ToString();
        }
        long[] finalPlanIds = new FilteredElementCollector(document).OfClass(typeof(ViewPlan)).Cast<ViewPlan>()
            .Select(view => view.Id.Value).Order().ToArray();
        bool restored = baselinePlanIds.SequenceEqual(finalPlanIds);
        report.Assert("rollback-status", report.RollbackStatus == "RolledBack", "RolledBack", report.RollbackStatus);
        report.Assert("baseline-plan-views-restored", restored, baselinePlanIds, finalPlanIds);
        if (!restored || report.RollbackStatus != "RolledBack") throw new InvalidOperationException("Transaction rollback did not restore the baseline plan views.");
        report.Status = report.Errors.Count == 0 && report.Assertions.Count > 0 && report.Assertions.All(assertion => assertion.Passed) ? "Passed" : "Failed";
    }
}
