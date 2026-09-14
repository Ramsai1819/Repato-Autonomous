using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using Autodesk.Revit.Attributes;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;
using WpfTextBox = System.Windows.Controls.TextBox;

namespace Repato.Revit;

[Transaction(TransactionMode.Manual)]
public sealed class OffsetGridBubblesCommand : IExternalCommand
{
    public Result Execute(
        ExternalCommandData commandData,
        ref string message,
        ElementSet elements)
    {
        UIDocument uiDocument = commandData.Application.ActiveUIDocument;
        Document document = uiDocument.Document;
        View activeView = document.ActiveView;

        var selectedGrids = uiDocument.Selection
            .GetElementIds()
            .Select(id => document.GetElement(id))
            .OfType<Autodesk.Revit.DB.Grid>()
            .ToList();

        if (selectedGrids.Count == 0)
        {
            TaskDialog.Show(
                "Repato - Offset Grid Bubbles",
                "Select one or more grids first, then run this tool."
            );
            return Result.Cancelled;
        }

        var inputWindow = new OffsetGridBubblesWindow();

        if (inputWindow.ShowDialog() != true)
        {
            return Result.Cancelled;
        }

        if (!TryParseMillimeters(inputWindow.LeftOffsetText, out double leftMm) ||
            !TryParseMillimeters(inputWindow.RightOffsetText, out double rightMm) ||
            !TryParseMillimeters(inputWindow.BottomOffsetText, out double bottomMm) ||
            !TryParseMillimeters(inputWindow.TopOffsetText, out double topMm) ||
            leftMm < 0 || rightMm < 0 || bottomMm < 0 || topMm < 0)
        {
            TaskDialog.Show(
                "Repato - Offset Grid Bubbles",
                "Enter zero or positive millimetre values for every offset."
            );
            return Result.Cancelled;
        }

        double leftFeet = UnitUtils.ConvertToInternalUnits(leftMm, UnitTypeId.Millimeters);
        double rightFeet = UnitUtils.ConvertToInternalUnits(rightMm, UnitTypeId.Millimeters);
        double bottomFeet = UnitUtils.ConvertToInternalUnits(bottomMm, UnitTypeId.Millimeters);
        double topFeet = UnitUtils.ConvertToInternalUnits(topMm, UnitTypeId.Millimeters);

        var allGrids = new FilteredElementCollector(document)
            .OfClass(typeof(Autodesk.Revit.DB.Grid))
            .Cast<Autodesk.Revit.DB.Grid>()
            .Where(grid => grid.CanBeVisibleInView(activeView))
            .ToList();

        var changed = new List<string>();
        var skipped = new List<string>();
        var errors = new List<string>();

        using (var transaction = new Transaction(
            document,
            "Repato - Offset Grid Bubbles"
        ))
        {
            transaction.Start();

            foreach (Autodesk.Revit.DB.Grid grid in selectedGrids)
            {
                try
                {
                    if (OffsetGrid(
                            grid,
                            allGrids,
                            activeView,
                            leftFeet,
                            rightFeet,
                            bottomFeet,
                            topFeet,
                            out string? skipReason))
                    {
                        changed.Add(grid.Name);
                    }
                    else
                    {
                        skipped.Add($"{grid.Name}: {skipReason}");
                    }
                }
                catch (Exception ex)
                {
                    errors.Add($"{grid.Name}: {ex.Message}");
                }
            }

            transaction.Commit();
        }

        uiDocument.RefreshActiveView();

        var lines = new List<string>
        {
            $"Changed: {changed.Count}",
            $"Skipped: {skipped.Count}",
            $"Errors: {errors.Count}"
        };

        if (skipped.Count > 0)
        {
            lines.Add("");
            lines.Add("Skipped");
            lines.AddRange(skipped);
        }

        if (errors.Count > 0)
        {
            lines.Add("");
            lines.Add("Errors");
            lines.AddRange(errors);
        }

        TaskDialog.Show(
            "Repato - Offset Grid Bubbles",
            string.Join(Environment.NewLine, lines)
        );

        return errors.Count == 0 ? Result.Succeeded : Result.Failed;
    }

