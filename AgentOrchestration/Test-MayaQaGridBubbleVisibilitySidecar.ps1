$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
$store=Join-Path ([IO.Path]::GetTempPath()) ('maya-grid-sidecar-'+[guid]::NewGuid().ToString('N'));$b=New-MayaQaBootstrap grid-bubble-visibility-v1 run-grid-sidecar $store
$run=New-MayaQaRun $b.StoreRoot $b.TaskId $b.WorkflowId grid-bubble-visibility-v1 run-grid-sidecar
if($run.ModelPath -notlike 'C:\Repato-Autonomous\Source\QA\TestRuns\*'){throw 'Coordinator did not use canonical Source QA TestRuns.'}
$side=Get-Content -LiteralPath $run.SidecarPath -Raw|ConvertFrom-Json
$expected=@('A','B','C','D','1','2','3','4')
if($side.fixtureId -cne 'GridBubbleVisibilityEmpty' -or $side.sourceSha256 -ine $run.FixtureSha256 -or (@($side.requiredGridNames)-join '|') -cne ($expected -join '|')){throw 'Grid Bubble Visibility sidecar grid set mismatch.'}
$bad=$false;try{if((Get-Content $run.SidecarPath -Raw|ConvertFrom-Json).requiredGridNames.Count -ne 8){throw 'missing'}}catch{$bad=$true};if($bad){throw 'Required grid set missing.'}
'Maya QA Grid Bubble Visibility sidecar checks passed: 4'
