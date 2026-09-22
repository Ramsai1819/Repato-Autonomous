using Autodesk.Revit.DB;
using Autodesk.Revit.UI;

namespace Repato.Revit.TestRunner;

/// <summary>Named command entry point for the unattended Create Grids QA runner.</summary>
public sealed class CreateGridsTestCommand : IExternalCommand
{
    public const string SupportedTestId = "create-grids-world-axis-v1";

    public Result Execute(ExternalCommandData data, ref string message, ElementSet elements)
    {
        var report = RepatoTestCommand.Run(data.Application, SupportedTestId);
        try
        {
            string path = report.Write();
            message = $"{report.Status}: {path}";
            return report.Status == "Passed" ? Result.Succeeded : Result.Failed;
        }
        catch (Exception ex)
        {
            message = "QA FAILED: evidence could not be saved. " + ex;
            return Result.Failed;
        }
    }
}
