# Create RCP Views — isolated QA preparation

## Candidate and safety boundary

The runner identity is `create-rcp-views-v1`, separate from Create Plan Views. Its source manifest is `QA/Repato.CreateRcpViews.TestRunner.addin`; that file is a template only. A future QA candidate must be built into a new versioned directory, have every loaded assembly and manifest hash recorded, pass isolated staging/integrity validation, and be explicitly authorized before installation. The CPV frozen candidate and installed QA profile are not inputs to this workflow.

No authoritative `.rvt` fixture is included or changed. The deterministic fixture definition is `QA/Fixtures/CreateRcpViewsEmpty.fixture-spec.json`; an authorized preparation workflow must create a new disposable Revit 2025 model from a blank project and authenticate its provenance before any RCP attempt.

## Fixture, inputs, and expected result

The fixture has exactly `Level 0`, `Level 1`, and `Level 2` at 0/3000/6000 mm, exactly one `CeilingPlan` family type named `Ceiling Plan`, no existing ceiling plan views, no links, and no worksharing. The request binds those exact three level names, view family type, `RCP` suffix, model/fixture hashes, manifest hash, runner DLL hash, shared Repato support DLL hash, request/task/workflow/test/attempt/run/claim IDs, a canonical request self-hash, and request expiry.

Expected views are `Level 0 - RCP`, `Level 1 - RCP`, and `Level 2 - RCP`; each must be a `CeilingPlan`, use the selected type, and have its `GenLevel` match the corresponding named level. Existing names, missing/duplicate levels, missing/duplicate types, expired requests, incorrect task/test identity, invalid model, or integrity mismatch fail closed before success.

## Transaction, integrity, and evidence

Capture baseline `ViewPlan` element IDs, create all requested views in one transaction inside one transaction group, inspect each view, commit the inner transaction for observation, then roll back the group. Success requires `RolledBack`, exact baseline view-ID restoration, and unchanged model-file SHA-256. Never save or synchronize. Cleanup must close the disposable document without saving; cleanup failure changes the result to `Failed`.

The JSON receipt at `<request>.result.json` binds request/task/workflow/QA-workflow/test/attempt/run/claim IDs and request hash, status, report path/hash, runner hash, and shared support DLL hash. The report repeats those identities, fixture/model/artifact hashes, expected and observed view names, and per-view element ID, view family, family type, level name/ID, rollback status, baseline restoration, assertions, errors, and finish time. Acceptance requires both receipt and report to correlate exactly; `Passed`; all positive assertions; no errors; all three exact views with unique element/level IDs and correct family/type/level; verified rollback and byte integrity. Screenshots are supplemental, not a substitute for model-state evidence.

## Synthetic-only coverage and remaining live prerequisites

Contract tests cover wrong test/request path, duplicate levels, wrong view family type, expired request, receipt/report correlation, candidate hash mismatch, report tampering, rollback failure, and baseline mismatch. Revit startup behavior and actual element creation remain live-only.

Before any future live attempt: authenticate a newly prepared disposable fixture; confirm the original CPV ambiguous execution is reconciled independently; build and hash a separate candidate; verify user/session, Revit 2025, no premature document or conflicting Revit process, exact selected manifest and all candidate dependencies, isolation allowlist and permissions; obtain a fresh human approval bound to the exact RCP request; set a sufficient execution timeout without extending authorization expiry; capture result/report and cleanup evidence. No RCP approval, dispatch, deployment, or live QA is created by this preparation.
