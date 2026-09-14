using Autodesk.Revit.DB;
using Autodesk.Revit.UI;
using System.Globalization;

namespace Forma.RevitConnector;

public sealed class FormaEventHandler : IExternalEventHandler
{
    private readonly object _gate = new();
    private readonly Queue<BridgeRequest> _queue = new();

    public string GetName() => "Forma workflow bridge";

    public void Enqueue(BridgeRequest request)
    {
        lock (_gate)
        {
            _queue.Enqueue(request);
        }
    }

    public void Execute(UIApplication app)
    {
        while (true)
        {
            BridgeRequest? request;

            lock (_gate)
            {
                request = _queue.Count > 0 ? _queue.Dequeue() : null;
            }

            if (request is null)
            {
                return;
            }

            try
            {
                request.Completion.SetResult(
                    request.Kind == "context"
                        ? ReadContext(app)
                        : ExecuteWorkflow(app, request.Workflow!)
                );
            }
            catch (Exception ex)
            {
                request.Completion.SetException(ex);
            }
        }
    }

    private static object ReadContext(UIApplication app)
    {
        var document = app.ActiveUIDocument?.Document
            ?? throw new InvalidOperationException("Open a Revit project first.");

        var levels = new FilteredElementCollector(document)
            .OfClass(typeof(Level))
            .Cast<Level>()
            .OrderBy(x => x.Elevation)
            .Select(x => x.Name)
            .ToArray();

        var wallTypes = new FilteredElementCollector(document)
            .OfClass(typeof(WallType))
            .Cast<WallType>()
            .Select(x => x.Name)
            .OrderBy(x => x)
            .ToArray();

        var grids = new FilteredElementCollector(document)
            .OfClass(typeof(Grid))
            .Cast<Grid>()
            .Select(x => x.Name)
            .OrderBy(x => x)
            .ToArray();

        return new
        {
            connected = true,
            revitVersion = app.Application.VersionNumber,
            document = document.Title,
            activeView = document.ActiveView.Name,
            levels,
            wallTypes,
            grids
        };
    }

    private static object ExecuteWorkflow(
        UIApplication app,
        WorkflowRequest workflow)
    {
        var document = app.ActiveUIDocument?.Document
            ?? throw new InvalidOperationException("Open a Revit project first.");

        var results = new List<object>();

        foreach (var step in workflow.Steps)
        {
            if (step.ToolId == "levels")
            {
                results.Add(CreateLevels(document, step.LevelData));
                continue;
            }

            if (step.ToolId == "grids")
            {
                results.Add(CreateGrids(
                    document,
                    step.VerticalGridData,
                    step.HorizontalGridData,
                    step.GridLength));

                continue;
            }

            if (step.ToolId == "project-info")
            {
                var info = document.ProjectInformation;

                results.Add(new
                {
                    toolId = step.ToolId,
                    status = "completed",
                    data = new
                    {
                        info.Name,
                        info.Number,
                        info.ClientName,
                        info.Address
                    }
                });

                continue;
            }

            if (step.ToolId == "scale")
            {
                if (!int.TryParse(step.Scale, out var scale) || scale < 1)
                {
                    results.Add(new
                    {
                        toolId = step.ToolId,
                        status = "failed",
                        message = "Scale must be a positive whole number."
                    });

                    continue;
                }

                if (document.ActiveView.ViewType is ViewType.ThreeD or ViewType.Schedule)
                {
                    results.Add(new
                    {
                        toolId = step.ToolId,
                        status = "failed",
                        message = "The active view does not support a drawing scale."
                    });

                    continue;
                }

                using var transaction = new Transaction(
                    document,
                    "Forma - Set view scale"
                );

                transaction.Start();
                document.ActiveView.Scale = scale;
                transaction.Commit();

                results.Add(new
                {
                    toolId = step.ToolId,
                    status = "completed",
                    message = $"Active view scale set to 1:{scale}."
                });

                continue;
            }

            results.Add(new
            {
                toolId = step.ToolId,
                status = "adapter_required",
                message = "Add this tool's Revit API or Dynamo adapter in FormaEventHandler."
            });
        }

        return new
        {
            workflow = workflow.Name,
            document = document.Title,
            results
        };
    }

