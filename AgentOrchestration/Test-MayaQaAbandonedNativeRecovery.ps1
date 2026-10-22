$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
$root=Join-Path $env:TEMP ('maya-qa-recovery-'+[guid]::NewGuid().ToString('N'));$store=Join-Path $root 'store';$target=Join-Path $root 'target';New-Item -ItemType Directory -Path $target|Out-Null
try {
    $artifact=Join-Path $target 'artifact.bin';$manifest=Join-Path $target 'manifest.addin';Set-Content $artifact 'artifact';Set-Content $manifest 'manifest'
    $taskId='recovery-'+[guid]::NewGuid().ToString('N').Substring(0,12);New-RepatoTask $store $taskId 'Recovery regression' 'synthetic' 'fix/test'|Out-Null
    $plan=New-DeployPlan $store $taskId $artifact $manifest -TargetRoot $target;$w=New-DeployWorkflow $store $plan
    $d=Read-RepatoTaskStore $store;$t=Find-RepatoTask $d $taskId
    $stale=@{qaReportPath='stale';qaReportSha256='stale';qaEvidence=[pscustomobject]@{NativeRunId='stale'};qaVerificationStatus='verified';qaCompletionStatus='completed';qaCompletedUtc='stale';nativeRunId='stale';nativeRunStatus='passed';nativeRunEvidence='stale';nativeRunStartedUtc='stale';nativeRunFinishedUtc='stale'}
    $mutation=Invoke-RepatoWorkflowMutation $store $taskId $w.workflowId $w.workflowRevision $t.revision {param($x)foreach($p in $stale.Keys){$x|Add-Member -NotePropertyName $p -NotePropertyValue $stale[$p] -Force};$x.stage='prepared';$x.status='prepared';$x};$w=$mutation.Workflow
    $before=Get-Content (Join-Path $store 'tasks.json') -Raw
    $replacement='replacement-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $r=Recover-MayaQaAbandonedNativeExecution $store $taskId $w.workflowId 'create-levels' $replacement
    if(!(Test-Path -LiteralPath $r.ModelPath -PathType Leaf) -or !(Test-Path -LiteralPath $r.SidecarPath -PathType Leaf)){throw 'Replacement model or sidecar was not created.'}
    $fixture=Join-Path $PSScriptRoot '..\QA\Fixtures\CreateLevelsEmpty.rvt';$hash=(Get-FileHash $fixture -Algorithm SHA256).Hash;$side=Get-Content $r.SidecarPath -Raw|ConvertFrom-Json
    if($side.fixtureId -cne 'CreateLevelsEmpty' -or $side.sourceSha256 -ine $hash -or (Get-FileHash $r.ModelPath -Algorithm SHA256).Hash -ine $hash -or $r.FixtureSha256 -ine $hash){throw 'Replacement fixture contents or hashes are invalid.'}
    $after=Get-DeployWorkflow $store $taskId $w.workflowId
    foreach($p in 'qaReportPath','qaReportSha256','qaEvidence','qaVerificationStatus','qaCompletionStatus','qaCompletedUtc','nativeRunId','nativeRunStatus','nativeRunEvidence','nativeRunStartedUtc','nativeRunFinishedUtc'){if($after.PSObject.Properties.Name -contains $p -and $after.$p){throw "Stale field survived recovery: $p"}}
    if($after.qaRunId -cne $replacement -or $after.qaModelPath -cne $r.ModelPath -or $after.qaSidecarPath -cne $r.SidecarPath -or $after.stage -ne 'prepared'){throw 'Replacement execution identity was not persisted.'}
    if((Get-Content (Join-Path $store 'tasks.json') -Raw) -eq $before){throw 'Synthetic Store was not updated.'}
    'Maya QA abandoned-native recovery checks passed: 10'
} finally {if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}}
