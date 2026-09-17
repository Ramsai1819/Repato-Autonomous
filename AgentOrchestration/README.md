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
