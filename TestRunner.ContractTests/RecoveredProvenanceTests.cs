using System.Security.Cryptography;
using System.Text.Json;
using Repato.Revit.TestRunner;

internal static class RecoveredProvenanceTests
{
    internal static int Run()
    {
        string directory = Path.Combine(Path.GetTempPath(), "repato-recovered-runner-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        int assertions = 0;
        void Pass(Action action) { action(); assertions++; }
        void Reject(Action action) { try { action(); } catch { assertions++; return; } throw new Exception("Recovered provenance negative test unexpectedly passed."); }
        string Hash(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
        try
        {
            string original = Path.Combine(directory, "original.rvt"), canonical = Path.Combine(directory, "canonical.rvt"), source = Path.Combine(directory, "source.rvt");
            string prep = Path.Combine(directory, "prep.json"), result = Path.Combine(directory, "result.json"), companion = original + ".recovered.fixture.json";
            File.WriteAllText(original, "prepared"); File.Copy(original, canonical); File.WriteAllText(source, "source");
            string task = "task-synthetic", workflow = Guid.NewGuid().ToString("N"), attempt = Guid.NewGuid().ToString("N"), run = Guid.NewGuid().ToString("N");
            File.WriteAllText(prep, JsonSerializer.Serialize(new { operation = "prepare-disposable-create-plan-views-fixture", taskId = task, workflowId = workflow,
                attemptId = attempt, runId = run, requestPath = prep, modelPath = original, modelSha256 = Hash(source),
                selectedManifestPath = Path.Combine(directory, "Repato.CreatePlanViews.TestRunner.addin"), selectedManifestSha256 = new string('A', 64),
                outputPath = result, expiresUtc = DateTimeOffset.UtcNow.AddDays(-1) }));
            File.WriteAllText(result, JsonSerializer.Serialize(new { Status = "Passed", Operation = "prepare-disposable-create-plan-views-fixture", TaskId = task,
                WorkflowId = workflow, AttemptId = attempt, RunId = run, ModelPath = original, SourceModelSha256 = Hash(source), PreparedModelSha256 = Hash(original) }));
            File.WriteAllText(original + ".fixture.json", JsonSerializer.Serialize(new { fixtureId = "CreatePlanViewsEmpty", sourceSha256 = Hash(source) }));
            File.Copy(original + ".fixture.json", canonical + ".fixture.json");
            string historicalHash = Hash(original + ".fixture.json");
            var fields = new Dictionary<string, object?> { ["schemaVersion"] = 1, ["recoveredFromOutcomeUnknown"] = true,
                ["fixtureId"] = "CreatePlanViewsEmpty", ["sourceSha256"] = Hash(source), ["preparedModelSha256"] = Hash(original),
                ["taskId"] = task, ["workflowId"] = workflow, ["historicalSidecarPath"] = original + ".fixture.json", ["historicalSidecarSha256"] = historicalHash,
                ["fixturePreparationRequestPath"] = prep, ["fixturePreparationRequestSha256"] = Hash(prep), ["fixturePreparationResultPath"] = result,
                ["fixturePreparationResultSha256"] = Hash(result), ["fixturePreparationAttemptId"] = attempt, ["fixturePreparationRunId"] = run,
                ["requestId"] = Guid.NewGuid().ToString("N"), ["recoveryApprovalId"] = Guid.NewGuid().ToString("N") };
            foreach (string key in new[] { "requestSha256", "approvalBindingHash", "originalReceiptSha256", "originalFailureReceiptSha256", "activeMarkerSha256", "failureEvidenceSha256" }) fields[key] = new string('A', 64);
            File.WriteAllText(companion, JsonSerializer.Serialize(fields));
            var request = new CreatePlanViewsRequest(Guid.NewGuid().ToString("N"), task, workflow, CreatePlanViewsRequest.Test, CreatePlanViewsRequest.Test,
                Guid.NewGuid().ToString("N"), Guid.NewGuid().ToString("N"), Guid.NewGuid().ToString("N"), Path.Combine(directory, "launch.json"), new string('A', 64),
                canonical, Hash(canonical), Hash(source), prep, Hash(prep), result, Hash(result), attempt, run,
                Path.Combine(directory, "Repato.CreatePlanViews.TestRunner.addin"), new string('A', 64), DateTimeOffset.UtcNow.AddMinutes(5), companion, Hash(companion));
            Pass(() => TestSafetyGateProvenance.Verify(RecoveredFixtureProvenance.Resolve(canonical, request), Hash(source), Hash(canonical), request));
            Pass(() => CreatePlanViewsPreparationEvidenceContract.Verify(request, source, canonical));
            Pass(() => TestSafetyGateProvenance.Verify(RecoveredFixtureProvenance.Resolve(original, request with { ModelPath = original }), Hash(source), Hash(original), request));
            Reject(() => CreatePlanViewsFixturePreparationRequest.Parse(File.ReadAllText(prep), prep));
            Reject(() => RecoveredFixtureProvenance.Resolve(canonical, request with { ExpiresUtc = DateTimeOffset.UtcNow.AddSeconds(-1) }));
            Reject(() => RecoveredFixtureProvenance.Resolve(canonical, request with { TaskId = "task-replay" }));
            Reject(() => RecoveredFixtureProvenance.Resolve(canonical, request with { WorkflowId = Guid.NewGuid().ToString("N") }));
            Reject(() => RecoveredFixtureProvenance.Resolve(canonical, request with { FixturePreparationRunId = Guid.NewGuid().ToString("N") }));
            Reject(() => RecoveredFixtureProvenance.Resolve(canonical, request with { RecoveredProvenanceSha256 = new string('F', 64) }));
            Reject(() => RecoveredFixtureProvenance.Resolve(canonical, request with { RecoveredProvenancePath = canonical + ".recovered.fixture.json" }));
            foreach (string key in new[] { "historicalSidecarSha256", "activeMarkerSha256", "requestId", "fixturePreparationResultPath" })
            {
                object? saved = fields[key]; fields.Remove(key); File.WriteAllText(companion, JsonSerializer.Serialize(fields));
                Reject(() => RecoveredFixtureProvenance.Resolve(canonical, request with { RecoveredProvenanceSha256 = Hash(companion) })); fields[key] = saved;
            }
            File.WriteAllText(companion, JsonSerializer.Serialize(fields));
            var refreshed = request with { RecoveredProvenanceSha256 = Hash(companion) };
            string preservedHistorical = File.ReadAllText(canonical + ".fixture.json");
            File.WriteAllText(canonical + ".fixture.json", JsonSerializer.Serialize(new { fixtureId = "CreatePlanViewsEmpty", sourceSha256 = Hash(source), unknownField = true }));
            Reject(() => RecoveredFixtureProvenance.Resolve(canonical, refreshed));
            File.WriteAllText(canonical + ".fixture.json", preservedHistorical);
            string preservedCompanion = File.ReadAllText(companion);
            File.Delete(companion); Reject(() => RecoveredFixtureProvenance.Resolve(canonical, refreshed));
            File.WriteAllText(companion, preservedCompanion);
            File.WriteAllText(companion, "{"); Reject(() => RecoveredFixtureProvenance.Resolve(canonical, refreshed with { RecoveredProvenanceSha256 = Hash(companion) }));
            File.WriteAllText(companion, preservedCompanion);
            File.AppendAllText(result, " "); Reject(() => RecoveredFixtureProvenance.Resolve(canonical, refreshed));
            if (Hash(original + ".fixture.json") != historicalHash || Hash(canonical + ".fixture.json") != historicalHash) throw new Exception("Historical evidence changed.");
            assertions++;
            return assertions;
        }
        finally { Directory.Delete(directory, true); }
    }
}
