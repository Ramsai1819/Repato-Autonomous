using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using Autodesk.Revit.Attributes;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;
using WpfComboBox = System.Windows.Controls.ComboBox;
using WpfTextBox = System.Windows.Controls.TextBox;

namespace Repato.Revit;

[Transaction(TransactionMode.Manual)]
public sealed class GridResequenceCommand : IExternalCommand
{
    public Result Execute(ExternalCommandData data, ref string message, ElementSet elements)
    {
        UIDocument ui = data.Application.ActiveUIDocument;
        Document doc = ui.Document;
        View view = doc.ActiveView;

        var selectedGrids = ui.Selection.GetElementIds()
            .Select(id => doc.GetElement(id))
            .OfType<Autodesk.Revit.DB.Grid>()
            .ToList();

        if (selectedGrids.Count == 0)
        {
            TaskDialog.Show(
                "Repato - Grid Resequence",
                "Select one or more straight grids first."
            );
            return Result.Cancelled;
        }

        var dialog = new GridResequenceWindow();

        if (dialog.ShowDialog() != true)
        {
            return Result.Cancelled;
        }

        if (!TryLetterNumber(dialog.VerticalStart, out int verticalStart))
        {
            TaskDialog.Show(
                "Repato - Grid Resequence",
                "Vertical Start must be a letter, such as A, B, or AA."
            );
            return Result.Cancelled;
        }

        if (!int.TryParse(dialog.HorizontalStart, out int horizontalStart))
        {
            TaskDialog.Show(
                "Repato - Grid Resequence",
                "Horizontal Start must be a whole number, such as 1."
            );
            return Result.Cancelled;
        }

        var verticals = new List<GridPosition>();
        var horizontals = new List<GridPosition>();

        foreach (Autodesk.Revit.DB.Grid grid in selectedGrids)
        {
            Curve? curve = grid
                .GetCurvesInView(DatumExtentType.ViewSpecific, view)
                .FirstOrDefault();

            if (!(curve is Line line))
            {
                TaskDialog.Show(
                    "Repato - Grid Resequence",
                    $"Grid \"{grid.Name}\" is not a visible straight grid in the current view."
                );
                return Result.Cancelled;
            }

            XYZ a = line.GetEndPoint(0);
            XYZ b = line.GetEndPoint(1);

            bool isHorizontal = Math.Abs(b.X - a.X) >= Math.Abs(b.Y - a.Y);

            if (isHorizontal)
            {
                horizontals.Add(new GridPosition(grid, (a.Y + b.Y) / 2.0));
            }
            else
            {
                verticals.Add(new GridPosition(grid, (a.X + b.X) / 2.0));
            }
        }

        List<GridPosition> orderedVerticals = dialog.VerticalDirection == "Right to Left"
            ? verticals.OrderByDescending(x => x.Position).ToList()
            : verticals.OrderBy(x => x.Position).ToList();

        List<GridPosition> orderedHorizontals = dialog.HorizontalDirection == "Top to Bottom"
            ? horizontals.OrderByDescending(x => x.Position).ToList()
            : horizontals.OrderBy(x => x.Position).ToList();

        List<RenameItem> verticalRenames = CreateResequenceRenames(
            orderedVerticals,
            true,
            verticalStart
        );

        List<RenameItem> horizontalRenames = CreateResequenceRenames(
            orderedHorizontals,
            false,
            horizontalStart
        );

        List<RenameItem> renames = verticalRenames
            .Concat(horizontalRenames)
            .ToList();

        if (renames.Count == 0)
        {
            TaskDialog.Show(
                "Repato - Grid Resequence",
                "No valid grids were found."
            );
            return Result.Cancelled;
        }

        var selectedIds = selectedGrids
            .Select(x => x.Id)
            .ToHashSet();

        var usedByUnselected = new FilteredElementCollector(doc)
            .OfClass(typeof(Autodesk.Revit.DB.Grid))
            .Cast<Autodesk.Revit.DB.Grid>()
            .Where(x => !selectedIds.Contains(x.Id))
            .Select(x => x.Name)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        List<string> conflicts = renames
            .Select(x => x.NewName)
            .Where(usedByUnselected.Contains)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        if (conflicts.Count > 0)
        {
            TaskDialog.Show(
                "Repato - Grid Resequence",
                "These target names are already used by unselected grids:\n\n"
                + string.Join(", ", conflicts)
                + "\n\nSelect those grids too, or use a different starting value."
            );
            return Result.Cancelled;
        }

        using (Transaction transaction = new Transaction(doc, "Repato - Grid Resequence"))
        {
            transaction.Start();

            // Temporary names prevent Revit duplicate-name errors during swaps.
            foreach (RenameItem item in renames)
            {
                item.Grid.Name = $"REPATO-TEMP-{item.Grid.Id.Value}";
            }

            foreach (RenameItem item in renames)
            {
                item.Grid.Name = item.NewName;
            }

            transaction.Commit();
        }

        ui.RefreshActiveView();

        TaskDialog.Show(
            "Repato - Grid Resequence",
            $"Resequenced {verticalRenames.Count} vertical grid(s) and "
            + $"{horizontalRenames.Count} horizontal grid(s).\n\n"
            + "Grid locations were not moved."
        );

        return Result.Succeeded;
    }

