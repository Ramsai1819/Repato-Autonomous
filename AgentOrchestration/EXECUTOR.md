# Controlled local executor v1

The executor is a dry-run action layer over the local Maya–Neil–Tara task store. Maya creates plans and manages approval requests. Neil may claim implementation, branch/worktree, commit-preview, and approved file-operation plans. Tara may claim build, regression, evidence, add-in, and supervised Revit-preview plans.

Every plan stores an execution ID, agent, workflow phase, exact command previews, timestamps, SHA-256 plan hash, logs, reports, evidence, and terminal error details. Task mutations and executor mutations use the existing exclusive `store.lock` and atomic JSON replacement. Active-run checks prevent duplicate planning and claiming.

## Allowlisted actions

| Action | Agent | Phase | Approval |
|---|---|---|---|
| `validate-branch` | Neil or Tara | assigned | none |
| `create-worktree` | Neil | assigned | none |
| `validate-worktree` | Neil or Tara | assigned | none |
| `production-edit` | Neil | implementation | none; preview only in v1 |
| `build-release` | Tara | build-checks | none |
| `run-agent-tests` | Tara | build-checks | none |
| `run-qa-tests` | Tara | qa | none |
| `production-commit` | Neil | approval | explicit user approval |
| `revit-launch` | Tara | qa | explicit user approval |
| `file-delete` | Neil or Tara | implementation | explicit user approval |
| `addin-change` | Tara | qa | explicit user approval |

Unknown actions and agent/action mismatches are rejected. Each plan contains one workflow phase and may target only the current or immediately following stage.

## Approval binding

Dangerous-action approval is bound to the exact plan SHA-256 and current task revision. Requests expire, accept only the required approver, and are single-use. Preview and completion recheck the approval under the exclusive lock immediately before the hypothetical execution point. Any intervening task mutation changes the revision and invalidates approval.

## Dry-run behavior

Version 1 never executes a planned command. `executor-preview` returns `WouldExecute` and `SideEffectsPerformed: false`. It does not launch Revit, run Git, commit, create a branch/worktree, edit production files, delete files, change add-ins, call APIs, or contact external services. The normal executor commands may update the local JSON task state; adding `-DryRun` previews that state transition without writing it.

## Example lifecycle

```powershell
$task = '.\AgentOrchestration\Invoke-RepatoAgentTask.ps1'
$executor = '.\AgentOrchestration\Invoke-RepatoAgentExecutor.ps1'

& $task create -TaskId REP-100 -Title 'Example' -Description 'Controlled executor example' -BranchName 'feat/rep-100' -ApprovalLevel user
& $executor executor-list-queued
$plan = & $executor executor-plan -TaskId REP-100 -Agent Neil -Actions validate-branch,create-worktree | ConvertFrom-Json
& $executor executor-claim -TaskId REP-100 -ExecutionId $plan.executionId -Agent Neil
& $executor executor-validate -TaskId REP-100 -ExecutionId $plan.executionId
& $executor executor-preview -TaskId REP-100 -ExecutionId $plan.executionId
& $executor executor-complete -TaskId REP-100 -ExecutionId $plan.executionId -LogPaths 'AgentOrchestration/Logs/REP-100.json'
```

For a dangerous plan, use `executor-request-approval`, approve through the existing Maya task CLI with the required user actor, then preview. Completion consumes that approval.

## Limitations

- No planned command is executed in v1.
- The executor does not create branches or worktrees; it shows exact intended Git commands.
- It does not inspect production diffs or authorize arbitrary shell text.
- Local JSON plus a file lock supports one-machine coordination, not distributed workers.
- Queue and status JSON replacements are individually atomic, not a multi-file database transaction.
- Approval identity is a local record without OS authentication or cryptographic signing.
