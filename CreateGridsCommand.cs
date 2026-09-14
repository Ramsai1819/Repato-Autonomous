using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Autodesk.Revit.Attributes;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;
using WpfTextBox = System.Windows.Controls.TextBox;

namespace Repato.Revit;

[Transaction(TransactionMode.Manual)]
public sealed class CreateGridsCommand : IExternalCommand
{
    public Result Execute(
        ExternalCommandData commandData,
        ref string message,
        ElementSet elements)
    {
        Document? document = commandData.Application.ActiveUIDocument?.Document;

        if (document is null)
        {
            TaskDialog.Show(
                "Repato - Create Grids",
                "Open a Revit project before running Create Grids."
            );
            return Result.Cancelled;
        }

        var inputWindow = new CreateGridsWindow();

        if (inputWindow.ShowDialog() != true)
        {
            return Result.Cancelled;
        }

        GridCreationResult result = GridCreator.Create(
            document,
            inputWindow.VerticalGridData,
            inputWindow.HorizontalGridData,
            inputWindow.GridLengthText
        );

        TaskDialog.Show(
            "Repato - Create Grids",
            result.ToDisplayText()
        );

        return result.Success ? Result.Succeeded : Result.Failed;
    }
}

public sealed class CreateGridsWindow : Window
{
    private readonly WpfTextBox _verticalGridTextBox;
    private readonly WpfTextBox _horizontalGridTextBox;
    private readonly WpfTextBox _gridLengthTextBox;

    public string VerticalGridData => _verticalGridTextBox.Text;
    public string HorizontalGridData => _horizontalGridTextBox.Text;
    public string GridLengthText => _gridLengthTextBox.Text;

    public CreateGridsWindow()
    {
        Title = "Repato - Create Grids";
        Width = 680;
        Height = 620;
        MinWidth = 680;
        MinHeight = 620;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ResizeMode = ResizeMode.CanResize;

        var root = new System.Windows.Controls.Grid
        {
            Margin = new Thickness(20)
        };

        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(10) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(12) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(18) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var instructions = new TextBlock
        {
            Text = "Enter one grid per line as: Grid Name, press Tab, then Position in mm",
            FontSize = 14,
            FontWeight = FontWeights.SemiBold,
            Foreground = Brushes.DimGray
        };
        System.Windows.Controls.Grid.SetRow(instructions, 0);
        root.Children.Add(instructions);

        var verticalLabel = new TextBlock
        {
            Text = "Vertical grids",
            FontWeight = FontWeights.SemiBold
        };
        System.Windows.Controls.Grid.SetRow(verticalLabel, 2);
        root.Children.Add(verticalLabel);

        _verticalGridTextBox = new WpfTextBox
        {
            AcceptsReturn = true,
            AcceptsTab = true,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            TextWrapping = TextWrapping.NoWrap,
            FontFamily = new FontFamily("Consolas"),
            FontSize = 13,
            Text = "A\t0\nB\t6000\nC\t12000"
        };
        System.Windows.Controls.Grid.SetRow(_verticalGridTextBox, 3);
        root.Children.Add(_verticalGridTextBox);

        var horizontalLabel = new TextBlock
        {
            Text = "Horizontal grids",
            FontWeight = FontWeights.SemiBold
        };
        System.Windows.Controls.Grid.SetRow(horizontalLabel, 5);
        root.Children.Add(horizontalLabel);

        _horizontalGridTextBox = new WpfTextBox
        {
            AcceptsReturn = true,
            AcceptsTab = true,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            TextWrapping = TextWrapping.NoWrap,
            FontFamily = new FontFamily("Consolas"),
            FontSize = 13,
            Text = "1\t0\n2\t6000\n3\t12000"
        };
        System.Windows.Controls.Grid.SetRow(_horizontalGridTextBox, 6);
        root.Children.Add(_horizontalGridTextBox);

        var footer = new System.Windows.Controls.Grid();
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(130) });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var lengthLabel = new TextBlock
        {
            Text = "Grid length (mm)",
            VerticalAlignment = VerticalAlignment.Center,
            FontWeight = FontWeights.SemiBold
        };
        System.Windows.Controls.Grid.SetColumn(lengthLabel, 0);
        footer.Children.Add(lengthLabel);

        _gridLengthTextBox = new WpfTextBox
        {
            Text = "30000",
            VerticalContentAlignment = VerticalAlignment.Center
        };
        System.Windows.Controls.Grid.SetColumn(_gridLengthTextBox, 2);
        footer.Children.Add(_gridLengthTextBox);

        var cancelButton = new Button
        {
            Content = "Cancel",
            MinWidth = 85,
            Padding = new Thickness(10, 5, 10, 5),
            IsCancel = true
        };
        System.Windows.Controls.Grid.SetColumn(cancelButton, 4);
        footer.Children.Add(cancelButton);

        var createButton = new Button
        {
            Content = "Create Grids",
            MinWidth = 105,
            Padding = new Thickness(10, 5, 10, 5),
            IsDefault = true
        };
        createButton.Click += (_, _) => DialogResult = true;
        System.Windows.Controls.Grid.SetColumn(createButton, 6);
        footer.Children.Add(createButton);

        System.Windows.Controls.Grid.SetRow(footer, 8);
        root.Children.Add(footer);

        Content = root;
    }
}