    private static bool OffsetGrid(
        Autodesk.Revit.DB.Grid grid,
        List<Autodesk.Revit.DB.Grid> allGrids,
        View activeView,
        double leftOffsetFeet,
        double rightOffsetFeet,
        double bottomOffsetFeet,
        double topOffsetFeet,
        out string? skipReason)
    {
        skipReason = null;

        Curve? viewCurve = grid
            .GetCurvesInView(DatumExtentType.ViewSpecific, activeView)
            .FirstOrDefault();

        if (viewCurve is not Line line)
        {
            skipReason = "only visible straight grids are supported.";
            return false;
        }

        XYZ point0 = line.GetEndPoint(0);
        XYZ point1 = line.GetEndPoint(1);

        bool isHorizontal = Math.Abs(point1.X - point0.X)
            >= Math.Abs(point1.Y - point0.Y);

        var perpendicularPositions = new List<double>();

        foreach (Autodesk.Revit.DB.Grid otherGrid in allGrids)
        {
            if (otherGrid.Id == grid.Id)
            {
                continue;
            }

            Curve? otherViewCurve = otherGrid
                .GetCurvesInView(DatumExtentType.ViewSpecific, activeView)
                .FirstOrDefault();

            if (otherViewCurve is not Line otherLine)
            {
                continue;
            }

            XYZ otherPoint0 = otherLine.GetEndPoint(0);
            XYZ otherPoint1 = otherLine.GetEndPoint(1);

            bool otherIsHorizontal = Math.Abs(otherPoint1.X - otherPoint0.X)
                >= Math.Abs(otherPoint1.Y - otherPoint0.Y);

            if (isHorizontal == otherIsHorizontal)
            {
                continue;
            }

            perpendicularPositions.Add(
                isHorizontal
                    ? (otherPoint0.X + otherPoint1.X) / 2.0
                    : (otherPoint0.Y + otherPoint1.Y) / 2.0
            );
        }

        if (perpendicularPositions.Count == 0)
        {
            skipReason = "no perpendicular visible grids were found.";
            return false;
        }

        bool end0BubbleVisible = grid.IsBubbleVisibleInView(
            DatumEnds.End0,
            activeView
        );

        bool end1BubbleVisible = grid.IsBubbleVisibleInView(
            DatumEnds.End1,
            activeView
        );

        Line newViewLine;

        if (isHorizontal)
        {
            double y = (point0.Y + point1.Y) / 2.0;

            XYZ leftPoint = new XYZ(
                perpendicularPositions.Min() - leftOffsetFeet,
                y,
                point0.Z
            );

            XYZ rightPoint = new XYZ(
                perpendicularPositions.Max() + rightOffsetFeet,
                y,
                point1.Z
            );

            newViewLine = point0.X <= point1.X
                ? Line.CreateBound(leftPoint, rightPoint)
                : Line.CreateBound(rightPoint, leftPoint);
        }
        else
        {
            double x = (point0.X + point1.X) / 2.0;

            XYZ bottomPoint = new XYZ(
                x,
                perpendicularPositions.Min() - bottomOffsetFeet,
                point0.Z
            );

            XYZ topPoint = new XYZ(
                x,
                perpendicularPositions.Max() + topOffsetFeet,
                point1.Z
            );

            newViewLine = point0.Y <= point1.Y
                ? Line.CreateBound(bottomPoint, topPoint)
                : Line.CreateBound(topPoint, bottomPoint);
        }

        grid.SetDatumExtentType(
            DatumEnds.End0,
            activeView,
            DatumExtentType.ViewSpecific
        );

        grid.SetDatumExtentType(
            DatumEnds.End1,
            activeView,
            DatumExtentType.ViewSpecific
        );

        grid.SetCurveInView(
            DatumExtentType.ViewSpecific,
            activeView,
            newViewLine
        );

        RestoreBubble(grid, DatumEnds.End0, end0BubbleVisible, activeView);
        RestoreBubble(grid, DatumEnds.End1, end1BubbleVisible, activeView);

        return true;
    }