    // QA-only entry point. It uses the same private ordering and rename planner as
    // Execute, but supplies fixed inputs and no UI. The caller owns rollback.
    internal static IReadOnlyDictionary<long, string> ApplyQaCase(
        Document document,
        View view,
        IReadOnlyCollection<Autodesk.Revit.DB.Grid> selectedGrids,
        string verticalDirection,
        string horizontalDirection,
        int verticalStart,
        int horizontalStart)
    {
        var verticals = new List<GridPosition>();
        var horizontals = new List<GridPosition>();
        foreach (Autodesk.Revit.DB.Grid grid in selectedGrids)
        {
            Curve curve = grid.GetCurvesInView(DatumExtentType.ViewSpecific, view).FirstOrDefault()
                ?? throw new InvalidOperationException($"Grid {grid.Name} is not visible in the active view.");
            if (curve is not Line line)
                throw new InvalidOperationException($"Grid {grid.Name} is not straight.");
            XYZ a = line.GetEndPoint(0);
            XYZ b = line.GetEndPoint(1);
            if (Math.Abs(b.X - a.X) >= Math.Abs(b.Y - a.Y))
                horizontals.Add(new GridPosition(grid, (a.Y + b.Y) / 2.0));
            else
                verticals.Add(new GridPosition(grid, (a.X + b.X) / 2.0));
        }
        List<GridPosition> orderedVerticals = verticalDirection == "Right to Left"
            ? verticals.OrderByDescending(x => x.Position).ToList()
            : verticals.OrderBy(x => x.Position).ToList();
        List<GridPosition> orderedHorizontals = horizontalDirection == "Top to Bottom"
            ? horizontals.OrderByDescending(x => x.Position).ToList()
            : horizontals.OrderBy(x => x.Position).ToList();
        List<RenameItem> renames = CreateResequenceRenames(orderedVerticals, true, verticalStart)
            .Concat(CreateResequenceRenames(orderedHorizontals, false, horizontalStart)).ToList();
        var selectedIds = selectedGrids.Select(grid => grid.Id).ToHashSet();
        var unselectedNames = new FilteredElementCollector(document).OfClass(typeof(Autodesk.Revit.DB.Grid))
            .Cast<Autodesk.Revit.DB.Grid>().Where(grid => !selectedIds.Contains(grid.Id))
            .Select(grid => grid.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        string[] conflicts = renames.Select(item => item.NewName).Where(unselectedNames.Contains)
            .Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        if (conflicts.Length != 0)
            throw new InvalidOperationException("Target names conflict with unselected grids: " + string.Join(", ", conflicts));
        using var transaction = new Transaction(document, "Repato QA - Grid Resequence");
        if (transaction.Start() != TransactionStatus.Started)
            throw new InvalidOperationException("Could not start resequence transaction.");
        foreach (RenameItem item in renames)
            item.Grid.Name = $"REPATO-QA-TEMP-{item.Grid.Id.Value}";
        foreach (RenameItem item in renames)
            item.Grid.Name = item.NewName;
        if (transaction.Commit() != TransactionStatus.Committed)
            throw new InvalidOperationException("Could not commit resequence transaction.");
        return renames.ToDictionary(item => item.Grid.Id.Value, item => item.NewName);
    }

    private static List<RenameItem> CreateResequenceRenames(
        List<GridPosition> gridsInPhysicalOrder,
        bool isLetterAxis,
        int startValue)
    {
        if (gridsInPhysicalOrder.Count == 0)
        {
            return new List<RenameItem>();
        }

        var labels = gridsInPhysicalOrder
            .Select(x => ParseGridLabel(x.Grid.Name))
            .ToList();

        var primaryNames = labels
            .Where(x => !x.IsSecondary)
            .Select(x => x.BaseName)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var groups = new Dictionary<string, GridFamily>(
            StringComparer.OrdinalIgnoreCase
        );

        foreach (GridLabel label in labels)
        {
            bool hasSelectedPrimary = primaryNames.Contains(label.BaseName);

            // A selected secondary grid without its primary is left unchanged.
            // Example: selecting only 3.2 keeps it as 3.2.
            bool isOrphanSecondary = label.IsSecondary && !hasSelectedPrimary;

            string groupKey = isOrphanSecondary
                ? $"ORPHAN::{label.FullName}"
                : label.BaseName;

            if (!groups.ContainsKey(groupKey))
            {
                groups[groupKey] = new GridFamily(
                    groupKey,
                    label.BaseName,
                    isOrphanSecondary
                );
            }

            groups[groupKey].Labels.Add(label);
        }

        List<GridFamily> orderedFamilies = groups.Values
            .OrderBy(x => x.BaseName, new GridBaseNameComparer(isLetterAxis))
            .ThenBy(x => x.IsOrphanSecondary ? 1 : 0)
            .ToList();

        var targetNames = new List<string>();
        int currentValue = startValue;

        foreach (GridFamily family in orderedFamilies)
        {
            if (family.IsOrphanSecondary)
            {
                targetNames.Add(family.Labels[0].FullName);
                continue;
            }

            string newBaseName = isLetterAxis
                ? LetterName(currentValue)
                : currentValue.ToString();

            targetNames.Add(newBaseName);

            List<GridLabel> secondaryLabels = family.Labels
                .Where(x => x.IsSecondary)
                .OrderBy(x => x.Suffix, new SecondarySuffixComparer())
                .ToList();

            foreach (GridLabel secondary in secondaryLabels)
            {
                targetNames.Add(newBaseName + secondary.Suffix);
            }

            currentValue++;
        }

        // The generated family sequence is applied to the grids in their
        // selected physical direction. This changes names only, never locations.
        var renames = new List<RenameItem>();

        for (int i = 0; i < gridsInPhysicalOrder.Count; i++)
        {
            renames.Add(
                new RenameItem(
                    gridsInPhysicalOrder[i].Grid,
                    targetNames[i]
                )
            );
        }

        return renames;
    }

    private static GridLabel ParseGridLabel(string gridName)
    {
        string name = (gridName ?? "").Trim();
        int dotIndex = name.IndexOf('.');

        if (dotIndex > 0 && dotIndex < name.Length - 1)
        {
            return new GridLabel(
                name,
                name.Substring(0, dotIndex),
                name.Substring(dotIndex),
                true
            );
        }

        return new GridLabel(name, name, "", false);
    }

    private static bool TryLetterNumber(string value, out int number)
    {
        number = 0;
        string text = (value ?? "").Trim().ToUpperInvariant();

        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        foreach (char c in text)
        {
            if (c < 'A' || c > 'Z')
            {
                return false;
            }

            number = (number * 26) + (c - 'A' + 1);
        }

        return true;
    }

    private static string LetterName(int number)
    {
        string result = "";

        while (number > 0)
        {
            number--;
            result = (char)('A' + (number % 26)) + result;
            number /= 26;
        }

        return result;
    }

    private sealed class GridPosition
    {
        public Autodesk.Revit.DB.Grid Grid { get; }
        public double Position { get; }

        public GridPosition(Autodesk.Revit.DB.Grid grid, double position)
        {
            Grid = grid;
            Position = position;
        }
    }

    private sealed class RenameItem
    {
        public Autodesk.Revit.DB.Grid Grid { get; }
        public string NewName { get; }

        public RenameItem(Autodesk.Revit.DB.Grid grid, string newName)
        {
            Grid = grid;
            NewName = newName;
        }
    }

    private sealed class GridLabel
    {
        public string FullName { get; }
        public string BaseName { get; }
        public string Suffix { get; }
        public bool IsSecondary { get; }

        public GridLabel(
            string fullName,
            string baseName,
            string suffix,
            bool isSecondary)
        {
            FullName = fullName;
            BaseName = baseName;
            Suffix = suffix;
            IsSecondary = isSecondary;
        }
    }

    private sealed class GridFamily
    {
        public string Key { get; }
        public string BaseName { get; }
        public bool IsOrphanSecondary { get; }
        public List<GridLabel> Labels { get; }

        public GridFamily(
            string key,
            string baseName,
            bool isOrphanSecondary)
        {
            Key = key;
            BaseName = baseName;
            IsOrphanSecondary = isOrphanSecondary;
            Labels = new List<GridLabel>();
        }
    }

    private sealed class GridBaseNameComparer : IComparer<string>
    {
        private readonly bool _isLetterAxis;

        public GridBaseNameComparer(bool isLetterAxis)
        {
            _isLetterAxis = isLetterAxis;
        }

        public int Compare(string? x, string? y)
        {
            string xValue = x ?? string.Empty;
            string yValue = y ?? string.Empty;

            if (string.Equals(xValue, yValue, StringComparison.OrdinalIgnoreCase))
            {
                return 0;
            }

            if (_isLetterAxis &&
                TryLetterNumber(xValue, out int xLetter) &&
                TryLetterNumber(yValue, out int yLetter))
            {
                return xLetter.CompareTo(yLetter);
            }

            if (!_isLetterAxis &&
                int.TryParse(xValue, out int xNumber) &&
                int.TryParse(yValue, out int yNumber))
            {
                return xNumber.CompareTo(yNumber);
            }

            return string.Compare(
                xValue,
                yValue,
                StringComparison.OrdinalIgnoreCase
            );
        }
    }

    private sealed class SecondarySuffixComparer : IComparer<string>
    {
        public int Compare(string? x, string? y)
        {
            string xText = (x ?? string.Empty).TrimStart('.');
            string yText = (y ?? string.Empty).TrimStart('.');

            if (int.TryParse(xText, out int xNumber) &&
                int.TryParse(yText, out int yNumber))
            {
                return xNumber.CompareTo(yNumber);
            }

            return string.Compare(
                xText,
                yText,
                StringComparison.OrdinalIgnoreCase
            );
        }
    }
}

public sealed class GridResequenceWindow : Window
{
    private readonly WpfTextBox _verticalStart;
    private readonly WpfTextBox _horizontalStart;
    private readonly WpfComboBox _verticalDirection;
    private readonly WpfComboBox _horizontalDirection;

