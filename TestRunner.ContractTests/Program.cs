using System.Text.Json;
using Repato.Revit.TestRunner;

static void Check(bool value, string reason) { if (!value) throw new InvalidOperationException("FAILED: " + reason); }
static void Reject(Action action, string reason) { try { action(); } catch { return; } throw new InvalidOperationException("FAILED: " + reason); }

var duplicateFloorPlanTypes = new[]
{
    (Id: 1, Family: "FloorPlan"),
    (Id: 2, Family: "FloorPlan"),
    (Id: 3, Family: "CeilingPlan")
};
var floorPlanTypes = duplicateFloorPlanTypes.Where(type => type.Family == "FloorPlan").ToArray();
var selectedFloorPlanType = ViewFamilyTypeSelection.SelectDefault(floorPlanTypes, type => type.Id == 2);
Check(selectedFloorPlanType.Id == 2, "multiple floor-plan family types resolve to the configured default");
Reject(() => ViewFamilyTypeSelection.SelectDefault(floorPlanTypes, type => type.Id == 4), "missing default floor-plan family type is rejected");
Reject(() => ViewFamilyTypeSelection.SelectDefault(floorPlanTypes, type => type.Family == "FloorPlan"), "ambiguous default floor-plan family type is rejected");

var architecturalTemplates = new[]
{
    (Id: 11L, IsTemplate: true, Name: "Architectural Plan"),
    (Id: 12L, IsTemplate: true, Name: "Architectural Reflected Ceiling Plan"),
    (Id: 13L, IsTemplate: false, Name: "Architectural Plan - Working")
};
var selectedArchitecturalTemplate = ArchitecturalTemplateSelection.SelectDefaultTemplate(
    architecturalTemplates, template => template.IsTemplate, template => template.Name, template => template.Id);
Check(selectedArchitecturalTemplate.Id == 11L, "multiple architectural view templates resolve by lowest element id");
var exactArchitecturalTemplates = new[]
{
    (Id: 21L, IsTemplate: true, Name: "Architectural"),
    (Id: 22L, IsTemplate: true, Name: "Architectural Plan")
};
var exactArchitecturalTemplate = ArchitecturalTemplateSelection.SelectDefaultTemplate(
    exactArchitecturalTemplates, template => template.IsTemplate, template => template.Name, template => template.Id);
Check(exactArchitecturalTemplate.Id == 21L, "exact architectural view template name is preferred");
Reject(() => ArchitecturalTemplateSelection.SelectDefaultTemplate(
    architecturalTemplates.Where(template => !template.IsTemplate), template => template.IsTemplate, template => template.Name, template => template.Id),
    "missing architectural view template is rejected");

