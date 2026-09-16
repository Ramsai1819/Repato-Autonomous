using Autodesk.Revit.Attributes;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;

namespace Repato.Revit;

[Transaction(TransactionMode.Manual)]
public sealed class RepatoWelcomeCommand : IExternalCommand
{
    internal const string DialogTitle = "Repato";
    internal const string DialogMessage = "Repato is running successfully.\n\nNext: Create Grids.";

    public Result Execute(
        ExternalCommandData commandData,
        ref string message,
        ElementSet elements)
    {
        return ShowWelcome();
    }

    internal static Result ShowWelcome()
    {
        TaskDialog.Show(DialogTitle, DialogMessage);
        return Result.Succeeded;
    }
}
