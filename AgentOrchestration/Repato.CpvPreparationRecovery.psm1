Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue

function Invoke-CpvPreparationTransport {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Request)
    $pipe=[IO.Pipes.NamedPipeClientStream]::new('.','Repato\QaLaunch',[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
    $reader=$null;$writer=$null
    try {
        $pipe.Connect(5000)
        $writer=[IO.StreamWriter]::new($pipe,[Text.UTF8Encoding]::new($false),1024,$true);$writer.AutoFlush=$true
        if(!$writer.WriteLineAsync(($Request|ConvertTo-Json -Depth 20 -Compress)).Wait(5000)){throw 'Preparation write timed out; reconcile status, never resend blindly.'}
        $reader=[IO.StreamReader]::new($pipe,[Text.Encoding]::UTF8,$false,1024,$true)
        $read=$reader.ReadLineAsync();if(!$read.Wait(10000)){throw 'Preparation response timed out; query the same request identity.'}
        if(!$read.Result -or $read.Result.Length -gt 32768){throw 'Preparation response missing or oversized.'}
        $read.Result|ConvertFrom-Json
    } finally {if($reader){$reader.Dispose()};if($writer){$writer.Dispose()};$pipe.Dispose()}
}
function Get-CpvPreparationCapabilities {
    [CmdletBinding()]
    param([scriptblock]$Transport)
    $q=[pscustomobject]@{schemaVersion=1;operation='cpv-preparation-capabilities'}
    $r=if($Transport){& $Transport $q}else{Invoke-CpvPreparationTransport $q}
    if(!$r -or $r.PSObject.Properties.Name -notcontains 'supported' -or $r.supported -ne $true -or
        $r.operation -cne $q.operation -or $r.user -ine 'RAMSAI\RepatoQA' -or $r.sid -cne 'S-1-5-21-1031246752-3872016183-2454652381-1015' -or $r.sessionId -le 0){throw 'Installed Launch Agent does not advertise authenticated CPV preparation support; validated runtime installation required.'}
    $r
}
function Get-CpvRecoveryHash($Value) {
    $bytes=[Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 20 -Compress));$sha=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')}finally{$sha.Dispose()}
}
function New-CpvPreparationRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][long]$ExpectedTaskRevision,
        [Parameter(Mandatory)][string]$ExpiredApprovalId,[scriptblock]$Transport)
    $null=Get-CpvPreparationCapabilities -Transport $Transport
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    if($task.PSObject.Properties.Name -contains 'cpvPreparationRecovery' -and $task.cpvPreparationRecovery){
        if($task.cpvPreparationRecovery.ExpiredApprovalId -cne $ExpiredApprovalId){throw 'A different preparation recovery already exists.'}
        return $task.cpvPreparationRecovery
    }
    if($task.revision -ne $ExpectedTaskRevision -or $task.status -cne 'awaiting-approval' -or $task.workflowStage -cne 'approval'){throw 'Recovery revision or state is stale.'}
    $pending=@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})
    if($pending.Count -ne 1 -or $pending[0].requestId -cne $ExpiredApprovalId -or [DateTimeOffset]::Parse($pending[0].expiresUtc) -gt [DateTimeOffset]::UtcNow){throw 'One exact expired pending human approval is required.'}
    $old=$pending[0];$binding=$old.executionBinding
    if($old.requiredLevel -cne 'user' -or $binding.SchemaVersion -cne 'maya-qa-canonical-execution-approval-v1' -or $binding.TaskId -cne $TaskId -or $binding.QaWorkflowId -cne 'create-plan-views-v1' -or (Get-CpvRecoveryHash $binding) -cne $old.bindingHash){throw 'Historical approval binding integrity failed.'}
    foreach($name in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket'){if($task.PSObject.Properties.Name -contains $name -and $task.$name){throw 'Active Tara state requires execution reconciliation.'}}
    if($task.PSObject.Properties.Name -contains 'taraRuns' -and @($task.taraRuns|Where-Object {$_.status -in @('running','unknown')}).Count){throw 'Native execution state requires reconciliation.'}
    if(@(Get-Process Revit -ErrorAction SilentlyContinue).Count){throw 'Revit is already running.'}
    $candidate=& (Get-Module Repato.MayaQaWorkflow) {param($store,$id,$b) New-MayaQaPersistedCandidateEvidence -StoreRoot $store -TaskId $id -WorkflowId $b.WorkflowId -QaWorkflowId $b.QaWorkflowId -TestId $b.QaWorkflowId} $StoreRoot $TaskId $binding
    if($candidate.CandidateDllSha256 -ine $binding.CandidateSha256 -or $candidate.CandidateSourceCommit -cne $binding.CandidateSourceCommit -or $candidate.RunnerManifestSha256 -ine $binding.RunnerManifestSha256){throw 'Frozen candidate differs from expired approval.'}
    foreach($pair in @(@($binding.ModelPath,$binding.ModelSha256),@($binding.SidecarPath,$binding.SidecarSha256),@($binding.CandidateProvenancePath,$binding.CandidateProvenanceSha256))){if((Get-FileHash -LiteralPath $pair[0]).Hash -ine $pair[1]){throw 'Previous preparation binding bytes changed.'}}
    $qa=Join-Path $PSScriptRoot '../QA'
    $null=& (Get-Module Repato.MayaQaWorkflow) {param($qa,$id,$b) Test-MayaQaFixturePreparationRecord -QaRoot $qa -TaskId $id -WorkflowId $b.WorkflowId -SourcePath (Join-Path $qa 'Fixtures/CreatePlanViewsEmpty.rvt') -SourceSha256 $b.FixtureSha256 -Evidence $b.FixturePreparationEvidence} $qa $TaskId $binding
    $request=[pscustomobject][ordered]@{schemaVersion=1;operation='prepare-cpv-fixture';requestId=[guid]::NewGuid().ToString('N');taskId=$TaskId;workflowId=$binding.WorkflowId;attemptId=[guid]::NewGuid().ToString('N');runId=[guid]::NewGuid().ToString('N');expiresUtc=[DateTimeOffset]::UtcNow.AddHours(4).ToString('O');timeoutSeconds=7200;candidateEvidence=$candidate}
    $recovery=[pscustomobject]@{SchemaVersion=1;ExpiredApprovalId=$ExpiredApprovalId;OldBinding=$binding;Request=$request;RequestHash=(Get-CpvRecoveryHash $request);Status='Prepared';Receipt=$null;ApprovalId=$null;CreatedUtc=Get-RepatoUtc}
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)
        $t=Find-RepatoTask $data $TaskId
        if($t.revision -ne $ExpectedTaskRevision -or ($t.PSObject.Properties.Name -contains 'cpvPreparationRecovery' -and $t.cpvPreparationRecovery)){throw 'Recovery compare-and-swap failed.'}
        $matches=@($t.approvalRequests|Where-Object {$_.requestId -ceq $ExpiredApprovalId -and $_.status -ceq 'pending'})
        if($matches.Count -ne 1 -or (Get-CpvRecoveryHash $matches[0].executionBinding) -cne $old.bindingHash){throw 'Approval changed during recovery.'}
        $matches[0].status='superseded';$matches[0].reason='Expired approval archived for authenticated CPV fixture-preparation recovery; no execution approval granted.'
        $t|Add-Member NoteProperty cpvPreparationRecovery $recovery
        $t.status='in-progress';$t.workflowStage='qa';Add-RepatoHistory $t 'cpv-preparation-recovery-prepared' 'Maya' "request=$($request.requestId); superseded=$ExpiredApprovalId"
        $recovery
    }
}
function Send-CpvPreparationRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][long]$ExpectedTaskRevision,[scriptblock]$Transport)
    $null=Get-CpvPreparationCapabilities -Transport $Transport
    $reserved=Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)
        $t=Find-RepatoTask $data $TaskId;$r=$t.cpvPreparationRecovery
        if($t.revision -ne $ExpectedTaskRevision -or $r.Status -cne 'Prepared' -or (Get-CpvRecoveryHash $r.Request) -cne $r.RequestHash -or [DateTimeOffset]::Parse($r.Request.expiresUtc) -le [DateTimeOffset]::UtcNow){throw 'Recovery dispatch revision, state, hash, or expiry is invalid.'}
        $r.Status='Dispatching';Add-RepatoHistory $t 'cpv-preparation-dispatch-reserved' 'Maya' $r.Request.requestId;$r
    }
    # Persist-before-send: a disconnect remains Dispatching; only status polling may resolve it.
    if($Transport){& $Transport $reserved.Request}else{Invoke-CpvPreparationTransport $reserved.Request}
}
function Get-CpvPreparationRecoveryStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[scriptblock]$Transport)
    $t=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    $marker=$t.PSObject.Properties['cpvPreparationRecovery']
    $r=if($marker){$marker.Value}else{$null}
    if($null -eq $r){return [pscustomobject][ordered]@{status='NotStarted';operation='cpv-preparation-status';taskId=$TaskId;recoveryStatus='NotStarted';sideEffectPerformed=$false}}
    $requestProperty=$r.PSObject.Properties['Request']
    $request=if($requestProperty){$requestProperty.Value}else{$null}
    $requestIdProperty=if($request){$request.PSObject.Properties['requestId']}else{$null}
    $requestId=[guid]::Empty
    if(!$requestIdProperty -or ![guid]::TryParseExact([string]$requestIdProperty.Value,'N',[ref]$requestId) -or $requestId -eq [guid]::Empty){throw 'Persisted CPV preparation recovery record is malformed: requestId must be a nonzero N-format GUID.'}
    $q=[pscustomobject]@{schemaVersion=1;operation='cpv-preparation-status';requestId=$r.Request.requestId}
    if($Transport){& $Transport $q}else{Invoke-CpvPreparationTransport $q}
}
function Set-CpvPreparationRecoveryFailedReconciled {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][long]$ExpectedTaskRevision,[scriptblock]$Transport)
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    $r=$task.cpvPreparationRecovery
    if($task.revision -ne $ExpectedTaskRevision -and $r.Status -ne 'FailedReconciled'){throw 'Failed reconciliation revision is stale.'}
    if(!$r -or $r.Status -notin @('Dispatching','FailedReconciled') -or (Get-CpvRecoveryHash $r.Request) -cne $r.RequestHash){throw 'Failed reconciliation requires the exact dispatched request.'}
    if($r.Status -eq 'Dispatching' -and @($task.approvalRequests|Where-Object {$_.status -ceq 'pending'}).Count){throw 'Pending approval state must be reconciled before failed preparation.'}
    $q=[pscustomobject]@{schemaVersion=1;operation='cpv-preparation-reconcile-failed';requestId=$r.Request.requestId;taskId=$TaskId;workflowId=$r.Request.workflowId;attemptId=$r.Request.attemptId;runId=$r.Request.runId}
    $receipt=if($Transport){& $Transport $q}else{Invoke-CpvPreparationTransport $q}
    foreach($name in 'requestId','taskId','workflowId','attemptId','runId'){if($receipt.$name -cne $q.$name){throw "Reconciliation receipt identity mismatch: $name"}}
    if($receipt.status -cne 'FailedReconciled' -or $receipt.failureCode -cne 'preparation-exited-without-result' -or
        $receipt.cleanupVerified -ne $false -or $receipt.rollbackStatus -cne 'NotRequired-NoPreparationResult') {throw 'Agent did not return a valid terminal failure reconciliation.'}
    if($r.Status -eq 'FailedReconciled'){
        if($r.Receipt.requestId -cne $receipt.requestId -or $r.Receipt.failureCode -cne $receipt.failureCode){throw 'Canonical reconciliation receipt differs.'}
        return $r
    }
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)
        $t=Find-RepatoTask $data $TaskId;$current=$t.cpvPreparationRecovery
        if($t.revision -ne $ExpectedTaskRevision -or $current.Status -cne 'Dispatching' -or (Get-CpvRecoveryHash $current.Request) -cne $current.RequestHash){throw 'Failed reconciliation compare-and-swap failed.'}
        if(@($t.approvalRequests|Where-Object {$_.status -ceq 'pending'}).Count){throw 'Pending approval state changed during reconciliation.'}
        $current.Status='FailedReconciled';$current.Receipt=$receipt
        Add-RepatoHistory $t 'cpv-preparation-failed-reconciled' 'Maya' $receipt.requestId
        $current
    }
}
function Complete-CpvPreparationRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][long]$ExpectedTaskRevision,[scriptblock]$Transport)
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId;$recovery=$task.cpvPreparationRecovery;$request=$recovery.Request
    if((Get-CpvRecoveryHash $request) -cne $recovery.RequestHash){throw 'Persisted recovery request hash changed.'}
    if($recovery.ApprovalId){return @($task.approvalRequests|Where-Object requestId -ceq $recovery.ApprovalId)[0]}
    if($task.revision -ne $ExpectedTaskRevision -or $recovery.Status -notin @('Dispatching','Verified')){throw 'Completion revision or state is stale.'}
    $receipt=Get-CpvPreparationRecoveryStatus -StoreRoot $StoreRoot -TaskId $TaskId -Transport $Transport
    if($receipt.status -cne 'Passed' -or $receipt.operation -cne 'prepare-cpv-fixture' -or $receipt.user -ine 'RAMSAI\RepatoQA' -or $receipt.sid -cne 'S-1-5-21-1031246752-3872016183-2454652381-1015' -or $receipt.sessionId -le 0 -or $receipt.cleanupVerified -ne $true -or $receipt.rollbackStatus -cne 'CommittedDisposableFixtureOnly'){throw 'Preparation is incomplete, ambiguous, failed, or cleanup is unverified.'}
    foreach($name in 'requestId','taskId','workflowId','attemptId','runId'){if($receipt.$name -cne $request.$name){throw "Preparation receipt identity mismatch: $name"}}
    if($receipt.candidateSha256 -ine $request.candidateEvidence.CandidateDllSha256 -or $receipt.manifestSha256 -ine $request.candidateEvidence.RunnerManifestSha256 -or [DateTimeOffset]::Parse($receipt.expiresUtc) -le [DateTimeOffset]::UtcNow -or [DateTimeOffset]::Parse($receipt.expiresUtc) -ne [DateTimeOffset]::Parse($request.expiresUtc)){throw 'Preparation receipt candidate or expiry changed.'}
    foreach($pair in @(@('modelPath','modelSha256'),@('requestPath','requestSha256'),@('resultPath','resultSha256'))){if((Get-FileHash -LiteralPath $receipt.($pair[0])).Hash -ine $receipt.($pair[1])){throw 'Preparation receipt file hash mismatch.'}}
    $runtime=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../QA/TestRuns'))
    if([IO.Path]::GetFullPath($StoreRoot).StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){$runtime=[IO.Path]::GetFullPath($env:TEMP)}
    $dir=[IO.Path]::GetFullPath((Join-Path $runtime ('cpv-preparation-'+$request.runId)))
    foreach($path in @($receipt.modelPath,$receipt.requestPath,$receipt.resultPath)){if(![IO.Path]::GetFullPath($path).StartsWith($dir.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Preparation receipt path escaped the dedicated run.'}}
    if([IO.Path]::GetFullPath($receipt.modelPath) -ine (Join-Path $dir 'model.rvt') -or [IO.Path]::GetFullPath($receipt.requestPath) -ine (Join-Path $dir ('tara-'+$request.attemptId+'.request.json')) -or $receipt.resultPath -ine ($receipt.requestPath+'.preparation.json')){throw 'Preparation receipt file names differ from fixed operation paths.'}
    $side=Get-Content -LiteralPath ($receipt.modelPath+'.fixture.json') -Raw|ConvertFrom-Json
    foreach($pair in @(@('preparedModelSha256','modelSha256'),@('fixturePreparationRequestPath','requestPath'),@('fixturePreparationRequestSha256','requestSha256'),@('fixturePreparationResultPath','resultPath'),@('fixturePreparationResultSha256','resultSha256'),@('fixturePreparationAttemptId','attemptId'),@('fixturePreparationRunId','runId'))){if($side.($pair[0]) -ine $receipt.($pair[1])){throw 'Prepared fixture provenance sidecar correlation failed.'}}
    $result=Get-Content -LiteralPath $receipt.resultPath -Raw|ConvertFrom-Json
    if($result.Status -cne 'Passed' -or $result.TaskId -cne $TaskId -or $result.WorkflowId -cne $request.workflowId -or $result.AttemptId -cne $request.attemptId -or $result.RunId -cne $request.runId -or $result.PreparedModelSha256 -ine $receipt.modelSha256){throw 'Prepared result correlation failed.'}
    $levels=@($result.Levels|Sort-Object Name);$expected=@(0.0,4.0,7.8)
    if($levels.Count -ne 3){throw 'Prepared fixture level count failed.'}
    if(@($levels.ElementId|Select-Object -Unique).Count -ne 3){throw 'Prepared level IDs are not unique.'}
    for($i=0;$i -lt 3;$i++){if($levels[$i].Name -cne [string]$i -or [double]::IsNaN([double]$levels[$i].ElevationMeters) -or [double]::IsInfinity([double]$levels[$i].ElevationMeters) -or [math]::Abs([double]$levels[$i].ElevationMeters-$expected[$i]) -gt 0.0000001 -or $levels[$i].ElementId -le 0){throw 'Prepared fixture level state failed.'}}
    if($recovery.Status -ceq 'Dispatching'){
        $null=Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)
            $t=Find-RepatoTask $data $TaskId;$r=$t.cpvPreparationRecovery
            if($t.revision -ne $ExpectedTaskRevision -or $r.Status -cne 'Dispatching' -or (Get-CpvRecoveryHash $r.Request) -cne $r.RequestHash){throw 'Preparation completion compare-and-swap failed.'}
            $w=@($t.deploymentWorkflows|Where-Object workflowId -ceq $request.workflowId)[0]
            $archive=ConvertFrom-Json ($w|ConvertTo-Json -Depth 20)
            $r|Add-Member NoteProperty PriorWorkflow $archive
            $prep=[pscustomobject]@{RequestPath=$receipt.requestPath;RequestSha256=$receipt.requestSha256;ResultPath=$receipt.resultPath;ResultSha256=$receipt.resultSha256;AttemptId=$request.attemptId;RunId=$request.runId;ExpiresUtc=$request.expiresUtc;SourceSha256=$r.OldBinding.FixtureSha256;PreparedModelPath=$receipt.modelPath;PreparedModelSha256=$receipt.modelSha256}
            foreach($entry in @(@('qaRunId',$request.runId),@('qaModelPath',$receipt.modelPath),@('qaSidecarPath',($receipt.modelPath+'.fixture.json')),@('qaDisposableModelSha256',$receipt.modelSha256),@('qaFixturePreparationEvidence',$prep))){$w|Add-Member NoteProperty $entry[0] $entry[1] -Force}
            foreach($name in 'qaHandoff','qaHandoffId','qaApprovalId','qaApprovalStatus','qaReportPath','qaReportSha256','qaEvidence','qaVerificationStatus','qaCompletionStatus','qaCompletedUtc'){$w|Add-Member NoteProperty $name $null -Force}
            $w.workflowRevision=[long]$w.workflowRevision+1
            $r.Receipt=$receipt;$r.Status='Verified';$t.status='in-progress';$t.workflowStage='qa';Add-RepatoHistory $t 'cpv-preparation-verified' 'Tara' $request.requestId
        }
    }
    $current=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    # Existing canonical approval builder performs its own optimistic transaction and artifact/deployment checks.
    $existing=@($current.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending' -and $_.executionBinding.RunId -ceq $request.runId})
    if($existing.Count -eq 0){
        $null=Request-MayaQaCanonicalExecutionApproval -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $request.workflowId -BuildRequestId $recovery.OldBinding.BuildRequestId -ExpectedTaskRevision $current.revision -CandidateSourceCommit $request.candidateEvidence.CandidateSourceCommit -CandidateSha256 $receipt.candidateSha256 -ExpiryMinutes 30
        $current=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
        $existing=@($current.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})
    }
    if($existing.Count -ne 1 -or $existing[0].executionBinding.RunId -cne $request.runId){throw 'Recovery approval is missing or ambiguous.'}
    $id=$existing[0].requestId;$revision=$current.revision
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$t=Find-RepatoTask $data $TaskId;if($t.revision -ne $revision){throw 'Approval linkage revision changed.'};$t.cpvPreparationRecovery.ApprovalId=$id;$t.cpvPreparationRecovery.Status='ApprovalPending';$existing[0]}
}
Export-ModuleMember -Function Invoke-CpvPreparationTransport,Get-CpvPreparationCapabilities,New-CpvPreparationRecovery,Send-CpvPreparationRecovery,Get-CpvPreparationRecoveryStatus,Set-CpvPreparationRecoveryFailedReconciled,Complete-CpvPreparationRecovery
