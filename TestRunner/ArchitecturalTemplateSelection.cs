using System;
using System.Collections.Generic;
using System.Linq;

namespace Repato.Revit.TestRunner;

internal static class ArchitecturalTemplateSelection
{
    private const string IntentToken = "Architectural";

    internal static T SelectDefaultTemplate<T>(IEnumerable<T> candidates, Func<T, bool> isTemplate, Func<T, string> name, Func<T, long> id)
    {
        List<T> matches = candidates
            .Where(candidate => isTemplate(candidate) && (name(candidate) ?? string.Empty).Contains(IntentToken, StringComparison.OrdinalIgnoreCase))
            .OrderBy(candidate => string.Equals(name(candidate), IntentToken, StringComparison.OrdinalIgnoreCase) ? 0 : 1)
            .ThenBy(candidate => id(candidate))
            .ToList();
        if (matches.Count == 0) throw new InvalidOperationException("Architectural view template is unavailable.");
        return matches[0];
    }
}
