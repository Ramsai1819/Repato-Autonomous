using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Repato.Revit.TestRunner;

public sealed class AddinInventory
{
    public string PolicyPath { get; set; } = AddinIsolationPolicy.PolicyPath;
    public string PolicySha256 { get; set; } = "";
    public List<DetectedAddin> DetectedAddins { get; } = [];
    public List<string> Errors { get; } = [];
    public bool Allowed => Errors.Count == 0 && DetectedAddins.All(item => item.Allowlisted);
}

public sealed record DetectedAddin(string Scope, string Path, string Sha256, bool Allowlisted, string Reason);

public static class AddinIsolationPolicy
{
    public const string PolicyPath = @"C:\Repato-Autonomous\Source\QA\MachineWideAddins.allowlist.json";
    public const string MachineWideRoot = @"C:\ProgramData\Autodesk\Revit\Addins\2025";
    private const string SourceRoot = @"C:\Repato-Autonomous\Source\QA";

    public static AddinInventory Inspect()
    {
        string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        return Inspect(PolicyPath, MachineWideRoot,
            string.IsNullOrWhiteSpace(appData) ? "" : Path.Combine(appData, "Autodesk", "Revit", "Addins", "2025"), SourceRoot);
    }

    // Injectable paths are internal and used only by the standalone no-Revit checks.
    internal static AddinInventory Inspect(string policyPath, string machineRoot, string userRoot, string sourceRoot)
    {
        var result = new AddinInventory { PolicyPath = policyPath };
        var approved = new Dictionary<string, (string Hash, string Reason)>(StringComparer.OrdinalIgnoreCase);
        try
        {
            CheckPath(policyPath);
            byte[] bytes = File.ReadAllBytes(policyPath);
            result.PolicySha256 = Convert.ToHexString(SHA256.HashData(bytes));
            ReadOnlyMemory<byte> json = bytes.AsMemory();
            if (bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
                json = json[3..];
            using var policy = JsonDocument.Parse(json);
            JsonElement root = policy.RootElement;
            if (root.GetProperty("schemaVersion").GetInt32() != 1 ||
                !string.Equals(root.GetProperty("machineWideRoot").GetString(), machineRoot, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Unexpected policy schema or machine-wide root.");
            foreach (JsonElement item in root.GetProperty("approvedMachineWideManifests").EnumerateArray())
            {
                string path = item.GetProperty("path").GetString() ?? "";
                string hash = item.GetProperty("sha256").GetString() ?? "";
                string reason = item.GetProperty("reviewReason").GetString() ?? "";
                if (!Path.IsPathFullyQualified(path) || !string.Equals(path, Path.GetFullPath(path), StringComparison.OrdinalIgnoreCase) ||
                    !string.Equals(Path.GetDirectoryName(path), machineRoot, StringComparison.OrdinalIgnoreCase) || path.IndexOfAny(['*', '?']) >= 0 ||
                    !string.Equals(Path.GetExtension(path), ".addin", StringComparison.OrdinalIgnoreCase) ||
                    !Regex.IsMatch(hash, @"\A[0-9a-fA-F]{64}\z") || string.IsNullOrWhiteSpace(reason) || path.IndexOf(':', 2) >= 0)
                    throw new InvalidOperationException("Malformed machine-wide manifest approval.");
                approved.Add(path, (hash, reason));
            }
        }
        catch (Exception ex)
        {
            approved.Clear();
            result.Errors.Add("Policy rejected: " + ex.Message);
        }

        Scan(machineRoot, "MachineWide", approved, result, sourceRoot);
        if (string.IsNullOrWhiteSpace(userRoot)) result.Errors.Add("Current user APPDATA is unavailable.");
        else Scan(userRoot, "UserProfile", approved, result, sourceRoot);
        return result;
    }

    public static void RequireAllowed(TestRunReport report)
    {
        report.AddinIsolation = Inspect();
        report.Assert("addin-isolation", report.AddinIsolation.Allowed, "Only approved manifest hashes", report.AddinIsolation);
        if (!report.AddinIsolation.Allowed)
            throw new InvalidOperationException("Add-in isolation failed. Review AddinIsolation inventory and errors; do not run QA.");
    }

    private static void Scan(string directory, string scope, Dictionary<string, (string Hash, string Reason)> approved, AddinInventory result, string sourceRoot)
    {
        string[] files;
        try
        {
            CheckPath(directory);
            files = Directory.GetFiles(directory).Where(path => string.Equals(Path.GetExtension(path), ".addin", StringComparison.OrdinalIgnoreCase)).Order(StringComparer.OrdinalIgnoreCase).ToArray();
        }
        catch (Exception ex)
        {
            result.Errors.Add(scope + " enumeration failed: " + ex.Message);
            return;
        }
        foreach (string path in files)
        {
            string hash = "";
            bool allowed = false;
            string reason;
            try
            {
                CheckPath(path);
                hash = Hash(path);
                if (scope == "MachineWide")
                {
                    allowed = approved.TryGetValue(path, out var approval) && string.Equals(hash, approval.Hash, StringComparison.OrdinalIgnoreCase);
                    reason = allowed ? approval.Reason : "Unlisted manifest or approved SHA-256 mismatch.";
                }
                else
                {
                    string name = Path.GetFileName(path);
                if (name.Equals("Repato.CreateLevels.TestRunner.addin", StringComparison.OrdinalIgnoreCase) || name.Equals("Repato.TestRunner.addin", StringComparison.OrdinalIgnoreCase) || name.Equals("Repato.GridBubbleVisibility.TestRunner.addin", StringComparison.OrdinalIgnoreCase) || name.Equals("Repato.GridBubbleOffset.TestRunner.addin", StringComparison.OrdinalIgnoreCase))
                    {
                        string source = Path.Combine(sourceRoot, name);
                        CheckPath(source);
                        allowed = string.Equals(hash, Hash(source), StringComparison.OrdinalIgnoreCase);
                        reason = allowed ? "Repository QA manifest bootstrap, exact source SHA-256." : "QA manifest differs from repository source.";
                    }
                    else reason = "User-profile manifest is not an approved QA bootstrap manifest.";
                }
            }
            catch (Exception ex) { reason = "Manifest inspection failed: " + ex.Message; }
            result.DetectedAddins.Add(new DetectedAddin(scope, path, hash, allowed, reason));
        }
    }

    private static string Hash(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    private static void CheckPath(string path)
    {
        if (!Path.IsPathFullyQualified(path) || path.StartsWith(@"\\", StringComparison.Ordinal) || path.IndexOf(':', 2) >= 0 || path.IndexOfAny(['*', '?']) >= 0)
            throw new InvalidOperationException("Only an absolute local path without alternate streams is permitted.");
        if (new DriveInfo(Path.GetPathRoot(path)!).DriveType != DriveType.Fixed)
            throw new InvalidOperationException("Only a fixed local drive is permitted.");
        for (string? item = Path.GetFullPath(path); item is not null; item = Path.GetDirectoryName(item))
        {
            // GetAttributes throws for missing/unreadable paths, so inspection fails closed.
            if ((File.GetAttributes(item) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("Reparse point is prohibited: " + item);
        }
    }
}
