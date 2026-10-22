# Recovered QA binding contract ready

Task task-bf61fe7f22d74df7a92599681da5919e remains revision130/in-progress/qa.
No production binding, validation transmission, approval, deployment or Revit launch.

Root cause: independent validation entry and evidence persistence accepted only
build-checks. The adopted recovered CPV task legitimately remains in QA.
No existing supported QA-stage binding path avoided restaging/re-adoption.

Fix: strict recovered-QA lineage guard, candidate-aware read-only preflight,
RecoveredQaCurrentDeployment operation purpose, and deployment-only persistence.
Only eight deployment-proof fields change during future binding. Adopted build
identity, timestamps, metadata, task stage, recovery/preparation and approvals remain
unchanged. Completed authenticated request/response and exact revision CAS are
mandatory. Downstream approval evidence verifies the new purpose and recovery
lineage. Ordinary QA, mismatches, active approvals/Tara state, tampering and replay
fail closed. Legacy build-checks lifecycle remains supported.

Tests: PowerShell5.1 and7 each passed34 guard +67 recovered integration +20 legacy
independent-validation +44 continuation assertions (165/engine). Synthetic clones
use injected validation endpoints; no production validation requests were sent.
Live supported DryRun at130 passed;32 protected files including task/status unchanged,
installed/immutable hashes and authenticated agent identity verified. Binding is NOT
executed. Agent/product source/artifacts unchanged; no rebuild or deployment required.
Logs:QA/Engineering/CPV-RecoveredQaBindingEngineering130/.

Exact future supported production continuation (documentation only; do not execute
under the engineering-only instruction). Run in Windows PowerShell5.1 as RepatoQA,
inside a7200-second bounded supervisor. Recheck revision130 and hashes first:

```powershell
Import-Module .\AgentOrchestration\Repato.MayaQaWorkflow.psm1 -WarningAction SilentlyContinue
Invoke-MayaQaIndependentDeploymentValidationRecovery `
  -StoreRoot 'C:\Repato-Autonomous\Source\QA\MayaRuns' `
  -TaskId 'task-bf61fe7f22d74df7a92599681da5919e' `
  -WorkflowId 'fa2c2f578cbc40cbacac45c96313ca4c' `
  -ExpectedTaskRevision 130 `
  -ExpectedBuildRequestId 'build-0cb433fde96248ea94ef0fe5e86a2c23' `
  -ExpectedCandidateSourceCommit '1b1a95443c2ff884aa69f068f26f6741aaa412bf' `
  -ExpectedCandidateSha256 '01C700B2F113871DAB18F4049FF3539A6BCB82FBA9716C2E398C70F86C441A54' `
  -ExpectedRunnerManifestPath 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin' `
  -ExpectedRunnerManifestSha256 'AF4DBFA78E61524DE7BD3B84178C6B70ED8D29D0A95BA17780826E09BE689D4F'
```

Append -DryRun for read-only review. The future mutating command creates one guarded
validation lifecycle and binds its proof; successful synthetic revision130 advanced
to134 while staying QA. It does not restage, re-adopt or create approvals. Uncertain
transmissions prohibit automatic retry. Stop before fresh native approval/execution.

COMPACTION / HANDOFF NOTES: engineering complete; prior one-binding authorization
was unused, but latest instruction explicitly prohibits binding now. Resume only
when user directs production continuation. Scoped shared-file staging excludes
unrelated worktree changes. Starting commit1cd656deab3d665c2f0e8cdcd41de1964cd7208a
remains reachable. No new Revit QA pass claimed.
