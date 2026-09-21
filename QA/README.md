# Safe Revit QA workspace

## Tara unattended execution bridge

The new `qa-tara-execute` Maya operation connects an approved build, handoff, and run plan to the existing native request/result runners. Read [the interactive operator guide](TaraExecutionOperatorGuide.md) for account setup, exact dry-run/integration commands, evidence, and recovery. `Show-TaraRevitQaConfiguration.ps1` prints the one-time paths and settings without changing files.

Real execution requires explicit authorization, `-IntegrationTest`, and the dedicated `RepatoQA` account logged in with an unlocked interactive desktop. Never use a service or Session 0, store passwords, bypass add-in security, deploy to a production profile, or use production models. The bridge deploys nothing. Current native runners require `C:\Repato-Autonomous\Source\QA`; the `AgentWork` development checkout alone is not a qualified execution environment. Supported unattended workflows are Create Levels, Grid Bubble Visibility, Grid Bubble Offset, and Grid Resequence. Welcome and Create Grids remain unsupported by this bridge. The historical runner-specific instructions below do not authorize execution or deployment.

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

## Create Levels automated QA

Work is confined to `qa/create-levels-runner`. The preserved passing Create Grids baseline is tag `repato-qa-create-grids-v1`, commit `04b62a29ad06db6ffe9c944dcfcf04f2fcd3b48c`. Its report is `aa2cc3b8d4fe402189c8d5ce22385a7c`. Create Levels has not yet been executed in Revit by this implementation task.

`CreateLevelsEmpty.rvt` is a dedicated byte-for-byte copy of the existing controlled `CreateGridsEmptyPlan.rvt` fixture, with provenance in `Fixtures/CreateLevelsEmpty.provenance.json`. It is empty of QA test levels, not necessarily empty of template levels. Do not remove those template levels: the test snapshots and preserves their IDs, names, and project elevations. The first native run must qualify the fixture's elevation/section view for screenshot export.

The existing Create Levels implementation was in the excluded legacy `FormaEventHandler.cs`. Its method and numeric parser are extracted unchanged into `LevelCreator.cs`; the legacy entry point delegates to the shared service. Input format, duplicate handling, transaction name, return shape, and normal creation behavior are preserved. The legacy connector remains excluded and no production ribbon button is added.

The separate QA command accepts only `create-levels-elevations-v1`. It creates three run-specific names ending LOW, MID, and HIGH at project elevations -1200, 3450, and 7800 mm, checks the exact names and count, verifies each elevation within 0.1 mm, and confirms the original levels remain unchanged. A transaction group always rolls back after assertions; a pass additionally requires restored element IDs, unchanged original levels, no test levels remaining, and unchanged source and copy hashes. Temporary modified/deleted IDs are recorded. Non-level parameter-by-parameter restoration is not independently asserted; it relies on the confirmed Revit group rollback.

The command exports three genuine Revit view PNGs into `Screenshots/<report-run-id>/`: before creation, after creation, and after rollback. It requires an uncropped elevation or section view with Levels visible, and all created level IDs must be exposed by that view. These are rendered view images, not desktop captures. Failure to obtain required images prevents a pass. Each report contains the image phase/path/hash/view identity in addition to inputs, observed element IDs, assertions, errors, timing, Revit version/build, and assembly identity. JSON remains authoritative for numerical checks; visual usefulness still needs native fixture qualification.

### Exact build, installation, run, and verification commands

Build from the source workspace using the approved command:

```powershell
Set-Location 'C:\Repato-Autonomous\Source'
dotnet build ".\Forma.RevitConnector.csproj" -c Release -p:RevitInstallDir="E:\revit\Revit 2025"
```

The following commands are for the **RepatoQA Windows account**, after Revit execution is authorized, with Revit closed. The account needs read access to the repository/build/fixtures and write access to `QA/TestRuns`, `QA/Reports`, and `QA/Screenshots`. License/sign-in and application-bundle isolation must be qualified beforehand. A separate account alone does not disable machine-wide add-ins. The explicit reviewed-manifest policy below permits known machine-wide add-ins; all other registrations remain blocked. The script never disables installed add-ins or changes a production profile.

