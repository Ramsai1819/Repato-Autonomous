$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
$module=Import-Module (Join-Path $PSScriptRoot 'Repato.CpvCompletedOutcomeRecovery.psm1') -Force -PassThru -WarningAction SilentlyContinue
$temp=Join-Path ([IO.Path]::GetTempPath()) ('cpv-completed-recovery-approval-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $temp|Out-Null
$script:count=0
function Check($Value,$Name){$script:count++;if(!$Value){throw "FAILED: $Name"}}
function Reject($Action,$Pattern){$script:count++;try{& $Action;throw 'Unexpected acceptance'}catch{if($_.Exception.Message -notmatch $Pattern){throw}}}
function New-Task($RequestId,$PreparationApprovalId,[long]$Revision,[string]$Status,[string]$Stage) {
    [pscustomobject]@{taskId='task-bf61fe7f22d74df7a92599681da5919e';title='Synthetic CPV recovery';description='Isolated test fixture';assignedAgent='Maya';status=$Status;workflowStage=$Stage;branchName='qa/cpv-outcome-recovery';createdUtc=[DateTimeOffset]::UtcNow.ToString('O');startedUtc=$null;finishedUtc=$null;logs=[object[]]@();reportPaths=[object[]]@();errorDetails=$null;requiredApprovalLevel='user';approvalRequests=[object[]]@();executorRuns=[object[]]@();revision=$Revision
        cpvPreparationRecovery=[pscustomobject]@{Status='Dispatching';PreparationApprovalId=$PreparationApprovalId;Request=[pscustomobject]@{requestId=$RequestId;taskId='task-bf61fe7f22d74df7a92599681da5919e';workflowId='fa2c2f578cbc40cbacac45c96313ca4c';attemptId='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';runId='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';operation='prepare-cpv-fixture';timeoutSeconds=7200};RequestHash=('A'*64);OutcomeRecoveryApprovalId=$null;OutcomeRecoveryRequest=$null;OutcomeRecoveryRequestHash=$null}
        history=[object[]]@([pscustomobject]@{timestampUtc=[DateTimeOffset]::UtcNow.ToString('O')})}
}
function Hash-Value($Value){& $module {param($v)Get-CpvOutcomeRecoveryHash $v} $Value}
try {
    $taskId='task-bf61fe7f22d74df7a92599681da5919e';$requestId='c11b311638a54bfc9ebdd1803671ec40';$prepApproval='7386efa2519b4c518e3d149f3a645a05';$approvalId=[guid]::NewGuid().ToString('N')
    $snapshot=[pscustomobject][ordered]@{TaskId=$taskId;TaskRevision=[long]101;RequestId=$requestId;PreparationApprovalId=$prepApproval;ModelSha256=('B'*64);ResultSha256=('C'*64)}
    $binding=[pscustomobject][ordered]@{SchemaVersion='cpv-preparation-outcome-recovery-approval-v1';ApprovalId=$approvalId;TaskId=$taskId;TaskRevision=[long]101;Operation='cpv-preparation-recover-completed';RecoveryStatusOperation='cpv-preparation-recover-completed-status';RecoveryRequestId=$requestId;RecoveryApprovalId=$prepApproval;ExpectedTaskRevision=[long]101;PermittedUser='RAMSAI\RepatoQA';PermittedSid='S-1-5-21-1031246752-3872016183-2454652381-1015';ExpiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(20).ToString('O');Snapshot=$snapshot;SnapshotHash=(Hash-Value $snapshot)}
    $approval=[pscustomobject]@{requestId=$approvalId;action='cpv-preparation-outcome-recovery';requiredLevel='user';status='pending';bindingHash=(Hash-Value $binding);outcomeRecoveryBinding=$binding;requestedRevision=[long]102;approvedRevision=$null;expiresUtc=$binding.ExpiresUtc;decidedBy=$null;consumedUtc=$null}
    $task=New-Task $requestId $prepApproval 102 'awaiting-approval' 'approval'
    Check ((& $module {param($t,$a) Assert-CpvOutcomeRecoveryApprovalEnvelope -Task $t -Approval $a} $task $approval) -eq $true) 'valid user approval envelope binds exact request and revision'
    $staleTask=New-Task $requestId $prepApproval 103 'awaiting-approval' 'approval';Reject {& $module {param($t,$a) Assert-CpvOutcomeRecoveryApprovalEnvelope -Task $t -Approval $a} $staleTask $approval} 'revision is stale'
    $tampered=[pscustomobject]@{};foreach($p in $binding.PSObject.Properties){$tampered|Add-Member NoteProperty $p.Name $p.Value};$tampered.Snapshot.ModelSha256=('0'*64)
    $badApproval=[pscustomobject]@{};foreach($p in $approval.PSObject.Properties){$badApproval|Add-Member NoteProperty $p.Name $p.Value};$badApproval.outcomeRecoveryBinding=$tampered
    Reject {& $module {param($t,$a) Assert-CpvOutcomeRecoveryApprovalEnvelope -Task $t -Approval $a} $task $badApproval} 'binding integrity failed'
    $expiredBinding=[pscustomobject]@{};foreach($p in $binding.PSObject.Properties){$expiredBinding|Add-Member NoteProperty $p.Name $p.Value};$expiredBinding.ExpiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('O');$expiredBinding.SnapshotHash=Hash-Value $expiredBinding.Snapshot
    $expiredApproval=[pscustomobject]@{};foreach($p in $approval.PSObject.Properties){$expiredApproval|Add-Member NoteProperty $p.Name $p.Value};$expiredApproval.outcomeRecoveryBinding=$expiredBinding;$expiredApproval.expiresUtc=$expiredBinding.ExpiresUtc;$expiredApproval.bindingHash=Hash-Value $expiredBinding
    Reject {& $module {param($t,$a) Assert-CpvOutcomeRecoveryApprovalEnvelope -Task $t -Approval $a} $task $expiredApproval} 'expired|expiry'

    $store=Join-Path $temp 'store';New-Item -ItemType Directory -Path $store|Out-Null
    $payload=[pscustomobject]@{schemaVersion=1;operation='cpv-preparation-recover-completed';requestId=$requestId;recoveryApprovalId=$approvalId}
    $task.cpvPreparationRecovery.OutcomeRecoveryApprovalId=$approvalId;$task.cpvPreparationRecovery.OutcomeRecoveryRequest=$payload
    $task.cpvPreparationRecovery.OutcomeRecoveryRequestHash=Hash-Value $payload
    $approval.status='approved';$approval.decidedBy='user';$approval.approvedRevision=[long]102;$approval.consumedUtc='2026-10-18T14:00:00Z'
    $task.status='in-progress';$task.workflowStage='qa';$task.approvalRequests=[object[]]@($approval)
    [IO.File]::WriteAllText((Join-Path $store 'tasks.json'),(ConvertTo-Json -InputObject ([pscustomobject]@{schemaVersion=1;tasks=[object[]]@($task)}) -Depth 20))
    $seen=[Collections.Generic.List[string]]::new();$statusTransport={param($q)$seen.Add([string]$q.operation);[pscustomobject]@{status='NotFound'}}
    $status=Get-CpvPreparationCompletedOutcomeRecoveryStatus -StoreRoot $store -TaskId $taskId -Transport $statusTransport
    Check ($status.Status -eq 'OutcomeUnknown' -and $seen.Count -eq 1 -and $seen[0] -eq 'cpv-preparation-recover-completed-status') 'unknown recovery is queried through read-only status and never resent'
    $dispatchCalls=0;$blockedTask=New-Task $requestId $prepApproval 103 'in-progress' 'qa';$badStore=Join-Path $temp 'no-approval'
    New-Item -ItemType Directory -Path $badStore|Out-Null;[IO.File]::WriteAllText((Join-Path $badStore 'tasks.json'),(ConvertTo-Json -InputObject ([pscustomobject]@{schemaVersion=1;tasks=[object[]]@($blockedTask)}) -Depth 20))
    $neverSend={param($q)$script:dispatchCalls++;throw 'Transport must not be invoked without approval'}
    Reject {Invoke-CpvPreparationCompletedOutcomeRecovery -StoreRoot $badStore -TaskId $taskId -ExpectedTaskRevision 103 -ApprovalId $approvalId -Transport $neverSend} 'approval is required'
    Check ($dispatchCalls -eq 0) 'no authenticated recovery dispatch occurs without matching user approval'
    $pendingTask=New-Task $requestId $prepApproval 101 'in-progress' 'qa';$pendingTask.cpvPreparationRecovery.OutcomeRecoveryApprovalId=$approvalId
    $pendingStore=Join-Path $temp 'already-reserved';New-Item -ItemType Directory -Path $pendingStore|Out-Null
    [IO.File]::WriteAllText((Join-Path $pendingStore 'tasks.json'),(ConvertTo-Json -InputObject ([pscustomobject]@{schemaVersion=1;tasks=[object[]]@($pendingTask)}) -Depth 20))
    $requestCalls=0;$neverQuery={param($q)$script:requestCalls++;throw 'Transport must not be invoked for duplicate approval'}
    Reject {Request-CpvPreparationOutcomeRecoveryApproval -StoreRoot $pendingStore -TaskId $taskId -ExpectedTaskRevision 101 -ExpectedAgentVersion '1.0.19+4b0066247088' -Transport $neverQuery} 'already reserved'
    Check ($requestCalls -eq 0) 'a recovery approval cannot be duplicated after an authorization identity is reserved'

    $expireStore=Join-Path $temp 'expire-store';New-Item -ItemType Directory -Path $expireStore|Out-Null
    $expireTask=New-Task $requestId $prepApproval 200 'awaiting-approval' 'approval'
    $expiredAt=[DateTimeOffset]::UtcNow.AddMinutes(-5).ToString('O')
    $expireBinding=[pscustomobject][ordered]@{SchemaVersion='cpv-preparation-outcome-recovery-approval-v1';ApprovalId='11111111111111111111111111111111';TaskId=$taskId;TaskRevision=[long]199;Operation='cpv-preparation-recover-completed';RecoveryStatusOperation='cpv-preparation-recover-completed-status';RecoveryRequestId=$requestId;RecoveryApprovalId=$prepApproval;ExpectedTaskRevision=[long]199;PermittedUser='RAMSAI\RepatoQA';PermittedSid='S-1-5-21-1031246752-3872016183-2454652381-1015';ExpiresUtc=$expiredAt;Snapshot=[pscustomobject][ordered]@{TaskId=$taskId;TaskRevision=[long]199;RequestId=$requestId;PreparationApprovalId=$prepApproval;ModelSha256=('B'*64);ResultSha256=('C'*64)};SnapshotHash=''}
    $expireBinding.SnapshotHash=Hash-Value $expireBinding.Snapshot
    $expireApproval=[pscustomobject]@{requestId='11111111111111111111111111111111';action='cpv-preparation-outcome-recovery';requiredLevel='user';status='pending';bindingHash=(Hash-Value $expireBinding);outcomeRecoveryBinding=$expireBinding;previousStatus='in-progress';previousWorkflowStage='qa';requestedRevision=[long]200;approvedRevision=$null;requestedUtc=[DateTimeOffset]::UtcNow.AddMinutes(-35).ToString('O');expiresUtc=$expiredAt;decidedUtc=$null;decidedBy=$null;reason=$null;consumedUtc=$null}
    $expireTask.approvalRequests=[object[]]@($expireApproval)
    [IO.File]::WriteAllText((Join-Path $expireStore 'tasks.json'),(ConvertTo-Json -InputObject ([pscustomobject]@{schemaVersion=1;tasks=[object[]]@($expireTask)}) -Depth 25))
    $expired=Expire-CpvPreparationOutcomeRecoveryApproval -StoreRoot $expireStore -TaskId $taskId -ExpectedTaskRevision 200
    Check ($expired.status -eq 'expired' -and $expired.reason -match 'Expired without a human decision') 'an expired pending recovery approval is retired with an audit reason'
    $restored=@((Get-Content -LiteralPath (Join-Path $expireStore 'tasks.json') -Raw|ConvertFrom-Json).tasks)[0]
    Check ($restored.status -eq 'in-progress' -and $restored.workflowStage -eq 'qa' -and [long]$restored.revision -eq 201 -and @($restored.approvalRequests|Where-Object {$_.status -ceq 'pending'}).Count -eq 0) 'expiring restores the QA-ready state and clears the pending gate'
    $liveStore=Join-Path $temp 'live-store';New-Item -ItemType Directory -Path $liveStore|Out-Null
    $liveTask=New-Task $requestId $prepApproval 300 'awaiting-approval' 'approval'
    $liveBinding=[pscustomobject]@{};foreach($p in $expireBinding.PSObject.Properties){$liveBinding|Add-Member NoteProperty $p.Name $p.Value}
    $liveAt=[DateTimeOffset]::UtcNow.AddMinutes(25).ToString('O');$liveBinding.ExpiresUtc=$liveAt;$liveBinding.SnapshotHash=Hash-Value $liveBinding.Snapshot
    $liveApproval=[pscustomobject]@{};foreach($p in $expireApproval.PSObject.Properties){$liveApproval|Add-Member NoteProperty $p.Name $p.Value}
    $liveApproval.outcomeRecoveryBinding=$liveBinding;$liveApproval.expiresUtc=$liveAt;$liveApproval.bindingHash=Hash-Value $liveBinding
    $liveTask.approvalRequests=[object[]]@($liveApproval)
    [IO.File]::WriteAllText((Join-Path $liveStore 'tasks.json'),(ConvertTo-Json -InputObject ([pscustomobject]@{schemaVersion=1;tasks=[object[]]@($liveTask)}) -Depth 25))
    Reject {Expire-CpvPreparationOutcomeRecoveryApproval -StoreRoot $liveStore -TaskId $taskId -ExpectedTaskRevision 300} 'has not expired'
    $afterLive=@((Get-Content -LiteralPath (Join-Path $liveStore 'tasks.json') -Raw|ConvertFrom-Json).tasks)[0]
    Check ($afterLive.status -eq 'awaiting-approval' -and @($afterLive.approvalRequests|Where-Object {$_.status -ceq 'pending'}).Count -eq 1) 'a still-valid pending recovery approval is never retired'

    $resApproval=[guid]::NewGuid().ToString('N');$workflowId='fa2c2f578cbc40cbacac45c96313ca4c';$attemptId=('a'*32);$runId=('b'*32)
    $resSnap=[pscustomobject][ordered]@{TaskId=$taskId;TaskRevision=[long]105;RequestId=$requestId;PreparationApprovalId=$prepApproval
        OriginalReceiptSha256=('1'*64);ActiveMarkerSha256=('2'*64);FailureEvidenceSha256=('3'*64);PreparationRequestSha256=('4'*64)
        ResultSha256=('5'*64);ModelSha256=('6'*64)}
    $resBinding=[pscustomobject][ordered]@{SchemaVersion='cpv-preparation-outcome-recovery-approval-v1';ApprovalId=$resApproval;TaskId=$taskId;TaskRevision=[long]105
        Operation='cpv-preparation-recover-completed';RecoveryStatusOperation='cpv-preparation-recover-completed-status';RecoveryRequestId=$requestId
        RecoveryApprovalId=$prepApproval;ExpectedTaskRevision=[long]105;PermittedUser='RAMSAI\RepatoQA';PermittedSid='S-1-5-21-1031246752-3872016183-2454652381-1015'
        ExpiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(20).ToString('O');Snapshot=$resSnap;SnapshotHash=(Hash-Value $resSnap)}
    $resApprovalObj=[pscustomobject]@{requestId=$resApproval;action='cpv-preparation-outcome-recovery';requiredLevel='user';status='approved'
        bindingHash=(Hash-Value $resBinding);outcomeRecoveryBinding=$resBinding;requestedRevision=[long]106;approvedRevision=[long]105
        expiresUtc=$resBinding.ExpiresUtc;decidedBy='user';consumedUtc=[DateTimeOffset]::UtcNow.ToString('O')}
    $resPayload=[pscustomobject][ordered]@{schemaVersion=1;operation='cpv-preparation-recover-completed';requestId=$requestId;taskId=$taskId
        workflowId=$workflowId;attemptId=$attemptId;runId=$runId;recoveryApprovalId=$resApproval;expectedTaskRevision=[long]105
        approvalBindingHash=$resApprovalObj.bindingHash;authorizationExpiresUtc=[string]$resApprovalObj.expiresUtc
        originalReceiptSha256=$resSnap.OriginalReceiptSha256;activeMarkerSha256=$resSnap.ActiveMarkerSha256
        failureEvidenceSha256=$resSnap.FailureEvidenceSha256;requestSha256=$resSnap.PreparationRequestSha256
        resultSha256=$resSnap.ResultSha256;modelSha256=$resSnap.ModelSha256}
    function New-Reserved([long]$Revision){$t=New-Task $requestId $prepApproval $Revision 'in-progress' 'qa'
        $t.cpvPreparationRecovery.OutcomeRecoveryApprovalId=$resApproval;$t.cpvPreparationRecovery.OutcomeRecoveryRequest=$resPayload
        $t.cpvPreparationRecovery.OutcomeRecoveryRequestHash=Hash-Value $resPayload;$t.approvalRequests=[object[]]@($resApprovalObj);$t}
    function Copy-OBJ($Value){$o=[pscustomobject]@{};foreach($p in $Value.PSObject.Properties){$o|Add-Member NoteProperty $p.Name $p.Value};$o}
    Check ((& $module {param($t,$id) Assert-CpvOutcomeRecoveryReservationResettable -Task $t -ApprovalId $id} (New-Reserved 106) $resApproval).requestId -eq $resApproval) 'a reserved, consumed human authorization on a dispatching recovery is resettable'
    $notDispatching=New-Reserved 106;$notDispatching.cpvPreparationRecovery.Status='OutcomeUnknown'
    Reject {& $module {param($t,$id) Assert-CpvOutcomeRecoveryReservationResettable -Task $t -ApprovalId $id} $notDispatching $resApproval} 'dispatching recovery'
    $wrongId=New-Reserved 106;$wrongId.cpvPreparationRecovery.OutcomeRecoveryApprovalId=[guid]::NewGuid().ToString('N')
    Reject {& $module {param($t,$id) Assert-CpvOutcomeRecoveryReservationResettable -Task $t -ApprovalId $id} $wrongId $resApproval} 'approval identity changed'
    $tamperedReq=New-Reserved 106;$tamperedReq.cpvPreparationRecovery.OutcomeRecoveryRequest=(Copy-OBJ $resPayload);$tamperedReq.cpvPreparationRecovery.OutcomeRecoveryRequest.resultSha256=('0'*64)
    $tamperedReq.cpvPreparationRecovery.OutcomeRecoveryRequestHash=Hash-Value $tamperedReq.cpvPreparationRecovery.OutcomeRecoveryRequest
    Reject {& $module {param($t,$id) Assert-CpvOutcomeRecoveryReservationResettable -Task $t -ApprovalId $id} $tamperedReq $resApproval} 'differs from its approved snapshot'
    $unconsumed=New-Reserved 106;$unconsumed.approvalRequests=@(Copy-OBJ $resApprovalObj);$unconsumed.approvalRequests[0].consumedUtc=$null
    Reject {& $module {param($t,$id) Assert-CpvOutcomeRecoveryReservationResettable -Task $t -ApprovalId $id} $unconsumed $resApproval} 'not a consumed human authorization'
    $wrongRev=New-Reserved 107
    Reject {& $module {param($t,$id) Assert-CpvOutcomeRecoveryReservationResettable -Task $t -ApprovalId $id} $wrongRev $resApproval} 'not a consumed human authorization'
    $pending=New-Reserved 106;$pending.approvalRequests=@($resApprovalObj,(Copy-OBJ $resApprovalObj));$pending.approvalRequests[1].requestId=[guid]::NewGuid().ToString('N');$pending.approvalRequests[1].status='pending'
    Reject {& $module {param($t,$id) Assert-CpvOutcomeRecoveryReservationResettable -Task $t -ApprovalId $id} $pending $resApproval} 'approval is pending'
    $duplicate=New-Reserved 106;$dup=Copy-OBJ $resApprovalObj;$dup.requestId=[guid]::NewGuid().ToString('N');$dup.bindingHash='';$dup.consumedUtc=$null;$dup.status='approved'
    $duplicate.approvalRequests=@($resApprovalObj,$dup)
    Reject {& $module {param($t,$id) Assert-CpvOutcomeRecoveryReservationResettable -Task $t -ApprovalId $id} $duplicate $resApproval} 'Another unconsumed approval is active'
    $okProof=[pscustomobject]@{status='NotExecuted';operation='cpv-preparation-recover-completed-reconcile';requestId=$requestId;taskId=$taskId
        workflowId=$workflowId;attemptId=$attemptId;runId=$runId;recoveryApprovalId=$resApproval;approvalBindingHash=$resApprovalObj.bindingHash
        originalReceiptSha256=$resSnap.OriginalReceiptSha256;activeMarkerSha256=$resSnap.ActiveMarkerSha256
        failureEvidenceSha256=$resSnap.FailureEvidenceSha256;requestSha256=$resSnap.PreparationRequestSha256}
    Check ((& $module {param($p,$a,$r) Assert-CpvOutcomeRecoveryNonExecutionProof -Proof $p -Approval $a -Request $r} $okProof $resApprovalObj $resPayload) -eq $true) 'an authenticated NotExecuted proof bound to the reserved approval is accepted'
    $snapStored=[pscustomobject][ordered]@{TaskId=$taskId;TaskRevision=[long]105;RequestId=$requestId;PreparationApprovalId=$prepApproval;ModelSha256=('6'*64);AgentVersion='1.0.19+05933ab8b587'}
    $snapBinding=[pscustomobject]@{Snapshot=$snapStored}
    $snapAdvanced=[pscustomobject][ordered]@{TaskId=$taskId;TaskRevision=[long]105;RequestId=$requestId;PreparationApprovalId=$prepApproval;ModelSha256=('6'*64);AgentVersion='1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e'}
    Check ((& $module {param($b,$c) Assert-CpvOutcomeRecoveryApprovedSnapshotCurrent -Binding $b -Current $c} $snapBinding $snapAdvanced) -eq $true) 'evidence identical apart from the authorized agent runtime advance is accepted for a reservation reset'
    Check ((& $module {param($b,$c) Assert-CpvOutcomeRecoveryApprovedSnapshotCurrent -Binding $b -Current $c} $snapBinding $snapStored) -eq $true) 'byte-identical evidence is accepted for a reservation reset'
    $snapAltered=[pscustomobject][ordered]@{TaskId=$taskId;TaskRevision=[long]105;RequestId=$requestId;PreparationApprovalId=$prepApproval;ModelSha256=('0'*64);AgentVersion='1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e'}
    Reject {& $module {param($b,$c) Assert-CpvOutcomeRecoveryApprovedSnapshotCurrent -Binding $b -Current $c} $snapBinding $snapAltered} 'differs from the approved snapshot'
    $snapMissingField=[pscustomobject][ordered]@{TaskId=$taskId;TaskRevision=[long]105;RequestId=$requestId;PreparationApprovalId=$prepApproval;ModelSha256=('6'*64)}
    Reject {& $module {param($b,$c) Assert-CpvOutcomeRecoveryApprovedSnapshotCurrent -Binding $b -Current $c} $snapBinding $snapMissingField} 'differs from the approved snapshot'
    $leanProof=[pscustomobject]@{schemaVersion=1;operation='cpv-preparation-recover-completed-reconcile';requestId=$requestId;status='NotExecuted'
        recoveryApprovalId=$resApproval;approvalBindingHash=$resApprovalObj.bindingHash;originalReceiptSha256=$resSnap.OriginalReceiptSha256
        activeMarkerSha256=$resSnap.ActiveMarkerSha256;failureEvidenceSha256=$resSnap.FailureEvidenceSha256;requestSha256=$resSnap.PreparationRequestSha256
        verifiedUtc=[DateTimeOffset]::UtcNow.ToString('O')}
    Check ((& $module {param($p,$a,$r) Assert-CpvOutcomeRecoveryNonExecutionProof -Proof $p -Approval $a -Request $r} $leanProof $resApprovalObj $resPayload) -eq $true) 'the installed agent NotExecuted proof (bound by requestId, approval binding hash, and evidence hashes, without optional task correlation fields) is accepted'
    $wrongCorrelation=Copy-OBJ $okProof;$wrongCorrelation.taskId=('d'*32)
    Reject {& $module {param($p,$a,$r) Assert-CpvOutcomeRecoveryNonExecutionProof -Proof $p -Approval $a -Request $r} $wrongCorrelation $resApprovalObj $resPayload} 'definitive non-execution'
    $executedProof=Copy-OBJ $okProof;$executedProof.status='Executed'
    Reject {& $module {param($p,$a,$r) Assert-CpvOutcomeRecoveryNonExecutionProof -Proof $p -Approval $a -Request $r} $executedProof $resApprovalObj $resPayload} 'reports the reserved recovery executed'
    $unknownProof=Copy-OBJ $okProof;$unknownProof.status='RejectedOrUnknown'
    Reject {& $module {param($p,$a,$r) Assert-CpvOutcomeRecoveryNonExecutionProof -Proof $p -Approval $a -Request $r} $unknownProof $resApprovalObj $resPayload} 'definitive non-execution'
    $notFoundProof=Copy-OBJ $okProof;$notFoundProof.status='NotFound'
    Reject {& $module {param($p,$a,$r) Assert-CpvOutcomeRecoveryNonExecutionProof -Proof $p -Approval $a -Request $r} $notFoundProof $resApprovalObj $resPayload} 'definitive non-execution'
    $staleProof=Copy-OBJ $okProof;$staleProof.activeMarkerSha256=('0'*64)
    Reject {& $module {param($p,$a,$r) Assert-CpvOutcomeRecoveryNonExecutionProof -Proof $p -Approval $a -Request $r} $staleProof $resApprovalObj $resPayload} 'definitive non-execution'
    $replayedProof=Copy-OBJ $okProof;$replayedProof.requestId=('c'*32)
    Reject {& $module {param($p,$a,$r) Assert-CpvOutcomeRecoveryNonExecutionProof -Proof $p -Approval $a -Request $r} $replayedProof $resApprovalObj $resPayload} 'definitive non-execution'
    Reject {& $module {param($p,$a,$r) Assert-CpvOutcomeRecoveryNonExecutionProof -Proof $null -Approval $a -Request $r} $null $resApprovalObj $resPayload} 'definitive non-execution'
    $capStore=Join-Path $temp 'reset-cap';New-Item -ItemType Directory -Path $capStore|Out-Null
    [IO.File]::WriteAllText((Join-Path $capStore 'tasks.json'),(ConvertTo-Json -InputObject ([pscustomobject]@{schemaVersion=1;tasks=[object[]]@((New-Reserved 106))}) -Depth 25))
    Reject {Reset-CpvPreparationOutcomeRecoveryReservation -StoreRoot $capStore -TaskId $taskId -ExpectedTaskRevision 105 -ApprovalId $resApproval} 'stale'
    $capCalls=[Collections.Generic.List[string]]::new()
    $capTransport={param($q)$capCalls.Add([string]$q.operation);[pscustomobject]@{supported=$true;operation='cpv-preparation-capabilities';user='RAMSAI\RepatoQA';sid='S-1-5-21-1031246752-3872016183-2454652381-1015';sessionId=1}}
    Reject {Reset-CpvPreparationOutcomeRecoveryReservation -StoreRoot $capStore -TaskId $taskId -ExpectedTaskRevision 106 -ApprovalId $resApproval -Transport $capTransport} 'cannot provide authenticated proof'
    $afterCap=@((Get-Content -LiteralPath (Join-Path $capStore 'tasks.json') -Raw|ConvertFrom-Json).tasks)[0]
    Check ($afterCap.cpvPreparationRecovery.OutcomeRecoveryApprovalId -eq $resApproval -and $capCalls.Count -eq 1 -and $capCalls[0] -eq 'cpv-preparation-capabilities') 'reset refuses without the agent reconcile capability and never clears the reservation'

    Reject {& $module {param($r) Assert-CpvPreparationCompletedOutcomeRecoveryResponse -Response $r} ([pscustomobject]@{schemaVersion=1;operation='cpv-preparation-recover-completed';status='RejectedOrUnknown';failureCode='preparation-rejected-or-reconcile-required'})} 'rejected by the agent'
    Check ((& $module {param($r) Assert-CpvPreparationCompletedOutcomeRecoveryResponse -Response $r} ([pscustomobject]@{Receipt=[pscustomobject]@{Status='Passed'}})).Receipt.Status -eq 'Passed') 'a valid recovery commit passes the response guard'
    $moduleText=Get-Content (Join-Path $PSScriptRoot 'Repato.CpvCompletedOutcomeRecovery.psm1') -Raw
    Check ($moduleText.Contains("operation='cpv-preparation-recover-completed-status'") -and !$moduleText.Contains("operation='prepare-cpv-fixture'")) 'status and recovery paths remain separate; the recovery module cannot dispatch preparation'
    Check ($moduleText.Contains('cpv-preparation-recover-completed-reconcile') -and $moduleText.Contains('cpv-outcome-recovery-reservation-reset') -and $moduleText.Contains('function Reset-CpvPreparationOutcomeRecoveryReservation')) 'the recovery module implements the authenticated non-execution reconcile proof and the audited reservation-reset path'
    'PASS: '+$script:count+' completed-outcome authorization assertions; synthetic task store only; Revit launched=false.'
} finally {
    $full=[IO.Path]::GetFullPath($temp);$base=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if($full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $full)){Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue}
}