public static class GridCreator
{
    public static GridCreationResult Create(
        Document document,
        string verticalGridData,
        string horizontalGridData,
        string gridLengthText)
    {
        if (!TryParseMillimeters(
                gridLengthText,
                out double gridLengthMillimetres) ||
            gridLengthMillimetres <= 0)
        {
            return GridCreationResult.Failure(
                "Grid length must be a positive value in millimetres."
            );
        }

        if (!TryParseNamedPositions(
                verticalGridData,
                out var verticals,
                out string? verticalError))
        {
            return GridCreationResult.Failure(verticalError!);
        }

        if (!TryParseNamedPositions(
                horizontalGridData,
                out var horizontals,
                out string? horizontalError))
        {
            return GridCreationResult.Failure(horizontalError!);
        }

        if (verticals.Count == 0 && horizontals.Count == 0)
        {
            return GridCreationResult.Failure(
                "Enter at least one vertical or horizontal grid."
            );
        }

        var existingNames = new FilteredElementCollector(document)
            .OfClass(typeof(Autodesk.Revit.DB.Grid))
            .Cast<Autodesk.Revit.DB.Grid>()
            .Select(grid => grid.Name)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        double halfLengthFeet = UnitUtils.ConvertToInternalUnits(
            gridLengthMillimetres / 2.0,
            UnitTypeId.Millimeters
        );

        var created = new List<string>();
        var skipped = new List<string>();
        var errors = new List<string>();

        using var transaction = new Transaction(
            document,
            "Repato - Create Grids"
        );

        transaction.Start();

        foreach (var definition in verticals)
        {
            CreateGrid(
                document,
                definition,
                true,
                halfLengthFeet,
                existingNames,
                created,
                skipped,
                errors
            );
        }

        foreach (var definition in horizontals)
        {
            CreateGrid(
                document,
                definition,
                false,
                halfLengthFeet,
                existingNames,
                created,
                skipped,
                errors
            );
        }

        transaction.Commit();

        return new GridCreationResult(
            true,
            created,
            skipped,
            errors,
            null
        );
    }

    private static bool TryParseNamedPositions(
        string input,
        out List<(string Name, double PositionMillimetres)> definitions,
        out string? error)
    {
        definitions = [];
        error = null;

        foreach (string rawLine in input.Replace("\r", "").Split('\n'))
        {
            string line = rawLine.Trim();

            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            string[] parts = line.Contains('\t')
                ? line.Split('\t', 2, StringSplitOptions.TrimEntries)
                : line.Split('|', 2, StringSplitOptions.TrimEntries);

            if (parts.Length != 2 ||
                string.IsNullOrWhiteSpace(parts[0]) ||
                !TryParseMillimeters(
                    parts[1],
                    out double positionMillimetres))
            {
                error =
                    "Use one grid per line: Grid Name, press Tab, then Position in mm. Example: A<Tab>6000";

                return false;
            }

            definitions.Add((parts[0], positionMillimetres));
        }

        return true;
    }

    private static void CreateGrid(
        Document document,
        (string Name, double PositionMillimetres) definition,
        bool isVertical,
        double halfLengthFeet,
        HashSet<string> existingNames,
        List<string> created,
        List<string> skipped,
        List<string> errors)
    {
        if (existingNames.Contains(definition.Name))
        {
            skipped.Add($"{definition.Name} already exists");
            return;
        }

        Autodesk.Revit.DB.Grid? grid = null;

        try
        {
            double positionFeet = UnitUtils.ConvertToInternalUnits(
                definition.PositionMillimetres,
                UnitTypeId.Millimeters
            );

            XYZ start = isVertical
                ? new XYZ(positionFeet, -halfLengthFeet, 0)
                : new XYZ(-halfLengthFeet, positionFeet, 0);

            XYZ end = isVertical
                ? new XYZ(positionFeet, halfLengthFeet, 0)
                : new XYZ(halfLengthFeet, positionFeet, 0);

            grid = Autodesk.Revit.DB.Grid.Create(
                document,
                Line.CreateBound(start, end)
            );

            grid.Name = definition.Name;
            existingNames.Add(definition.Name);

            created.Add(
                $"{definition.Name} ({(isVertical ? "vertical" : "horizontal")}) created"
            );
        }
        catch (Exception ex)
        {
            if (grid is not null && grid.IsValidObject)
            {
                document.Delete(grid.Id);
            }

            errors.Add($"{definition.Name}: {ex.Message}");
        }
    }

    private static bool TryParseMillimeters(
        string value,
        out double millimetres)
    {
        return double.TryParse(
                   value,
                   NumberStyles.Float,
                   CultureInfo.InvariantCulture,
                   out millimetres
               )
               ||
               double.TryParse(
                   value,
                   NumberStyles.Float,
                   CultureInfo.CurrentCulture,
                   out millimetres
               );
    }
}

public sealed record GridCreationResult(
    bool Success,
    List<string> Created,
    List<string> Skipped,
    List<string> Errors,
    string? FailureMessage)
{
    public static GridCreationResult Failure(string message)
    {
        return new GridCreationResult(false, [], [], [], message);
    }

    public string ToDisplayText()
    {
        if (!Success)
        {
            return FailureMessage ?? "Create Grids failed.";
        }

        var lines = new List<string>
        {
            $"Created: {Created.Count}",
            $"Skipped: {Skipped.Count}",
            $"Errors: {Errors.Count}"
        };

        if (Created.Count > 0)
        {
            lines.Add("");
            lines.AddRange(Created);
        }

        if (Skipped.Count > 0)
        {
            lines.Add("");
            lines.Add("Skipped");
            lines.AddRange(Skipped);
        }

        if (Errors.Count > 0)
        {
            lines.Add("");
            lines.Add("Errors");
            lines.AddRange(Errors);
        }

        return string.Join(Environment.NewLine, lines);
    }
}