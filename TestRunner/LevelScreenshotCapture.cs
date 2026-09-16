using System.IO;
using Autodesk.Revit.DB;

namespace Repato.Revit.TestRunner;

internal static class LevelScreenshotCapture
{
    internal static void Capture(Document document, TestRunReport report, string phase)
    {
        if (phase is not ("before" or "created" or "rolled-back"))
            throw new ArgumentException("Unknown evidence phase.", nameof(phase));

        // Export an actual model view, not a generated diagram or a desktop screenshot.
        // Do not change the fixture's views just to obtain evidence.
        ViewSection view = new FilteredElementCollector(document)
            .OfClass(typeof(ViewSection)).Cast<ViewSection>()
            .Where(v => !v.IsTemplate && !v.CropBoxActive &&
                !v.GetCategoryHidden(new ElementId(BuiltInCategory.OST_Levels)) &&
                (v.ViewType == ViewType.Elevation || v.ViewType == ViewType.Section))
            .OrderBy(v => v.Id.Value).FirstOrDefault()
            ?? throw new InvalidOperationException(
                "The levels fixture needs an uncropped elevation or section view for screenshots.");

        if (phase == "created")
        {
            var visible = new FilteredElementCollector(document, view.Id).OfClass(typeof(Level))
                .ToElementIds().Select(id => id.Value.ToString(System.Globalization.CultureInfo.InvariantCulture)).ToHashSet();
            if (report.CreatedIds.Count != 3 || !report.CreatedIds.All(visible.Contains))
                throw new InvalidOperationException("Screenshot view does not expose all three test levels.");
        }

        string directory = QAPathPolicy.ValidatePath(
            Path.Combine(QAPathPolicy.RepositoryRoot, "QA", "Screenshots", report.RunId, phase),
            QAPathPolicy.RepositoryRoot + @"\QA\Screenshots", false);
        if (Directory.Exists(directory))
            throw new IOException("Screenshot directory already exists; refusing to reuse evidence.");
        Directory.CreateDirectory(directory);

        using var options = new ImageExportOptions
        {
            ExportRange = ExportRange.SetOfViews,
            FilePath = Path.Combine(directory, "levels"),
            HLRandWFViewsFileType = ImageFileType.PNG,
            ShadowViewsFileType = ImageFileType.PNG,
            ZoomType = ZoomFitType.FitToPage,
            PixelSize = 1600,
            ImageResolution = ImageResolution.DPI_150
        };
        options.SetViewsAndSheets(new List<ElementId> { view.Id });
        document.ExportImage(options);
        string[] files = Directory.GetFiles(directory, "*.png");
        if (files.Length != 1 || new FileInfo(files[0]).Length == 0)
            throw new IOException("Revit did not produce the expected PNG screenshot.");

        report.Screenshots.Add(new ScreenshotEvidence(
            phase, files[0], TestRunReport.Hash(files[0]),
            view.Id.Value.ToString(System.Globalization.CultureInfo.InvariantCulture), view.Name));
        report.Assert("screenshot-" + phase, true, "One nonempty Revit view PNG", files[0]);
    }
}
