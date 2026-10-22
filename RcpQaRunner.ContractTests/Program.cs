using System.Security.Cryptography;
using System.Text.Json;
using Repato.RcpQaRunner;
using Repato.ToolQaFramework;

static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException("FAILED: " + message); }
static void Reject(Action action, string message) { try { action(); } catch { return; } throw new InvalidOperationException("FAILED: " + message); }
string dir = Path.Combine(Path.GetTempPath(), "repato-rcp-contract-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(dir);
try
{
    string Hash(byte[] data) => Convert.ToHexString(SHA256.HashData(data));
    string model = Path.Combine(dir, "model.rvt"), requestPath = Path.Combine(dir, "request.json"), manifest = Path.Combine(dir, "Repato.CreateRcpViews.TestRunner.addin");
    byte[] modelBytes = [1, 2, 3, 4]; File.WriteAllBytes(model, modelBytes); File.WriteAllText(manifest, "synthetic manifest");
    var request = new RcpQaRequest(1, "create-rcp-views-qa", Guid.NewGuid().ToString("N"), new string('0', 64), "task-synthetic", Guid.NewGuid().ToString("N"),
        RcpQaRequest.Test, RcpQaRequest.Test, Guid.NewGuid().ToString("N"), Guid.NewGuid().ToString("N"), Guid.NewGuid().ToString("N"),
        requestPath, model, Hash(modelBytes), "RcpEmptyThreeLevels", Hash(modelBytes), manifest, Hash(File.ReadAllBytes(manifest)),
        new string('A', 64), new string('D', 64), DateTimeOffset.UtcNow.AddMinutes(15), ["Level 0", "Level 1", "Level 2"], "Ceiling Plan", "RCP");
    string json = JsonSerializer.Serialize(request);
    request = request with { RequestSha256 = RcpQaRequest.CanonicalSha256(json) };
    json = JsonSerializer.Serialize(request);
    RcpQaRequest parsed = RcpQaRequest.Parse(json, requestPath);
    Check(parsed.TestId == RcpQaRequest.Test && parsed.LevelNames.Length == 3, "strict RCP identity and deterministic inputs parse");
    Check(RcpQaRequest.RunnerIdentity == "Repato.RcpQaRunner.RcpQaApplication", "RCP uses registered shared runner identity");
    using (JsonDocument spec = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "CreateRcpViewsEmpty.fixture-spec.json"))))
    {
        ToolQaDescriptor descriptor = ToolQaRegistry.LoadBuiltIn().Get(RcpQaRequest.Test);
        Check(spec.RootElement.GetProperty("fixtureSpecId").GetString() == descriptor.FixtureSpecId &&
            spec.RootElement.GetProperty("fixtureId").GetString() == request.FixtureId, "registered RCP fixture spec matches runner contract");
    }
    string runnerAssembly = Path.Combine(dir, "Repato.RcpQaRunner.dll"); File.WriteAllBytes(runnerAssembly, [5, 6, 7]);
    string manifestXml = "<RevitAddIns><AddIn Type=\"Application\"><Assembly>.\\Repato.RcpQaRunner.dll</Assembly><FullClassName>Repato.RcpQaRunner.RcpQaApplication</FullClassName></AddIn></RevitAddIns>";
    File.WriteAllText(manifest, manifestXml);
    RcpQaManifestContract.Verify(manifest, Hash(File.ReadAllBytes(manifest)), runnerAssembly);
    Check(true, "manifest hash, runner class, and loaded assembly binding accepted");
    Reject(() => RcpQaManifestContract.Verify(manifest, new string('B', 64), runnerAssembly), "manifest hash mismatch rejected");
    Reject(() => RcpQaManifestContract.Verify(manifest, Hash(File.ReadAllBytes(manifest)), model), "manifest cannot bind a different loaded artifact");
    RcpQaStartupContract.Validate("2025", "RepatoQA", 0, requestPath);
    Check(true, "qualified identity and clean startup accepted");
    Reject(() => RcpQaStartupContract.Validate("2024", "RepatoQA", 0, requestPath), "wrong Revit version rejected");
    Reject(() => RcpQaStartupContract.Validate("2025", "OtherUser", 0, requestPath), "wrong QA identity rejected");
    Reject(() => RcpQaStartupContract.Validate("2025", "RepatoQA", 1, requestPath), "premature model open rejected");
    Reject(() => RcpQaRequest.Parse(json.Replace(RcpQaRequest.Test, "create-plan-views-v1"), requestPath), "CPV TestId cannot bind to RCP runner");
    Reject(() => RcpQaRequest.Parse(json, requestPath + ".other"), "request path must match actual request");
    Reject(() => RcpQaRequest.Parse(json.Replace("Level 1", "Level 0"), requestPath), "duplicate level inputs rejected");
    Reject(() => RcpQaRequest.Parse(json.Replace("Ceiling Plan", "Floor Plan"), requestPath), "wrong view family type rejected");
    Reject(() => RcpQaRequest.Parse(json, requestPath, DateTimeOffset.UtcNow.AddHours(1)), "expired QA request rejected");
    Reject(() => RcpQaRequest.Parse(json.Replace("task-synthetic", "task-mutated"), requestPath), "request self-hash detects identity tampering");

    string reportPath = Path.Combine(dir, request.RunId + ".report.json");
    var report = new RcpQaReport(1, request.RequestId, request.RequestSha256, request.TaskId, request.WorkflowId, request.QaWorkflowId, request.TestId,
        request.AttemptId, request.RunId, request.ClaimId, "Passed", request.FixtureId, request.FixtureSha256, request.ModelSha256,
        request.ArtifactSha256, request.SupportArtifactSha256, "Ceiling Plan", ["Level 0 - RCP", "Level 1 - RCP", "Level 2 - RCP"],
        ["Level 0 - RCP", "Level 1 - RCP", "Level 2 - RCP"],
        [new("100", "Level 0 - RCP", "CeilingPlan", "Ceiling Plan", "Level 0", "1"),
         new("101", "Level 1 - RCP", "CeilingPlan", "Ceiling Plan", "Level 1", "2"),
         new("102", "Level 2 - RCP", "CeilingPlan", "Ceiling Plan", "Level 2", "3")],
        "RolledBack", true, "Closed", [], ["PASS:views", "PASS:rollback", "PASS:model-hash"], DateTimeOffset.UtcNow);
    File.WriteAllText(reportPath, JsonSerializer.Serialize(report));
    var receipt = new RcpQaReceipt(1, request.RequestId, request.RequestSha256, request.TaskId, request.WorkflowId, request.QaWorkflowId, request.TestId,
        request.AttemptId, request.RunId, request.ClaimId, "Passed", reportPath, Hash(File.ReadAllBytes(reportPath)), request.ArtifactSha256, request.SupportArtifactSha256);
    Check(RcpQaResultContract.IsPassing(request, receipt, report, request.ArtifactSha256), "fully correlated receipt/report and rollback evidence accepted");
    Check(!RcpQaResultContract.IsPassing(request, receipt with { ClaimId = Guid.NewGuid().ToString("N") }, report, request.ArtifactSha256), "claim mismatch rejected");
    Check(!RcpQaResultContract.IsPassing(request, receipt, report with { RollbackStatus = "Committed" }, request.ArtifactSha256), "rollback failure rejected");
    Check(!RcpQaResultContract.IsPassing(request, receipt, report with { BaselineRestored = false }, request.ArtifactSha256), "baseline integrity failure rejected");
    Check(!RcpQaResultContract.IsPassing(request, receipt, report with { CleanupStatus = "Failed" }, request.ArtifactSha256), "cleanup failure rejected for passing receipt");
    Check(!RcpQaResultContract.IsPassing(request, receipt, report, new string('B', 64)), "artifact mismatch rejected");
    Check(!RcpQaResultContract.IsPassing(request, receipt, report with { SupportArtifactSha256 = new string('E', 64) }, request.ArtifactSha256), "shared support artifact mismatch rejected");
    Check(!RcpQaResultContract.IsPassing(request, receipt, report with { CreatedViews = [report.CreatedViews[0] with { ViewFamily = "FloorPlan" }, report.CreatedViews[1], report.CreatedViews[2]] }, request.ArtifactSha256), "wrong created view family rejected");
    Check(!RcpQaResultContract.IsPassing(request, receipt, report with { CreatedViews = [report.CreatedViews[0], report.CreatedViews[1] with { ElementId = "100" }, report.CreatedViews[2]] }, request.ArtifactSha256), "duplicate created element identity rejected");
    Check(!RcpQaResultContract.IsPassing(request, receipt with { ReportPath = Path.Combine(dir, "missing.json") }, report, request.ArtifactSha256), "missing report remains non-passing");
    File.AppendAllText(reportPath, " ");
    Check(!RcpQaResultContract.IsPassing(request, receipt, report, request.ArtifactSha256), "report bytes changed after receipt hash rejected");
    Console.WriteLine("RCP runner synthetic contracts passed: assertions=26; Revit invoked=false; store mutated=false.");
}
finally { Directory.Delete(dir, recursive: true); }
