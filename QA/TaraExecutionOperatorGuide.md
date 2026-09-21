# Tara interactive execution bridge

This bridge runs an approved native QA runner without a manual tool click. It does not install an add-in, prepare Windows accounts, approve fixtures, or authorize Revit execution. Current session authorization forbids launching or modifying Revit. The real-run instructions below are for a future explicitly authorized integration session.

Implementation branch: `feat/tara-unattended-execution-bridge`. Preserved starting commit: `12a5c3e05078a243a1e47b9ff3b015271835ac22`. That starting commit has not been verified passing for this task. PowerShell regression success is not a native Revit QA pass.

## One-time Windows setup

1. Have the Windows administrator provision the dedicated `RepatoQA` account through normal Windows account management. Do not put passwords in scripts, scheduled-task arguments, environment variables, or source control. Do not run the bridge as the normal production user.
2. Log into `RepatoQA` interactively and keep its desktop unlocked throughout the run. Qualify Revit 2025 licensing, startup, and the installed add-in security prompts under supervision after explicit authorization. Never bypass security or automate dismissal of an unknown dialog.
3. Qualify the isolated QA environment, including application bundles and machine-wide add-ins. Review `QA/MachineWideAddins.allowlist.json`; every detected manifest must meet the existing exact-path/hash policy. The bridge cannot make third-party add-ins safe. No production `Repato.addin` is permitted in the QA profile.
4. Arrange read access to the approved checkout, fixtures, artifact, and task store, and the necessary write access to that task store and disposable QA run/report/screenshot directories. Do not grant access to production models for testing. Do not move or copy production models into the fixture area.
5. The current compiled runners require `C:\Repato-Autonomous\Source\QA`. This is a native code constraint, not a configurable workspace alias. This implementation is developed in `AgentWork`; a qualified, matching checkout/build/policy at `Source` is required before integration. Do not redirect this path with a junction. The bridge rejects incompatible paths.
6. Separately authorize and provision the exact reviewed QA DLL and runner manifest under the dedicated profile. The bridge never copies or deploys them. For the usual profile, the DLL is `C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA\Repato.Revit.dll`; the manifest sits in the parent `2025` registration directory. `QaAddinRoot` means the `RepatoQA` subdirectory, not that parent. There are two manifests: Neil's artifact manifest (validated as build evidence) and the workflow-selected QA startup runner manifest (for example `Repato.CreateLevels.TestRunner.addin`). Their filenames and hashes are intentionally independent; the runner manifest must match the installed QA DLL, workflow startup class, and approved QA policy.
7. Print the exact configuration values without modifying anything:

   ```powershell
   .\QA\Show-TaraRevitQaConfiguration.ps1
   ```

   If Windows assigned another profile path, pass `-QaProfileRoot` with that actual dedicated-account path. The output describes paths and requirements; it does not certify readiness or account ownership.

Use an explicitly started PowerShell process in that interactive account, or an operator-configured Task Scheduler task set to **Run only when user is logged on** for `RepatoQA` (`InteractiveToken`). Do not select **Run whether user is logged on or not**. Never run Revit in a Windows service or Session 0. There is no service, password storage, automatic login, unlock, or scheduled-task installation in this change. Signing out, locking, or losing the interactive desktop prevents safe unattended qualification.

## Prepare an approved run through Maya

Maya owns task identity, explicit execution authorization, and acceptance criteria. Neil supplies successful build evidence with the artifact and manifest paths/hashes. Use the existing `qa-build-request` and `qa-build-execute` operations as appropriate, then `qa-handoff` and `qa-run-plan` for the same task/workflow/QA workflow/run. Keep the actual returned identities; do not invent a workflow ID or reuse another run's model. Build success alone does not approve execution.

The run plan must supply a fresh disposable model under native `QA\TestRuns` and its adjacent fixture sidecar. The registered controlled source fixture, run copy, expected fixture ID, sidecar, and expected source SHA256 must agree. Fixture provenance approval is still a human trust boundary: matching hashes do not establish non-production provenance.

