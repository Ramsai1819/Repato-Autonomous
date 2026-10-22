namespace Repato.Revit;

public sealed record ReflectedCeilingPlanLevel(long Id, string Name);
public sealed record ReflectedCeilingPlanType(long Id, string Name);
public sealed record ReflectedCeilingPlanInput(IReadOnlyList<long> LevelIds, long ViewTypeId, string NameSuffix);
public sealed record ReflectedCeilingPlanRequest(long LevelId, string LevelName, string ViewName);
public sealed record CreatedReflectedCeilingPlan(long ElementId, long LevelId, string LevelName, string ViewName);
public sealed record ReflectedCeilingPlanResult(IReadOnlyList<CreatedReflectedCeilingPlan> Created);

/// <summary>Boundary between deterministic planning/transaction behavior and the Revit API.</summary>
public interface IReflectedCeilingPlanHost
{
    bool IsFamilyDocument { get; }
    bool IsModifiable { get; }
    bool IsReadOnly { get; }
    IReadOnlyList<ReflectedCeilingPlanLevel> GetLevels();
    IReadOnlyList<ReflectedCeilingPlanType> GetCeilingPlanTypes();
    IReadOnlyCollection<string> GetExistingViewNames();
    void StartTransactionGroup(string name);
    void StartTransaction(string name);
    long CreateViewPlan(long viewTypeId, long levelId, string viewName);
    void CommitTransaction();
    void AssimilateTransactionGroup();
    void RollBackTransactionGroup();
}

public static class ReflectedCeilingPlanWorkflow
{
    public static IReadOnlyList<ReflectedCeilingPlanRequest> Plan(
        ReflectedCeilingPlanInput input,
        IReadOnlyList<ReflectedCeilingPlanLevel> levels,
        IReadOnlyList<ReflectedCeilingPlanType> viewTypes,
        IReadOnlyCollection<string> existingViewNames)
    {
        ArgumentNullException.ThrowIfNull(input);
        ArgumentNullException.ThrowIfNull(levels);
        ArgumentNullException.ThrowIfNull(viewTypes);
        ArgumentNullException.ThrowIfNull(existingViewNames);

        if (input.LevelIds is null || input.LevelIds.Count == 0)
            throw new ArgumentException("Select at least one project level.", nameof(input));
        if (input.ViewTypeId <= 0 || !viewTypes.Any(x => x.Id == input.ViewTypeId))
            throw new ArgumentException("Select an available reflected ceiling plan type.", nameof(input));
        if (string.IsNullOrWhiteSpace(input.NameSuffix) || input.NameSuffix.Any(char.IsControl))
            throw new ArgumentException("The view-name suffix must be non-empty and contain no control characters.", nameof(input));
        if (input.LevelIds.Any(x => x <= 0) || input.LevelIds.Distinct().Count() != input.LevelIds.Count)
            throw new ArgumentException("Selected level identifiers must be valid and unique.", nameof(input));

        var byId = levels.ToDictionary(x => x.Id);
        var suffix = input.NameSuffix.Trim();
        var existing = new HashSet<string>(existingViewNames, StringComparer.OrdinalIgnoreCase);
        var requested = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var plans = new List<ReflectedCeilingPlanRequest>(input.LevelIds.Count);

        foreach (long levelId in input.LevelIds)
        {
            if (!byId.TryGetValue(levelId, out var level) || string.IsNullOrWhiteSpace(level.Name))
                throw new ArgumentException($"Selected level {levelId} is no longer available.", nameof(input));

            string levelName = level.Name.Trim();
            string viewName = $"{levelName} - {suffix}";
            if (!requested.Add(viewName))
                throw new ArgumentException($"Selected levels generate duplicate view name '{viewName}'.", nameof(input));
            if (existing.Contains(viewName))
                throw new ArgumentException($"A view named '{viewName}' already exists; no views were created.", nameof(input));

            plans.Add(new ReflectedCeilingPlanRequest(level.Id, levelName, viewName));
        }

        return plans;
    }

    public static ReflectedCeilingPlanResult Execute(
        ReflectedCeilingPlanInput input,
        IReflectedCeilingPlanHost host)
    {
        ArgumentNullException.ThrowIfNull(host);
        if (host.IsFamilyDocument)
            throw new InvalidOperationException("Reflected ceiling plans can only be created in a Revit project.");
        if (host.IsReadOnly)
            throw new InvalidOperationException("The project is read-only; no reflected ceiling plans were created.");
        if (host.IsModifiable)
            throw new InvalidOperationException("The document is already inside a transaction; close the active edit before creating views.");

        IReadOnlyList<ReflectedCeilingPlanRequest> plans = Plan(
            input, host.GetLevels(), host.GetCeilingPlanTypes(), host.GetExistingViewNames());

        bool groupStarted = false;
        bool groupFinished = false;
        try
        {
            host.StartTransactionGroup("Repato - Create Reflected Ceiling Plans");
            groupStarted = true;
            host.StartTransaction("Create Reflected Ceiling Plans");

            var created = new List<CreatedReflectedCeilingPlan>(plans.Count);
            foreach (var plan in plans)
            {
                long id = host.CreateViewPlan(input.ViewTypeId, plan.LevelId, plan.ViewName);
                created.Add(new CreatedReflectedCeilingPlan(id, plan.LevelId, plan.LevelName, plan.ViewName));
            }

            host.CommitTransaction();
            host.AssimilateTransactionGroup();
            groupFinished = true;
            return new ReflectedCeilingPlanResult(created);
        }
        catch (Exception executionError)
        {
            if (groupStarted && !groupFinished)
            {
                try
                {
                    host.RollBackTransactionGroup();
                }
                catch (Exception rollbackError)
                {
                    throw new AggregateException(
                        "Reflected ceiling plan creation failed and the transaction group rollback also failed.",
                        executionError, rollbackError);
                }
            }

            throw;
        }
    }
}
