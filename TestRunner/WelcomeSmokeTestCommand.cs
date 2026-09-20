using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using Autodesk.Revit.Attributes;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;
using Autodesk.Revit.UI.Events;

namespace Repato.Revit.TestRunner;

[Transaction(TransactionMode.Manual)]
public sealed class WelcomeSmokeTestCommand : IExternalCommand
{
    public const string SupportedTestId = "welcome-supervised-dialog-v1";
    internal const string QaApplicationTitle = "Repato Welcome Smoke QA Startup";
    internal const string ExpectedVisibleWindowTitle = "Repato QA - Welcome Smoke - Repato";

    public Result Execute(ExternalCommandData data, ref string message, ElementSet elements)
    {
        TestRunReport report = Run(data.Application,
            data.JournalData.TryGetValue("testId", out string? id) ? id : SupportedTestId);
        try { string path = report.Write(); message = $"{report.Status}: {path}"; return report.Status == "Passed" ? Result.Succeeded : Result.Failed; }
        catch (Exception ex) { message = ex.ToString(); return Result.Failed; }
    }

    public static TestRunReport Run(UIApplication app, string testId)
    {
        var report = new TestRunReport
        {
            TestId = testId,
            FixtureId = "CreateLevelsEmpty",
            Inputs = new { Mode = "Supervised UI", ExpectedTitle = RepatoWelcomeCommand.DialogTitle,
                ExpectedVisibleWindowTitle, ExpectedMessage = RepatoWelcomeCommand.DialogMessage }
        };
        var timer = Stopwatch.StartNew();
        try
        {
            report.RevitVersion = $"{app.Application.VersionName}; {app.Application.VersionNumber}; {app.Application.VersionBuild}";
            report.IdentifyAssembly();
            AddinIsolationPolicy.RequireAllowed(report);
            if (testId != SupportedTestId) throw new InvalidOperationException("Unknown test ID.");
            Document document = app.ActiveUIDocument?.Document ?? throw new InvalidOperationException("No active disposable document.");
            TestSafetyGate.Verify(document, report, "CreateLevelsEmpty");
            string beforeHash = TestRunReport.Hash(document.PathName);
            string[] beforeElements = Elements(document);
            bool observed = false;
            string observedMessage = "";
            string observedWindowTitle = "";
            string screenshot = Path.Combine(QAPathPolicy.RepositoryRoot, "QA", "Screenshots", report.RunId, "welcome-dialog.png");
            System.Threading.Timer? captureTimer = null;
            using var captureCompleted = new ManualResetEventSlim(false);
            void OnDialog(object? sender, DialogBoxShowingEventArgs args)
            {
                if (args is not TaskDialogShowingEventArgs taskDialog) return;
                observed = true;
                observedMessage = taskDialog.Message ?? "";
                Directory.CreateDirectory(Path.GetDirectoryName(screenshot)!);
                captureTimer = new System.Threading.Timer(_ =>
                {
                    try { observedWindowTitle = CaptureDesktop(screenshot); }
                    finally { captureCompleted.Set(); }
                }, null, 750, Timeout.Infinite);
                // Deliberately do not override or dismiss the dialog. Tara supervises and clicks OK.
            }
            app.DialogBoxShowing += OnDialog;
            Result result;
            try { result = RepatoWelcomeCommand.ShowWelcome(); }
            finally { app.DialogBoxShowing -= OnDialog; }
            captureCompleted.Wait(TimeSpan.FromSeconds(2));
            captureTimer?.Dispose();
            report.Assert("command-result", result == Result.Succeeded, Result.Succeeded.ToString(), result.ToString());
            report.Assert("dialog-observed", observed, true, observed);
            string prefix = QaApplicationTitle + " - ";
            string observedCommandTitle = observedWindowTitle.StartsWith(prefix, StringComparison.Ordinal)
                ? observedWindowTitle[prefix.Length..] : "";
            report.Assert("dialog-window-title", observedWindowTitle == ExpectedVisibleWindowTitle,
                ExpectedVisibleWindowTitle, observedWindowTitle);
            report.Assert("dialog-title", string.IsNullOrEmpty(observedCommandTitle) || observedCommandTitle == RepatoWelcomeCommand.DialogTitle,
                RepatoWelcomeCommand.DialogTitle, observedCommandTitle);
            report.Assert("dialog-message", observedMessage == RepatoWelcomeCommand.DialogMessage, RepatoWelcomeCommand.DialogMessage, observedMessage);
            if (File.Exists(screenshot)) QaRunnerFoundation.RegisterEvidence(report, "dialog", screenshot, document.ActiveView.Id.Value.ToString(), "Supervised TaskDialog desktop capture");
            else throw new IOException("Supervised dialog screenshot was not captured.");
            report.Assert("model-file-unchanged", TestRunReport.Hash(document.PathName) == beforeHash, beforeHash, TestRunReport.Hash(document.PathName));
            report.Assert("model-elements-unchanged", Elements(document).SequenceEqual(beforeElements), beforeElements, Elements(document));
            QaRunnerFoundation.VerifyRollback(report, true, "RolledBack");
        }
        catch (Exception ex) { report.Errors.Add(ex.ToString()); }
        finally { QaRunnerFoundation.Finish(report, timer); }
        return report;
    }

