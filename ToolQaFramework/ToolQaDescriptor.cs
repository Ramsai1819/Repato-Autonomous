using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;

namespace Repato.ToolQaFramework;

public sealed record ToolQaDescriptor(string ToolId, string TestId, string RunnerIdentity,
    string ManifestFile, int RequestSchemaVersion, string RequestOperation,
    string FixtureContractId, string FixtureSpecId, string[] Capabilities);
public sealed record ToolQaRegistryDocument(int SchemaVersion, ToolQaDescriptor[] Tools);

public sealed class ToolQaRegistry
{
    private static readonly HashSet<string> AllowedCapabilities = new(StringComparer.Ordinal)
        { "fixture-evidence", "approval-binding", "receipt-report", "rollback", "cleanup" };
    private readonly IReadOnlyDictionary<string, ToolQaDescriptor> _tools;

    public ToolQaRegistry(string json)
    {
        var document = JsonSerializer.Deserialize<ToolQaRegistryDocument>(json,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
            ?? throw new InvalidDataException("Tool QA registry is empty.");
        if (document.SchemaVersion != 1 || document.Tools is null || document.Tools.Length == 0)
            throw new InvalidDataException("Unsupported or empty tool QA registry.");
        var tools = new Dictionary<string, ToolQaDescriptor>(StringComparer.Ordinal);
        foreach (var tool in document.Tools)
        {
            if (string.IsNullOrWhiteSpace(tool.ToolId) || tool.ToolId != tool.TestId ||
                string.IsNullOrWhiteSpace(tool.RunnerIdentity) || tool.RunnerIdentity.Contains('\\') || tool.RunnerIdentity.Contains('/') ||
                string.IsNullOrWhiteSpace(tool.ManifestFile) || Path.GetFileName(tool.ManifestFile) != tool.ManifestFile ||
                tool.RequestSchemaVersion is < 1 or > 2 || string.IsNullOrWhiteSpace(tool.RequestOperation) ||
                string.IsNullOrWhiteSpace(tool.FixtureContractId) || string.IsNullOrWhiteSpace(tool.FixtureSpecId) || tool.Capabilities is null || tool.Capabilities.Length == 0 ||
                tool.Capabilities.Any(value => string.IsNullOrWhiteSpace(value) || !AllowedCapabilities.Contains(value)) ||
                tool.Capabilities.Distinct(StringComparer.Ordinal).Count() != tool.Capabilities.Length ||
                !tools.TryAdd(tool.ToolId, tool))
                throw new InvalidDataException("Tool QA descriptor is invalid, unsafe, or duplicated.");
        }
        _tools = tools;
    }

    public static ToolQaRegistry LoadBuiltIn()
    {
        using Stream stream = typeof(ToolQaRegistry).Assembly.GetManifestResourceStream("Repato.ToolQaRegistry.v1.json")
            ?? throw new InvalidDataException("Embedded tool QA registry is missing.");
        using var reader = new StreamReader(stream);
        return new ToolQaRegistry(reader.ReadToEnd());
    }

    public ToolQaDescriptor Get(string toolId) => _tools.TryGetValue(toolId, out var tool)
        ? tool : throw new InvalidDataException("Tool ID is not explicitly registered.");
    public IReadOnlyCollection<ToolQaDescriptor> Tools => _tools.Values.ToArray();

    public void ValidateRunner(string toolId, string runnerIdentity)
    {
        if (Get(toolId).RunnerIdentity != runnerIdentity)
            throw new InvalidDataException("Runner identity does not match the registered tool descriptor.");
    }
}

public sealed record ToolQaBinding(string ToolId, string TestId, string RunnerIdentity,
    string CandidatePath, string CandidateSha256, string ManifestPath, string ManifestSha256);
public sealed record ToolQaApproval(string ApprovalId, string TaskId, string WorkflowId,
    string ToolId, string TestId, string AttemptId, string RunId, string ClaimId,
    string CandidateSha256, string ManifestSha256, long TaskRevision,
    DateTimeOffset ExpiresUtc, bool Approved);
public sealed record ToolQaFixtureEvidence(string TaskId, string WorkflowId, string ToolId,
    string AttemptId, string RunId, string FixtureId, string FixtureSha256,
    string EvidencePath, string EvidenceSha256);

public enum ToolQaDispatchState { Prepared, Dispatching, LaunchRejected, DispatchAccepted, OutcomeUnknown, QaPassed, QaFailed }
public sealed record ToolQaDispatchReservation(string RequestId, string TaskId, string WorkflowId,
    string ToolId, string AttemptId, string RunId, string ClaimId);

/// <summary>Storage adapter must implement atomic compare-and-reserve semantics for its canonical or isolated store.</summary>
public interface IToolQaDispatchLedger
{
    bool TryReserve(ToolQaDispatchReservation reservation);
    bool TryTransition(ToolQaDispatchReservation reservation, ToolQaDispatchState expected, ToolQaDispatchState next);
    ToolQaDispatchState Read(ToolQaDispatchReservation reservation);
}

public sealed record ToolQaTerminalEvidence(string RequestId, string TaskId, string WorkflowId,
    string ToolId, string TestId, string AttemptId, string RunId, string ClaimId,
    string CandidateSha256, string ManifestSha256, string FixtureSha256,
    string ReceiptPath, string ReceiptSha256, string ReportPath, string ReportSha256,
    string Status, bool RollbackVerified, bool CleanupVerified);
public interface IToolQaNativeEvidenceAuthenticator { bool Verify(ToolQaTerminalEvidence evidence); }
public enum ToolQaInterruptionKind { None, KnownLicenseIntervention, KnownAddinTrustIntervention, UnknownInterventionRequired }

/// <summary>Common fail-closed checks. Tool adapters still validate their request/report schemas.</summary>
public static class ToolQaGate
{
    public static void ValidateBinding(ToolQaRegistry registry, ToolQaBinding binding)
    {
        var descriptor = registry.Get(binding.ToolId);
        if (binding.TestId != descriptor.TestId || binding.RunnerIdentity != descriptor.RunnerIdentity ||
            Path.GetFileName(binding.ManifestPath) != descriptor.ManifestFile ||
            !File.Exists(binding.CandidatePath) || !File.Exists(binding.ManifestPath) ||
            !SameHash(Sha256(binding.CandidatePath), binding.CandidateSha256) ||
            !SameHash(Sha256(binding.ManifestPath), binding.ManifestSha256))
            throw new InvalidDataException("Tool, runner, candidate, or manifest binding mismatch.");
    }

