# Repato local agent orchestration

This first local foundation coordinates work without a server or external service. Maya owns task intake, planning, status, approval requests, and user communication. Neil claims implementation work and attaches build or implementation logs. Tara validates builds, non-Revit tests, QA reports, and regressions; Tara does not edit production C#.

## Files and runtime state

- `Invoke-RepatoAgentTask.ps1`: command-line entry point.
- `Repato.AgentOrchestration.psm1`: validated state machine, atomic JSON storage, approvals, and dry-run behavior.
- `Store/tasks.json`: local authoritative task queue, created on first non-dry-run command and ignored by Git.
- `Store/status.json`: local task-status index, regenerated after every mutation and ignored by Git.
- `Store/store.lock`: exclusive mutation lock, ignored by Git.

Each task records its ID, title/description, agent, status, workflow stage, branch, UTC timestamps, logs, reports, errors, approval level, approval requests, and append-only history. Failed and completed tasks are terminal and remain in the store.

## Workflow

`queued -> assigned -> implementation -> build-checks -> qa -> approval -> completed`

Status and stage are separate. Claiming sets `in-progress/assigned`; implementation and checks remain `in-progress`; successful QA sets `passed/qa`; requesting approval sets `awaiting-approval/approval`; approval returns the status to `passed`; completion sets `completed/completed`. Blocked and failed statuses preserve evidence and errors.

The CLI never runs Git, launches Revit, edits production files, disables add-ins, or deletes project data. Requests for `production-commit`, `revit-launch`, `destructive-file-operation`, or `disable-addins` require explicit `user` approval. A future executor must check the recorded approved request immediately before performing one of those actions. Work should use the task's isolated branch and a worktree when concurrent work makes that practical.

`-DryRun` validates and previews an operation without writing queue/status files. It cannot perform production edits, commits, Revit launches, add-in changes, or deletion because those capabilities are absent from this CLI.

## Examples

```powershell
$cli = '.\AgentOrchestration\Invoke-RepatoAgentTask.ps1'
& $cli create -TaskId REP-001 -Title 'Example' -Description 'Implement and validate an example' -BranchName 'feat/rep-001' -ApprovalLevel maya
& $cli list
& $cli claim -TaskId REP-001 -Agent Neil
& $cli update -TaskId REP-001 -Stage implementation -LogPath 'AgentOrchestration/Logs/REP-001-neil.log'
& $cli update -TaskId REP-001 -Stage build-checks
& $cli update -TaskId REP-001 -Stage qa -Status passed -Agent Tara
& $cli attach-report -TaskId REP-001 -Agent Tara -ReportPath 'QA/Reports/rep-001.json'
& $cli request-approval -TaskId REP-001 -ApprovalAction completion -ApprovalLevel maya
& $cli approve -TaskId REP-001 -Agent Maya -Reason 'Checks reviewed'
& $cli complete -TaskId REP-001
```

Use `-ApprovalAction production-commit -ApprovalLevel user` to record a commit request. Approval records authorization; this foundation deliberately does not execute the commit.

## Controlled executor v1

`Invoke-RepatoAgentExecutor.ps1` adds a dry-run executor over the same task queue, atomic writers, and exclusive `store.lock`. Maya creates hashed action plans and manages approvals. Neil claims branch/worktree validation and implementation plans. Tara claims build, regression, evidence, add-in, and supervised Revit plans. Executor runs store their own plan, agent, start/validation/completion timestamps, log/report/evidence paths, failure details, and append-only task-history events.

The executor validates branch names against `feat/`, `fix/`, `qa/`, or `chore/` plus a restricted character set. Worktree paths are derived from the safe task ID. It only records branch and worktree commands; it never creates either in v1.

### Allowed executor actions