string pathPolicyRoot = Path.Combine(Path.GetTempPath(), "repato-runner-path-policy-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(pathPolicyRoot);
try
{
    string prepRequest = Path.Combine(pathPolicyRoot, "fixture.request.json");
    string prepResult = Path.Combine(pathPolicyRoot, "fixture.result.json");
    string modelPath = Path.Combine(pathPolicyRoot, "model.rvt");
    File.WriteAllText(prepRequest, "{}"); File.WriteAllText(prepResult, "{}"); File.WriteAllBytes(modelPath, new byte[] { 1 });
    Check(QAPathPolicy.ValidatePreparationEvidencePath(prepRequest, pathPolicyRoot) == Path.GetFullPath(prepRequest), "JSON preparation request path accepted under the attempt root");
    Check(QAPathPolicy.ValidatePreparationEvidencePath(prepResult, pathPolicyRoot) == Path.GetFullPath(prepResult), "JSON preparation result path accepted under the attempt root");
    Check(QAPathPolicy.ValidatePath(modelPath, pathPolicyRoot, requireRvt: true) == Path.GetFullPath(modelPath), "existing RVT model remains required");
    Reject(() => QAPathPolicy.ValidatePath(prepRequest, pathPolicyRoot, requireRvt: true), "JSON evidence cannot satisfy a model path check");
    Reject(() => QAPathPolicy.ValidatePath(Path.Combine(pathPolicyRoot, "missing.rvt"), pathPolicyRoot, requireRvt: true), "missing RVT model is rejected");
    Reject(() => QAPathPolicy.ValidatePreparationEvidencePath(Path.Combine(pathPolicyRoot, "..", "outside.json"), pathPolicyRoot), "preparation evidence cannot escape its allowed attempt root");
    Reject(() => QAPathPolicy.ValidatePreparationEvidencePath(Path.Combine(pathPolicyRoot, "missing.json"), pathPolicyRoot), "preparation evidence must already exist");
}
finally { Directory.Delete(pathPolicyRoot, recursive: true); }

string preparationDirectory = Path.Combine(Path.GetTempPath(), "repato-fixture-prep-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(preparationDirectory);
try
{
    string preparationRequestPath = Path.Combine(preparationDirectory, "prep.request.json");
    var preparationJson = JsonSerializer.Serialize(new
    {
        operation = "prepare-disposable-create-plan-views-fixture",
        taskId = "task-41cfec12ef3e406990d36c9997cf6591",
        workflowId = "78b5a11ab95e4cac86dcf45a1cb9cfdc",
        attemptId = Guid.NewGuid().ToString("N"),
        runId = Guid.NewGuid().ToString("N"),
        requestPath = preparationRequestPath,
        modelPath = Path.Combine(preparationDirectory, "model.rvt"),
        modelSha256 = new string('A', 64),
        selectedManifestPath = Path.Combine(preparationDirectory, "Repato.CreatePlanViews.TestRunner.addin"),
        selectedManifestSha256 = new string('B', 64),
        outputPath = Path.Combine(preparationDirectory, "prep.result.json"),
        expiresUtc = DateTimeOffset.UtcNow.AddMinutes(5)
    });
    var parsedPreparation = CreatePlanViewsFixturePreparationRequest.Parse(preparationJson, preparationRequestPath);
    Check(parsedPreparation.TaskId == "task-41cfec12ef3e406990d36c9997cf6591" && parsedPreparation.AttemptId.Length == 32 && parsedPreparation.RunId.Length == 32, "fixture-preparation request identity parses and correlates");
    Reject(() => CreatePlanViewsFixturePreparationRequest.Parse(preparationJson.Replace(parsedPreparation.RunId, Guid.NewGuid().ToString("D")), preparationRequestPath), "fixture-preparation mismatched run ID rejected");
    Reject(() => CreatePlanViewsFixturePreparationRequest.Parse(preparationJson, preparationRequestPath + ".other"), "fixture-preparation request path binding enforced");
    Reject(() => CreatePlanViewsFixturePreparationRequest.Parse(preparationJson.Replace(new string('B', 64), new string('G', 64)), preparationRequestPath), "fixture-preparation manifest hash format enforced");
}
finally { Directory.Delete(preparationDirectory, recursive: true); }

string evidenceDirectory = Path.Combine(Path.GetTempPath(), "repato-prep-evidence-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(evidenceDirectory);
try
{
    string sourceModel = Path.Combine(evidenceDirectory, "source.rvt"), preparedModel = Path.Combine(evidenceDirectory, "prepared.rvt");
    string canonicalModel = Path.Combine(evidenceDirectory, "canonical.rvt"), prepRequestPath = Path.Combine(evidenceDirectory, "prep.request.json");
    string prepResultPath = Path.Combine(evidenceDirectory, "prep.result.json");
    File.WriteAllBytes(sourceModel, new byte[] { 1, 2, 3 }); File.WriteAllBytes(preparedModel, new byte[] { 4, 5, 6 }); File.Copy(preparedModel, canonicalModel);
    string Hash(string path) => Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(path)));
    string sourceEvidenceHash = Hash(sourceModel), preparedEvidenceHash = Hash(preparedModel);
    string prepAttempt = Guid.NewGuid().ToString("N"), prepRun = Guid.NewGuid().ToString("N"), workflowId = Guid.NewGuid().ToString("N");
    string prepJson = JsonSerializer.Serialize(new { operation = "prepare-disposable-create-plan-views-fixture", taskId = "task-contract", workflowId,
        attemptId = prepAttempt, runId = prepRun, requestPath = prepRequestPath, modelPath = sourceModel, modelSha256 = sourceEvidenceHash,
        selectedManifestPath = Path.Combine(evidenceDirectory, "Repato.CreatePlanViews.TestRunner.addin"), selectedManifestSha256 = new string('B', 64),
        outputPath = prepResultPath, expiresUtc = DateTimeOffset.UtcNow.AddMinutes(5) });
    File.WriteAllText(prepRequestPath, prepJson);
    File.WriteAllText(prepResultPath, JsonSerializer.Serialize(new { Status = "Passed", Operation = "prepare-disposable-create-plan-views-fixture",
        TaskId = "task-contract", WorkflowId = workflowId, AttemptId = prepAttempt, RunId = prepRun, ModelPath = sourceModel,
        SourceModelSha256 = sourceEvidenceHash, PreparedModelSha256 = preparedEvidenceHash }));
    var evidenceRequest = new CreatePlanViewsRequest(Guid.NewGuid().ToString("N"), "task-contract", workflowId, CreatePlanViewsRequest.Test,
        CreatePlanViewsRequest.Test, Guid.NewGuid().ToString("N"), Guid.NewGuid().ToString("N"), Guid.NewGuid().ToString("N"),
        Path.Combine(evidenceDirectory, "launch.request.json"), new string('A', 64), canonicalModel, preparedEvidenceHash, sourceEvidenceHash,
        prepRequestPath, Hash(prepRequestPath), prepResultPath, Hash(prepResultPath), prepAttempt, prepRun,
        Path.Combine(evidenceDirectory, "Repato.CreatePlanViews.TestRunner.addin"), new string('B', 64), DateTimeOffset.UtcNow.AddMinutes(5));
    CreatePlanViewsPreparationEvidenceContract.Verify(evidenceRequest, sourceModel, canonicalModel);
    Check(true, "separate source and prepared model hashes accepted only with correlated preparation evidence");
    string mismatchedResult = JsonSerializer.Serialize(new { Status = "Passed", Operation = "prepare-disposable-create-plan-views-fixture",
        TaskId = "task-contract", WorkflowId = workflowId, AttemptId = Guid.NewGuid().ToString("N"), RunId = prepRun, ModelPath = sourceModel,
        SourceModelSha256 = sourceEvidenceHash, PreparedModelSha256 = preparedEvidenceHash });
    File.WriteAllText(prepResultPath, mismatchedResult);
    Reject(() => CreatePlanViewsPreparationEvidenceContract.Verify(evidenceRequest with { FixturePreparationResultSha256 = Hash(prepResultPath) }, sourceModel, canonicalModel),
        "mismatched preparation result identity rejected");
    File.WriteAllText(prepResultPath, JsonSerializer.Serialize(new { Status = "Passed", Operation = "prepare-disposable-create-plan-views-fixture",
        TaskId = "task-contract", WorkflowId = workflowId, AttemptId = prepAttempt, RunId = prepRun, ModelPath = sourceModel,
        SourceModelSha256 = sourceEvidenceHash, PreparedModelSha256 = preparedEvidenceHash }));
    Reject(() => CreatePlanViewsPreparationEvidenceContract.Verify(evidenceRequest with { FixtureSha256 = preparedEvidenceHash }, sourceModel, canonicalModel),
        "prepared model hash cannot replace source fixture hash");
}
finally { Directory.Delete(evidenceDirectory, recursive: true); }

string tempRequest = Path.Combine(Path.GetTempPath(), "repato-request-" + Guid.NewGuid().ToString("N") + ".json");
string modelHash = new('A', 64), sourceHash = new('D', 64), preparationRequestHash = new('E', 64), preparationResultHash = new('F', 64), manifestHash = new('B', 64), artifactHash = new('C', 64);
var jsonObject = new Dictionary<string, object?>
{
    ["schemaVersion"] = 2, ["operation"] = "launch-revit-qa", ["requestId"] = Guid.NewGuid().ToString("N"),
    ["taskId"] = "task-synthetic", ["workflowId"] = Guid.NewGuid().ToString("N"), ["qaWorkflowId"] = CreatePlanViewsRequest.Test,
    ["testId"] = CreatePlanViewsRequest.Test, ["attemptId"] = Guid.NewGuid().ToString("N"), ["runId"] = Environment.GetEnvironmentVariable("REPATO_CONTRACT_RUN_ID") ?? Guid.NewGuid().ToString("N"),
    ["claimId"] = Guid.NewGuid().ToString("N"), ["requestPath"] = tempRequest, ["requestSha256"] = new string('0', 64),
    ["modelPath"] = Path.Combine(Path.GetTempPath(), "model.rvt"), ["modelSha256"] = modelHash,
    ["fixtureSha256"] = sourceHash, ["fixturePreparationRequestPath"] = Path.Combine(Path.GetTempPath(), "prep.request.json"),
    ["fixturePreparationRequestSha256"] = preparationRequestHash, ["fixturePreparationResultPath"] = Path.Combine(Path.GetTempPath(), "prep.result.json"),
    ["fixturePreparationResultSha256"] = preparationResultHash, ["fixturePreparationAttemptId"] = Guid.NewGuid().ToString("N"),
    ["fixturePreparationRunId"] = Guid.NewGuid().ToString("N"),
    ["manifestPath"] = Path.Combine(Path.GetTempPath(), "Repato.CreatePlanViews.TestRunner.addin"), ["manifestSha256"] = manifestHash,
    ["expiresUtc"] = DateTimeOffset.UtcNow.AddMinutes(5)
};
string placeholderJson = JsonSerializer.Serialize(jsonObject);
jsonObject["requestSha256"] = CreatePlanViewsRequest.CanonicalSha256(placeholderJson);
string requestJson = JsonSerializer.Serialize(jsonObject);
var request = CreatePlanViewsRequest.Parse(requestJson, tempRequest);
Check(request.RequestId == (string)jsonObject["requestId"]!, "request id parsed and bound");
Check(request.AttemptId == (string)jsonObject["attemptId"]! && request.RunId == (string)jsonObject["runId"]!, "attempt/run identity parsed");
if (Environment.GetEnvironmentVariable("REPATO_CONTRACT_RUN_ID") is string producedRunId)
    Check(request.RunId == producedRunId && Guid.TryParseExact(request.RunId, "N", out _), "actual producer run id accepted and correlated by compiled runner parser");
Reject(() => CreatePlanViewsRequest.Parse(requestJson.Replace("task-synthetic", "task-tampered"), tempRequest), "tampered request self-hash rejected");
Reject(() => CreatePlanViewsRequest.Parse(requestJson, tempRequest + ".other"), "request path binding enforced");
Reject(() => CreatePlanViewsRequest.Parse(requestJson.Replace(CreatePlanViewsRequest.Test, "other-test"), tempRequest), "wrong test contract rejected");
Reject(() => CreatePlanViewsRequest.Parse(requestJson.Replace("\"schemaVersion\":2", "\"schemaVersion\":1"), tempRequest), "wrong schema rejected");

string reportPath = Path.Combine(Path.GetTempPath(), request.RunId + ".json");
var identity = new Dictionary<string, object?>
{
    ["RequestId"] = request.RequestId, ["TaskId"] = request.TaskId, ["WorkflowId"] = request.WorkflowId,
    ["TestId"] = request.TestId, ["AttemptId"] = request.AttemptId, ["RunId"] = request.RunId, ["ClaimId"] = request.ClaimId
};
var passingReport = new Dictionary<string, object?>(identity)
{
    ["Status"] = "Passed", ["RollbackStatus"] = "RolledBack", ["FixtureSha256"] = sourceHash,
    ["RuntimeModelSha256"] = modelHash, ["FinishedUtc"] = DateTimeOffset.UtcNow,
    ["AssemblyIdentity"] = new { Sha256 = artifactHash }, ["Errors"] = Array.Empty<string>(),
    ["Assertions"] = new[] { new { Passed = true } }
};
var receipt = new Dictionary<string, object?>(identity)
{
    ["QaWorkflowId"] = request.QaWorkflowId, ["ReportPath"] = reportPath, ["Status"] = "Passed"
};
string passingReportJson = JsonSerializer.Serialize(passingReport), passingReceiptJson = JsonSerializer.Serialize(receipt);
Check(CreatePlanViewsResultContract.IsPassing(passingReceiptJson, passingReportJson, request, artifactHash), "canonical passing report/receipt contract accepted");
Check(!CreatePlanViewsResultContract.IsPassing(passingReceiptJson, passingReportJson.Replace("RolledBack", "Committed"), request, artifactHash), "missing rollback proof rejected");
Check(!CreatePlanViewsResultContract.IsPassing(passingReceiptJson.Replace(request.RequestId, Guid.NewGuid().ToString("N")), passingReportJson, request, artifactHash), "unmatched receipt request id rejected");
Check(!CreatePlanViewsResultContract.IsPassing(passingReceiptJson, passingReportJson.Replace("Passed", "Failed"), request, artifactHash), "failed report cannot pass");
Check(!CreatePlanViewsResultContract.IsPassing(passingReceiptJson, passingReportJson, request, new string('D', 64)), "candidate hash mismatch rejected");
Check(!CreatePlanViewsResultContract.IsPassing(passingReceiptJson, passingReportJson.Replace(sourceHash, modelHash), request, artifactHash), "prepared-model hash cannot stand in for authoritative source fixture hash");

var failedReceipt = CreatePlanViewsResultContract.CreateReceipt(request, request.RequestId, request.TaskId, request.WorkflowId,
    request.TestId, request.AttemptId, request.RunId, request.ClaimId, "Failed", reportPath);
Check(failedReceipt.Status == "Failed" && failedReceipt.RequestId == request.RequestId, "negative runner result remains request-bound and terminally failed");
var failedReportJson = JsonSerializer.Serialize(new Dictionary<string, object?>(identity)
{
    ["Status"] = "Failed", ["RollbackStatus"] = "NotStarted", ["Errors"] = new[] { "Architectural template is unavailable." },
    ["FinishedUtc"] = DateTimeOffset.UtcNow, ["Assertions"] = Array.Empty<object>()
});
Check(!CreatePlanViewsResultContract.IsPassing(JsonSerializer.Serialize(failedReceipt), failedReportJson, request, artifactHash), "failed report and its exact error are retained but cannot pass");
Reject(() => CreatePlanViewsResultContract.CreateReceipt(request, request.RequestId, request.TaskId, request.WorkflowId,
    request.TestId, request.AttemptId, Guid.NewGuid().ToString("N"), request.ClaimId, "Passed", reportPath), "mismatched result run identity rejected");
string isolationRoot = Path.Combine(Path.GetTempPath(), "repato-isolation-contract-" + Guid.NewGuid().ToString("N"));
string machineRoot = Path.Combine(isolationRoot, "machine"), userRoot = Path.Combine(isolationRoot, "user");
string sourceRoot = Path.Combine(isolationRoot, "trusted-source"), policyPath = Path.Combine(isolationRoot, "allowlist.json");
Directory.CreateDirectory(machineRoot); Directory.CreateDirectory(userRoot); Directory.CreateDirectory(sourceRoot);
try
{
    string rcpName = "Repato.CreateRcpViews.TestRunner.addin";
    string sourceManifest = Path.Combine(sourceRoot, rcpName), installedManifest = Path.Combine(userRoot, rcpName);
    string contents = "<RevitAddIns><AddIn Type=\"Application\"><FullClassName>Repato.RcpQaRunner.RcpQaApplication</FullClassName></AddIn></RevitAddIns>";
    File.WriteAllText(sourceManifest, contents); File.Copy(sourceManifest, installedManifest);
    string policy = JsonSerializer.Serialize(new { schemaVersion = 1, machineWideRoot = machineRoot, approvedMachineWideManifests = Array.Empty<object>() });
    File.WriteAllText(policyPath, policy);
    string selectedHash = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(sourceManifest)));
    var allowed = AddinIsolationPolicy.Inspect(policyPath, machineRoot, userRoot, sourceRoot, installedManifest, selectedHash);
    Check(allowed.Allowed, "RCP selected manifest passes exact source-hash isolation binding");
    var notSelected = AddinIsolationPolicy.Inspect(policyPath, machineRoot, userRoot, sourceRoot,
        Path.Combine(userRoot, "Repato.CreatePlanViews.TestRunner.addin"), new string('B', 64));
    Check(!notSelected.Allowed, "RCP manifest is not allowlisted during a different QA workflow");
    File.WriteAllText(installedManifest, contents + "tampered");
    var mismatch = AddinIsolationPolicy.Inspect(policyPath, machineRoot, userRoot, sourceRoot, installedManifest, selectedHash);
    Check(!mismatch.Allowed, "tampered RCP selected manifest fails isolation");
    File.Copy(sourceManifest, installedManifest, true);
    File.WriteAllText(Path.Combine(userRoot, "unexpected.addin"), "<RevitAddIns />");
    var extra = AddinIsolationPolicy.Inspect(policyPath, machineRoot, userRoot, sourceRoot, installedManifest, selectedHash);
    Check(!extra.Allowed, "unexpected user-profile add-in fails RCP isolation");
}
finally { Directory.Delete(isolationRoot, recursive: true); }

