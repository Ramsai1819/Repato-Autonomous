$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('maya-handoff-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force

$dry = New-MayaQaHandoff $root task-dry workflow-dry create-levels -DryRun
if ($dry.SideEffectsPerformed -or $dry.HandoffStatus -ne 'planned') { throw 'Dry-run mismatch.' }
$boot = New-MayaQaBootstrap create-levels ('run-' + [guid]::NewGuid().ToString('N')) $root ('task-' + [guid]::NewGuid().ToString('N'))
$request = New-MayaQaBuildRequest $boot.StoreRoot $boot.TaskId $boot.WorkflowId create-levels 'create-levels'
$data = Read-RepatoTaskStore $boot.StoreRoot
$task = Find-RepatoTask $data $boot.TaskId
$workflow = Get-DeployWorkflow $boot.StoreRoot $boot.TaskId $boot.WorkflowId
@(Invoke-RepatoWorkflowMutation $boot.StoreRoot $boot.TaskId $boot.WorkflowId $workflow.workflowRevision $task.revision { param($current) $current | Add-Member -NotePropertyName qaBuildStatus -NotePropertyValue 'requested' -Force; return $current })[-1] | Out-Null
$build = Invoke-MayaQaBuildExecute $boot.StoreRoot $boot.TaskId $boot.WorkflowId create-levels
if ($build.BuildStatus -ne 'succeeded') { throw 'Build did not succeed.' }
$run = New-MayaQaRun $boot.StoreRoot $boot.TaskId $boot.WorkflowId create-levels ('qa-' + [guid]::NewGuid().ToString('N'))
$handoff = New-MayaQaHandoff $boot.StoreRoot $boot.TaskId $boot.WorkflowId create-levels
if ($handoff.HandoffStatus -ne 'ready' -or [string]::IsNullOrWhiteSpace($handoff.HandoffId)) { throw 'Valid handoff was not created.' }
if (!(Test-Path -LiteralPath $handoff.ArtifactPath) -or !(Test-Path -LiteralPath $handoff.ManifestPath) -or !(Test-Path -LiteralPath $handoff.ModelPath) -or !(Test-Path -LiteralPath $handoff.SidecarPath)) { throw 'Handoff paths are incomplete.' }
$duplicate = $false
try { New-MayaQaHandoff $boot.StoreRoot $boot.TaskId $boot.WorkflowId create-levels | Out-Null } catch { $duplicate = $true }
if (-not $duplicate) { throw 'Duplicate handoff accepted.' }
$mismatchRoot = Join-Path ([IO.Path]::GetTempPath()) ('maya-handoff-mismatch-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $mismatchRoot -Force | Out-Null
$bad = $false
try { New-MayaQaHandoff $mismatchRoot $boot.TaskId $boot.WorkflowId create-levels | Out-Null } catch { $bad = $true }
if (-not $bad) { throw 'Mismatched store accepted.' }
$unsupported = $false
try { New-MayaQaHandoff $root ('task-' + [guid]::NewGuid().ToString('N')) ('workflow-' + [guid]::NewGuid().ToString('N')) create-plan-views -DryRun | Out-Null } catch { $unsupported = $true }
if (-not $unsupported) { throw 'Unsupported workflow accepted.' }
'Maya QA handoff checks passed: 8'
