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
