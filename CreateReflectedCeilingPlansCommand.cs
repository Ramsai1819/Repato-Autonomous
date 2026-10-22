using System.Windows;
using System.Windows.Controls;
using Autodesk.Revit.Attributes;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;
using WpfComboBox = System.Windows.Controls.ComboBox;
using WpfTextBox = System.Windows.Controls.TextBox;

namespace Repato.Revit;

[Transaction(TransactionMode.Manual)]
public sealed class CreateReflectedCeilingPlansCommand : IExternalCommand
{
    public Result Execute(ExternalCommandData commandData, ref string message, ElementSet elements)
    {
        Document? document = commandData.Application.ActiveUIDocument?.Document;
        if (document is null)
        {
            TaskDialog.Show("Repato - Create RCP Views", "Open a Revit project before running Create RCP Views.");
            return Result.Cancelled;
        }

        try
        {
            using var host = new RevitReflectedCeilingPlanHost(document);
            IReadOnlyList<ReflectedCeilingPlanLevel> levels = host.GetLevels();
            IReadOnlyList<ReflectedCeilingPlanType> types = host.GetCeilingPlanTypes();
            if (levels.Count == 0)
            {
                TaskDialog.Show("Repato - Create RCP Views", "This project has no levels to select.");
                return Result.Cancelled;
            }
            if (types.Count == 0)
            {
                TaskDialog.Show("Repato - Create RCP Views", "This project has no Ceiling Plan view type.");
                return Result.Cancelled;
            }

            var picker = new ReflectedCeilingPlanPicker(levels, types);
            if (picker.ShowDialog() != true)
                return Result.Cancelled;

            ReflectedCeilingPlanResult result = ReflectedCeilingPlanWorkflow.Execute(picker.Input, host);
            string names = string.Join(Environment.NewLine, result.Created.Select(x => "• " + x.ViewName));
            TaskDialog.Show("Repato - Create RCP Views", $"Created {result.Created.Count} reflected ceiling plan(s):{Environment.NewLine}{names}");
            return Result.Succeeded;
        }
        catch (Exception ex)
        {
            message = ex.Message;
            TaskDialog.Show("Repato - Create RCP Views", "No successful result was reported.\n\n" + ex.Message);
            return Result.Failed;
        }
    }
}

internal sealed class RevitReflectedCeilingPlanHost : IReflectedCeilingPlanHost, IDisposable
{
    private readonly Document _document;
    private TransactionGroup? _group;
    private Transaction? _transaction;

    public RevitReflectedCeilingPlanHost(Document document) => _document = document;
    public bool IsFamilyDocument => _document.IsFamilyDocument;
    public bool IsModifiable => _document.IsModifiable;
    public bool IsReadOnly => _document.IsReadOnly;

    public IReadOnlyList<ReflectedCeilingPlanLevel> GetLevels() =>
        new FilteredElementCollector(_document)
            .OfClass(typeof(Level)).Cast<Level>()
            .OrderBy(x => x.Elevation).ThenBy(x => x.Name, StringComparer.OrdinalIgnoreCase)
            .Select(x => new ReflectedCeilingPlanLevel(x.Id.Value, x.Name)).ToArray();

