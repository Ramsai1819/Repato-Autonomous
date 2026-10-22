using System.Diagnostics;
using System.Security.Principal;

namespace Repato.QaLaunchAgent;

public sealed record ChildLaunchResult(int Pid, string User, string Sid, int SessionId, string ImagePath, DateTimeOffset LaunchUtc);
public interface IIdentitySessionProvider { string User { get; } string Sid { get; } int SessionId { get; } bool Interactive { get; } }
public interface IChildProcessLauncher { ChildLaunchResult Launch(QaLaunchRequest request, QaAgentOptions options); }
public interface IChildProcessVerifier { bool Verify(ChildLaunchResult result, QaLaunchRequest request, QaAgentOptions options); }

public sealed class CurrentIdentitySessionProvider : IIdentitySessionProvider
{
    public string User => WindowsIdentity.GetCurrent().Name;
    public string Sid => WindowsIdentity.GetCurrent().User?.Value ?? "";
    public int SessionId => Process.GetCurrentProcess().SessionId;
    public bool Interactive => Environment.UserInteractive;
}

public sealed class RevitChildProcessLauncher : IChildProcessLauncher
{
    public static ProcessStartInfo CreateStartInfo(QaLaunchRequest request, QaAgentOptions options)
    {
        if (string.IsNullOrWhiteSpace(request.ModelPath)) throw new InvalidDataException("A model path is required before Revit can start.");
        var modelPath = Path.GetFullPath(request.ModelPath);
        if (!modelPath.EndsWith(".rvt", StringComparison.OrdinalIgnoreCase) || !File.Exists(modelPath))
            throw new InvalidDataException("An existing .rvt model is required before Revit can start.");

        var psi = new ProcessStartInfo(options.RevitExe) { UseShellExecute = false, WorkingDirectory = Path.GetDirectoryName(options.RevitExe)! };
        // The request-bound runner validates an empty session and opens the disposable
        // model after manifest, isolation, fixture, and model safety checks. Passing
        // the model on Revit's command line would open it before those checks.
        // An inherited inventory/preparation request takes precedence in the runner.
        // Only this authenticated dispatch may be present in the child environment.
        foreach (var key in psi.Environment.Keys.ToArray())
            if (key.StartsWith("REPATO_QA_", StringComparison.OrdinalIgnoreCase)) psi.Environment.Remove(key);
        psi.Environment[QaLaunchPolicy.RequestEnvironmentVariable] = request.RequestPath;
        return psi;
    }

    public ChildLaunchResult Launch(QaLaunchRequest request, QaAgentOptions options)
    {
        var psi = CreateStartInfo(request, options);
        using var process = Process.Start(psi) ?? throw new InvalidOperationException("Revit process creation failed.");
        var identity = WindowsIdentity.GetCurrent();
        return new ChildLaunchResult(process.Id, identity.Name, identity.User?.Value ?? "", process.SessionId, options.RevitExe, DateTimeOffset.UtcNow);
    }
}

public sealed class StrictChildProcessVerifier : IChildProcessVerifier
{
    public bool Verify(ChildLaunchResult result, QaLaunchRequest request, QaAgentOptions options) =>
        result.Pid > 0 && result.User.Equals(options.ExpectedUser, StringComparison.OrdinalIgnoreCase) &&
        result.Sid.Equals(options.ExpectedUserSid, StringComparison.OrdinalIgnoreCase) &&
        result.ImagePath.Equals(options.RevitExe, StringComparison.OrdinalIgnoreCase) &&
        result.SessionId == Process.GetCurrentProcess().SessionId;
}
