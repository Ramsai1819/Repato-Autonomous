using Repato.Revit;

int assertions = 0;
void Check(bool value, string message)
{
    assertions++;
    if (!value) throw new InvalidOperationException("FAILED: " + message);
}
void Reject(Action action, string expectedMessage, string label)
{
    try { action(); }
    catch (Exception ex)
    {
        Check(ex.Message.Contains(expectedMessage, StringComparison.OrdinalIgnoreCase), label + " (expected diagnostic)");
        return;
    }
    throw new InvalidOperationException("FAILED: " + label + " (operation was accepted)");
}

var levels = new[] { new ReflectedCeilingPlanLevel(1, "Level 1"), new ReflectedCeilingPlanLevel(2, "Level 2") };
var types = new[] { new ReflectedCeilingPlanType(10, "Architectural Ceiling Plan") };
var valid = new ReflectedCeilingPlanInput(new long[] { 1, 2 }, 10, "RCP");
var plan = ReflectedCeilingPlanWorkflow.Plan(valid, levels, types, Array.Empty<string>());
Check(plan.Count == 2, "one requested view per selected level");
Check(plan.Select(x => x.ViewName).SequenceEqual(new[] { "Level 1 - RCP", "Level 2 - RCP" }), "deterministic level/suffix naming");

Reject(() => ReflectedCeilingPlanWorkflow.Plan(valid with { LevelIds = Array.Empty<long>() }, levels, types, Array.Empty<string>()), "at least one", "empty level selection rejected");
Reject(() => ReflectedCeilingPlanWorkflow.Plan(valid with { LevelIds = new long[] { 1, 1 } }, levels, types, Array.Empty<string>()), "unique", "duplicate selected ids rejected");
Reject(() => ReflectedCeilingPlanWorkflow.Plan(valid with { LevelIds = new long[] { 99 } }, levels, types, Array.Empty<string>()), "no longer available", "stale level id rejected");
Reject(() => ReflectedCeilingPlanWorkflow.Plan(valid with { ViewTypeId = 99 }, levels, types, Array.Empty<string>()), "available reflected ceiling plan type", "non-ceiling or missing type rejected");
Reject(() => ReflectedCeilingPlanWorkflow.Plan(valid with { NameSuffix = "  " }, levels, types, Array.Empty<string>()), "suffix", "blank suffix rejected");
Reject(() => ReflectedCeilingPlanWorkflow.Plan(valid with { NameSuffix = "RCP\nBad" }, levels, types, Array.Empty<string>()), "control characters", "control characters rejected");
Reject(() => ReflectedCeilingPlanWorkflow.Plan(valid, levels, types, new[] { "level 1 - rcp" }), "already exists", "case-insensitive collision rejected before transaction");
Reject(() => ReflectedCeilingPlanWorkflow.Plan(
    new ReflectedCeilingPlanInput(new long[] { 1, 2 }, 10, "RCP"),
    new[] { new ReflectedCeilingPlanLevel(1, "Level"), new ReflectedCeilingPlanLevel(2, " level ") },
    types, Array.Empty<string>()), "duplicate view name", "generated duplicate names rejected");

var successfulHost = new FakeHost(levels, types);
var successful = ReflectedCeilingPlanWorkflow.Execute(valid, successfulHost);
Check(successful.Created.Count == 2 && successfulHost.Created.Count == 2, "synthetic integration creates selected views");
Check(successfulHost.TransactionStarted && successfulHost.TransactionCommitted && successfulHost.GroupAssimilated, "successful operation commits and assimilates one atomic group");
Check(!successfulHost.RolledBack, "successful operation is not rolled back");

var createFailureHost = new FakeHost(levels, types) { FailOnCreateNumber = 2 };
Reject(() => ReflectedCeilingPlanWorkflow.Execute(valid, createFailureHost), "synthetic create failure", "creation failure reported");
Check(createFailureHost.RolledBack && !createFailureHost.TransactionCommitted && !createFailureHost.GroupAssimilated, "mid-batch failure rolls back the entire group");
Check(createFailureHost.Created.Count == 0, "mid-batch rollback leaves no partial synthetic views");