    public static void ValidateApproval(ToolQaApproval approval, string taskId, string workflowId,
        string toolId, string testId, string attemptId, string runId, string claimId,
        string candidateSha256, string manifestSha256, long taskRevision, DateTimeOffset now)
    {
        if (!approval.Approved || !Guid.TryParse(approval.ApprovalId, out _) || approval.TaskId != taskId ||
            approval.WorkflowId != workflowId || approval.ToolId != toolId || approval.TestId != testId ||
            approval.AttemptId != attemptId || approval.RunId != runId || approval.ClaimId != claimId ||
            !SameHash(approval.CandidateSha256, candidateSha256) || !SameHash(approval.ManifestSha256, manifestSha256) ||
            approval.TaskRevision != taskRevision || approval.ExpiresUtc <= now)
            throw new InvalidDataException("Approval is missing, expired, stale, or not bound to this claim and attempt.");
    }

    public static void ValidateFixture(ToolQaFixtureEvidence evidence, string taskId, string workflowId,
        string toolId, string attemptId, string runId, string fixtureId, string fixtureSha256)
    {
        if (evidence.TaskId != taskId || evidence.WorkflowId != workflowId || evidence.ToolId != toolId ||
            evidence.AttemptId != attemptId || evidence.RunId != runId || evidence.FixtureId != fixtureId ||
            !SameHash(evidence.FixtureSha256, fixtureSha256) || !File.Exists(evidence.EvidencePath) ||
            !SameHash(Sha256(evidence.EvidencePath), evidence.EvidenceSha256))
            throw new InvalidDataException("Fixture evidence bytes or correlation are invalid.");
    }