// === Preparation-aware safety gate provenance regression tests ===
string sourceHash2 = new string('A', 64), preparedHash2 = new string('B', 64);
string prepAttemptId = Guid.NewGuid().ToString("N"), prepRunIdVal = Guid.NewGuid().ToString("N");

// Helper: build a sidecar JSON element from a dictionary
JsonElement MakeSidecar(Dictionary<string, object?> fields)
{
    string json = JsonSerializer.Serialize(fields);
    return JsonDocument.Parse(json).RootElement;
}

Dictionary<string, object?> MakePreparationAwareSidecar() => new()
{
    ["fixtureId"] = "CreatePlanViewsEmpty",
    ["sourceSha256"] = sourceHash2,
    ["preparedModelSha256"] = preparedHash2,
    ["fixturePreparationRequestPath"] = @"C:\Repato-Autonomous\Source\QA\TestRuns\test\prep.request.json",
    ["fixturePreparationRequestSha256"] = new string('C', 64),
    ["fixturePreparationResultPath"] = @"C:\Repato-Autonomous\Source\QA\TestRuns\test\prep.result.json",
    ["fixturePreparationResultSha256"] = new string('D', 64),
    ["fixturePreparationAttemptId"] = prepAttemptId,
    ["fixturePreparationRunId"] = prepRunIdVal
};

