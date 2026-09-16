using System.Diagnostics;
using System.IO;
using System.Text.Json;

namespace Repato.Revit.TestRunner;

internal static class QaRunnerFoundation
{
    internal static void RegisterEvidence(TestRunReport report, string phase, string path, string viewId, string viewName)
    {
        if (!File.Exists(path) || new FileInfo(path).Length == 0)
            throw new IOException("Evidence file is missing or empty.");
        if (report.Screenshots.Any(item => item.Phase == phase))
            throw new InvalidOperationException("Evidence phase already registered: " + phase);
        report.Screenshots.Add(new ScreenshotEvidence(phase, path, TestRunReport.Hash(path), viewId, viewName));
        report.Assert("screenshot-" + phase, true, "Nonempty hashed evidence", path);
    }

    internal static void VerifyRollback(TestRunReport report, bool baselineRestored, string actualStatus)
    {
        report.RollbackStatus = actualStatus;
        report.Assert("rollback-status", actualStatus == "RolledBack", "RolledBack", actualStatus);
        report.Assert("baseline-restored", baselineRestored, true, baselineRestored);
    }

    internal static void Finish(TestRunReport report, Stopwatch timer)
    {
        report.FinishedUtc = DateTimeOffset.UtcNow;
        report.DurationMilliseconds = timer.Elapsed.TotalMilliseconds;
        report.Status = report.Errors.Count == 0 && report.Assertions.Count > 0 &&
            report.Assertions.All(item => item.Passed) && report.RollbackStatus == "RolledBack" ? "Passed" : "Failed";
    }

    internal static void WriteReceiptAtomic(string path, object receipt)
    {
        string temporary = path + ".partial";
        if (File.Exists(path)) throw new IOException("Receipt already exists.");
        using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(stream, receipt);
            stream.Flush(true);
        }
        File.Move(temporary, path);
    }
}