Supported unattended workflows are `create-levels`, `grid-bubble-visibility-v1`, `grid-bubble-offset-v1`, and `grid-resequence-v1`. The Welcome smoke workflow requires a supervised dialog and is rejected. The Create Grids workflow has no compatible unattended startup protocol and is rejected.

## Dry run and authorized integration command

Run from the qualified checkout. Populate the first seven entries from Maya's actual store and run-plan response; the example assumes that response has been parsed into `$plan` and that `$storeRoot` and `$taskId` identify its store/task:

```powershell
$tara = @{
    StoreRoot = $storeRoot
    TaskId = $taskId
    WorkflowId = $plan.WorkflowId
    QaWorkflowId = $plan.QaWorkflowId
    RunId = $plan.RunId
    ModelPath = $plan.ModelPath
    SidecarPath = $plan.SidecarPath
    ReportDirectory = 'C:\Repato-Autonomous\Source\QA\Reports'
    RevitInstallDir = 'E:\revit\Revit 2025'
    QaAddinRoot = 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA'
    TimeoutSeconds = 900
}
.\AgentOrchestration\Invoke-MayaQaWorkflow.ps1 -Operation qa-tara-execute @tara -DryRun
```

Dry run validates the prepared inputs, artifact, manifests, and policy and returns the exact proposed command with `SideEffectsPerformed = false`. It does not create a request, reserve the run, mutate the store, or start Revit. It can reject missing prerequisites; it is not a way to bypass them. Interactive-session validation applies to real execution.

DryRun may be run as `rsgud` only when the approved QA paths are readable. An inaccessible `RepatoQA` add-in path is reported as a structured validation failure; the bridge never grants permissions or attempts to read through the denial. Real Tara execution must run in the logged-in, unlocked `RepatoQA` session.

Only after Maya receives explicit Revit integration authorization and all prerequisites are satisfied, in the logged-in and unlocked `RepatoQA` session:

```powershell
.\AgentOrchestration\Invoke-MayaQaWorkflow.ps1 -Operation qa-tara-execute @tara -IntegrationTest
```

`-IntegrationTest` is the deliberate launch opt-in. Its presence does not replace the user's authorization or environment qualification. Do not add it to automated unit/regression runs.

## Evidence, timeout, and recovery

The Maya operation requires valid Neil build evidence, a handoff, and a matching run plan. It reserves execution to prevent duplicates. The bridge creates a unique native request, passes it to the matching startup runner, starts a new Revit process, and waits for that request's result. Revit opens only the disposable model through the validated runner protocol; there is no UI-click automation or command sent to an existing session.

Results include execution status, request/result/report paths, request and native run identity, report hash, process ID, UTC timing, exit state, and side-effect status. Verification requires the passing native report, required rollback, no errors, identity correlation, unchanged model/fixture hashes, and matching artifact/manifest evidence. Preserve the complete request, native receipt/report, controller evidence, hashes, logs, task-store history, and failed run files. Do not substitute a latest report or reuse old IDs.

The hard timeout may terminate only the exact QA Revit process started by this bridge. It never kills all Revit processes. A forced termination cannot prove rollback of an interrupted operation. A failed/absent report, crash, timeout, unexpected dialog, or unknown target is a failure requiring Maya review; do not retry mutations in the same session. No automatic deletion of fixtures, reports, or run directories occurs. A completed runner can leave Revit open for review; close the disposable model without saving after review. A native pass does not automatically promote the task baseline or replace the existing report/complete workflow.

Remaining qualification requires a real interactive Windows desktop, exact installed QA artifact and manifest, approved dedicated fixtures, and native execution evidence. Synthetic regression tests cannot qualify Revit licensing, dialogs, third-party startup behavior, transaction outcomes, or the visual usefulness of exported screenshots.
