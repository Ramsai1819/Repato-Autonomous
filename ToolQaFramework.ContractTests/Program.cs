using System.Security.Cryptography;
using System.Text.Json;
using Repato.ToolQaFramework;

int assertions = 0;
void Check(bool value, string name) { assertions++; if (!value) throw new InvalidOperationException("FAILED: " + name); }
void Reject(Action action, string name) { assertions++; try { action(); } catch { return; } throw new InvalidOperationException("FAILED: " + name); }
string hash(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
var registry = new ToolQaRegistry(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "ToolQaRegistry.v1.json")));
var embedded = ToolQaRegistry.LoadBuiltIn();
Check(embedded.Tools.Count == 2, "runtime embedded registry loads");
var cpv = registry.Get("create-plan-views-v1");
var rcp = registry.Get("create-rcp-views-v1");
Check(registry.Tools.Count == 2 && cpv.TestId == cpv.ToolId && cpv.RequestSchemaVersion == 2, "CPV legacy request identity preserved");
Check(rcp.TestId == rcp.ToolId && rcp.RunnerIdentity == "Repato.RcpQaRunner.RcpQaApplication" && rcp.RequestSchemaVersion == 1, "RCP separately registered with its existing request contract");
Check(rcp.FixtureSpecId == "rcp-empty-three-levels-v1" && cpv.FixtureSpecId == "CreatePlanViewsEmpty", "registered fixture specs bind both tool runners");
Reject(() => registry.Get("arbitrary-runner"), "unregistered tool rejected");
Reject(() => new ToolQaRegistry("{\"schemaVersion\":1,\"tools\":[{\"toolId\":\"x\",\"testId\":\"x\",\"runnerIdentity\":\"x\",\"manifestFile\":\"../evil.addin\",\"requestSchemaVersion\":1,\"requestOperation\":\"run\",\"fixtureContractId\":\"f\",\"capabilities\":[\"arbitrary-executable\"]}]}"), "unknown capability and path traversal rejected");
string isolated = Path.Combine(Path.GetTempPath(), "repato-tool-qa-store-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(isolated);
try
{
    foreach (var descriptor in registry.Tools)
    {
        string candidate = Path.Combine(isolated, descriptor.ToolId + ".dll");
        string manifest = Path.Combine(isolated, descriptor.ManifestFile);
        File.WriteAllText(candidate, "synthetic candidate " + descriptor.ToolId);
        File.WriteAllText(manifest, "synthetic manifest " + descriptor.ToolId);
        string candidateHash = hash(candidate), manifestHash = hash(manifest);
        var binding = new ToolQaBinding(descriptor.ToolId, descriptor.TestId, descriptor.RunnerIdentity,
            candidate, candidateHash, manifest, manifestHash);
        ToolQaGate.ValidateBinding(registry, binding);
        Check(true, descriptor.ToolId + " candidate/manifest file hashes accepted");
        Reject(() => ToolQaGate.ValidateBinding(registry, binding with { RunnerIdentity = cpv.RunnerIdentity == descriptor.RunnerIdentity ? "wrong.runner" : cpv.RunnerIdentity }), "wrong runner rejected");
        File.AppendAllText(manifest, "tampered");
        Reject(() => ToolQaGate.ValidateBinding(registry, binding), "manifest byte mismatch rejected");
        File.WriteAllText(manifest, "synthetic manifest " + descriptor.ToolId);
        File.AppendAllText(candidate, "tampered");
        Reject(() => ToolQaGate.ValidateBinding(registry, binding), "candidate byte mismatch rejected");
        File.WriteAllText(candidate, "synthetic candidate " + descriptor.ToolId);

        string attempt = Guid.NewGuid().ToString("N"), run = Guid.NewGuid().ToString("N"), claim = Guid.NewGuid().ToString("N");
        var now = DateTimeOffset.UtcNow;
        var approval = new ToolQaApproval(Guid.NewGuid().ToString(), "task", "workflow", descriptor.ToolId,
            descriptor.TestId, attempt, run, claim, candidateHash, manifestHash, 4, now.AddMinutes(5), true);
        string approvalPath = Path.Combine(isolated, descriptor.ToolId + ".approval.json");
        File.WriteAllText(approvalPath, JsonSerializer.Serialize(approval));
        approval = JsonSerializer.Deserialize<ToolQaApproval>(File.ReadAllText(approvalPath))!;
        ToolQaGate.ValidateApproval(approval, "task", "workflow", descriptor.ToolId, descriptor.TestId,
            attempt, run, claim, candidateHash, manifestHash, 4, now);
        Reject(() => ToolQaGate.ValidateApproval(approval with { ExpiresUtc = now }, "task", "workflow", descriptor.ToolId,
            descriptor.TestId, attempt, run, claim, candidateHash, manifestHash, 4, now), "expired approval rejected");
        Reject(() => ToolQaGate.ValidateApproval(approval, "task", "workflow", descriptor.ToolId,
            descriptor.TestId, attempt, run, "wrong-claim", candidateHash, manifestHash, 4, now), "claim mismatch rejected");
        Reject(() => ToolQaGate.ValidateApproval(approval, "task", "workflow", descriptor.ToolId,
            descriptor.TestId, attempt, run, claim, candidateHash, manifestHash, 5, now), "stale revision rejected");

        var fixture = new ToolQaFixtureEvidence("task", "workflow", descriptor.ToolId, attempt, run,
            descriptor.FixtureContractId, candidateHash, Path.Combine(isolated, descriptor.ToolId + ".fixture-evidence.json"), "");
        File.WriteAllText(fixture.EvidencePath, JsonSerializer.Serialize(new { Status = "Passed", TaskId = "task", WorkflowId = "workflow", ToolId = descriptor.ToolId, AttemptId = attempt, RunId = run, FixtureId = descriptor.FixtureContractId, FixtureSha256 = candidateHash }));
        fixture = fixture with { EvidenceSha256 = hash(fixture.EvidencePath) };
        ToolQaGate.ValidateFixture(fixture, "task", "workflow", descriptor.ToolId, attempt, run, descriptor.FixtureContractId, candidateHash);
        Check(true, descriptor.ToolId + " isolated synthetic fixture evidence integrity/correlation accepted");
        Reject(() => ToolQaGate.ValidateFixture(fixture with { RunId = "other" }, "task", "workflow", descriptor.ToolId, attempt, run, descriptor.FixtureContractId, candidateHash), "fixture run mismatch rejected");
        File.AppendAllText(fixture.EvidencePath, "tampered");
        Reject(() => ToolQaGate.ValidateFixture(fixture, "task", "workflow", descriptor.ToolId, attempt, run, descriptor.FixtureContractId, candidateHash), "fixture evidence byte mismatch rejected");
        File.WriteAllText(fixture.EvidencePath, JsonSerializer.Serialize(new { Status = "Passed", TaskId = "task", WorkflowId = "workflow", ToolId = descriptor.ToolId, AttemptId = attempt, RunId = run, FixtureId = descriptor.FixtureContractId, FixtureSha256 = candidateHash }));
        fixture = fixture with { EvidenceSha256 = hash(fixture.EvidencePath) };
        Check(ToolQaLifecycleAdapter.Prepare(registry, binding, approval, fixture, "task", "workflow", attempt,
            run, claim, 4, now).ToolId == descriptor.ToolId, "shared pre-dispatch adapter validates candidate, approval, and fixture");

        var reservation = new ToolQaDispatchReservation(Guid.NewGuid().ToString(), "task", "workflow", descriptor.ToolId, attempt, run, claim);
        var ledger = new TempLedger(isolated);
        ToolQaLifecycleAdapter.BeginDispatch(ledger, reservation);
        Reject(() => ToolQaLifecycleAdapter.BeginDispatch(new TempLedger(isolated), reservation), "persisted duplicate dispatch rejected");
        Check(ledger.Read(reservation) == ToolQaDispatchState.Dispatching, "reserved state persisted as dispatching");
        Check(ToolQaLifecycleAdapter.RecordLaunchResponse(ledger, reservation, true, true) == ToolQaDispatchState.DispatchAccepted, "authenticated accepted response is not terminal QA");
        Reject(() => ToolQaLifecycleAdapter.RecordLaunchResponse(ledger, reservation, true, true), "accepted attempt cannot consume a second native response");
        var ambiguousReservation = reservation with { RequestId = Guid.NewGuid().ToString() };
        var ambiguousLedger = new TempLedger(isolated);
        ToolQaLifecycleAdapter.BeginDispatch(ambiguousLedger, ambiguousReservation);
        var ambiguous = ToolQaLifecycleAdapter.RecordLaunchResponse(ambiguousLedger, ambiguousReservation, true, false);
        Check(ambiguous == ToolQaDispatchState.OutcomeUnknown, "lost response remains ambiguous");
        Reject(() => ToolQaLifecycleAdapter.BeginDispatch(ambiguousLedger, ambiguousReservation), "ambiguous dispatch cannot be launched again");

        string receiptPath = Path.Combine(isolated, descriptor.ToolId + ".receipt.json");
        string reportPath = Path.Combine(isolated, descriptor.ToolId + ".report.json");
        var report = new { RequestId = ambiguousReservation.RequestId, TaskId = "task", WorkflowId = "workflow", QaWorkflowId = descriptor.ToolId,
            TestId = descriptor.TestId, AttemptId = attempt, RunId = run, ClaimId = claim, Status = "Passed" };
        File.WriteAllText(receiptPath, JsonSerializer.Serialize(report)); File.WriteAllText(reportPath, JsonSerializer.Serialize(report));
        var terminal = new ToolQaTerminalEvidence(ambiguousReservation.RequestId, "task", "workflow", descriptor.ToolId,
            descriptor.TestId, attempt, run, claim, candidateHash, manifestHash, candidateHash,
            receiptPath, hash(receiptPath), reportPath, hash(reportPath), "Passed", true, true);
        var authenticator = new SyntheticAuthenticator(true);
        Check(ToolQaLifecycleAdapter.Reconcile(ambiguousLedger, ambiguousReservation, registry, terminal, terminal, authenticator) == ToolQaDispatchState.QaPassed,
            "authenticated correlated terminal evidence reconciles to QA pass");
        Reject(() => ToolQaGate.Reconcile(ambiguous, registry, terminal with { ClaimId = "wrong" }, terminal, authenticator), "claim-mismatched terminal evidence rejected");
        File.WriteAllText(reportPath, JsonSerializer.Serialize(report with { ClaimId = "wrong" }));
        Reject(() => ToolQaGate.Reconcile(ambiguous, registry, terminal with { ReportSha256 = hash(reportPath) }, terminal, authenticator), "report identity mismatch rejected even with recomputed hash");
        File.WriteAllText(reportPath, JsonSerializer.Serialize(report));
        File.WriteAllText(receiptPath, JsonSerializer.Serialize(report with { RequestId = Guid.NewGuid().ToString() }));
        Reject(() => ToolQaGate.Reconcile(ambiguous, registry, terminal with { ReceiptSha256 = hash(receiptPath) }, terminal, authenticator), "receipt identity mismatch rejected even with recomputed hash");
        File.WriteAllText(receiptPath, JsonSerializer.Serialize(report));
        Reject(() => ToolQaGate.Reconcile(ambiguous, registry, terminal, terminal, new SyntheticAuthenticator(false)), "unauthenticated terminal response rejected");
        Reject(() => ToolQaGate.Reconcile(ambiguous, registry, terminal with { RollbackVerified = false }, terminal, authenticator), "rollback failure blocks closure");
        Reject(() => ToolQaGate.Reconcile(ambiguous, registry, terminal with { CleanupVerified = false }, terminal, authenticator), "cleanup failure blocks closure");
        File.AppendAllText(reportPath, "tamper");
        Reject(() => ToolQaGate.Reconcile(ambiguous, registry, terminal, terminal, authenticator), "report hash mismatch blocks closure");
        Check(ToolQaGate.ClassifyInterruption(false, false, null) == ToolQaInterruptionKind.None, "no prompt permits continuation");
        Check(ToolQaGate.ClassifyInterruption(true, true, "AutodeskLicenseLimit") == ToolQaInterruptionKind.KnownLicenseIntervention, "known license interruption requires intervention");
        Check(ToolQaGate.ClassifyInterruption(true, true, "RevitAddinTrust") == ToolQaInterruptionKind.KnownAddinTrustIntervention, "add-in trust prompt remains human-only");
        var unknownPrompt = ToolQaGate.ClassifyInterruption(true, false, "unrecognized");
        Check(unknownPrompt == ToolQaInterruptionKind.UnknownInterventionRequired && !ToolQaGate.CanContinueAfterInterruption(unknownPrompt), "unknown prompt fails closed");
    }
}
finally { Directory.Delete(isolated, recursive: true); }
Console.WriteLine($"Shared tool QA contract tests passed: assertions={assertions}; CPV/RCP stores isolated under temp; Revit invoked=false; native dispatch=false; canonical store mutated=false.");

sealed class SyntheticAuthenticator(bool trusted) : IToolQaNativeEvidenceAuthenticator
{
    public bool Verify(ToolQaTerminalEvidence evidence) => trusted && !string.IsNullOrWhiteSpace(evidence.RequestId);
}

sealed class TempLedger(string root) : IToolQaDispatchLedger
{
    private static string Key(ToolQaDispatchReservation reservation) => reservation.RequestId;
    public bool TryReserve(ToolQaDispatchReservation reservation)
    {
        string path = Path.Combine(root, Key(reservation) + ".dispatch.json");
        try
        {
            using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            JsonSerializer.Serialize(stream, new TempLedgerEntry(reservation, ToolQaDispatchState.Dispatching));
            return true;
        }
        catch (IOException) { return false; }
    }
    public bool TryTransition(ToolQaDispatchReservation reservation, ToolQaDispatchState expected, ToolQaDispatchState next)
    {
        string path = Path.Combine(root, Key(reservation) + ".dispatch.json");
        lock (path)
        {
            if (!File.Exists(path)) return false;
            var entry = JsonSerializer.Deserialize<TempLedgerEntry>(File.ReadAllText(path));
            if (entry is null || entry.State != expected || entry.Reservation != reservation) return false;
            string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            File.WriteAllText(temporary, JsonSerializer.Serialize(entry with { State = next }));
            File.Move(temporary, path, true);
            return true;
        }
    }
    public ToolQaDispatchState Read(ToolQaDispatchReservation reservation)
    {
        string path = Path.Combine(root, Key(reservation) + ".dispatch.json");
        var entry = JsonSerializer.Deserialize<TempLedgerEntry>(File.ReadAllText(path));
        return entry?.Reservation == reservation ? entry.State : throw new InvalidOperationException("Synthetic dispatch reservation not found.");
    }
}
sealed record TempLedgerEntry(ToolQaDispatchReservation Reservation, ToolQaDispatchState State);
