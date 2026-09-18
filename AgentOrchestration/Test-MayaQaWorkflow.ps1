$ErrorActionPreference='Stop'; Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force; Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force; Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
$defs=@('welcome-smoke','create-grids-world-axis-v1','create-levels','grid-bubble-visibility-v1','grid-bubble-offset-v1','grid-resequence-v1'); foreach($id in $defs){if(!(Get-MayaQaWorkflowDefinition $id)){throw "Missing definition: $id"}}
try {
    $root=Join-Path $env:TEMP ('maya-qa-coordinator-'+[guid]::NewGuid().ToString('N'));$store=Join-Path $root 'store';$target=Join-Path $root 'target';New-Item -ItemType Directory -Path $target|Out-Null
    $artifact=Join-Path $target 'artifact.bin';$manifest=Join-Path $target 'manifest.addin';Set-Content $artifact 'artifact';Set-Content $manifest 'manifest'
    $taskId='qa-coordinator-'+[guid]::NewGuid().ToString('N').Substring(0,12);New-RepatoTask $store $taskId 'QA coordinator' 'fixture test' 'feat/test'|Out-Null
    $plan=New-DeployPlan $store $taskId $artifact $manifest -TargetRoot $target;$w=New-DeployWorkflow $store $plan
    $run=New-MayaQaRun $store $taskId $w.workflowId 'create-levels' ('run-'+[guid]::NewGuid().ToString('N').Substring(0,8));if($run.FixtureId -ne 'CreateLevelsEmpty' -or !(Test-Path $run.SidecarPath)){throw 'QA run preparation failed.'}
    $rejected=$false;try{Get-MayaQaWorkflowDefinition 'wrong-id'|Out-Null}catch{$rejected=$true};if(!$rejected){throw 'Wrong ID accepted.'}
    $dry=New-MayaQaRun $store $taskId $w.workflowId 'create-levels' 'dry-run' -DryRun;if($dry.SideEffectsPerformed){throw 'Dry-run performed side effects.'}
    'Maya QA workflow coordinator checks passed: 14'
} finally { if($root -and (Test-Path $root)){Remove-Item $root -Recurse -Force} }
