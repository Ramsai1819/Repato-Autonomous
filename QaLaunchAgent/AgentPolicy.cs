using System.Diagnostics;
using System.Security.Principal;

namespace Repato.QaLaunchAgent;

public sealed record QaAgentOptions(string RevitExe, string RuntimeRoot, string QaProfileRoot, string ReplayLedgerPath, string LogRoot, string ExpectedUser = QaLaunchPolicy.ExpectedUser, string ExpectedUserSid = QaLaunchPolicy.ExpectedUserSid, string ClientAccount = QaLaunchPolicy.ClientAccount, string ClientSid = QaLaunchPolicy.ClientSid, string PipeName = "Repato\\QaLaunch", string? RcpCandidateRoot = null, string? RcpManifestRoot = null, string? RcpIsolationRoot = null);

public sealed class QaLaunchAgent(QaAgentOptions options)
{
    private readonly HashSet<string> _seen = new(StringComparer.OrdinalIgnoreCase);

    public QaLaunchResponse ValidateOnly(QaLaunchRequest request, DateTimeOffset now)
    {
        if (!QaLaunchPolicy.IsValidRequest(request, now)) return Reject(request, "request-invalid");
        if (!_seen.Add(request.RequestId)) return Reject(request, "request-replayed");
        if (!IsUnder(request.RequestPath, options.RuntimeRoot) || !IsUnder(request.ModelPath, options.RuntimeRoot))
            return Reject(request, "request-root-invalid");
        if (!IsUnder(request.ManifestPath, options.QaProfileRoot)) return Reject(request, "manifest-boundary-invalid");
        if (!File.Exists(options.RevitExe)) return Reject(request, "executable-unavailable");
        return new QaLaunchResponse(1, request.RequestId, true, null, WindowsIdentity.GetCurrent().Name,
            Process.GetCurrentProcess().SessionId, null, options.RevitExe, request.RequestPath, request.RunId, null);
    }

    private static bool IsUnder(string path, string root) =>
        Path.GetFullPath(path).StartsWith(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    private static QaLaunchResponse Reject(QaLaunchRequest r, string code) =>
        new(1, r?.RequestId ?? "", false, null, null, null, null, null, r?.RequestPath, r?.RunId, code);
}