CreatePlanViewsRequest MakeQaRequest() => new(
    Guid.NewGuid().ToString("N"), "task-contract", Guid.NewGuid().ToString("N"), CreatePlanViewsRequest.Test,
    CreatePlanViewsRequest.Test, prepAttemptId, prepRunIdVal, Guid.NewGuid().ToString("N"),
    @"C:\Repato-Autonomous\Source\QA\TestRuns\test\launch.request.json", new string('E', 64),
    @"C:\Repato-Autonomous\Source\QA\TestRuns\test\model.rvt", preparedHash2, sourceHash2,
    @"C:\Repato-Autonomous\Source\QA\TestRuns\test\prep.request.json", new string('C', 64),
    @"C:\Repato-Autonomous\Source\QA\TestRuns\test\prep.result.json", new string('D', 64),
    prepAttemptId, prepRunIdVal, @"C:\Repato-Autonomous\Source\QA\TestRuns\test\runner.addin",
    new string('F', 64), DateTimeOffset.UtcNow.AddMinutes(5));

// 1. Valid legacy sidecar (no preparation) — runtime model matches source
{
    var sidecar = MakeSidecar(new() { ["fixtureId"] = "GridResequenceEmpty", ["sourceSha256"] = sourceHash2 });
    TestSafetyGateProvenance.Verify(sidecar, sourceHash2, sourceHash2);
    Check(true, "legacy sidecar: source fixture and runtime model both match sourceSha256");
}

