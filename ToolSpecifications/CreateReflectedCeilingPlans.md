# Create RCP Views — implementation contract

## Selection and behavior

- Ribbon command: **Repato → Project Setup → Create RCP Views**.
- Revit 2025 project document only; family, read-only, and already-modifiable documents are rejected.
- The user selects one or more existing levels, one available `CeilingPlan` view family type, and a non-empty name suffix (default `RCP`).
- The generated name is `<level name> - <suffix>`. No view template is applied in this first slice.
- Existing view-name collisions are rejected case-insensitively before a transaction begins. The command does not overwrite, auto-rename, or silently skip collisions. Re-running the same request therefore fails safely without creating duplicates.
- Missing/stale levels and unavailable/non-ceiling-plan type IDs are rejected before mutation. Revit-specific invalid-name or capability errors abort the entire batch.

## Transaction and recovery

All selected views are created in one `Transaction` within one `TransactionGroup`. The transaction is committed only after every view is created and named; the group is assimilated only after that commit. Any creation, naming, or commit failure rolls back the group. If rollback also fails, both errors are retained and the operation is not reported as successful.

## Project prerequisites

- The active document is a writable Revit 2025 project, not a family document or an already-open transaction.
- At least one existing Level and one `ViewFamilyType` with `ViewFamily.CeilingPlan` are present.
- The Revit document's discipline/configuration permits plan-view creation. Revit API rejection is surfaced; partial creation is not accepted.

## Acceptance and evidence contract

Offline acceptance checks cover request planning, exact names, unique IDs, case-insensitive name collisions, stale levels, invalid type selection, unsafe document states, successful all-level creation, mid-batch failure, commit failure, group rollback, and explicit rollback-failure reporting. The future live QA runner should report task/artifact identity, chosen type, selected level IDs/names, created view IDs/names, status, exception text, and transaction-group rollback status. Screenshots are supplementary and are not a substitute for verifying the model state. This command does not yet emit an authenticated QA receipt or establish live QA acceptance.

## Current scope boundary

This native ribbon command is separate from the Create Plan Views recovery workflow and does not consume its runner, fixture, attempt, approval, deployment candidate, or evidence. The configured external Dynamo registry remains unchanged; connector/Dynamo registration and live QA are later adoption work requiring their own review and authorization.