var commitFailureHost = new FakeHost(levels, types) { FailCommit = true };
Reject(() => ReflectedCeilingPlanWorkflow.Execute(valid, commitFailureHost), "synthetic commit failure", "commit failure reported");
Check(commitFailureHost.RolledBack && !commitFailureHost.GroupAssimilated, "commit failure rolls back the group");
Check(commitFailureHost.Created.Count == 0, "commit failure leaves no partial synthetic views");

var rollbackFailureHost = new FakeHost(levels, types) { FailOnCreateNumber = 2, FailRollback = true };
try { ReflectedCeilingPlanWorkflow.Execute(valid, rollbackFailureHost); throw new InvalidOperationException("FAILED: rollback failure should be explicit"); }
catch (AggregateException ex) { Check(ex.InnerExceptions.Count == 2 && rollbackFailureHost.RolledBack, "rollback failure retains both execution and recovery errors"); }

foreach (var invalidHost in new[]
{
    new FakeHost(levels, types) { FamilyDocument = true },
    new FakeHost(levels, types) { ReadOnly = true },
    new FakeHost(levels, types) { AlreadyModifiable = true }
})
{
    try { ReflectedCeilingPlanWorkflow.Execute(valid, invalidHost); throw new InvalidOperationException("FAILED: unsafe document state accepted"); }
    catch (InvalidOperationException) { Check(!invalidHost.GroupStarted, "unsafe document state rejected before transaction"); }
}

Console.WriteLine($"Reflected Ceiling Plans synthetic contract tests passed: assertions={assertions}; real Revit/API invoked=false.");

sealed class FakeHost(
    IReadOnlyList<ReflectedCeilingPlanLevel> levels,
    IReadOnlyList<ReflectedCeilingPlanType> types) : IReflectedCeilingPlanHost
{
    private int _nextId = 100;
    public bool FamilyDocument { get; init; }
    public bool ReadOnly { get; init; }
    public bool AlreadyModifiable { get; init; }
    public int FailOnCreateNumber { get; init; }
    public bool FailCommit { get; init; }
    public bool FailRollback { get; init; }
    public bool IsFamilyDocument => FamilyDocument;
    public bool IsReadOnly => ReadOnly;
    public bool IsModifiable => AlreadyModifiable;
    public bool GroupStarted { get; private set; }
    public bool TransactionStarted { get; private set; }
    public bool TransactionCommitted { get; private set; }
    public bool GroupAssimilated { get; private set; }
    public bool RolledBack { get; private set; }
    public List<CreatedReflectedCeilingPlan> Created { get; } = new();
    public IReadOnlyList<ReflectedCeilingPlanLevel> GetLevels() => levels;
    public IReadOnlyList<ReflectedCeilingPlanType> GetCeilingPlanTypes() => types;
    public IReadOnlyCollection<string> GetExistingViewNames() => Array.Empty<string>();
    public void StartTransactionGroup(string name) => GroupStarted = true;
    public void StartTransaction(string name) => TransactionStarted = true;
    public long CreateViewPlan(long viewTypeId, long levelId, string viewName)
    {
        if (FailOnCreateNumber > 0 && Created.Count + 1 == FailOnCreateNumber)
            throw new InvalidOperationException("Synthetic create failure.");
        long id = _nextId++;
        Created.Add(new CreatedReflectedCeilingPlan(id, levelId, viewName.Split(" - ")[0], viewName));
        return id;
    }
    public void CommitTransaction()
    {
        if (FailCommit) throw new InvalidOperationException("Synthetic commit failure.");
        TransactionCommitted = true;
    }
    public void AssimilateTransactionGroup() => GroupAssimilated = true;
    public void RollBackTransactionGroup()
    {
        RolledBack = true;
        if (FailRollback) throw new InvalidOperationException("Synthetic rollback failure.");
        Created.Clear();
    }
}
