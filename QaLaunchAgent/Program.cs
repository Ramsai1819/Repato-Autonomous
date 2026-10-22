using System.Security.Principal;

namespace Repato.QaLaunchAgent;

internal static class Program
{
    // Phase 1 deliberately exposes no live listener. Phase 2 will bind the
    // restricted named pipe only after one-time RepatoQA installation.
    public static int Main(string[] args)
    {
        if (args.Length > 0 && (args[0] == "--help" || args[0] == "-h")) { Console.WriteLine("RepatoQA launch agent: fixed local QA listener."); return 0; }
        if (args.Length > 0) return 64;
        if (!OperatingSystem.IsWindows()) return 2;
        if (!string.Equals(WindowsIdentity.GetCurrent().Name, QaLaunchPolicy.ExpectedUser, StringComparison.OrdinalIgnoreCase)) return 3;
        var options = new QaAgentOptions(
            @"E:\revit\Revit 2025\Revit.exe",
            @"C:\Repato-Autonomous\Source\QA\TestRuns",
            @"C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025",
            @"C:\Users\RepatoQA\AppData\Local\Repato\QaLaunchAgent\replay.json",
            QaLaunchPolicy.LogRoot);
        var identity = new CurrentIdentitySessionProvider();
        if (!identity.User.Equals(options.ExpectedUser, StringComparison.OrdinalIgnoreCase) || identity.Sid != options.ExpectedUserSid || !identity.Interactive) return 3;
        using var stop = new CancellationTokenSource();
        Console.CancelKeyPress += (_, e) => { e.Cancel = true; stop.Cancel(); };
        // RCP remains fail-closed until an authorized deployment supplies protected,
        // version-specific roots. Never trust a QA-writable runtime directory as a candidate root.
        var coordinator = new LaunchCoordinator(options, identity, new FileReplayLedger(options.ReplayLedgerPath), new RevitChildProcessLauncher(), new StrictChildProcessVerifier(), new RevitRcpChildProcessLauncher(), new StrictRcpChildProcessVerifier());
        var server = new NamedPipeLaunchServer(options, coordinator);
        try { while (!stop.IsCancellationRequested) server.ServeOnceAsync(stop.Token).GetAwaiter().GetResult(); } catch (OperationCanceledException) { }
        return 0;
    }
}
