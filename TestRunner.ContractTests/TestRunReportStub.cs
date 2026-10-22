namespace Repato.Revit.TestRunner;

public sealed class TestRunReport
{
    public AddinInventory? AddinIsolation { get; set; }
    public void Assert(string id, bool passed, object expected, object actual) { }
}