| Action | Agent | Workflow phase | Approval |
|---|---|---|---|
| `validate-branch` | Neil or Tara | assigned | none |
| `create-worktree` | Neil | assigned | none |
| `validate-worktree` | Neil or Tara | assigned | none |
| `production-edit` | Neil | implementation | preview only |
| `build-release` | Tara | build-checks | none |
| `run-agent-tests` | Tara | build-checks | none |
| `run-qa-tests` | Tara | qa | none |
| `production-commit` | Neil | approval | user |
| `revit-launch` | Tara | qa | user |
| `file-delete` | Neil or Tara | implementation | user |
| `addin-change` | Tara | qa | user |

Unknown actions and agent/action mismatches are rejected. Each plan is limited to one phase and may target only the current or immediately following workflow stage.

Dangerous approvals are bound to the exact plan SHA-256 and current task revision. They expire, can be used once, and are checked under the exclusive lock immediately before preview or completion. Any intervening task change invalidates the approval. Production commits, Revit launches, deletion, and add-in changes cannot proceed without a current user approval.

`executor-preview` returns the exact `WouldExecute` commands and `SideEffectsPerformed: false`. Version 1 never executes those commands, launches Revit, runs Git, edits production files, deletes files, changes add-ins, calls OpenAI, or contacts an external service. Executor state commands update only the local JSON store; `-DryRun` also suppresses those state writes. Failed and blocked tasks, runs, logs, reports, and evidence remain preserved.

```powershell
$executor = '.\AgentOrchestration\Invoke-RepatoAgentExecutor.ps1'
& $executor executor-list-queued
$plan = & $executor executor-plan -TaskId REP-001 -Agent Neil -Actions validate-branch,create-worktree | ConvertFrom-Json
& $executor executor-claim -TaskId REP-001 -ExecutionId $plan.executionId -Agent Neil
& $executor executor-validate -TaskId REP-001 -ExecutionId $plan.executionId
& $executor executor-preview -TaskId REP-001 -ExecutionId $plan.executionId
& $executor executor-complete -TaskId REP-001 -ExecutionId $plan.executionId -LogPaths 'AgentOrchestration/Logs/REP-001.json'
```

The executor remains local and single-machine. It does not run autonomous agent processes, create worktrees, inspect diffs, authenticate approvers through the operating system, or provide a transactional database across both JSON files. See `EXECUTOR.md` for the complete action and approval contract.

## Tara controlled execution adapter

`Invoke-RepatoTaraAdapter.ps1` is the first executor that may start local processes. It is limited to the fixed repository root `C:\Repato-Autonomous\Source` and resolves every command from `TaraCommands.json`; callers cannot supply an executable, arguments, working directory, or script path. Registered scripts must be repository-owned `Test-*.ps1` validation scripts (plus the isolated failure fixture used by adapter regression tests). The adapter never uses `Invoke-Expression`.

Allowed command IDs are:

- `build.release`: the required Release build of `Forma.RevitConnector.csproj` with the approved Revit 2025 install path.
- `script.<registered-path>`: an exact script listed in `TaraCommands.json`.
- `syntax.powershell`: parse all repository PowerShell sources.
- `git.diff-check`, `git.status`, `git.log`, and `git.diff`: fixed read-only Git inspections. No Git ref, path, or extra argument can be supplied.

Each plan records the executable, fixed argument array, registry SHA-256, command SHA-256 (including the executable and registered script hashes), plan SHA-256, and task revision. Tara must own the task, and its workflow stage must match the command. Maya approval is required for every real run and is bound to that plan and revision. The adapter checks the approval, command registry, script identity, stage, assignment, and exclusive task-store lock immediately before starting the process. Approval expires, is consumed once, and becomes invalid after any task or plan change.

The adapter records UTC start/end times, duration, stdout, stderr, exit code, command identity, and build artifact paths and hashes in `AgentOrchestration/Logs`. Logs are retained for successful and failed commands. A nonzero exit marks the run and task failed without deleting prior state or evidence. The exclusive store lock and terminal run state reject concurrent and duplicate execution.

