$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationRecovery.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
$live=Join-Path $PSScriptRoot '../QA/MayaRuns/tasks.json';$liveHash=(Get-FileHash $live).Hash
$root=Join-Path $env:TEMP ('repato-cpv-canonical-'+[guid]::NewGuid().ToString('N'));New-Item $root -ItemType Directory|Out-Null
$script:count=0;$dirs=[Collections.Generic.List[string]]::new()
function Check($condition,$name){$script:count++;if(!$condition){throw "FAILED: $name"}}
function Reject([scriptblock]$action,$pattern){$script:count++;try{&$action;throw 'Unexpected acceptance'}catch{if($_.Exception.Message -notmatch $pattern){throw}}}
$id='task-bf61fe7f22d74df7a92599681da5919e'
$transport={param($q) if($q.operation -eq 'cpv-preparation-capabilities'){return [pscustomobject]@{schemaVersion=1;operation=$q.operation;supported=$true;user='RAMSAI\RepatoQA';sid='S-1-5-21-1031246752-3872016183-2454652381-1015';sessionId=1}};if($q.operation -eq 'cpv-preparation-status'){return $script:receipt};[pscustomobject]@{status='Executing'}}
function MakeStore {
    $store=Join-Path $root ([guid]::NewGuid().ToString('N'));New-Item $store -ItemType Directory|Out-Null
    Copy-Item $live (Join-Path $store 'tasks.json')
    Invoke-RepatoStoreMutation $store {param($d,$p)
        $t=Find-RepatoTask $d $id
        $q=@($t.approvalRequests|Where-Object {$_.requestId -ceq 'be82b860606d46598716e6fe191e6522' -and $_.PSObject.Properties['executionBinding'] -and $_.executionBinding -and $_.executionBinding.SchemaVersion -ceq 'maya-qa-canonical-execution-approval-v1'})
        if($q.Count -ne 1){throw 'Synthetic recovery fixture requires the bound historical approval.'}
        foreach($pending in @($t.approvalRequests|Where-Object status -ceq pending)){$pending.status='superseded'}
        $q[0].status='pending';if($q[0].PSObject.Properties.Name -notcontains 'expiresUtc'){$q[0]|Add-Member NoteProperty expiresUtc ([DateTimeOffset]::UtcNow.AddMinutes(-5).ToString('O'))}else{$q[0].expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('O')}
        $t.PSObject.Properties.Remove('cpvPreparationRecovery');$t.status='awaiting-approval';$t.workflowStage='approval';$t
    }|Out-Null
    $t=Find-RepatoTask (Read-RepatoTaskStore $store) $id;$pending=@($t.approvalRequests|Where-Object status -ceq pending)
    if($pending.Count -ne 1){throw 'Synthetic recovery fixture requires one pending approval in its copied store.'}
    [pscustomobject]@{Store=$store;Revision=$t.revision;Approval=$pending[0].requestId}
}
try {
    $c=MakeStore
    $active=MakeStore
    $script:statusCalls=0
    $statusTransport={param($q)$script:statusCalls++;[pscustomobject]@{status='Executing';operation='prepare-cpv-fixture';requestId=$q.requestId}}
    $notStarted=Get-CpvPreparationRecoveryStatus $c.Store $id -Transport $statusTransport
    Check ($notStarted.status -ceq 'NotStarted' -and $notStarted.taskId -ceq $id -and $notStarted.sideEffectPerformed -eq $false -and $script:statusCalls -eq 0) 'absent recovery marker returns not-started without transport'
    $nullRecord=MakeStore
    Invoke-RepatoStoreMutation $nullRecord.Store {param($d,$p)$t=Find-RepatoTask $d $id;$t|Add-Member NoteProperty cpvPreparationRecovery $null;$t}|Out-Null
    $nullStatus=Get-CpvPreparationRecoveryStatus $nullRecord.Store $id -Transport $statusTransport
    Check ($nullStatus.status -ceq 'NotStarted' -and $nullStatus.sideEffectPerformed -eq $false -and $script:statusCalls -eq 0) 'null recovery marker returns not-started without transport'
    $validRecord=MakeStore
    $validRequestId=[guid]::NewGuid().ToString('N')
    Invoke-RepatoStoreMutation $validRecord.Store {param($d,$p)$t=Find-RepatoTask $d $id;$t|Add-Member NoteProperty cpvPreparationRecovery ([pscustomobject]@{Request=[pscustomobject]@{requestId=$validRequestId}});$t}|Out-Null
    $validStatus=Get-CpvPreparationRecoveryStatus $validRecord.Store $id -Transport $statusTransport
    Check ($validStatus.status -ceq 'Executing' -and $validStatus.requestId -ceq $validRequestId -and $script:statusCalls -eq 1) 'valid recovery marker queries its request status'
    $malformedRecord=MakeStore
    Invoke-RepatoStoreMutation $malformedRecord.Store {param($d,$p)$t=Find-RepatoTask $d $id;$t|Add-Member NoteProperty cpvPreparationRecovery ([pscustomobject]@{Request=[pscustomobject]@{}});$t}|Out-Null
    Reject {Get-CpvPreparationRecoveryStatus $malformedRecord.Store $id -Transport $statusTransport} 'malformed.*requestId'
    Check ($script:statusCalls -eq 1) 'malformed recovery marker is not sent to agent'
    $invalidIdRecord=MakeStore
    Invoke-RepatoStoreMutation $invalidIdRecord.Store {param($d,$p)$t=Find-RepatoTask $d $id;$t|Add-Member NoteProperty cpvPreparationRecovery ([pscustomobject]@{Request=[pscustomobject]@{requestId='not-a-guid'}});$t}|Out-Null
    Reject {Get-CpvPreparationRecoveryStatus $invalidIdRecord.Store $id -Transport $statusTransport} 'malformed.*requestId'
    Check ($script:statusCalls -eq 1) 'invalid request id is not sent to agent'
    Invoke-RepatoStoreMutation $active.Store {param($d,$p)$t=Find-RepatoTask $d $id;@($t.approvalRequests|Where-Object status -ceq pending)[0].expiresUtc=[DateTimeOffset]::UtcNow.AddHours(1).ToString('O');$t}|Out-Null
    Reject {New-CpvPreparationRecovery $active.Store $id $active.Revision $active.Approval -Transport $transport} 'expired pending'
    Reject {New-CpvPreparationRecovery $c.Store $id ($c.Revision-1) $c.Approval -Transport $transport} 'stale'
    Reject {New-CpvPreparationRecovery $c.Store $id $c.Revision $c.Approval -Transport {param($q)[pscustomobject]@{supported=$false}}} 'installation required'
    $r=New-CpvPreparationRecovery $c.Store $id $c.Revision $c.Approval -Transport $transport
    $t=Find-RepatoTask (Read-RepatoTaskStore $c.Store) $id
    Check ($t.revision -eq ($c.Revision+1) -and @($t.approvalRequests|Where-Object status -ceq pending).Count -eq 0) 'begin archives expired approval atomically'
    $retry=New-CpvPreparationRecovery $c.Store $id $c.Revision $c.Approval -Transport $transport
    Check ($retry.Request.requestId -ceq $r.Request.requestId) 'begin retry retains one request'
    $null=Send-CpvPreparationRecovery $c.Store $id $t.revision -Transport $transport
    $t=Find-RepatoTask (Read-RepatoTaskStore $c.Store) $id
    Reject {Send-CpvPreparationRecovery $c.Store $id $t.revision -Transport $transport} 'invalid'
    $script:receipt=[pscustomobject]@{status='OutcomeUnknown'}
    Reject {Complete-CpvPreparationRecovery $c.Store $id $t.revision -Transport $transport} 'ambiguous'
    $q=$r.Request;$dir=Join-Path $env:TEMP ('cpv-preparation-'+$q.runId);New-Item $dir -ItemType Directory|Out-Null;$dirs.Add($dir)
    $model=Join-Path $dir 'model.rvt';[IO.File]::WriteAllText($model,'synthetic prepared disposable model')
    $modelHash=(Get-FileHash $model).Hash;$requestPath=Join-Path $dir ('tara-'+$q.attemptId+'.request.json');$resultPath=$requestPath+'.preparation.json'
    [pscustomobject]@{fixtureId='CreatePlanViewsEmpty';sourceSha256=$r.OldBinding.FixtureSha256}|ConvertTo-Json|Set-Content ($model+'.fixture.json')
    [pscustomobject]@{operation='prepare-disposable-create-plan-views-fixture';requestId=$q.attemptId;taskId=$id;workflowId=$q.workflowId;attemptId=$q.attemptId;runId=$q.runId;requestPath=$requestPath;modelPath=$model;modelSha256=$r.OldBinding.FixtureSha256;outputPath=$resultPath;expiresUtc=$q.expiresUtc}|ConvertTo-Json|Set-Content $requestPath
    [pscustomobject]@{Status='Passed';TaskId=$id;WorkflowId=$q.workflowId;AttemptId=$q.attemptId;RunId=$q.runId;Operation='prepare-disposable-create-plan-views-fixture';ModelPath=$model;SourceModelSha256=$r.OldBinding.FixtureSha256;PreparedModelSha256=$modelHash;Levels=@(@{Name='0';ElevationMeters=0;ElementId=1},@{Name='1';ElevationMeters=4;ElementId=2},@{Name='2';ElevationMeters=7.8;ElementId=3})}|ConvertTo-Json -Depth 6|Set-Content $resultPath
    $script:receipt=[pscustomobject]@{schemaVersion=1;operation='prepare-cpv-fixture';requestId=$q.requestId;taskId=$id;workflowId=$q.workflowId;attemptId=$q.attemptId;runId=$q.runId;status='Passed';user='RAMSAI\RepatoQA';sid='S-1-5-21-1031246752-3872016183-2454652381-1015';sessionId=1;cleanupVerified=$true;rollbackStatus='CommittedDisposableFixtureOnly';candidateSha256=$q.candidateEvidence.CandidateDllSha256;manifestSha256=$q.candidateEvidence.RunnerManifestSha256;modelPath=$model;modelSha256=$modelHash;requestPath=$requestPath;requestSha256=(Get-FileHash $requestPath).Hash;resultPath=$resultPath;resultSha256=(Get-FileHash $resultPath).Hash;expiresUtc=$q.expiresUtc}
    $side=Get-Content ($model+'.fixture.json') -Raw|ConvertFrom-Json
    foreach($pair in @(@('preparedModelSha256','modelSha256'),@('fixturePreparationRequestPath','requestPath'),@('fixturePreparationRequestSha256','requestSha256'),@('fixturePreparationResultPath','resultPath'),@('fixturePreparationResultSha256','resultSha256'),@('fixturePreparationAttemptId','attemptId'),@('fixturePreparationRunId','runId'))){$side|Add-Member NoteProperty $pair[0] $script:receipt.($pair[1])}
    $side|ConvertTo-Json|Set-Content ($model+'.fixture.json')
    $script:receipt.cleanupVerified=$false
    Reject {Complete-CpvPreparationRecovery $c.Store $id $t.revision -Transport $transport} 'cleanup'
    $script:receipt.cleanupVerified=$true;$script:receipt.attemptId=[guid]::NewGuid().ToString('N')
    Reject {Complete-CpvPreparationRecovery $c.Store $id $t.revision -Transport $transport} 'identity mismatch'
    $script:receipt.attemptId=$q.attemptId
    $originalExpiry=$script:receipt.expiresUtc;$script:receipt.expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('O')
    Reject {Complete-CpvPreparationRecovery $c.Store $id $t.revision -Transport $transport} 'expiry changed'
    $script:receipt.expiresUtc=$originalExpiry
    $approval=Complete-CpvPreparationRecovery $c.Store $id $t.revision -Transport $transport
    $after=Find-RepatoTask (Read-RepatoTaskStore $c.Store) $id
    Check (@($after.approvalRequests|Where-Object status -ceq pending).Count -eq 1 -and $approval.requiredLevel -ceq 'user' -and $approval.executionBinding.RunId -ceq $q.runId) 'exactly one bound human approval'
    $again=Complete-CpvPreparationRecovery $c.Store $id $after.revision -Transport $transport
    Check ($again.requestId -ceq $approval.requestId -and (Find-RepatoTask (Read-RepatoTaskStore $c.Store) $id).revision -eq $after.revision) 'completion retry creates no duplicate or revision'
    Check (!$approval.decidedBy -and !$approval.consumedUtc) 'approval remains undecided and unconsumed'
    Check ($approval.executionBinding.FixturePreparationEvidence.AttemptId -ceq $q.attemptId -and $approval.executionBinding.ModelSha256 -ceq $modelHash -and $approval.bindingHash.Length -eq 64) 'approval binds fresh attempt and verified model hash'
    $workflow=@($after.deploymentWorkflows|Where-Object workflowId -ceq $q.workflowId)[0]
    Check (!$workflow.qaHandoff -and !$workflow.qaReportPath -and $after.cpvPreparationRecovery.PriorWorkflow.qaRunId -ceq $r.OldBinding.RunId) 'stale handoff/report cleared with original workflow archived'
    $failed=MakeStore;$failedRequest=[pscustomobject]@{schemaVersion=1;operation='prepare-cpv-fixture';requestId=[guid]::NewGuid().ToString('N');taskId=$id;workflowId=[guid]::NewGuid().ToString('N');attemptId=[guid]::NewGuid().ToString('N');runId=[guid]::NewGuid().ToString('N')}
    $requestHash=& (Get-Module Repato.CpvPreparationRecovery) {param($x)Get-CpvRecoveryHash $x} $failedRequest
    Invoke-RepatoStoreMutation $failed.Store {param($d,$p)$t=Find-RepatoTask $d $id;foreach($pending in @($t.approvalRequests|Where-Object status -ceq pending)){$pending.status='superseded'};$t|Add-Member NoteProperty cpvPreparationRecovery ([pscustomobject]@{Status='Dispatching';Request=$failedRequest;RequestHash=$requestHash;Receipt=$null});$t}|Out-Null
    $script:reconcileCalls=0;$script:agentReceipt=[pscustomobject]@{schemaVersion=1;operation='prepare-cpv-fixture';requestId=$failedRequest.requestId;taskId=$id;workflowId=$failedRequest.workflowId;attemptId=$failedRequest.attemptId;runId=$failedRequest.runId;status='FailedReconciled';failureCode='preparation-exited-without-result';cleanupVerified=$false;rollbackStatus='NotRequired-NoPreparationResult'}
    $reconcileTransport={param($q)$script:reconcileCalls++;if($q.operation -cne 'cpv-preparation-reconcile-failed'){throw 'Wrong reconciliation operation.'};$script:agentReceipt}
    Reject {Set-CpvPreparationRecoveryFailedReconciled $failed.Store $id ($failed.Revision-1) -Transport $reconcileTransport} 'revision is stale'
    Check ($script:reconcileCalls -eq 0) 'stale revision does not contact agent'
    $failedTask=Find-RepatoTask (Read-RepatoTaskStore $failed.Store) $id
    Reject {Set-CpvPreparationRecoveryFailedReconciled $failed.Store $id $failedTask.revision -Transport {param($q)throw 'response lost after agent persisted terminal receipt'}} 'response lost'
    $recovered=Set-CpvPreparationRecoveryFailedReconciled $failed.Store $id $failedTask.revision -Transport $reconcileTransport
    $terminal=Find-RepatoTask (Read-RepatoTaskStore $failed.Store) $id
    Check ($recovered.Status -ceq 'FailedReconciled' -and $terminal.cpvPreparationRecovery.Receipt.status -ceq 'FailedReconciled' -and @($terminal.approvalRequests|Where-Object status -ceq pending).Count -eq 0) 'lost response reconciles same terminal failure without approval'
    $canonicalRevision=$terminal.revision
    $same=Set-CpvPreparationRecoveryFailedReconciled $failed.Store $id ($canonicalRevision-1) -Transport $reconcileTransport
    Check ($same.Status -ceq 'FailedReconciled' -and (Find-RepatoTask (Read-RepatoTaskStore $failed.Store) $id).revision -eq $canonicalRevision) 'duplicate reconciliation is idempotent'
    Reject {Set-CpvPreparationRecoveryFailedReconciled $failed.Store $id $canonicalRevision -Transport {param($q)$x=$script:agentReceipt|Select-Object *;$x.runId=[guid]::NewGuid().ToString('N');$x}} 'identity mismatch'
    Check ((Get-FileHash $live).Hash -ceq $liveHash) 'live canonical store unchanged'
    "PASS: $script:count canonical CPV recovery assertions; isolated copied store, synthetic preparation; Revit launched=false."
} finally {
    foreach($p in @($dirs)+@($root)){if([IO.Path]::GetFullPath($p).StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\')){Remove-Item -LiteralPath $p -Recurse -Force}}
}