    public string VerticalStart => _verticalStart.Text;
    public string HorizontalStart => _horizontalStart.Text;

    public string VerticalDirection =>
        _verticalDirection.SelectedItem?.ToString() ?? "Left to Right";

    public string HorizontalDirection =>
        _horizontalDirection.SelectedItem?.ToString() ?? "Bottom to Top";

    public GridResequenceWindow()
    {
        Title = "Repato - Grid Resequence";
        Width = 520;
        Height = 285;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        var root = new StackPanel
        {
            Margin = new Thickness(20)
        };

        root.Children.Add(new TextBlock
        {
            Text = "Secondary grids remain grouped with their parent grid.",
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 0, 0, 5)
        });

        root.Children.Add(new TextBlock
        {
            Text = "Example: A, B, A.1 becomes A, A.1, B. "
                + "Grid positions are never moved.",
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 16)
        });

        _verticalStart = new WpfTextBox
        {
            Text = "A",
            Width = 80
        };

        _verticalDirection = new WpfComboBox
        {
            ItemsSource = new[] { "Left to Right", "Right to Left" },
            SelectedIndex = 0,
            Width = 180
        };

        _horizontalStart = new WpfTextBox
        {
            Text = "1",
            Width = 80
        };

        _horizontalDirection = new WpfComboBox
        {
            ItemsSource = new[] { "Bottom to Top", "Top to Bottom" },
            SelectedIndex = 0,
            Width = 180
        };

        root.Children.Add(
            CreateRow("Vertical grids", _verticalStart, _verticalDirection)
        );

        root.Children.Add(
            CreateRow("Horizontal grids", _horizontalStart, _horizontalDirection)
        );

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 18, 0, 0)
        };

        var cancel = new Button
        {
            Content = "Cancel",
            MinWidth = 85,
            IsCancel = true,
            Margin = new Thickness(0, 0, 8, 0)
        };

        var apply = new Button
        {
            Content = "Resequence",
            MinWidth = 100,
            IsDefault = true
        };

        apply.Click += (_, _) => DialogResult = true;

        buttons.Children.Add(cancel);
        buttons.Children.Add(apply);
        root.Children.Add(buttons);

        Content = root;
    }

    private static StackPanel CreateRow(
        string label,
        WpfTextBox start,
        WpfComboBox direction)
    {
        var row = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Margin = new Thickness(0, 0, 0, 12)
        };

        row.Children.Add(new TextBlock
        {
            Text = label,
            Width = 135,
            VerticalAlignment = VerticalAlignment.Center,
            FontWeight = FontWeights.SemiBold
        });

        row.Children.Add(start);
        row.Children.Add(new TextBlock { Width = 15 });
        row.Children.Add(direction);

        return row;
    }
}
