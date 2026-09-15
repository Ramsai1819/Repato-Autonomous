# Safe Revit QA workspace

Revit execution is still disabled until a dedicated fixture and Test Runner are created. Their creation alone does not enable execution: Maya must also confirm the safety prerequisites and obtain explicit user authorization under the root AGENTS.md rules. Do not launch Revit, send commands to an existing session, or deploy an add-in yet.

## Allowed models

Tara may test only copied, local, non-workshared `.rvt` fixtures created specifically for QA. Never test a production, client, company, cloud, central, or workshared model, including a copy or detached version of such a model. Copying a prohibited model does not make it a safe fixture.

`Fixtures/` contains controlled test assets, never an active work project. Each future fixture must have a documented test purpose, provenance, expected state, and verified local, non-workshared status. Preserve the source fixture and test only a fresh copy in `TestRuns/`. The QA command source is implemented, but no dedicated fixture is supplied and Revit execution remains unauthorized.

## Directory rules

| Directory | Purpose | Git policy |
| --- | --- | --- |
| `Fixtures/` | Controlled source test assets; never execute tests against the original. | Assets require deliberate review before tracking. |
| `TestRuns/` | Disposable per-run model copies and runtime outputs. | Ignore all contents except the root `.gitkeep`. |
| `Reports/` | Disposable run reports, logs, and model-state evidence. | Ignore all contents except the root `.gitkeep`. |
| `Screenshots/` | Disposable visual evidence. | Ignore all contents except the root `.gitkeep`. |

Do not force-add runtime evidence to Git. Capture and report evidence to Maya before disposal; ignored evidence is not a durable Git archive.

## Checklist for future authorized Tara runs

1. **Create copy:** Copy an approved dedicated `.rvt` fixture into a unique local `TestRuns/` run directory; record the fixture identity and run ID.
2. **Verify safety:** Confirm provenance, resolved path, test ownership, non-workshared status, document identity, and supported view. Reject cloud, central, workshared, or other prohibited targets. Recheck the target inside the future Test Runner before mutations.
3. **Build artifact:** Have Neil build on the task branch using the exact command below. Record the commit, build result, warnings, artifact path, and hash. Preserve the last known passing baseline.
4. **Deploy test-only add-in:** Only after execution is authorized, deploy the identified artifact into the isolated QA environment. Verify the loaded assembly identity and controlled manifest set; never replace a production installation.
5. **Run test:** Execute the bounded test through the future Test Runner against the verified copy. Check transaction outcomes and model state against acceptance criteria. Never synchronize or save outside the disposable run area.
6. **Capture evidence:** Record inputs, expected and actual results, document/view identity, transaction outcomes, errors, and relevant logs/screenshots in `Reports/` and `Screenshots/`. Report results to Maya. Tara must not edit production C# code.
7. **Dispose test copy:** After evidence is captured and reported, close the test copy and remove only the owned disposable run files. Before recursive cleanup, verify resolved paths remain inside that run directory. Never delete or overwrite the source fixture.

Required build command, run by Neil from the repository root:

```powershell
dotnet build ".\Forma.RevitConnector.csproj" -c Release -p:RevitInstallDir="E:\revit\Revit 2025"
```

On uncertainty, error, an unknown dialog, or an unsafe target, stop execution and report evidence to Maya. Do not dismiss unknown dialogs, retry mutations blindly, or continue cleanup that could destroy failure evidence. Maya coordinates fixes with Neil and subsequent QA with Tara.

## Create Grids Test Runner v1

The QA-only `Repato.Revit.TestRunner.RepatoTestCommand` calls the existing `GridCreator.Create` service directly. It does not add a normal Repato ribbon button or modify the ribbon tools. The source manifest is `QA/Repato.TestRunner.addin`; merely keeping it here does not register or deploy it.

The only accepted test ID is `create-grids-world-axis-v1`. Manual invocation uses this default. A future journal invocation can supply the `testId` entry in `ExternalCommandData.JournalData`; any other value is rejected. Inputs cannot be overridden: vertical grids A, B, C, D and horizontal grids 1, 2, 3, 4 at positions 0, 6000, 12000, 18000 mm. Grid length is fixed at 48000 mm so each grid spans the complete test layout. Coordinates are world X/Y at Z=0. Geometry assertions use a 0.1 mm tolerance.

The runner checks exactly eight grids, exact names, straight world-axis geometry, positions, lengths, and adjacent 6000 mm spacing. It captures created element IDs and observes transaction changes independently of the service's display result. A surrounding transaction group is explicitly rolled back after assertions on both passing and failing runs. IDs in the report describe observations before rollback, not persistent elements. Rollback and restored element inventory must be verified before a pass can be reported. Revit failures are recorded and trigger rollback; failure handling never tries to repair the model automatically.

### Preparing a future approved fixture copy

This is a documented preparation contract, not permission to create or open Revit models now.

1. Maya must approve a purpose-built local Revit 2025 fixture with no grids or Revit links, no worksharing, and documented non-production provenance. Place the controlled source at `QA/Fixtures/<fixtureId>.rvt`. The fixture ID must start with a letter or digit, contain only letters, digits, `_` or `-`, and be at most 80 characters.
2. Copy that file, without modifying it, to `QA/TestRuns/<run-id>/model.rvt`. Record its SHA-256 and create the adjacent `model.rvt.fixture.json` with the following shape, replacing the illustrative values:

   ```json
   {
     "fixtureId": "CreateGridsEmptyPlan",
     "sourceSha256": "<64 hexadecimal characters from the approved source fixture>"
   }
   ```

3. The runner requires the source fixture, run copy, and sidecar hash to agree. It rejects missing or invalid provenance, modified/unsaved documents, workshared/cloud/central/detached documents, links, family/read-only documents, external paths, network drives, and reparse points. Merely renaming or moving a model into `TestRuns` does not authorize it.

Fixture approval remains a human-controlled trust boundary: hashes prove copy identity, not that the source was never a company or client project. Do not register prohibited models as controlled fixtures.

### Future isolated deployment and invocation

After explicit authorization and environment qualification, copy the built `Repato.Revit.dll` into the isolated Revit 2025 add-ins directory's `RepatoQA` subfolder and install a copy of the QA manifest beside that folder. Its relative assembly path is `.\RepatoQA\Repato.Revit.dll`. Verify the assembly hash and ensure no duplicate Repato/legacy Forma registrations or unrelated add-ins interfere. Do not install into the user's production profile. The command is exposed through Revit's External Tools menu, not the normal Repato ribbon.

Open only the approved disposable copy and invoke the QA command under supervision. It never saves a model. Reports are written to `QA/Reports/<run-id>.json` and include the test ID, fixed inputs, observed element IDs, assertion results, errors, UTC timing/duration, Revit version/build, assembly full name/path/SHA-256/module identity, fixture identity, and rollback outcome. Unknown test IDs and rejected targets produce failed reports when the report directory is safely writable. Report-writing failures must be treated as failures; absent or incomplete JSON is never a pass.

### Remaining qualification

Compilation and filesystem guard checks do not verify Revit behavior. No fixture, deployment automation, journal harness, watchdog, screenshot capture, or unattended execution qualification is supplied in v1. A hang/crash cannot guarantee rollback or a completed report; stop and escalate to Maya and never reuse that test session blindly. The first authorized run must verify the native transaction, failure handling, assertions, and rollback behavior, including rejection paths. Preserve report evidence before disposing a failed run copy.
