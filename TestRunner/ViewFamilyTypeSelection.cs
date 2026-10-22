using System;
using System.Collections.Generic;
using System.Linq;

namespace Repato.Revit.TestRunner;

internal static class ViewFamilyTypeSelection
{
    internal static T SelectDefault<T>(IEnumerable<T> candidates, Func<T, bool> isDefault)
    {
        T[] matches = candidates.Where(isDefault).Take(2).ToArray();
        return matches.Length switch
        {
            1 => matches[0],
            0 => throw new InvalidOperationException("The configured default floor-plan view family type is unavailable."),
            _ => throw new InvalidOperationException("The configured default floor-plan view family type is ambiguous.")
        };
    }
}
