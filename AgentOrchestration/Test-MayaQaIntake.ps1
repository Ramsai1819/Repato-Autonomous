$ErrorActionPreference = 'Stop'
$cli = Join-Path $PSScriptRoot 'Invoke-MayaQaWorkflow.ps1'
function Invoke-Intake([string[]] $CliArgs) {
$o = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $cli @CliArgs 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Intake child failed.' }
($o -join "`n") | ConvertFrom-Json
}
$ids = @('welcome-smoke','create-grids-world-axis-v1','create-levels','grid-bubble-visibility-v1','grid-bubble-offset-v1','grid-resequence-v1')
foreach ($id in $ids) {
$r = Invoke-Intake @('-Operation','qa-intake','-TaskId','task-test-01','-WorkflowId','workflow-test-01','-QaWorkflowId',$id,'-UserRequest',$id,'-DryRun')
if ($r.QaWorkflowId -ne $id -or $r.SideEffectsPerformed -or $r.NextAllowedOperation -ne 'qa-run-plan') { throw "Valid intake mismatch: $id" }
}
$failed = $false; try { Invoke-Intake @('-Operation','qa-intake','-TaskId','task-test-01','-WorkflowId','workflow-test-01','-QaWorkflowId','create-plan-views','-UserRequest','create-plan-views','-DryRun') | Out-Null } catch { $failed = $true }; if (-not $failed) { throw 'Create Plan Views accepted.' }
$failed = $false; try { Invoke-Intake @('-Operation','qa-intake','-TaskId','task-test-01','-WorkflowId','workflow-test-01','-QaWorkflowId','create-levels','-UserRequest','create-levels grid-resequence-v1','-DryRun') | Out-Null } catch { $failed = $true }; if (-not $failed) { throw 'Ambiguous request accepted.' }
$failed = $false; try { Invoke-Intake @('-Operation','qa-intake','-TaskId','bad identity!','-WorkflowId','workflow-test-01','-QaWorkflowId','create-levels','-UserRequest','create-levels','-DryRun') | Out-Null } catch { $failed = $true }; if (-not $failed) { throw 'Invalid task identity accepted.' }
'Maya QA intake checks passed: 16'
