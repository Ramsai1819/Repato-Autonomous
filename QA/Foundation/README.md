# Repato QA runner foundation

`QaRunner.Foundation.ps1` owns controller mechanics: path containment, shared-read SHA-256, provenance validation, unique disposable copies, atomic JSON, request expiry, launch diagnostics, Revit startup, bounded waiting without process termination, stale-request discovery, and preservation of failed runs.

`TestRunner/QaRunnerFoundation.cs` owns native evidence registration, rollback-result assertions, report completion, and atomic receipt writing. `TestSafetyGate`, `FixtureContentPolicy`, `AddinIsolationPolicy`, and `TestRunReport` remain the authoritative native safety and report components.

Tool runners retain their fixture policy, test ID, inputs, Revit operation, assertions, and result verifier. A tool controller must fail closed before calling `Start-RepatoQaRevit` and must never delete a failed run.

## New runner checklist

1. Create a dedicated local, non-workshared Revit 2025 fixture and provenance JSON.
2. Add the exact fixture name set to `FixtureContentPolicy` when the fixture is not empty.
3. Add a QA application, command, and QA-only manifest from `QA/Templates`.
4. Add the repository manifest filename to both isolation implementations and their tests.
5. Define one fixed test ID and fixed inputs; reject unknown IDs.
6. Call the production service or planner used by the ribbon command.
7. Snapshot selected, unselected, and geometry state before mutation.
8. Use a transaction group and always roll it back in `finally`.
9. Register assertions, errors, timing, artifact identity, Revit version, changed IDs, evidence, and rollback status.
10. Verify the receipt and report independently in PowerShell.
11. Add static, workflow, startup, report-schema, isolation, and rollback regression tests.
12. Build, install in RepatoQA, run on a fresh disposable copy, verify, and retain failures.

The template intentionally contains placeholders that prevent execution until every tool-specific contract is filled in.
