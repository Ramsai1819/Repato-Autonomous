$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('maya-build-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
$dry = New-MayaQaBuildRequest $root task-test-01 workflow-test-01 create-levels create-levels -DryRun
if ($dry.SideEffectsPerformed -or $dry.BuildStatus -ne 'requested') { throw 'Dry-run build request mismatch.' }
$boot = New-MayaQaBootstrap create-levels run-build-test $root task-test-01
$req = New-MayaQaBuildRequest $boot.StoreRoot $boot.TaskId $boot.WorkflowId create-levels create-levels
if ($req.BuildStatus -ne 'requested' -or [string]::IsNullOrWhiteSpace($req.BuildRequestId) -or -not $req.SideEffectsPerformed) { throw 'Build request mismatch.' }
$dup = $false; try { New-MayaQaBuildRequest $boot.StoreRoot $boot.TaskId $boot.WorkflowId create-levels create-levels | Out-Null } catch { $dup = $true }; if (-not $dup) { throw 'Duplicate build request accepted.' }
$missing = $false; try { New-MayaQaBuildRequest $root missing-task missing-workflow create-levels create-levels | Out-Null } catch { $missing = $true }; if (-not $missing) { throw 'Missing intake accepted.' }
$unsupported = $false; try { New-MayaQaBuildRequest $root task-test-01 workflow-test-01 create-plan-views create-plan-views -DryRun | Out-Null } catch { $unsupported = $true }; if (-not $unsupported) { throw 'Unsupported workflow accepted.' }
'Maya QA build-request checks passed: 8'
