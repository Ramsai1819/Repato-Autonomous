# Create Plan Views — read-only ambiguous native request reconciliation

## Current offline observation

Request `184ebc8c62434efcbd1aaf6dd18bc6ed` is present at:

`C:\Repato-Autonomous\Source\QA\TestRuns\fa2c2f578cbc40cbacac45c96313ca4c-2f55ada86af64b0a80d7fab82362494a\maya-tara-2f55ada86af64b0a80d7fab82362494a.request.json`

Its observed SHA-256 is `647D465317587BF14FE6443940C7C648CA234E474F255F5D52B948E810507C98`. The derived native result (`<request>.result.json`) was absent at inspection. This is not evidence that Revit stopped or never started.

## Disposition meanings

`Get-RepatoQaNativeDisposition` in `AgentOrchestration/Repato.QaNativeDisposition.psm1` is read-only and non-waiting. It reads `tasks.json`, the request, derived result, and report; it never calls the Launch Agent, waits, updates task state, or terminates processes.

- `Unknown`: missing/malformed/mismatched request, task-store identity, result, report, or hashes. Also returned when no accepted-launch execution record exists and no terminal result exists. Never retry from this state.
- `Accepted`: exact canonical execution IDs and request path match, and the persisted execution is in an execution/evidence terminal stage with a PID and launch time, but no terminal result exists. This records that the production path accepted a correlated Launch Agent response; it does not prove the process remains alive or has stopped.
- `Completed`: correlated `Passed` receipt/report, nonempty all-passing assertions, no report errors, `RolledBack`, exact candidate, authoritative fixture and runtime-model hashes, all bound to the exact canonical execution.
- `Failed`: correlated `Failed` receipt/report with an explicit failure and a valid rollback state. If report/receipt identities conflict or required terminal evidence is absent, the result remains `Unknown`.

These are integrity/correlation checks, not digital signatures. Acceptance still depends on the protected canonical store and the production Launch Agent response validation path. A process exit, expired approval/request, absent PID, or timeout is never a terminal result.

## Human-assisted steps in the original interactive RepatoQA environment

1. Do not retry, approve, claim, dispatch, terminate, or restart anything. Preserve the task store and original request/result/report/log artifacts.
2. In the original interactive RepatoQA session, use the supported read-only task-status route to inspect `task-bf61fe7f22d74df7a92599681da5919e`, workflow `fa2c2f578cbc40cbacac45c96313ca4c`, attempt `9340e05410aa43dab037a934b0423dba`, claim `cfbf9d2d79ea4b0b9d443fa3e091e473`, and request `184ebc8c62434efcbd1aaf6dd18bc6ed`. Preserve the actual revision and execution record as observed.
3. To establish launch acceptance, require the persisted execution record’s exact IDs, request path, `Stage`/`ExecutionStatus`, nonzero `NativeProcessId`, and `LaunchedUtc`. Also inspect the original authenticated agent/IPC audit evidence for the same request and correlation IDs, `accepted=true`, `failureCode=null`, expected `RAMSAI\RepatoQA` user/SID, the interactive session, exact Revit image path, and launch time. If either side is missing or disagrees, report `Unknown`, not `Accepted`.
4. Inspect `<request>.result.json` and the exact report path it names without altering them. Check every request/task/workflow/QA-workflow/test/attempt/run/claim ID, report and receipt statuses, report SHA-256 stability, candidate assembly SHA-256, authoritative fixture and disposable model hashes, finished time, errors, assertions, and rollback status. A passing terminal classification requires the checks enforced by the read-only reconciler and production verifier. A failed terminal classification requires an explicit correlated failure report; missing/partial evidence stays `Unknown`.
5. Separately verify cleanup/owned-process evidence from the original agent session. A terminal QA report alone does not prove process cleanup; process absence alone does not prove the QA result.
6. Record the evidence paths and hashes, exact human observations, and current task revision. If the result remains unknown, stop. A later run requires the supported recovery workflow, a fresh attempt, and fresh human authorization; the expired request is never reused.

The reconciler may be run only against the canonical store and the explicit evidence root as a read-only diagnostic. Synthetic regression coverage is `AgentOrchestration/Test-QaNativeDispositionReadOnly.ps1` and uses a unique temporary store only.

## Replacing the reconciled duplicate-FloorPlan candidate

`Recover-MayaQaReconciledDuplicateFloorPlanFailureForCandidateReplacement` is limited to the exact terminal `duplicate-floor-plan-view-family-type` failure. It requires the current task revision and matching task, workflow, attempt, run, released claim, native request, receipt, report, candidate, and model identities. It re-hashes the original request/result/report/model, fixture-preparation evidence, and shutdown journal; verifies the recorded graceful process exit, absence of Revit, `TransactionStatus=NotStarted`, and `RollbackStatus=NotRequired`; and compares the report's failure stack and assembly identity. Empty element-ID arrays are not sufficient evidence of no side effects.

The transition archives the failed execution and attempt without changing their failure status, clears only the active QA pointers, and advances to `in-progress/build-checks` for supported candidate replacement. It preserves the expired approval record byte-for-byte at the object level and records it as `expired-unconsumed`; it must never manufacture consumption or reuse that approval. A fresh QA approval request is blocked only by pending or approved, unconsumed QA approvals whose expiry is still in the future. Invalid expiry data fails closed. Replaying the exact transition is read-only and idempotent.