    public static void ReserveDispatchOnce(IToolQaDispatchLedger ledger, ToolQaDispatchReservation reservation)
    {
        if (!Guid.TryParse(reservation.RequestId, out _) || !Guid.TryParse(reservation.AttemptId, out _) ||
            !Guid.TryParse(reservation.RunId, out _) || !Guid.TryParse(reservation.ClaimId, out _) ||
            string.IsNullOrWhiteSpace(reservation.TaskId) || string.IsNullOrWhiteSpace(reservation.WorkflowId) ||
            string.IsNullOrWhiteSpace(reservation.ToolId) || !ledger.TryReserve(reservation))
            throw new InvalidOperationException("Dispatch reservation is invalid, duplicated, or unavailable.");
    }

    public static ToolQaDispatchState AfterDispatch(ToolQaDispatchState current, bool accepted, bool responseAuthenticated)
    {
        if (current != ToolQaDispatchState.Dispatching)
            throw new InvalidOperationException("Only a reserved dispatch can consume a native response.");
        if (!responseAuthenticated) return ToolQaDispatchState.OutcomeUnknown;
        return accepted ? ToolQaDispatchState.DispatchAccepted : ToolQaDispatchState.LaunchRejected;
    }

    public static ToolQaDispatchState Reconcile(ToolQaDispatchState current, ToolQaRegistry registry,
        ToolQaTerminalEvidence evidence, ToolQaTerminalEvidence expected, IToolQaNativeEvidenceAuthenticator authenticator)
    {
        if (current is not (ToolQaDispatchState.DispatchAccepted or ToolQaDispatchState.OutcomeUnknown))
            throw new InvalidOperationException("Only an accepted or ambiguous dispatch can be reconciled.");
        var descriptor = registry.Get(expected.ToolId);
        if (evidence.RequestId != expected.RequestId || evidence.TaskId != expected.TaskId || evidence.WorkflowId != expected.WorkflowId ||
            evidence.ToolId != descriptor.ToolId || evidence.TestId != descriptor.TestId || evidence.AttemptId != expected.AttemptId ||
            evidence.RunId != expected.RunId || evidence.ClaimId != expected.ClaimId ||
            !SameHash(evidence.CandidateSha256, expected.CandidateSha256) || !SameHash(evidence.ManifestSha256, expected.ManifestSha256) ||
            !SameHash(evidence.FixtureSha256, expected.FixtureSha256))
            throw new InvalidDataException("Native terminal evidence task/tool/attempt/artifact correlation mismatch.");
        if (!File.Exists(evidence.ReceiptPath) || !File.Exists(evidence.ReportPath) ||
            !SameHash(Sha256(evidence.ReceiptPath), evidence.ReceiptSha256) || !SameHash(Sha256(evidence.ReportPath), evidence.ReportSha256))
            throw new InvalidDataException("Native receipt/report bytes do not match their evidence hashes.");
        if (!IdentityMatches(evidence.ReceiptPath, evidence))
            throw new InvalidDataException("Native receipt identity fields do not match the correlated execution.");
        if (!IdentityMatches(evidence.ReportPath, evidence))
            throw new InvalidDataException("Native report identity fields do not match the correlated execution.");
        if (!evidence.RollbackVerified || !evidence.CleanupVerified || evidence.Status is not ("Passed" or "Failed"))
            throw new InvalidDataException("Rollback, cleanup, or terminal status verification failed.");
        if (!authenticator.Verify(evidence))
            throw new InvalidDataException("Native terminal evidence is unauthenticated, incomplete, or mismatched.");
        return evidence.Status == "Passed" ? ToolQaDispatchState.QaPassed : ToolQaDispatchState.QaFailed;
    }