    private static object CreateLevels(
        Document document,
        string levelData)
    {
        var definitions = new List<(string Name, double ElevationMillimeters)>();

        foreach (var rawLine in levelData.Replace("\r", "").Split('\n'))
        {
            var line = rawLine.Trim();

            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            var parts = line.Split(
                '|',
                2,
                StringSplitOptions.TrimEntries
            );

            if (
                parts.Length != 2 ||
                string.IsNullOrWhiteSpace(parts[0]) ||
                !TryParseMillimeters(parts[1], out var elevationMillimeters)
            )
            {
                return new
                {
                    toolId = "levels",
                    status = "failed",
                    message =
                        "Use one level per line: Level Name | Elevation in mm. Example: Level 1 | 3600"
                };
            }

            definitions.Add((parts[0], elevationMillimeters));
        }

        if (definitions.Count == 0)
        {
            return new
            {
                toolId = "levels",
                status = "failed",
                message = "Enter at least one level definition before running Create Levels."
            };
        }

        var existingNames = new FilteredElementCollector(document)
            .OfClass(typeof(Level))
            .Cast<Level>()
            .Select(level => level.Name)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var created = new List<string>();
        var skipped = new List<string>();

        using var transaction = new Transaction(
            document,
            "Forma - Create Levels"
        );

        transaction.Start();

        foreach (var definition in definitions)
        {
            if (existingNames.Contains(definition.Name))
            {
                skipped.Add($"{definition.Name} already exists");
                continue;
            }

            var elevationFeet = UnitUtils.ConvertToInternalUnits(
                definition.ElevationMillimeters,
                UnitTypeId.Millimeters
            );

            var level = Level.Create(document, elevationFeet);
            level.Name = definition.Name;

            existingNames.Add(definition.Name);

            created.Add(
                $"{definition.Name} at {definition.ElevationMillimeters:0.##} mm"
            );
        }

        transaction.Commit();

        return new
        {
            toolId = "levels",
            status = "completed",
            message = $"Created {created.Count} level(s). Skipped {skipped.Count} existing level(s).",
            data = new
            {
                created,
                skipped
            }
        };
    }

private static object CreateGrids(
    Document document,
    string verticalGridData,
    string horizontalGridData,
    string gridLengthText)
{
    if (!TryParseMillimeters(gridLengthText, out var gridLengthMillimeters) ||
        gridLengthMillimeters <= 0)
    {
        return new
        {
            toolId = "grids",
            status = "failed",
            message = "Grid length must be a positive value in millimeters."
        };
    }

    var verticalDataIsValid = TryParseNamedPositions(
        verticalGridData,
        out var verticals,
        out var verticalError);

    var horizontalDataIsValid = TryParseNamedPositions(
        horizontalGridData,
        out var horizontals,
        out var horizontalError);

    if (!verticalDataIsValid || !horizontalDataIsValid)
    {
        return new
        {
            toolId = "grids",
            status = "failed",
            message = verticalError ?? horizontalError ??
                "Use one grid per line: Grid Name | Position in mm."
        };
    }

    if (verticals.Count == 0 && horizontals.Count == 0)
    {
        return new
        {
            toolId = "grids",
            status = "failed",
            message = "Enter at least one vertical or horizontal grid."
        };
    }

    var existingNames = new FilteredElementCollector(document)
        .OfClass(typeof(Grid))
        .Cast<Grid>()
        .Select(grid => grid.Name)
        .ToHashSet(StringComparer.OrdinalIgnoreCase);

    var halfLengthFeet = UnitUtils.ConvertToInternalUnits(
        gridLengthMillimeters / 2.0,
        UnitTypeId.Millimeters);

    var created = new List<string>();
    var skipped = new List<string>();

    using var transaction = new Transaction(document, "Forma - Create Grids");
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
            skipped);
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
            skipped);
    }

    transaction.Commit();

    return new
    {
        toolId = "grids",
        status = "completed",
        message = $"Created {created.Count} grid(s). Skipped {skipped.Count} existing grid(s).",
        data = new { created, skipped }
    };
}
    private static bool TryParseNamedPositions(
        string input,
        out List<(string Name, double PositionMillimeters)> definitions,
        out string? error)
    {
        definitions = [];
        error = null;

        foreach (var rawLine in input.Replace("\r", "").Split('\n'))
        {
            var line = rawLine.Trim();

            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            var parts = line.Split(
                '|',
                2,
                StringSplitOptions.TrimEntries
            );

            if (
                parts.Length != 2 ||
                string.IsNullOrWhiteSpace(parts[0]) ||
                !TryParseMillimeters(parts[1], out var positionMillimeters)
            )
            {
                error =
                    "Use one grid per line: Grid Name | Position in mm. Example: A | 6000";

                return false;
            }

            definitions.Add((parts[0], positionMillimeters));
        }

        return true;
    }

    private static void CreateGrid(
        Document document,
        (string Name, double PositionMillimeters) definition,
        bool isVertical,
        double halfLengthFeet,
        HashSet<string> existingNames,
        List<string> created,
        List<string> skipped)
    {
        if (existingNames.Contains(definition.Name))
        {
            skipped.Add($"{definition.Name} already exists");
            return;
        }

        var positionFeet = UnitUtils.ConvertToInternalUnits(
            definition.PositionMillimeters,
            UnitTypeId.Millimeters
        );

        var start = isVertical
            ? new XYZ(positionFeet, -halfLengthFeet, 0)
            : new XYZ(-halfLengthFeet, positionFeet, 0);

        var end = isVertical
            ? new XYZ(positionFeet, halfLengthFeet, 0)
            : new XYZ(halfLengthFeet, positionFeet, 0);

        var grid = Grid.Create(
            document,
            Line.CreateBound(start, end)
        );

        grid.Name = definition.Name;

        existingNames.Add(definition.Name);

        created.Add(
            $"{definition.Name} ({(isVertical ? "vertical" : "horizontal")}) at {definition.PositionMillimeters:0.##} mm"
        );
    }

    private static bool TryParseMillimeters(
        string value,
        out double millimeters)
    {
        return
            double.TryParse(
                value,
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out millimeters
            )
            ||
            double.TryParse(
                value,
                NumberStyles.Float,
                CultureInfo.CurrentCulture,
                out millimeters
            );
    }
}