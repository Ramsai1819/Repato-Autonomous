using Autodesk.Revit.DB;
using System.Globalization;

namespace Repato.Revit;

/// <summary>Original legacy Create Levels service, shared with QA without enabling the bridge.</summary>
public static class LevelCreator
{
    public static object Create(
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