    public static ToolQaInterruptionKind ClassifyInterruption(bool promptObserved, bool observationAuthenticated, string? exactKnownKind)
    {
        if (!promptObserved) return ToolQaInterruptionKind.None;
        if (!observationAuthenticated) return ToolQaInterruptionKind.UnknownInterventionRequired;
        return exactKnownKind switch
        {
            "AutodeskLicenseLimit" => ToolQaInterruptionKind.KnownLicenseIntervention,
            "RevitAddinTrust" => ToolQaInterruptionKind.KnownAddinTrustIntervention,
            _ => ToolQaInterruptionKind.UnknownInterventionRequired
        };
    }

    public static bool CanContinueAfterInterruption(ToolQaInterruptionKind kind) => kind == ToolQaInterruptionKind.None;

    private static bool IdentityMatches(string path, ToolQaTerminalEvidence evidence)
    {
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            JsonElement root = document.RootElement;
            bool Is(string name, string expected) => root.TryGetProperty(name, out JsonElement value) &&
                value.ValueKind == JsonValueKind.String && value.GetString() == expected;
            return Is("RequestId", evidence.RequestId) && Is("TaskId", evidence.TaskId) &&
                Is("WorkflowId", evidence.WorkflowId) && Is("QaWorkflowId", evidence.ToolId) &&
                Is("TestId", evidence.TestId) && Is("AttemptId", evidence.AttemptId) &&
                Is("RunId", evidence.RunId) && Is("ClaimId", evidence.ClaimId) && Is("Status", evidence.Status);
        }
        catch { return false; }
    }

    public static string Sha256(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
    private static bool SameHash(string a, string b) => IsHash(a) && IsHash(b) && a.Equals(b, StringComparison.OrdinalIgnoreCase);
    private static bool IsHash(string value) => value is { Length: 64 } && value.All(Uri.IsHexDigit);
}

/// <summary>Reusable lifecycle adapter around a caller-supplied atomic store and authenticated tool evidence adapters.</summary>
public static class ToolQaLifecycleAdapter
{
    public static ToolQaDescriptor Prepare(ToolQaRegistry registry, ToolQaBinding binding, ToolQaApproval approval,
        ToolQaFixtureEvidence fixture, string taskId, string workflowId, string attemptId, string runId, string claimId,
        long taskRevision, DateTimeOffset now)
    {
        ToolQaGate.ValidateBinding(registry, binding);
        ToolQaGate.ValidateApproval(approval, taskId, workflowId, binding.ToolId, binding.TestId, attemptId, runId,
            claimId, binding.CandidateSha256, binding.ManifestSha256, taskRevision, now);
        var descriptor = registry.Get(binding.ToolId);
        ToolQaGate.ValidateFixture(fixture, taskId, workflowId, binding.ToolId, attemptId, runId,
            descriptor.FixtureContractId, fixture.FixtureSha256);
        return descriptor;
    }

    public static void BeginDispatch(IToolQaDispatchLedger ledger, ToolQaDispatchReservation reservation) =>
        ToolQaGate.ReserveDispatchOnce(ledger, reservation);

    public static ToolQaDispatchState RecordLaunchResponse(IToolQaDispatchLedger ledger,
        ToolQaDispatchReservation reservation, bool accepted, bool responseAuthenticated)
    {
        ToolQaDispatchState current = ledger.Read(reservation);
        ToolQaDispatchState next = ToolQaGate.AfterDispatch(current, accepted, responseAuthenticated);
        if (!ledger.TryTransition(reservation, current, next))
            throw new InvalidOperationException("Dispatch state changed concurrently; disposition must be reconciled.");
        return next;
    }

    public static ToolQaDispatchState Reconcile(IToolQaDispatchLedger ledger, ToolQaDispatchReservation reservation,
        ToolQaRegistry registry, ToolQaTerminalEvidence evidence, ToolQaTerminalEvidence expected,
        IToolQaNativeEvidenceAuthenticator authenticator)
    {
        ToolQaDispatchState current = ledger.Read(reservation);
        ToolQaDispatchState terminal = ToolQaGate.Reconcile(current, registry, evidence, expected, authenticator);
        if (!ledger.TryTransition(reservation, current, terminal))
            throw new InvalidOperationException("Dispatch state changed concurrently; reconciliation must be repeated read-only.");
        return terminal;
    }
}
