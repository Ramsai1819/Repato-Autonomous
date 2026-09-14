using System.Windows;
using System.Windows.Controls;
using Autodesk.Revit.Attributes;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;

namespace Repato.Revit;

[Transaction(TransactionMode.Manual)]
public sealed class GridBubbleVisibilityCommand : IExternalCommand
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
                "Repato - Grid Bubble Visibility",
                "Select one or more grids first, then run this tool."
            );

            return Result.Cancelled;
        }

        var inputWindow = new GridBubbleVisibilityWindow();

        if (inputWindow.ShowDialog() != true)
        {
            return Result.Cancelled;
        }

        var changed = new List<string>();
        var errors = new List<string>();

        using (var transaction = new Transaction(
            document,
            "Repato - Grid Bubble Visibility"
        ))
        {
            transaction.Start();

            foreach (Autodesk.Revit.DB.Grid grid in selectedGrids)
            {
                try
                {
                    UpdateBubbleVisibility(
                        grid,
                        activeView,
                        inputWindow.ShowHorizontalLeft,
                        inputWindow.ShowHorizontalRight,
                        inputWindow.ShowVerticalBottom,
                        inputWindow.ShowVerticalTop
                    );

                    changed.Add(grid.Name);
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
            $"Errors: {errors.Count}"
        };

        if (changed.Count > 0)
        {
            lines.Add("");
            lines.Add("Updated grids");
            lines.AddRange(changed);
        }

        if (errors.Count > 0)
        {
            lines.Add("");
            lines.Add("Errors");
            lines.AddRange(errors);
        }

        TaskDialog.Show(
            "Repato - Grid Bubble Visibility",
            string.Join(Environment.NewLine, lines)
        );

        return errors.Count == 0 ? Result.Succeeded : Result.Failed;
    }

    private static void UpdateBubbleVisibility(
        Autodesk.Revit.DB.Grid grid,
        View activeView,
        bool showHorizontalLeft,
        bool showHorizontalRight,
        bool showVerticalBottom,
        bool showVerticalTop)
    {
        Curve viewCurve = grid
            .GetCurvesInView(DatumExtentType.ViewSpecific, activeView)
            .FirstOrDefault()
            ?? throw new InvalidOperationException(
                "The grid has no visible curve in the active view."
            );

        XYZ point0 = viewCurve.GetEndPoint(0);
        XYZ point1 = viewCurve.GetEndPoint(1);

        bool isHorizontal = Math.Abs(point1.X - point0.X)
            >= Math.Abs(point1.Y - point0.Y);

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

        if (isHorizontal)
        {
            DatumEnds leftEnd = point0.X <= point1.X
                ? DatumEnds.End0
                : DatumEnds.End1;

            DatumEnds rightEnd = leftEnd == DatumEnds.End0
                ? DatumEnds.End1
                : DatumEnds.End0;

            SetBubble(grid, leftEnd, showHorizontalLeft, activeView);
            SetBubble(grid, rightEnd, showHorizontalRight, activeView);

            VerifyBubble(grid, leftEnd, showHorizontalLeft, activeView, "left");
            VerifyBubble(grid, rightEnd, showHorizontalRight, activeView, "right");
        }
        else
        {
            DatumEnds bottomEnd = point0.Y <= point1.Y
                ? DatumEnds.End0
                : DatumEnds.End1;

            DatumEnds topEnd = bottomEnd == DatumEnds.End0
                ? DatumEnds.End1
                : DatumEnds.End0;

            SetBubble(grid, bottomEnd, showVerticalBottom, activeView);
            SetBubble(grid, topEnd, showVerticalTop, activeView);

            VerifyBubble(grid, bottomEnd, showVerticalBottom, activeView, "bottom");
            VerifyBubble(grid, topEnd, showVerticalTop, activeView, "top");
        }
    }

    private static void SetBubble(
        Autodesk.Revit.DB.Grid grid,
        DatumEnds end,
        bool shouldShow,
        View activeView)
    {
        if (shouldShow)
        {
            grid.ShowBubbleInView(end, activeView);
        }
        else
        {
            grid.HideBubbleInView(end, activeView);
        }
    }

    private static void VerifyBubble(
        Autodesk.Revit.DB.Grid grid,
        DatumEnds end,
        bool shouldBeVisible,
        View activeView,
        string position)
    {
        bool isVisible = grid.IsBubbleVisibleInView(end, activeView);

        if (isVisible != shouldBeVisible)
        {
            throw new InvalidOperationException(
                $"Revit did not apply the requested bubble visibility at the {position} end."
            );
        }
    }
}

public sealed class GridBubbleVisibilityWindow : Window
{
    private readonly CheckBox _horizontalLeftCheckBox;
    private readonly CheckBox _horizontalRightCheckBox;
    private readonly CheckBox _verticalBottomCheckBox;
    private readonly CheckBox _verticalTopCheckBox;

    public bool ShowHorizontalLeft => _horizontalLeftCheckBox.IsChecked == true;
    public bool ShowHorizontalRight => _horizontalRightCheckBox.IsChecked == true;
    public bool ShowVerticalBottom => _verticalBottomCheckBox.IsChecked == true;
    public bool ShowVerticalTop => _verticalTopCheckBox.IsChecked == true;

    public GridBubbleVisibilityWindow()
    {
        Title = "Repato - Grid Bubble Visibility";
        Width = 430;
        Height = 265;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        var root = new StackPanel
        {
            Margin = new Thickness(20)
        };

        root.Children.Add(new TextBlock
        {
            Text = "Apply bubble visibility to the selected grids",
            FontSize = 14,
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 0, 0, 16)
        });

        var horizontalPanel = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Margin = new Thickness(0, 0, 0, 10)
        };

        horizontalPanel.Children.Add(new TextBlock
        {
            Text = "Horizontal grids:",
            Width = 125,
            VerticalAlignment = VerticalAlignment.Center
        });

        _horizontalLeftCheckBox = new CheckBox
        {
            Content = "Left",
            IsChecked = true,
            Margin = new Thickness(0, 0, 14, 0)
        };

        _horizontalRightCheckBox = new CheckBox
        {
            Content = "Right",
            IsChecked = false
        };

        horizontalPanel.Children.Add(_horizontalLeftCheckBox);
        horizontalPanel.Children.Add(_horizontalRightCheckBox);
        root.Children.Add(horizontalPanel);

        var verticalPanel = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Margin = new Thickness(0, 0, 0, 20)
        };

        verticalPanel.Children.Add(new TextBlock
        {
            Text = "Vertical grids:",
            Width = 125,
            VerticalAlignment = VerticalAlignment.Center
        });

        _verticalBottomCheckBox = new CheckBox
        {
            Content = "Bottom",
            IsChecked = true,
            Margin = new Thickness(0, 0, 14, 0)
        };

        _verticalTopCheckBox = new CheckBox
        {
            Content = "Top",
            IsChecked = false
        };

        verticalPanel.Children.Add(_verticalBottomCheckBox);
        verticalPanel.Children.Add(_verticalTopCheckBox);
        root.Children.Add(verticalPanel);

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right
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
}