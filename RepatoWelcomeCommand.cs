using Autodesk.Revit.Attributes;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;

namespace Repato.Revit;

[Transaction(TransactionMode.Manual)]
public sealed class RepatoWelcomeCommand : IExternalCommand
{
    public Result Execute(
        ExternalCommandData commandData,
        ref string message,
        ElementSet elements)
    {
        TaskDialog.Show(
            "Repato",
            "Repato is running successfully.\n\nNext: Create Grids."
        );

        return Result.Succeeded;
    }
}