```powershell
Set-Location 'C:\Repato-Autonomous\Source'
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\QA\Invoke-CreateLevelsQA.ps1 -Action Install
$receipt = .\QA\Invoke-CreateLevelsQA.ps1 -Action Run -TimeoutSeconds 900
.\QA\Invoke-CreateLevelsQA.ps1 -Action Verify -ReceiptPath $receipt
```

`Install` copies the current DLL, available PDB/dependency metadata, and only the new QA manifest into the current RepatoQA profile, verifying the DLL hash. It preserves the existing Create Grids QA manifest. `Run` reports each preserved expired or malformed request under `Reports/`, never reuses or deletes it, then creates a fresh unique model, request ID, and receipt. The request expiry includes at least 1200 seconds of Revit startup grace; the controller wait timeout remains configurable. Revit 2025 starts only after the fresh request is written. The QA-only application consumes that request once on Idling, rejects expiry before mutations, checks provenance and file metadata, and invokes the same levels runner as the QA External Tools command. No production ribbon changes or network listener are involved.

`Verify` checks request/report correlation, test and fixture identity, artifact hash, fixed inputs, three distinct created IDs, all required passing assertions, rollback, unchanged model hashes, and all three PNG signatures/hashes. It does not use an arbitrary latest report. The receipt is saved beside `levels.request.json` as `levels.request.json.result.json`; supply that exact path to `Verify` if using another PowerShell session.

The script leaves Revit open on the disposable copy for inspection. Close without saving after review. It never kills a process or dismisses an unknown dialog. Timeout/crash stops the controller, preserves the run, and writes a controller failure report; it does not prove an in-flight native API operation was cancelled or rolled back. Expired requests are rejected before test mutations. No desktop screenshot is taken on timeout. Do not retry in the same session after uncertainty. Inspect/report evidence to Maya before disposing anything.

### Verification without launching Revit

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\QA\Test-CreateLevelsWorkflow.ps1
```

This exercises the actual PowerShell path and result-verification functions against explicitly synthetic files under the OS temporary directory. It does not open an RVT, load Revit, deploy a manifest, or generate evidence in the real QA folders. It covers valid verification plus rejection of path escapes, stale identities, wrong inputs, absent cleanup, failed assertions, and missing/altered screenshots. The regression also verifies that an expired request is reported and preserved while a later run can create a fresh request. These checks and a successful build do not constitute a Create Levels Revit QA pass.

## Reviewed add-in manifest policy

`QA/MachineWideAddins.allowlist.json` is the repository-controlled approval list. It contains exact absolute paths and SHA-256 hashes of reviewed manifest bytes, with a review date and reason. There are no wildcard, publisher-wide, directory-wide, environment-variable, or command-line bypass approvals. Missing/malformed policy, duplicate or invalid entries, hash mismatch, reparse points, and failed directory enumeration all block QA.

The initial reviewed set contains these ten files, exclusively under `C:\ProgramData\Autodesk\Revit\Addins\2025`:

- `0_Enscape.addin`
- `Autodesk.BatchPrint.addin`
- `Autodesk.Collaborate.addin`
- `Autodesk.eTransmitApplication.addin`
- `Autodesk.TotalCarbonAnalysis.addin`
- `Autodesk.WorksharingMonitor.Application.addin`
- `D5Converter.addin`
- `EvolveLAB.Veras.addin`
- `ExportViewSelectorApp.addin`
- `FormItConverter.addin`

An unlisted Autodesk add-in is blocked just like any other unknown add-in. Moving an approved filename into the user profile does not approve it. All ordinary user-profile manifests, including the production Repato and legacy Forma manifests, stay blocked. The only necessary bootstrap exceptions are `Repato.CreateLevels.TestRunner.addin` and `Repato.TestRunner.addin` in the QA profile, and their full contents must hash-match the corresponding repository QA source. A filename alone is insufficient.

### Enforcement and evidence

PowerShell scans both registration folders before Install and Run. Each preflight writes `Reports/isolation-<id>.json`, including when blocked. The request records its inventory and policy hash. The in-Revit gate independently rechecks before opening the test model and before test mutations, so invoking the QA command manually does not skip isolation checks. The result verifier requires the preflight and execution inventories and policy hashes to match; stale or missing evidence cannot pass.

`AddinIsolation` records the policy path/hash, enumeration/policy errors, overall decision, and every detected manifest's scope, full path, SHA-256, `Allowlisted` decision, and reason. This inventory is included in the levels report and controller failure reports. It records discovered registrations, not proof that every registered application loaded successfully. Each manifest may register multiple applications; the approval covers the complete hashed manifest.

### Review procedure

1. On a block, inspect the saved inventory and the exact manifest XML. Identify the publisher, application classes, assembly targets, and whether the registration belongs in the QA environment.
2. Maya reviews the change and obtains authorization for any newly approved add-in. Do not auto-enroll everything currently installed or merely copy a failing hash into the policy.
3. On the QA task branch, add or amend only the reviewed exact machine-wide path, current manifest SHA-256, review reason/date, and relevant documentation. Never add a user-profile or wildcard path to this policy. Review the Git diff and preserve the passing baseline.
4. Run the checks below and the approved add-in build. Commit the reviewed policy together with its associated safety changes when the implementation is accepted. Keep the policy and QA build from the same checkout.
5. Re-run Install/Run preflight. A manifest update invalidates its recorded hash and needs a fresh review. Approval of one file never authorizes newly discovered files.

### Scope and limitations

This permits explicitly reviewed coexistence; it does not provide a clean-room Revit session or certify third-party runtime behavior. Manifest hashes do not pin referenced DLLs, so vendor binary updates can occur without changing the manifest. Revit application bundles, dynamically loaded code, native plug-ins, licensing dialogs, and startup side effects are outside this two-directory manifest inventory. They still require environment qualification. Revit may load an add-in before the in-Revit gate runs; the PowerShell preflight is therefore mandatory for automated launches. Do not install/update add-ins during a QA run. Unknown dialogs, unexpected behavior, or incomplete reports still stop QA and must be reported to Maya.

Run all non-Revit checks from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\QA\Test-AddinIsolation.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\QA\Test-AddinIsolationDotNet.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\QA\Test-CreateLevelsWorkflow.ps1
dotnet build ".\Forma.RevitConnector.csproj" -c Release -p:RevitInstallDir="E:\revit\Revit 2025"
```