    private static void RestoreBubble(
        Autodesk.Revit.DB.Grid grid,
        DatumEnds end,
        bool shouldBeVisible,
        View activeView)
    {
        if (shouldBeVisible)
        {
            grid.ShowBubbleInView(end, activeView);
        }
        else
        {
            grid.HideBubbleInView(end, activeView);
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

public sealed class OffsetGridBubblesWindow : Window
{
    private readonly WpfTextBox _leftOffsetTextBox;
    private readonly WpfTextBox _rightOffsetTextBox;
    private readonly WpfTextBox _bottomOffsetTextBox;
    private readonly WpfTextBox _topOffsetTextBox;

    private readonly HashSet<WpfTextBox> _manuallyEditedTextBoxes = [];
    private bool _isSynchronising;

    public string LeftOffsetText => _leftOffsetTextBox.Text;
    public string RightOffsetText => _rightOffsetTextBox.Text;
    public string BottomOffsetText => _bottomOffsetTextBox.Text;
    public string TopOffsetText => _topOffsetTextBox.Text;

    public OffsetGridBubblesWindow()
    {
        Title = "Repato - Offset Grid Bubbles";
        Width = 470;
        Height = 330;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        var root = new StackPanel
        {
            Margin = new Thickness(20)
        };

        root.Children.Add(new TextBlock
        {
            Text = "Extend selected grids outside the outer visible perpendicular grids.",
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 8)
        });

        root.Children.Add(new TextBlock
        {
            Text = "Type one value first; unchanged fields automatically follow it.",
            TextWrapping = TextWrapping.Wrap,
            FontStyle = FontStyles.Italic,
            Margin = new Thickness(0, 0, 0, 16)
        });

        var offsetGrid = new System.Windows.Controls.Grid();
        offsetGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(140) });
        offsetGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) });

        for (int i = 0; i < 4; i++)
        {
            offsetGrid.RowDefinitions.Add(
                new RowDefinition { Height = new GridLength(34) }
            );
        }

        _leftOffsetTextBox = AddOffsetField(
            offsetGrid,
            0,
            "Left offset (mm)",
            "1000"
        );

        _rightOffsetTextBox = AddOffsetField(
            offsetGrid,
            1,
            "Right offset (mm)",
            "1000"
        );

        _bottomOffsetTextBox = AddOffsetField(
            offsetGrid,
            2,
            "Bottom offset (mm)",
            "1000"
        );

        _topOffsetTextBox = AddOffsetField(
            offsetGrid,
            3,
            "Top offset (mm)",
            "1000"
        );

        root.Children.Add(offsetGrid);

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 20, 0, 0)
        };

        var cancelButton = new Button
        {
            Content = "Cancel",
            MinWidth = 85,
            Padding = new Thickness(10, 5, 10, 5),
            IsCancel = true,
            Margin = new Thickness(0, 0, 8, 0)
        };

        var applyButton = new Button
        {
            Content = "Apply",
            MinWidth = 85,
            Padding = new Thickness(10, 5, 10, 5),
            IsDefault = true
        };

        applyButton.Click += (_, _) => DialogResult = true;

        buttons.Children.Add(cancelButton);
        buttons.Children.Add(applyButton);
        root.Children.Add(buttons);

        Content = root;
    }

    private WpfTextBox AddOffsetField(
        System.Windows.Controls.Grid grid,
        int row,
        string label,
        string defaultValue)
    {
        var labelText = new TextBlock
        {
            Text = label,
            VerticalAlignment = VerticalAlignment.Center
        };

        System.Windows.Controls.Grid.SetRow(labelText, row);
        System.Windows.Controls.Grid.SetColumn(labelText, 0);
        grid.Children.Add(labelText);

        var textBox = new WpfTextBox
        {
            Text = defaultValue,
            Width = 140,
            VerticalContentAlignment = VerticalAlignment.Center
        };

        textBox.TextChanged += OffsetTextBox_TextChanged;

        System.Windows.Controls.Grid.SetRow(textBox, row);
        System.Windows.Controls.Grid.SetColumn(textBox, 1);
        grid.Children.Add(textBox);

        return textBox;
    }

    private void OffsetTextBox_TextChanged(
        object sender,
        TextChangedEventArgs e)
    {
        if (_isSynchronising || sender is not WpfTextBox changedTextBox)
        {
            return;
        }

        _manuallyEditedTextBoxes.Add(changedTextBox);

        _isSynchronising = true;

        foreach (WpfTextBox textBox in GetAllOffsetTextBoxes())
        {
            if (!_manuallyEditedTextBoxes.Contains(textBox))
            {
                textBox.Text = changedTextBox.Text;
            }
        }

        _isSynchronising = false;
    }

    private IEnumerable<WpfTextBox> GetAllOffsetTextBoxes()
    {
        yield return _leftOffsetTextBox;
        yield return _rightOffsetTextBox;
        yield return _bottomOffsetTextBox;
        yield return _topOffsetTextBox;
    }
}