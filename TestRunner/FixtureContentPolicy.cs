namespace Repato.Revit.TestRunner;

internal static class FixtureContentPolicy
{
    internal static readonly string[] ApprovedGridNames =
        ["A", "B", "C", "D", "1", "2", "3", "4"];
    internal static readonly string[] ApprovedGridResequenceNames =
        ["1", "2", "3", "3.2", "4", "A", "A.1", "B", "C"];

    internal static void Validate(string? fixtureId, IEnumerable<string> gridNames, int linkCount)
    {
        if (linkCount != 0)
            throw new InvalidOperationException("Fixture must have zero Revit links.");

        string[] actual = gridNames.ToArray();
        string[]? approved = ApprovedNames(fixtureId);
        if (approved is not null)
        {
            if (!SameNames(actual, approved))
                throw new InvalidOperationException(
                    $"{fixtureId} contains missing, duplicate, or unexpected grids.");
            return;
        }

        if (actual.Length != 0)
            throw new InvalidOperationException("Fixture must have no grids and no Revit links.");
    }

    internal static bool IsGridBubbleFixture(string? fixtureId) =>
        string.Equals(fixtureId, "GridBubbleVisibilityEmpty", StringComparison.Ordinal) ||
        string.Equals(fixtureId, "GridBubbleOffsetEmpty", StringComparison.Ordinal);

    internal static string[]? ApprovedNames(string? fixtureId) =>
        IsGridBubbleFixture(fixtureId) ? ApprovedGridNames :
        string.Equals(fixtureId, "GridResequenceEmpty", StringComparison.Ordinal) ? ApprovedGridResequenceNames : null;

    internal static bool SameNames(IEnumerable<string> actual, IEnumerable<string> expected) =>
        actual.Order(StringComparer.Ordinal).SequenceEqual(expected.Order(StringComparer.Ordinal));
}