    private static string[] Elements(Document document) => new FilteredElementCollector(document)
        .WhereElementIsNotElementType().Select(element => $"{element.Id.Value}|{element.Name}").Order(StringComparer.Ordinal).ToArray();

    private static string CaptureDesktop(string path)
    {
        IntPtr screen = IntPtr.Zero;
        IntPtr memory = IntPtr.Zero;
        IntPtr bitmap = IntPtr.Zero;
        IntPtr previous = IntPtr.Zero;
        try
        {
            int left = GetSystemMetrics(76), top = GetSystemMetrics(77);
            int width = GetSystemMetrics(78), height = GetSystemMetrics(79);
            string title = ReadWindowTitle(GetForegroundWindow());
            screen = GetDC(IntPtr.Zero);
            memory = CreateCompatibleDC(screen);
            bitmap = CreateCompatibleBitmap(screen, width, height);
            previous = SelectObject(memory, bitmap);
            if (!BitBlt(memory, 0, 0, width, height, screen, left, top, 0x00CC0020))
                throw new IOException("Desktop capture failed.");
            BitmapSource source = Imaging.CreateBitmapSourceFromHBitmap(bitmap, IntPtr.Zero, Int32Rect.Empty,
                BitmapSizeOptions.FromEmptyOptions());
            source.Freeze();
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(source));
            using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            encoder.Save(stream);
            stream.Flush(true);
            return title;
        }
        catch { return ""; }
        finally
        {
            if (previous != IntPtr.Zero && memory != IntPtr.Zero) SelectObject(memory, previous);
            if (bitmap != IntPtr.Zero) DeleteObject(bitmap);
            if (memory != IntPtr.Zero) DeleteDC(memory);
            if (screen != IntPtr.Zero) ReleaseDC(IntPtr.Zero, screen);
        }
    }

    private static string ReadWindowTitle(IntPtr window)
    {
        int length = GetWindowTextLength(window);
        if (window == IntPtr.Zero || length <= 0) return "";
        var text = new StringBuilder(length + 1);
        return GetWindowText(window, text, text.Capacity) > 0 ? text.ToString() : "";
    }

    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder text, int count);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLength(IntPtr window);
    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr window, IntPtr dc);
    [DllImport("user32.dll")] private static extern int GetSystemMetrics(int index);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleBitmap(IntPtr dc, int width, int height);
    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr dc, IntPtr value);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr value);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] private static extern bool BitBlt(IntPtr destination, int x, int y, int width, int height,
        IntPtr source, int sourceX, int sourceY, int operation);
}
