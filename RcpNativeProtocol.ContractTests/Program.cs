using System.Security.Cryptography;
using System.Text.Json;
using Repato.QaLaunchAgent;
using Repato.ToolQaFramework;

static void Check(bool value, string message) { if (!value) throw new InvalidOperationException("FAILED: " + message); }
static void Reject(Action action, string message) { try { action(); } catch (InvalidDataException) { return; } throw new InvalidOperationException("FAILED: " + message); }
string root = Path.Combine(Path.GetTempPath(), "repato-rcp-native-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
try
{
    string runtime = Directory.CreateDirectory(Path.Combine(root, "runtime")).FullName;
    string candidate = Directory.CreateDirectory(Path.Combine(root, "candidate")).FullName;
    string manifests = Directory.CreateDirectory(Path.Combine(root, "manifests")).FullName;
    string isolation = Directory.CreateDirectory(Path.Combine(root, "isolation")).FullName;
    string Put(string dir, string name, string body) { var path = Path.Combine(dir, name); File.WriteAllText(path, body); return path; }
    string Hash(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
    string model = Put(runtime, "model.rvt", "synthetic model");
    string evidence = Put(runtime, "fixture.evidence.json", "synthetic authenticated evidence");
    string requestPath = Path.Combine(runtime, "runner.request.json");
    string artifact = Put(candidate, "Repato.RcpQaRunner.dll", "candidate");
    string support = Put(candidate, "Repato.Revit.dll", "runner support");
    string manifest = Put(manifests, "Repato.CreateRcpViews.TestRunner.addin", "<RevitAddIns><AddIn Type=\"Application\"><Assembly>..\\candidate\\Repato.RcpQaRunner.dll</Assembly><FullClassName>Repato.RcpQaRunner.RcpQaApplication</FullClassName></AddIn></RevitAddIns>");
    string policy = Put(isolation, "isolation.json", "{\"schemaVersion\":1,\"machineWideRoot\":\"C:\\\\ProgramData\\\\Autodesk\\\\Revit\\\\Addins\\\\2025\",\"approvedMachineWideManifests\":[]}");
    var seed = new RcpQaLaunchRequest(1, RcpQaLaunchPolicy.Operation, Guid.NewGuid().ToString("N"), new string('0',64),
        "task-synthetic", Guid.NewGuid().ToString("N"), RcpQaLaunchPolicy.ToolId, RcpQaLaunchPolicy.ToolId,
        Guid.NewGuid().ToString("N"), Guid.NewGuid().ToString("N"), Guid.NewGuid().ToString("N"), requestPath, new string('0',64),
        model, Hash(model), "RcpEmptyThreeLevels", new string('A',64), evidence, Hash(evidence), artifact, Hash(artifact), support, Hash(support),
        manifest, Hash(manifest), policy, Hash(policy), DateTimeOffset.UtcNow.AddMinutes(15));
    (RcpQaLaunchRequest req, string json) BindRunner(RcpQaLaunchRequest value)
    {
        var runner = new Dictionary<string, object?>
        {
            ["schemaVersion"] = 1, ["operation"] = RcpQaLaunchPolicy.RunnerRequestOperation,
            ["requestId"] = value.RequestId, ["requestSha256"] = new string('0',64), ["taskId"] = value.TaskId,
            ["workflowId"] = value.WorkflowId, ["qaWorkflowId"] = value.QaWorkflowId, ["testId"] = value.TestId,
            ["attemptId"] = value.AttemptId, ["runId"] = value.RunId, ["claimId"] = value.ClaimId,
            ["requestPath"] = value.RequestPath, ["modelPath"] = value.ModelPath, ["modelSha256"] = value.ModelSha256,
            ["fixtureId"] = value.FixtureId, ["fixtureSha256"] = value.FixtureSha256,
            ["manifestPath"] = value.ManifestPath, ["manifestSha256"] = value.ManifestSha256,
            ["artifactSha256"] = value.CandidateSha256, ["supportArtifactSha256"] = value.SupportArtifactSha256,
            ["expiresUtc"] = value.ExpiresUtc, ["levelNames"] = new[] { "Level 0", "Level 1", "Level 2" },
            ["viewTypeName"] = "Ceiling Plan", ["nameSuffix"] = "RCP"
        };
        string runnerJson = JsonSerializer.Serialize(runner);
        runner["requestSha256"] = RcpQaLaunchPolicy.CanonicalSha256(runnerJson);
        File.WriteAllText(value.RequestPath, JsonSerializer.Serialize(runner));
        value = value with { RunnerRequestFileSha256 = Hash(value.RequestPath), RequestSha256 = new string('0',64) };
        string nativeJson = JsonSerializer.Serialize(value, QaLaunchPolicy.JsonOptions);
        value = value with { RequestSha256 = RcpQaLaunchPolicy.CanonicalSha256(nativeJson) };
        return (value, JsonSerializer.Serialize(value, QaLaunchPolicy.JsonOptions));
    }
    (var req, var json) = BindRunner(seed);
    var roots = new RcpQaLaunchRoots(runtime, candidate, manifests, isolation, "RepatoQA", "synthetic-sid");
    var descriptor = ToolQaRegistry.LoadBuiltIn().Get(RcpQaLaunchPolicy.ToolId);
    var binding = new RcpQaLaunchPolicy.ToolQaDescriptorBinding(descriptor.ToolId, descriptor.TestId, descriptor.RunnerIdentity, descriptor.ManifestFile, descriptor.RequestSchemaVersion, descriptor.RequestOperation);
    RcpQaLaunchPolicy.Validate(req, json, roots, binding, DateTimeOffset.UtcNow, "RepatoQA", "synthetic-sid", true);
    Check(true, "valid RCP schema 1 envelope and distinct evidence/model files accepted");
    Reject(() => RcpQaLaunchPolicy.Validate(req with { QaWorkflowId = "create-plan-views-v1" }, json, roots, binding, DateTimeOffset.UtcNow, "RepatoQA", "synthetic-sid", true), "cross-tool request rejected");
    Reject(() => RcpQaLaunchPolicy.Validate(req with { ExpiresUtc = DateTimeOffset.UtcNow.AddSeconds(-1) }, json, roots, binding, DateTimeOffset.UtcNow, "RepatoQA", "synthetic-sid", true), "expired request rejected");
    Reject(() => RcpQaLaunchPolicy.Validate(req with { CandidateSha256 = new string('B',64) }, json, roots, binding, DateTimeOffset.UtcNow, "RepatoQA", "synthetic-sid", true), "candidate hash mismatch rejected");
    Reject(() => RcpQaLaunchPolicy.Validate(req with { FixtureEvidencePath = model }, json, roots, binding, DateTimeOffset.UtcNow, "RepatoQA", "synthetic-sid", true), "fixture JSON path cannot be confused with model path");
    Reject(() => RcpQaLaunchPolicy.Validate(req, json, roots with { ManifestRoot = runtime }, binding, DateTimeOffset.UtcNow, "RepatoQA", "synthetic-sid", true), "manifest root mismatch rejected");
    Reject(() => RcpQaLaunchPolicy.Validate(req, json, roots, binding, DateTimeOffset.UtcNow, "wrong-user", "synthetic-sid", true), "wrong Windows identity rejected");

    var identity = new FakeIdentity(); var ledger = new FakeLedger(); var dispatch = new FakeRcpDispatcher();
    var options = new QaAgentOptions("C:\\Synthetic\\Revit.exe", runtime, manifests, Path.Combine(root, "replay.json"), root,
        "RepatoQA", "synthetic-sid", RcpCandidateRoot: candidate, RcpManifestRoot: manifests, RcpIsolationRoot: isolation);
    var coordinator = new LaunchCoordinator(options, identity, ledger, new UnusedCpvLauncher(), new UnusedCpvVerifier(), dispatch, dispatch);
    RcpQaLaunchRequest NewRequest()
    {
        return BindRunner(req with { RequestId = Guid.NewGuid().ToString("N"), RequestSha256 = new string('0',64) }).Item1;
    }
    var liveReq = NewRequest(); var liveJson = JsonSerializer.Serialize(liveReq, QaLaunchPolicy.JsonOptions);
    var accepted = (RcpQaLaunchResponse)NamedPipeLaunchServer.RouteLaunchRequest(liveJson, coordinator, DateTimeOffset.UtcNow);
    Check(accepted.Accepted == true && accepted.Disposition == "accepted" && dispatch.LaunchCount == 1, "coordinator returns correlated authenticated acceptance after exactly one dispatch");
    Check(((RcpQaLaunchResponse)NamedPipeLaunchServer.RouteLaunchRequest(liveJson, coordinator, DateTimeOffset.UtcNow)).FailureCode == "request-replayed" && dispatch.LaunchCount == 1, "duplicate native request is rejected without redispatch");
    var ambiguousReq = NewRequest(); var ambiguousJson = JsonSerializer.Serialize(ambiguousReq, QaLaunchPolicy.JsonOptions); dispatch.ThrowAfterAccept = true;
    var ambiguous = (RcpQaLaunchResponse)NamedPipeLaunchServer.RouteLaunchRequest(ambiguousJson, coordinator, DateTimeOffset.UtcNow);
    Check(ambiguous.Accepted is null && ambiguous.Disposition == "unknown" && ambiguous.FailureCode == "native-disposition-unknown", "lost response after possible acceptance remains unknown and is not retried");
    dispatch.ThrowAfterAccept = false; identity.User = "other";
    var wrongIdentityReq = NewRequest(); var wrongIdentityJson = JsonSerializer.Serialize(wrongIdentityReq, QaLaunchPolicy.JsonOptions);
    Check(((RcpQaLaunchResponse)NamedPipeLaunchServer.RouteLaunchRequest(wrongIdentityJson, coordinator, DateTimeOffset.UtcNow)).FailureCode == "wrong-agent-identity" && dispatch.LaunchCount == 2, "wrong identity blocks native boundary");
    identity.User = "RepatoQA";
    var noDeployment = new LaunchCoordinator(options with { RcpCandidateRoot = null, RcpManifestRoot = null, RcpIsolationRoot = null }, identity, ledger, new UnusedCpvLauncher(), new UnusedCpvVerifier(), dispatch, dispatch);
    var gatedReq = NewRequest(); var gatedJson = JsonSerializer.Serialize(gatedReq, QaLaunchPolicy.JsonOptions);
    Check(noDeployment.HandleRcp(gatedReq, DateTimeOffset.UtcNow, gatedJson).FailureCode == "rcp-deployment-not-authorized" && dispatch.LaunchCount == 2, "RCP fails closed until protected deployment roots are configured");
    using (var unknown = JsonDocument.Parse(JsonSerializer.Serialize(NamedPipeLaunchServer.RouteLaunchRequest("{\"schemaVersion\":1,\"operation\":\"arbitrary-executable\"}", coordinator, DateTimeOffset.UtcNow))))
        Check(unknown.RootElement.GetProperty("failureCode").GetString() == "unsupported-operation", "arbitrary native operation rejected by production pipe router");
    Console.WriteLine("RCP native protocol contract passed: 13 assertions; temporary artifacts and injected process boundary only; no Revit launch.");
}
finally { Directory.Delete(root, true); }

sealed class FakeIdentity : IIdentitySessionProvider { public string User { get; set; } = "RepatoQA"; public string Sid => "synthetic-sid"; public int SessionId => 4; public bool Interactive => true; }
sealed class FakeLedger : IReplayLedger
{
    private readonly HashSet<string> _seen = new(StringComparer.Ordinal);
    public bool TryReserve(string requestId, DateTimeOffset now) => _seen.Add(requestId);
    public bool TryReserve(QaLaunchRequest request, DateTimeOffset now) => _seen.Add(request.RequestId);
}
sealed class FakeRcpDispatcher : IRcpChildProcessLauncher, IRcpChildProcessVerifier
{
    public int LaunchCount { get; private set; }
    public bool ThrowAfterAccept { get; set; }
    public RcpChildLaunchResult Launch(RcpQaLaunchRequest request, string revitExe)
    {
        LaunchCount++;
        var result = new RcpChildLaunchResult(321, "RepatoQA", "synthetic-sid", 4, revitExe, DateTimeOffset.UtcNow);
        if (ThrowAfterAccept) throw new IOException("synthetic response lost after acceptance");
        return result;
    }
    public bool Verify(RcpChildLaunchResult result, RcpQaLaunchRequest request, string revitExe, string expectedUser, string expectedSid, int currentSession) =>
        result.Pid == 321 && result.User == expectedUser && result.Sid == expectedSid && result.SessionId == currentSession && result.ImagePath == revitExe;
}
sealed class UnusedCpvLauncher : IChildProcessLauncher { public ChildLaunchResult Launch(QaLaunchRequest request, QaAgentOptions options) => throw new NotSupportedException(); }
sealed class UnusedCpvVerifier : IChildProcessVerifier { public bool Verify(ChildLaunchResult result, QaLaunchRequest request, QaAgentOptions options) => false; }