The isolation checks use temporary synthetic registration folders. They never edit installed add-ins or launch Revit. The C# harness compiles the actual pure policy source without Revit references; its temporary report stub only supplies the report container used by `RequireAllowed`.

## Repato Welcome supervised UI smoke test

The Welcome runner uses the existing controlled `CreateLevelsEmpty.rvt` fixture and invokes the same `RepatoWelcomeCommand` implementation as production. It adds no production ribbon button and performs no model operation. The run verifies `Result.Succeeded`, the exact `Repato` dialog title and message, a hashed desktop screenshot, the loaded assembly identity and SHA-256, unchanged document elements, and byte-for-byte equality between the disposable model, its pre-run hash, and the source fixture.

This is a **supervised UI smoke test**, not a fully unattended test. Tara must watch the known Welcome dialog, leave it visible long enough for the screenshot, then click **OK**. Any different or additional dialog is an unknown dialog and stops the run. The controller never dismisses UI, saves the model, closes Revit, or kills a timed-out process. Failed reports, run folders, launch logs, and startup logs are preserved for Maya.

After explicit Revit authorization, run under the `RepatoQA` Windows account with Revit closed:

```powershell
Set-Location 'C:\Repato-Autonomous\Source'
.\QA\Invoke-WelcomeSmokeQA.ps1 -Action Install
$receipt = .\QA\Invoke-WelcomeSmokeQA.ps1 -Action Run -TimeoutSeconds 900
.\QA\Invoke-WelcomeSmokeQA.ps1 -Action Verify -ReceiptPath $receipt
```
Tara dry runs may be performed by `rsgud` only when the approved QA paths are readable. Permission-denied paths are reported as structured validation failures; no permissions are changed. Real Tara execution requires the logged-in, unlocked `RepatoQA` interactive session.
Tara uses two independent manifests. Neil's artifact manifest and SHA-256 remain build evidence; the workflow-selected QA runner manifest (such as `Repato.CreateLevels.TestRunner.addin`) is resolved from the QA registration/source directory and is validated separately against the installed QA DLL, startup class, and policy. Their filenames are not required to match.
