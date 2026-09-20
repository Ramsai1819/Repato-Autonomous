using WpfTextBox = System.Windows.Controls.TextBox;
using System.Windows;
using System.Windows.Controls;
using Autodesk.Revit.Attributes;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;

namespace Repato.Revit;

[Transaction(TransactionMode.Manual)]
public sealed class CreateLevelsCommand : IExternalCommand
{
    public Result Execute(
        ExternalCommandData commandData,
        ref string message,
        ElementSet elements)
    {
        Document? document =
            commandData.Application.ActiveUIDocument?.Document;

        if (document is null)
        {
            TaskDialog.Show(
                "Repato - Create Levels",
                "Open a Revit project before running Create Levels.");

            return Result.Cancelled;
        }

        var window = new CreateLevelsWindow();

        if (window.ShowDialog() != true)
        {
            return Result.Cancelled;
        }

        var result = LevelCreator.Create(document, window.LevelData);

        TaskDialog.Show(
            "Repato - Create Levels",
            result.ToString() ?? "Create Levels completed.");

        return Result.Succeeded;
    }
}

internal sealed class CreateLevelsWindow : Window
{
    private readonly WpfTextBox _levelData;

    public string LevelData => _levelData.Text;

    public CreateLevelsWindow()
    {
        Title = "Repato - Create Levels";
        Width = 560;
        Height = 360;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        var panel = new StackPanel
        {
            Margin = new Thickness(20)
        };

        panel.Children.Add(
            new TextBlock
            {
                Text = "One level per line: Level Name<TAB>Elevation in mm"
            });

        _levelData = new WpfTextBox
        {
            AcceptsReturn = true,
            AcceptsTab = true,
            Height = 220,
            Margin = new Thickness(0, 12, 0, 12)
        };

        panel.Children.Add(_levelData);

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right
        };

        var ok = new Button
        {
            Content = "Create",
            Width = 90,
            IsDefault = true,
            Margin = new Thickness(0, 0, 8, 0)
        };

        ok.Click += (_, _) => { DialogResult = true; };

        var cancel = new Button
        {
            Content = "Cancel",
            Width = 90,
            IsCancel = true
        };

        buttons.Children.Add(ok);
        buttons.Children.Add(cancel);
        panel.Children.Add(buttons);

        Content = panel;
    }
}
