$ErrorActionPreference='Stop'
Set-ExecutionPolicy -Scope Process Bypass -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue

$root=Join-Path ([IO.Path]::GetTempPath()) ('canonical-qa-ready-'+[guid]::NewGuid().ToString('N'))
$taskId='task-canonical-qa-ready';$workflowId='workflow-canonical-qa-ready';$qaId='create-plan-views-v1'
function New-State([string]$approvalState='consumed',[switch]$BadModelHash) {
    $store=Join-Path $root ([guid]::NewGuid().ToString('N'))
    New-RepatoTask $store $taskId 'QA transition' 'canonical transition regression' 'qa/canonical-transition'|Out-Null
    $modelRoot=Join-Path $store 'TestRuns';New-Item -ItemType Directory -Path $modelRoot -Force|Out-Null
    $model=Join-Path $modelRoot 'model.rvt';[IO.File]::WriteAllText($model,'prepared disposable model')
    $hash=(Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash
    $sidecar=$model+'.fixture.json';([ordered]@{fixtureId='CreatePlanViewsEmpty';sourceSha256=('A'*64)}|ConvertTo-Json)|Set-Content -LiteralPath $sidecar
    Invoke-RepatoStoreMutation $store {
        param($data,$preview)
        $task=Find-RepatoTask $data $taskId;$task.status='in-progress';$task.workflowStage='build-checks'
        $task|Add-Member NoteProperty deploymentWorkflows ([object[]]@([pscustomobject]@{taskId=$taskId;workflowId=$workflowId;qaWorkflowId=$qaId;workflowRevision=1;stage='planned';qaRunId=([guid]::NewGuid().ToString('N'));qaModelPath=$model;qaSidecarPath=$sidecar;qaDisposableModelSha256=$(if($BadModelHash){'F'*64}else{$hash});qaFixtureId='CreatePlanViewsEmpty';qaFixtureSha256=('A'*64)})) -Force
        if($approvalState -eq 'consumed'){$task|Add-Member NoteProperty approvalRequests ([object[]]@([pscustomobject]@{requestId='history-approved-consumed';action='qa-run';status='approved';consumedUtc='2026-10-14T03:46:46Z'})) -Force}
        elseif($approvalState -eq 'active'){$task|Add-Member NoteProperty approvalRequests ([object[]]@([pscustomobject]@{requestId='active-approved';action='qa-run';status='approved';consumedUtc=$null;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(10).ToString('O')})) -Force}
        elseif($approvalState -eq 'expired'){$task|Add-Member NoteProperty approvalRequests ([object[]]@([pscustomobject]@{requestId='expired-approved';action='qa-run';status='approved';consumedUtc=$null;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(-10).ToString('O')})) -Force}
        elseif($approvalState -eq 'pending'){$task|Add-Member NoteProperty approvalRequests ([object[]]@([pscustomobject]@{requestId='pending';action='qa-run';status='pending';consumedUtc=$null;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(10).ToString('O')})) -Force}
        elseif($approvalState -eq 'malformed'){$task|Add-Member NoteProperty approvalRequests ([object[]]@([pscustomobject]@{requestId='malformed';action='qa-run';status='approved';consumedUtc=$null;expiresUtc='not-a-date'})) -Force}
        $task
    }|Out-Null
    [pscustomobject]@{Store=$store;Task=(Find-RepatoTask (Read-RepatoTaskStore $store) $taskId)}
}
function Invoke-Transition($state,[long]$revision) {
    Update-RepatoTask $state.Store $taskId 'in-progress' 'qa' 'Maya' $null $null -ExpectedTaskRevision $revision -ExpectedWorkflowId $workflowId -ExpectedWorkflowRevision 1 -ExpectedQaWorkflowId $qaId
}
try {
    $consumed=New-State
    $priorApprovals=ConvertTo-Json -InputObject $consumed.Task.approvalRequests -Depth 8 -Compress
    $updated=Invoke-Transition $consumed ([long]$consumed.Task.revision)
    if($updated.status -cne 'in-progress' -or $updated.workflowStage -cne 'qa'){throw 'Valid consumed-history transition did not enter QA.'}
    if((ConvertTo-Json -InputObject $updated.approvalRequests -Depth 8 -Compress) -cne $priorApprovals){throw 'Consumed approval history changed during transition.'}

    $expired=New-State 'expired'
    $expiredSnapshot=ConvertTo-Json -InputObject $expired.Task.approvalRequests -Depth 8 -Compress
    $expiredUpdated=Invoke-Transition $expired ([long]$expired.Task.revision)
    if($expiredUpdated.workflowStage -cne 'qa' -or (ConvertTo-Json -InputObject $expiredUpdated.approvalRequests -Depth 8 -Compress) -cne $expiredSnapshot){throw 'Expired unconsumed approval history was not preserved while allowing the fresh QA transition.'}

    foreach($stateName in 'active','pending','malformed') {
        $blocked=New-State $stateName;$beforeRevision=[long]$blocked.Task.revision;$rejected=$false
        try{Invoke-Transition $blocked $beforeRevision|Out-Null}catch{$rejected=$true}
        $after=Find-RepatoTask (Read-RepatoTaskStore $blocked.Store) $taskId
        if(!$rejected -or [long]$after.revision -ne $beforeRevision){throw "$stateName authorization was not rejected without mutation."}
    }
    $bad=New-State consumed -BadModelHash;$badRevision=[long]$bad.Task.revision;$badRejected=$false
    try{Invoke-Transition $bad $badRevision|Out-Null}catch{$badRejected=$_.Exception.Message -match 'prerequisites are stale'}
    if(!$badRejected){throw 'Mismatched prepared model hash was not rejected.'}
    $stale=New-State consumed;$staleRejected=$false
    try{Invoke-Transition $stale ([long]$stale.Task.revision+1)|Out-Null}catch{$staleRejected=$_.Exception.Message -match 'Task compare-and-swap revision changed'}
    if(!$staleRejected){throw 'Stale task revision was not rejected.'}

    [pscustomobject]@{Status='PASS';ConsumedApprovalHistoryPreserved=$true;ExpiredApprovalPreservedAndIgnored=$true;ActiveApprovedRejected=$true;PendingRejected=$true;MalformedExpiryRejected=$true;InvalidModelRejected=$true;StaleRevisionRejected=$true;RevitLaunched=$false}|ConvertTo-Json -Compress
} finally {if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}}