    public IReadOnlyList<ReflectedCeilingPlanType> GetCeilingPlanTypes() =>
        new FilteredElementCollector(_document)
            .OfClass(typeof(ViewFamilyType)).Cast<ViewFamilyType>()
            .Where(x => x.ViewFamily == ViewFamily.CeilingPlan)
            .OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase)
            .Select(x => new ReflectedCeilingPlanType(x.Id.Value, x.Name)).ToArray();

    public IReadOnlyCollection<string> GetExistingViewNames() =>
        new FilteredElementCollector(_document)
            .OfClass(typeof(View)).Cast<View>()
            .Where(x => !x.IsTemplate)
            .Select(x => x.Name).ToArray();

    public void StartTransactionGroup(string name)
    {
        _group = new TransactionGroup(_document, name);
        if (_group.Start() != TransactionStatus.Started)
            throw new InvalidOperationException("Could not start the reflected ceiling plan transaction group.");
    }

    public void StartTransaction(string name)
    {
        _transaction = new Transaction(_document, name);
        if (_transaction.Start() != TransactionStatus.Started)
            throw new InvalidOperationException("Could not start the reflected ceiling plan transaction.");
    }

    public long CreateViewPlan(long viewTypeId, long levelId, string viewName)
    {
        ViewPlan view = ViewPlan.Create(_document, new ElementId(viewTypeId), new ElementId(levelId));
        view.Name = viewName;
        return view.Id.Value;
    }

    public void CommitTransaction()
    {
        if (_transaction?.Commit() != TransactionStatus.Committed)
            throw new InvalidOperationException("Revit did not commit the reflected ceiling plan transaction.");
    }

    public void AssimilateTransactionGroup()
    {
        if (_group?.Assimilate() != TransactionStatus.Committed)
            throw new InvalidOperationException("Revit did not assimilate the reflected ceiling plan transaction group.");
    }

    public void RollBackTransactionGroup()
    {
        if (_transaction?.GetStatus() == TransactionStatus.Started)
            _transaction.RollBack();
        if (_group?.GetStatus() == TransactionStatus.Started)
            _group.RollBack();
    }

    public void Dispose()
    {
        _transaction?.Dispose();
        _group?.Dispose();
    }
}

internal sealed class ReflectedCeilingPlanPicker : Window
{
    private readonly ListBox _levels;
    private readonly WpfComboBox _types;
    private readonly WpfTextBox _suffix;

    public ReflectedCeilingPlanInput Input => new(
        _levels.SelectedItems.Cast<ReflectedCeilingPlanLevel>().Select(x => x.Id).ToArray(),
        ((ReflectedCeilingPlanType?)_types.SelectedItem)?.Id ?? 0,
        _suffix.Text);

    public ReflectedCeilingPlanPicker(
        IReadOnlyList<ReflectedCeilingPlanLevel> levels,
        IReadOnlyList<ReflectedCeilingPlanType> types)
    {
        Title = "Repato - Create RCP Views";
        Width = 440;
        Height = 520;
        MinWidth = 400;
        MinHeight = 460;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        ResizeMode = ResizeMode.CanResize;

        var panel = new StackPanel { Margin = new Thickness(18) };
        panel.Children.Add(new TextBlock
        {
            Text = "Select one or more levels. Each new view will be named ‘Level - Suffix’. Existing names are not overwritten or auto-renamed.",
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 0, 0, 12)
        });

        panel.Children.Add(new TextBlock { Text = "Levels", FontWeight = FontWeights.SemiBold });
        _levels = new ListBox
        {
            ItemsSource = levels,
            DisplayMemberPath = nameof(ReflectedCeilingPlanLevel.Name),
            SelectionMode = SelectionMode.Extended,
            Height = 190,
            Margin = new Thickness(0, 4, 0, 12)
        };
        panel.Children.Add(_levels);

        panel.Children.Add(new TextBlock { Text = "Ceiling plan type", FontWeight = FontWeights.SemiBold });
        _types = new WpfComboBox
        {
            ItemsSource = types,
            DisplayMemberPath = nameof(ReflectedCeilingPlanType.Name),
            SelectedIndex = 0,
            Margin = new Thickness(0, 4, 0, 12)
        };
        panel.Children.Add(_types);

        panel.Children.Add(new TextBlock { Text = "View-name suffix", FontWeight = FontWeights.SemiBold });
        _suffix = new WpfTextBox { Text = "RCP", Margin = new Thickness(0, 4, 0, 14) };
        panel.Children.Add(_suffix);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = new Button { Content = "Cancel", IsCancel = true, MinWidth = 90, Margin = new Thickness(0, 0, 8, 0), Padding = new Thickness(10, 5, 10, 5) };
        var create = new Button { Content = "Create Views", IsDefault = true, MinWidth = 105, Padding = new Thickness(10, 5, 10, 5) };
        cancel.Click += (_, _) => { DialogResult = false; };
        create.Click += (_, _) =>
        {
            if (_levels.SelectedItems.Count == 0)
            {
                TaskDialog.Show("Repato - Create RCP Views", "Select at least one level.");
                return;
            }
            DialogResult = true;
        };
        buttons.Children.Add(cancel);
        buttons.Children.Add(create);
        panel.Children.Add(buttons);
        Content = panel;
    }
}
