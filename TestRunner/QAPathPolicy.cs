using System.IO;

namespace Repato.Revit.TestRunner;

internal static class QAPathPolicy
{
    internal const string RepositoryRoot = @"C:\Repato-Autonomous\Source";
    internal const string RunsRoot = RepositoryRoot + @"\QA\TestRuns";
    internal const string ReportsRoot = RepositoryRoot + @"\QA\Reports";
    internal static string ValidatePath(string path, string parent, bool requireRvt)
    {
        if (string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path) || path.StartsWith(@"\\", StringComparison.Ordinal))
            throw new InvalidOperationException("A saved absolute local path is required.");
        string full = Path.GetFullPath(path);
        string prefix = Path.GetFullPath(parent).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (!full.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) || full.IndexOf(':', 2) >= 0)
            throw new InvalidOperationException("Path is outside the allowed directory or contains an alternate data stream.");
        if (new DriveInfo(Path.GetPathRoot(full)!).DriveType != DriveType.Fixed)
            throw new InvalidOperationException("Only a fixed local drive is allowed.");
        for (string? part = full; part is not null; part = Path.GetDirectoryName(part))
            if ((File.Exists(part) || Directory.Exists(part)) && (File.GetAttributes(part) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("Reparse points, junctions and symlinks are prohibited.");
        if (requireRvt && (!string.Equals(Path.GetExtension(full), ".rvt", StringComparison.OrdinalIgnoreCase) || !File.Exists(full)))
            throw new InvalidOperationException("An existing .rvt file is required.");
        return full;
    }
}

