# Safe Revit QA workspace

Revit execution is still disabled until a dedicated fixture and Test Runner are created. Their creation alone does not enable execution: Maya must also confirm the safety prerequisites and obtain explicit user authorization under the root AGENTS.md rules. Do not launch Revit, send commands to an existing session, or deploy an add-in yet.

## Allowed models

Tara may test only copied, local, non-workshared `.rvt` fixtures created specifically for QA. Never test a production, client, company, cloud, central, or workshared model, including a copy or detached version of such a model. Copying a prohibited model does not make it a safe fixture.

`Fixtures/` contains controlled test assets, never an active work project. Each future fixture must have a documented test purpose, provenance, expected state, and verified local, non-workshared status. Preserve the source fixture and test only a fresh copy in `TestRuns/`. This setup contains placeholders only; it supplies neither a fixture nor a Test Runner.

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
