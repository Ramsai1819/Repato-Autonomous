using System.Security.Cryptography;
using System.Text.Json;
using Repato.QaLaunchAgent;

internal static class ReadonlyCandidatePreflightTests
{
    internal static void Run(QaLaunchRequest launch)
    {
        var root = Path.Combine(QaLaunchPolicy.ApprovedCandidateRoot, "synthetic-preflight-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var dll = Path.Combine(root, "Repato.Revit.dll"); File.WriteAllText(dll, "synthetic candidate");
            var hash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(dll)));
            var provenance = Path.Combine(root, "provenance.json");
            var commit = new string('a', 40);
            File.WriteAllText(provenance, JsonSerializer.Serialize(new { SourceCommit = commit, FrozenArtifactSha256 = hash }));
            var manifest = Path.Combine(QaLaunchPolicy.ApprovedRunnerManifestRoot, "Repato.CreatePlanViews.TestRunner.addin");
            var evidence = new QaCandidateEvidence(1, "synthetic-task", "synthetic-workflow", "create-plan-views-v1", "create-plan-views-v1", commit, root, dll, hash, hash, manifest, QaLaunchPolicy.ExpectedRunnerManifestSha256, provenance);
            var request = new QaPreflightRequest(1, QaLaunchPolicy.PreflightOperation, evidence.TaskId, evidence.WorkflowId, evidence.QaWorkflowId, evidence.TestId, commit, hash, evidence);
            void Assert(bool condition) { if (!condition) throw new Exception("Readonly candidate preflight regression failed."); }
            Assert(QaLaunchPolicy.IsValidPreflightRequest(new(1, QaLaunchPolicy.PreflightOperation)));
            Assert(QaLaunchPolicy.IsValidPreflightRequest(request));
            Assert(!QaLaunchPolicy.IsValidPreflightRequest(request with { TaskId = "other" }));
            Assert(!QaLaunchPolicy.IsValidPreflightRequest(request with { CandidateCommit = new string('b', 40) }));
            Assert(!QaLaunchPolicy.IsValidPreflightRequest(request with { ExpectedCandidateSha256 = new string('0', 64) }));
            Assert(!QaLaunchPolicy.IsValidPreflightRequest(request with { CandidateEvidence = null }));
            Assert(!QaLaunchPolicy.IsValidPreflightRequest(request with { CandidateEvidence = evidence with { RunnerManifestSha256 = new string('0', 64) } }));
            var options = new QaAgentOptions("absent-revit.exe", root, root, Path.Combine(root, "must-not-exist-ledger"), root);
            // Null mutation/launch dependencies deliberately make any accidental use fail.
            var coordinator = new LaunchCoordinator(options, new Identity(), null!, null!, null!);
            var response = coordinator.HandlePreflight(request);
            Assert(response.Checks.Single(c => c.Name == "request-bindings").Passed);
            Assert(response.Checks.Single(c => c.Name == "frozen-candidate").Passed);
            Assert(response.Checks.Single(c => c.Name == "frozen-candidate").Detail!.Contains(hash));
            Assert(!File.Exists(options.ReplayLedgerPath));
            File.AppendAllText(dll, "tampered");
            Assert(!QaLaunchPolicy.IsValidPreflightRequest(request));
            File.Delete(provenance);
            Assert(!QaLaunchPolicy.IsValidPreflightRequest(request));
            var model = Path.Combine(root, "synthetic.rvt");
            var companion = model + ".recovered.fixture.json"; File.WriteAllText(companion, "synthetic");
            var companionHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(companion)));
            var bound = launch with { ModelPath = model, RecoveredProvenancePath = companion, RecoveredProvenanceSha256 = companionHash };
            Assert(QaLaunchPolicy.IsValidRecoveredProvenanceBinding(bound));
            Assert(QaLaunchPolicy.CanonicalRequestSha256(JsonSerializer.Serialize(bound, QaLaunchPolicy.JsonOptions)) !=
                QaLaunchPolicy.CanonicalRequestSha256(JsonSerializer.Serialize(bound with { RecoveredProvenanceSha256 = new string('0', 64) }, QaLaunchPolicy.JsonOptions)));
            Assert(!QaLaunchPolicy.IsValidRecoveredProvenanceBinding(bound with { RecoveredProvenanceSha256 = null }));
            Assert(!QaLaunchPolicy.IsValidRecoveredProvenanceBinding(bound with { RecoveredProvenancePath = dll }));
            Assert(!QaLaunchPolicy.IsValidRecoveredProvenanceBinding(bound with { RecoveredProvenanceSha256 = new string('0', 64) }));
            Assert(QaLaunchPolicy.IsValidRecoveredProvenanceBinding(launch));
            Console.WriteLine("Readonly candidate preflight and recovered binding: 19 assertions passed; no ledger or child launch.");
        }
        finally { Directory.Delete(root, true); }
    }
    private sealed class Identity : IIdentitySessionProvider
    {
        public string User => QaLaunchPolicy.ExpectedUser;
        public string Sid => QaLaunchPolicy.ExpectedUserSid;
        public int SessionId => 1;
        public bool Interactive => true;
    }
}
