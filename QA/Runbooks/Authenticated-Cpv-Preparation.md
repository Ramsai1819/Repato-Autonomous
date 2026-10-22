# Authenticated Create Plan Views fixture preparation

This operation prepares only a new disposable copy of the fixed CreatePlanViewsEmpty source fixture. It does not run the final Create Plan Views QA test. Its Launch Agent operation is `prepare-cpv-fixture`, with separate `cpv-preparation-capabilities` and `cpv-preparation-status` operations on the existing ACL-protected named pipe. Existing operations and their contracts remain intact.

The request accepts task/workflow/request/attempt/run identities, a bounded expiry/timeout, and existing frozen-candidate evidence. It accepts no model, executable, command line, or environment-variable override. Candidate paths are checked against existing approved roots and provenance; deployment is authenticated through the existing validation adapter, including manifest integrity and isolation. The legacy preflight hash is not substituted for current-candidate evidence. The fixed source fixture has an independent pinned hash and provenance contract.

The agent chooses QA/TestRuns/cpv-preparation-RUNID/model.rvt, writes the existing preparation runner request, clears inherited QA dispatch variables, and sets only the fixture-preparation dispatch. Preparation runs under the agent's fixed RepatoQA identity and interactive session. Before dispatch it checks Revit absence, source/model locks, path reparse points, fixture/candidate hashes, provenance, and deployment. The owned child is checked against the fixed executable/session. Modal dialogs stop preparation without being dismissed. Bounded waits end on result, child exit, dialog, or timeout.

The result must identify the exact task/workflow/attempt/run/model and source hash. It must contain exactly levels 0, 1, 2, with distinct positive IDs and elevations 0, 4, 7.8 metres. The agent verifies the saved model hash, terminates only its owned child, confirms process exit and exclusive model readability, and checks residual lock markers. It writes a receipt over the authenticated pipe and stores it with the request and failure diagnostics under the fixed QA account's Launch Agent log root.

Replay protection uses the existing ledger plus permanent attempt/run reservations and an exclusive active marker. An identical same-request retry can return its receipt; a different payload cannot reuse the ID. Concurrent preparation, staging, and final QA dispatch are blocked while the marker exists. A marker left by interruption, timeout, cleanup failure, or ambiguous execution remains for reconciliation. A restarted agent reports an in-flight receipt as OutcomeUnknown. There is no automatic native retry. Failed disposable copies and historical receipts remain evidence; rollback is never claimed for an unverified outcome.

## Canonical sequence

Use AgentOrchestration/Invoke-CpvPreparationRecovery.ps1. Run `capabilities` before any canonical mutation. An older installed agent returns unsupported; stop for validated runtime installation.

1. `begin -ExpectedTaskRevision REVISION -ExpiredApprovalId ID` validates the exact expired pending user approval, candidate, prior preparation bytes/provenance, and absence of active native state. One atomic revision-guarded store transaction supersedes the expired request, preserves its binding, and persists fresh request/attempt/run identities. It creates no approval and launches no process.
2. `dispatch -ExpectedTaskRevision REVISION` atomically records Dispatching before sending. A timeout or lost response must be reconciled by `status`; do not dispatch again.
3. Poll `status` using short calls. OutcomeUnknown, NotFound after an uncertain send, failure, or unverified cleanup requires evidence review. Never infer success from a dialog or process disappearance.
4. `complete -ExpectedTaskRevision REVISION` obtains the authenticated agent receipt itself, verifies identities, expiry, files, levels, and provenance, and records verified preparation with the old workflow snapshot retained. It reuses Request-MayaQaCanonicalExecutionApproval for the existing candidate/deployment binding and exactly one pending human approval. Completion retries reuse that approval. No approval is decided and final native QA is never dispatched by this workflow.

The original fixture-preparation expiry is never extended. A new preparation has its own attempt/run/request and expiry. Final QA requires a separate explicit human decision on the fresh canonical approval. If that expires, reconcile it through supported transactions before doing anything else.

## Deployment boundary

Do not install automatically. Build the Launch Agent, run its preparation/protocol/canonical regressions, commit the scoped source, and package with New-QaLaunchAgentRelease.ps1. The source commit and file hashes are recorded in its immutable release manifest. After explicit installation authorization, run Install-CpvPreparationAgentCandidate.ps1 with the exact ReleaseRoot, ManifestSha256, and -Execute in an elevated administrator PowerShell. That script uses the existing bootstrap installer and rollback token, verifies installed runtime/task integrity, starts the existing scheduled task, and requires authenticated preparation capability before completing installation. It changes the Launch Agent runtime only; it does not replace a product candidate, add-in manifest, or QA fixture.

Synthetic validation uses injected preparation/process boundaries and isolated temporary canonical stores. Real preparation and final QA are not part of those tests. A successful synthetic run or build is not a Revit QA pass.
