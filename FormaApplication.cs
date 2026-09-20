using Autodesk.Revit.UI;

namespace Repato.Revit;

public sealed class RepatoApplication : IExternalApplication
{
    public Result OnStartup(UIControlledApplication application)
    {
        const string tabName = "REPATO";
        const string panelName = "PROJECT SETUP";

        try
        {
            application.CreateRibbonTab(tabName);
        }
        catch
        {
            // REPATO already exists in the current Revit session.
        }

        RibbonPanel panel = application.CreateRibbonPanel(tabName, panelName);

        string assemblyPath = typeof(RepatoApplication).Assembly.Location;

        var createGridsButton = new PushButtonData(
            "RepatoCreateGrids",
            "Create\nGrids",
            assemblyPath,
            "Repato.Revit.CreateGridsCommand"
        )
        {
            ToolTip = "Create named vertical and horizontal grids from Tab-separated millimetre positions."
        };

        var createLevelsButton = new PushButtonData(
            "RepatoCreateLevels",
            "Create\nLevels",
            assemblyPath,
            "Repato.Revit.CreateLevelsCommand"
        )
        {
            ToolTip = "Create named levels from the Repato level definition workflow."
        };

        var bubbleVisibilityButton = new PushButtonData(
            "RepatoGridBubbleVisibility",
            "Grid Bubble\nVisibility",
            assemblyPath,
            "Repato.Revit.GridBubbleVisibilityCommand"
        )
        {
            ToolTip = "Set left, right, bottom, and top bubble visibility for selected grids."
        };

        var offsetBubblesButton = new PushButtonData(
            "RepatoOffsetGridBubbles",
            "Offset Grid\nBubbles",
            assemblyPath,
            "Repato.Revit.OffsetGridBubblesCommand"
        )
        {
            ToolTip = "Extend selected grids outside the outer perpendicular grid by specified offsets."
        };

        var resequenceButton = new PushButtonData(
            "RepatoGridResequence",
            "Grid\nResequence",
            assemblyPath,
            "Repato.Revit.GridResequenceCommand"
        )
        {
            ToolTip = "Rename selected vertical grids left to right and horizontal grids bottom to top."
        };

        panel.AddItem(createGridsButton);
        panel.AddItem(createLevelsButton);
        panel.AddItem(bubbleVisibilityButton);
        panel.AddItem(offsetBubblesButton);
        panel.AddItem(resequenceButton);

        return Result.Succeeded;
    }

    public Result OnShutdown(UIControlledApplication application)
    {
        return Result.Succeeded;
    }
}