// 2. Valid preparation-aware sidecar — runtime model matches preparedModelSha256
{
    var sidecar = MakeSidecar(MakePreparationAwareSidecar());
    TestSafetyGateProvenance.Verify(sidecar, sourceHash2, preparedHash2, MakeQaRequest());
    Check(true, "preparation-aware sidecar: source fixture matches sourceSha256, runtime matches preparedModelSha256");
}

// 3. Wrong runtime model hash against prepared fixture
Reject(() =>
{
    var sidecar = MakeSidecar(MakePreparationAwareSidecar());
    TestSafetyGateProvenance.Verify(sidecar, sourceHash2, new string('F', 64), MakeQaRequest());
}, "preparation-aware: wrong runtime model hash rejected");

// 4. Wrong source fixture hash
Reject(() =>
{
    var sidecar = MakeSidecar(MakePreparationAwareSidecar());
    TestSafetyGateProvenance.Verify(sidecar, new string('E', 64), preparedHash2, MakeQaRequest());
}, "preparation-aware: wrong source fixture hash rejected");

// 5. Legacy sidecar: runtime model does not match source
Reject(() =>
{
    var sidecar = MakeSidecar(new() { ["fixtureId"] = "GridResequenceEmpty", ["sourceSha256"] = sourceHash2 });
    TestSafetyGateProvenance.Verify(sidecar, sourceHash2, preparedHash2);
}, "legacy sidecar: runtime model hash mismatch rejected");

