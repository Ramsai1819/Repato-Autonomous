using Repato.QaLaunchAgent;

internal static class StartupContractTests
{
    internal static void Run(QaLaunchRequest request)
    {
        var root = Path.Combine(Path.GetTempPath(), "repato-empty-startup-" + Guid.NewGuid().ToString("N"));
        var key = "REPATO_QA_CREATE_PLAN_VIEWS_FIXTURE_PREPARATION";
        var previous = Environment.GetEnvironmentVariable(key);
        Directory.CreateDirectory(root);
        try
        {
            var model = Path.Combine(root, "disposable with spaces.rvt");
            File.WriteAllBytes(model, new byte[] { 1 });
            Environment.SetEnvironmentVariable(key, "stale-request.json");
            var options = new QaAgentOptions(@"E:\revit\Revit 2025\Revit.exe", root, root, "ledger.json", "logs");
            var info = RevitChildProcessLauncher.CreateStartInfo(request with { ModelPath = model }, options);
            if (info.ArgumentList.Count != 0 || !string.IsNullOrEmpty(info.Arguments)) throw new Exception("Launcher opened a document before the runner's empty-session gate.");
            if (info.Environment.ContainsKey(key) || info.Environment[QaLaunchPolicy.RequestEnvironmentVariable] != request.RequestPath) throw new Exception("Child environment contains an unauthenticated QA dispatch.");
            if (Environment.GetEnvironmentVariable(key) != "stale-request.json") throw new Exception("Child launch preparation altered the parent environment.");
        }
        finally
        {
            Environment.SetEnvironmentVariable(key, previous);
            Directory.Delete(root, true);
        }
    }
}
