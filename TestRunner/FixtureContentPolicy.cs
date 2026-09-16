namespace Repato.Revit.TestRunner;

internal static class FixtureContentPolicy
{
    internal static readonly string[] ApprovedGridNames =
        ["A", "B", "C", "D", "1", "2", "3", "4"];

    internal static void Validate(string? fixtureId, IEnumerable<string> gridNames, int linkCount)
    {
        if (linkCount != 0)
            throw new InvalidOperationException("Fixture must have zero Revit links.");

        string[] actual = gridNames.ToArray();
        if (IsGridBubbleFixture(fixtureId))
        {
            if (!SameNames(actual, ApprovedGridNames))
                throw new InvalidOperationException(
                    $"{fixtureId} must contain exactly grids A, B, C, D, 1, 2, 3, 4.");
            return;
        }

        if (actual.Length != 0)
            throw new InvalidOperationException("Fixture must have no grids and no Revit links.");
    }

    internal static bool IsGridBubbleFixture(string? fixtureId) =>
        string.Equals(fixtureId, "GridBubbleVisibilityEmpty", StringComparison.Ordinal) ||
        string.Equals(fixtureId, "GridBubbleOffsetEmpty", StringComparison.Ordinal);

    internal static bool SameNames(IEnumerable<string> actual, IEnumerable<string> expected) =>
        actual.Order(StringComparer.Ordinal).SequenceEqual(expected.Order(StringComparer.Ordinal));
}