// 6. Legacy sidecar: source fixture does not match
Reject(() =>
{
    var sidecar = MakeSidecar(new() { ["fixtureId"] = "GridResequenceEmpty", ["sourceSha256"] = sourceHash2 });
    TestSafetyGateProvenance.Verify(sidecar, new string('E', 64), sourceHash2);
}, "legacy sidecar: source fixture hash mismatch rejected");

// 7. Invalid preparedModelSha256 format
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields["preparedModelSha256"] = "not-a-hash";
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, preparedHash2, MakeQaRequest());
}, "preparation-aware: invalid prepared hash format rejected");

// 8. Prepared hash equals source hash (identity must change)
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields["preparedModelSha256"] = sourceHash2;
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, sourceHash2, MakeQaRequest());
}, "preparation-aware: prepared=source hash collision rejected");

// 9. Missing fixturePreparationRequestPath
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields.Remove("fixturePreparationRequestPath");
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, preparedHash2, MakeQaRequest());
}, "preparation-aware: missing preparation request path rejected");

// 10. Missing fixturePreparationRequestSha256
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields.Remove("fixturePreparationRequestSha256");
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, preparedHash2, MakeQaRequest());
}, "preparation-aware: missing preparation request sha256 rejected");

// 11. Missing fixturePreparationResultPath
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields.Remove("fixturePreparationResultPath");
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, preparedHash2, MakeQaRequest());
}, "preparation-aware: missing preparation result path rejected");