```powershell
$tara = '.\AgentOrchestration\Invoke-RepatoTaraAdapter.ps1'
$task = '.\AgentOrchestration\Invoke-RepatoAgentTask.ps1'

$plan = & $tara tara-plan -TaskId REP-001 -CommandId build.release | ConvertFrom-Json
& $tara tara-validate -TaskId REP-001 -RunId $plan.runId
& $tara tara-request-approval -TaskId REP-001 -RunId $plan.runId
& $task approve -TaskId REP-001 -Agent Maya -Reason 'Exact build plan reviewed'
& $tara tara-preview -TaskId REP-001 -RunId $plan.runId
& $tara tara-run -TaskId REP-001 -RunId $plan.runId
```

Use `tara-run -DryRun` after approval to produce the exact `WouldExecute` preview. It does not execute a process or write task state or logs. `tara-fail` records a pre-execution failure while retaining the task and run.

The adapter blocks arbitrary shell text, Revit launch, commits, deletion, add-in changes, production edits, path traversal, external scripts, external services, and caller-selected arguments. It does not authenticate Maya through the operating system, manage branches or worktrees, schedule work, retry commands, kill processes, or impose a child-process timeout. Validation scripts can write their documented repository test artifacts; their behavior remains part of their reviewed source identity. A future version needs an authenticated approval principal and bounded process supervision before broader actions are considered.

## Neil controlled implementation adapter

`Invoke-RepatoNeilAdapter.ps1` plans and applies exact declarative transformations from `NeilActions.json`. Callers provide a task ID and registered action ID; they cannot provide a command, target path, replacement text, patch, or executable. The registry fixes the repository root, explicitly lists eligible production C# files, and stores each action's exact target and replacements. Path traversal, external paths, unknown files, unknown actions, duplicate actions, and malformed transformations fail closed.

Neil may plan only an `in-progress` task assigned to `Neil` at the `implementation` stage. The task branch must exactly match `.git/HEAD`; detached HEAD is rejected. Planning records the current file SHA-256, approved result SHA-256, exact unified before/after diff, action and registry identities, branch, task revision, and plan SHA-256. Validation repeats those checks. Maya approval is bound to the plan hash and latest revision, expires, and is consumed once under the task-store lock immediately before the edit.

Application rechecks the branch, registry, action, source bytes, plan, approval, and task revision, then writes the approved UTF-8 bytes through an atomic replacement. The log records timestamps, duration, changed files, before/after hashes, diff, and errors. If post-write verification fails, the adapter restores the original bytes and marks the run failed. Successful and failed runs remain in task history, and the exclusive store lock prevents concurrent claims.

The currently enabled action IDs are validation-only and exercise the full lifecycle without touching production code:

- `validation.fixture-marker-forward-v1`
- `validation.fixture-marker-reset-v1`

No production edit action is currently enabled. A future implementation task must add a reviewed, version-controlled action with a concrete required transformation before Neil can change an allowlisted production file.

```powershell
$neil = '.\AgentOrchestration\Invoke-RepatoNeilAdapter.ps1'
$task = '.\AgentOrchestration\Invoke-RepatoAgentTask.ps1'
$plan = & $neil neil-plan -TaskId REP-002 -ActionId validation.fixture-marker-forward-v1 | ConvertFrom-Json
& $neil neil-validate -TaskId REP-002 -RunId $plan.runId
& $neil neil-request-approval -TaskId REP-002 -RunId $plan.runId
& $task approve -TaskId REP-002 -Agent Maya -Reason 'Exact diff reviewed'
& $neil neil-apply -TaskId REP-002 -RunId $plan.runId -DryRun
& $neil neil-apply -TaskId REP-002 -RunId $plan.runId
```

The operations are `neil-plan`, `neil-validate`, `neil-preview`, `neil-request-approval`, `neil-apply`, and `neil-fail`. Dry-run application returns the exact changed-file list, hashes, and diff without editing a file, changing task state, or creating a log.

The adapter cannot create arbitrary patches, add or delete files, rename files, run commands, commit, launch Revit, modify add-ins, contact external services, or edit outside the registry. It does not authenticate Maya through the operating system, merge multiple files in one atomic filesystem transaction, or resolve merge conflicts. Registry changes remain ordinary reviewed repository changes and are not self-authorizing.
