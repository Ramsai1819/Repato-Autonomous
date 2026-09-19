# Maya QA workflow coordinator

The coordinator supports exactly six fixture-only QA workflows:

| Workflow ID | Fixture | Native test ID |
|---|---|---|
| `welcome-smoke` | `CreateLevelsEmpty` | `welcome-supervised-dialog-v1` |
| `create-grids-world-axis-v1` | `CreateGridsEmptyPlan` | `create-grids-world-axis-v1` |
| `create-levels` | `CreateLevelsEmpty` | `create-levels-elevations-v1` |
| `grid-bubble-visibility-v1` | `GridBubbleVisibilityEmpty` | `grid-bubble-visibility-v1` |
| `grid-bubble-offset-v1` | `GridBubbleOffsetEmpty` | `grid-bubble-offset-v1` |
| `grid-resequence-v1` | `GridResequenceEmpty` | `grid-resequence-all-directions-v1` |

Create Plan Views is not supported by this coordinator.

## Boundaries

`qa-bootstrap` and `qa-run-plan` create disposable fixture state only. `qa-report-verify` accepts a report produced by a separately supervised Revit run and verifies its canonical model path, fixture identity/hash, native test ID, assertions, status, rollback state, and report hash. `qa-complete` persists verified/completed evidence. The coordinator never launches Revit, performs real deployment, edits production models, or deletes source fixtures.

## Workflow

```text
qa-bootstrap
  -> qa-run-plan
  -> supervised Revit execution (separate, explicit operator step)
  -> qa-report-verify
  -> qa-complete
```

Machine-readable discovery is available through `qa-catalog`, `qa-help`, and `qa-capabilities`. `qa-status` reports deployment and QA state for a persisted workflow. Every operation emits one compact JSON object on stdout; failures are written to stderr with a non-zero exit code.

Example discovery:

```powershell
& .\AgentOrchestration\Invoke-MayaQaWorkflow.ps1 -Operation qa-help
& .\AgentOrchestration\Invoke-MayaQaWorkflow.ps1 -Operation qa-catalog
```