// 12. Missing fixturePreparationResultSha256
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields.Remove("fixturePreparationResultSha256");
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, preparedHash2, MakeQaRequest());
}, "preparation-aware: missing preparation result sha256 rejected");

// 13. Missing fixturePreparationAttemptId
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields.Remove("fixturePreparationAttemptId");
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, preparedHash2, MakeQaRequest());
}, "preparation-aware: missing preparation attempt ID rejected");

// 14. Missing fixturePreparationRunId
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields.Remove("fixturePreparationRunId");
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, preparedHash2, MakeQaRequest());
}, "preparation-aware: missing preparation run ID rejected");

// 15. Invalid fixturePreparationAttemptId format (not N-format GUID)
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields["fixturePreparationAttemptId"] = "not-a-guid";
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, preparedHash2, MakeQaRequest());
}, "preparation-aware: invalid preparation attempt ID format rejected");

// 16. Invalid fixturePreparationRunId format
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields["fixturePreparationRunId"] = Guid.NewGuid().ToString("D"); // D-format not N-format
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, preparedHash2, MakeQaRequest());
}, "preparation-aware: D-format preparation run ID rejected");

// 17. Invalid fixturePreparationRequestSha256 format
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields["fixturePreparationRequestSha256"] = "ZZZZ";
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, preparedHash2);
}, "preparation-aware: invalid request sha256 format rejected");

// 18. Empty fixturePreparationRequestPath
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields["fixturePreparationRequestPath"] = "";
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, preparedHash2);
}, "preparation-aware: empty preparation request path rejected");

// 19-24. Well-formed but mismatched preparation binding values are rejected.
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields["fixturePreparationAttemptId"] = Guid.NewGuid().ToString("N");
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, preparedHash2, MakeQaRequest());
}, "preparation-aware: different canonical attempt ID rejected");
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields["fixturePreparationRunId"] = Guid.NewGuid().ToString("N");
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, preparedHash2, MakeQaRequest());
}, "preparation-aware: different canonical run ID rejected");
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields["fixturePreparationRequestSha256"] = new string('1', 64);
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, preparedHash2, MakeQaRequest());
}, "preparation-aware: mismatched request evidence hash rejected");
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields["fixturePreparationResultSha256"] = new string('2', 64);
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, preparedHash2, MakeQaRequest());
}, "preparation-aware: mismatched result evidence hash rejected");
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields["fixturePreparationResultPath"] = @"C:\Repato-Autonomous\Source\QA\TestRuns\test\other.result.json";
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, preparedHash2, MakeQaRequest());
}, "preparation-aware: mismatched result evidence path rejected");
Reject(() =>
{
    var fields = MakePreparationAwareSidecar();
    fields["preparedModelSha256"] = 42;
    TestSafetyGateProvenance.Verify(MakeSidecar(fields), sourceHash2, preparedHash2, MakeQaRequest());
}, "preparation-aware: malformed prepared hash type rejected");

// 25. Invalid sourceSha256 format
Reject(() =>
{
    var sidecar = MakeSidecar(new() { ["fixtureId"] = "Test", ["sourceSha256"] = "not-hex" });
    TestSafetyGateProvenance.Verify(sidecar, "not-hex", "not-hex");
}, "invalid sourceSha256 format rejected");

Console.WriteLine($"Create Plan Views runner contract tests passed: request parsing/binding, result identity, failed reporting, canonical verifier expectations, preparation-aware safety gate provenance (28 assertions); recovered provenance ({RecoveredProvenanceTests.Run()} assertions).");
