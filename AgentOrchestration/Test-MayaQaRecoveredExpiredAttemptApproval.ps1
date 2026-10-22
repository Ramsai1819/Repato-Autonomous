$ErrorActionPreference='Stop'
$here=$PSScriptRoot
Import-Module (Join-Path $here 'Repato.AgentOrchestration.psm1') -Force
Import-Module (Join-Path $here 'Repato.Deployment.psm1') -Force
Import-Module (Join-Path $here 'Repato.MayaQaWorkflow.psm1') -Force

$taskId='task-expired-attempt-approval';$workflowId='workflow-expired-attempt-approval';$oldAttempt='11111111111111111111111111111111';$oldRun='22222222222222222222222222222222';$midAttempt='55555555555555555555555555555555';$midRun='66666666666666666666666666666666';$newAttempt='33333333333333333333333333333333';$newRun='44444444444444444444444444444444';$oldRequest='expired-old-request';$commit='e2b5bcf889657b82cc10fd46909d145cd27ff2e0';$hash='56B6E70E42FBFEAF8DA502E53C31C5CC1DAE1CA6A56A7CD3AC258CA573C5D9F5';$manifestHash='AF4DBFA78E61524DE7BD3B84178C6B70ED8D29D0A95BA17780826E09BE689D4F';$runtime='1.0.10+50d5d752d9a8';$revision=[long]20
$root=Join-Path ([IO.Path]::GetTempPath()) ('maya-expired-attempt-approval-'+[guid]::NewGuid().ToString('N'))

function New-State([switch]$WrongExpired,[switch]$Pending,[switch]$ValidApproval,[switch]$UnrelatedApproval) {
    $store=Join-Path $root ([guid]::NewGuid().ToString('N'));New-RepatoTask $store $taskId 'Expired QA' 'expired prepared approval test' 'qa/expired-prepared'|Out-Null
    Invoke-RepatoStoreMutation $store {
        param($d,$preview)
        $t=Find-RepatoTask $d $taskId;$t.status='in-progress';$t.workflowStage='approval';$t.revision=$revision
        $t|Add-Member NoteProperty mayaPlan ([pscustomobject]@{WorkflowId=$workflowId;QaWorkflowId='create-plan-views-v1'}) -Force
        $arch1=[pscustomobject]@{TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId='create-plan-views-v1';AttemptId=$oldAttempt;RunId=$oldRun;Stage='expired';ExecutionStatus='Expired';FailureCode=$(if($WrongExpired){'native-qa-failed'}else{'attempt-expired'});ReplacementAttemptId=$midAttempt;ReplacementRunId=$midRun}
        $arch2=[pscustomobject]@{TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId='create-plan-views-v1';AttemptId=$midAttempt;RunId=$midRun;Stage='expired';ExecutionStatus='Expired';FailureCode='attempt-expired';ReplacementAttemptId=$newAttempt;ReplacementRunId=$newRun}
        $t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@($arch1,$arch2)) -Force
        $t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@([pscustomobject]@{TaskId=$taskId;WorkflowId=$workflowId;AttemptId=$oldAttempt;RunId=$oldRun},[pscustomobject]@{TaskId=$taskId;WorkflowId=$workflowId;AttemptId=$midAttempt;RunId=$midRun})) -Force
        $packet1=[pscustomobject]@{TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId='create-plan-views-v1';AttemptId=$oldAttempt;RunId=$oldRun;ArtifactSha256=$hash;ManifestSha256=$manifestHash;RunnerManifestSha256=$manifestHash}
        $packet2=[pscustomobject]@{TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId='create-plan-views-v1';AttemptId=$midAttempt;RunId=$midRun;ArtifactSha256=$hash;ManifestSha256=$manifestHash;RunnerManifestSha256=$manifestHash}
        $t|Add-Member NoteProperty mayaTaraQaPacketHistory ([object[]]@([pscustomobject]@{Packet=$packet1;AttemptId=$oldAttempt;RunId=$oldRun},[pscustomobject]@{Packet=$packet2;AttemptId=$midAttempt;RunId=$midRun})) -Force
        $t|Add-Member NoteProperty mayaTaraAttempt ([pscustomobject]@{AttemptId=$newAttempt;RunId=$newRun;RequestExpiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(20).ToString('O')}) -Force
        $t|Add-Member NoteProperty mayaTaraExecution ([pscustomobject]@{TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId='create-plan-views-v1';AttemptId=$newAttempt;RunId=$newRun;ArtifactSha256=$hash;Stage='prepared';ExecutionStatus='Prepared';ClaimStatus='unclaimed';ClaimId=$null;ClaimOwner=$null;NativeProcessId=$null;RequestPath=$null;ResultPath=$null;ReportPath=$null;ReceiptPath=$null;SideEffectsPerformed=$false;TaskRevisionAtPrepare=17}) -Force
        $approved=[pscustomobject]@{requestId=$oldRequest;action='qa-run';requiredLevel='user';status='approved';bindingHash='old-binding';candidate=[pscustomobject]@{BuildRequestId='build-expired-test';SourceCommit=$commit;ArtifactSha256=$hash};attemptId=$oldAttempt;runId=$oldRun;runtime=[pscustomobject]@{Name='Repato.QaLaunchAgent';Version=$runtime};previousStatus='in-progress';requestedRevision=18;approvedRevision=19;requestedUtc='2026-10-12T00:00:00Z';expiresUtc=$(if($ValidApproval){[DateTimeOffset]::UtcNow.AddMinutes(10).ToString('O')}else{'2026-10-12T00:30:00Z'});decidedUtc='2026-10-12T00:01:00Z';decidedBy='user';reason='explicit approval';consumedUtc=$null}
        $t.approvalRequests=[object[]]@($approved)
        if($Pending){$t.approvalRequests=[object[]]@($t.approvalRequests)+[pscustomobject]@{requestId='pending-existing';action='qa-run';requiredLevel='user';status='pending';attemptId='other';runId='other'}}
        if($UnrelatedApproval){$t.approvalRequests=[object[]]@($t.approvalRequests)+[pscustomobject]@{requestId='unrelated-approved';action='qa-run';requiredLevel='user';status='approved';attemptId='unrelated-attempt';runId='unrelated-run';expiresUtc='2026-10-11T00:00:00Z'}}
        $t|Add-Member NoteProperty deploymentWorkflows ([object[]]@([pscustomobject]@{workflowId=$workflowId;qaWorkflowId='create-plan-views-v1';qaBuildStatus='succeeded';qaBuildRequest=[pscustomobject]@{BuildRequestId='build-expired-test'};qaBuildEvidence=[pscustomobject]@{BuildRequestId='build-expired-test';BuildStatus='succeeded';EvidenceSource='FrozenCandidate';SourceCommit=$commit;CandidateSourceCommit=$commit;ArtifactSha256=$hash;ManifestSha256=$manifestHash;RunnerManifestSha256=$manifestHash;DeploymentValidation=$true;ManifestIntegrityValidation=$true;QaIsolation=$true}})) -Force
        $t
    }|Out-Null
    [pscustomobject]@{Store=$store}
}
function Invoke-Request($state,[string]$requestId=$oldRequest,[string]$expiredId=$oldAttempt,[string]$replacementAttempt=$newAttempt,[string]$replacementRun=$newRun,[string]$candidate=$commit,[string]$candidateHash=$hash,[long]$expectedRevision=$revision) {
    Request-MayaQaRecoveredExpiredAttemptApproval -StoreRoot $state.Store -TaskId $taskId -WorkflowId $workflowId -ExpiredApprovalRequestId $requestId -ExpiredAttemptId $expiredId -ExpiredRunId $oldRun -RecoveredAttemptId $replacementAttempt -RecoveredRunId $replacementRun -ExpectedTaskRevision $expectedRevision -ExpectedCandidateSourceCommit $candidate -ExpectedCandidateSha256 $candidateHash -LaunchAgentRuntimeVersion $runtime
}
function Snapshot([string]$store) {@(Get-ChildItem -LiteralPath $store -File -Recurse|Sort-Object FullName|ForEach-Object {"$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"}) -join "`n"}
function Reject([string]$name,[object]$state,[scriptblock]$invoke,[string]$guard) {$before=Snapshot $state.Store;try{& $invoke $state|Out-Null;throw "$name unexpectedly accepted."}catch{if($_.Exception.Message -eq "$name unexpectedly accepted."){throw};if($_.Exception.Message -notmatch [regex]::Escape($guard)){throw "$name returned unexpected guard: $($_.Exception.Message)"}};if((Snapshot $state.Store) -cne $before){throw "$name mutated state on rejection."}}

try {
    $valid=New-State;$result=Invoke-Request $valid;$task=Find-RepatoTask (Read-RepatoTaskStore $valid.Store) $taskId;$pending=@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'});$expired=@($task.approvalRequests|Where-Object requestId -ceq $oldRequest)[0]
    if($pending.Count -ne 1 -or $pending[0].requiredLevel -cne 'user' -or $pending[0].previousStatus -cne 'in-progress' -or $pending[0].attemptId -cne $newAttempt -or $pending[0].runId -cne $newRun -or $pending[0].candidate.SourceCommit -cne $commit -or $pending[0].candidate.ArtifactSha256 -ine $hash -or $pending[0].runtime.Version -cne $runtime -or $pending[0].requestedRevision -ne $task.revision -or [DateTimeOffset]::Parse($pending[0].expiresUtc) -le [DateTimeOffset]::UtcNow -or $task.status -cne 'awaiting-approval'){throw 'Fresh approval identity, pre-QA status, or window is invalid.'}
    if($expired.status -cne 'approved' -or $expired.decidedBy -cne 'user' -or $expired.reason -cne 'explicit approval' -or $expired.expiresUtc -cne '2026-10-12T00:30:00Z'){throw 'Prior approval history was mutated.'}
    if([long]$task.mayaTaraExecution.TaskRevisionAtPrepare -ne [long]$task.revision){throw 'Prepared revision was not aligned to fresh approval revision.'}
    $null=Resolve-RepatoTaskApproval -StoreRoot $valid.Store -TaskId $taskId -Decision approve -Actor user -Reason 'test approval'
    $approved=Find-RepatoTask (Read-RepatoTaskStore $valid.Store) $taskId
    if([long]$approved.revision -ne ([long]$approved.mayaTaraExecution.TaskRevisionAtPrepare+1) -or $approved.status -cne 'in-progress' -or $approved.workflowStage -cne 'approval'){throw 'Prepared revision or pre-QA task state would fail the claim guard after approval.'}

    Reject 'wrong expired failure code' (New-State -WrongExpired) {param($s)Invoke-Request $s} 'Expired attempt recovery lineage is missing or ambiguous.'
    Reject 'mismatched attempt' (New-State) {param($s)Invoke-Request $s $oldRequest 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'} 'Expired attempt recovery lineage is missing or ambiguous.'
    Reject 'mismatched replacement run' (New-State) {param($s)Invoke-Request $s $oldRequest $oldAttempt $newAttempt 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'} 'Expired attempt recovery lineage is missing or ambiguous.'
    Reject 'mismatched candidate' (New-State) {param($s)Invoke-Request $s $oldRequest $oldAttempt $newAttempt $newRun ('F'*40)} 'Recovered attempt candidate evidence does not match the expected QA product candidate.'
    Reject 'stale task revision' (New-State) {param($s)Invoke-Request $s $oldRequest $oldAttempt $newAttempt $newRun $commit $hash ($revision-1)} 'Expired attempt task revision is stale.'
    Reject 'duplicate pending request' (New-State -Pending) {param($s)Invoke-Request $s} 'A pending qa-run approval already exists.'
    $broken=New-State;Invoke-RepatoStoreMutation $broken.Store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.mayaTaraExecutionHistory[1].ReplacementAttemptId='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';$t}|Out-Null
    Reject 'broken lineage' $broken {param($s)Invoke-Request $s} 'Expired attempt recovery lineage is missing or ambiguous.'
    $badPacket=New-State;Invoke-RepatoStoreMutation $badPacket.Store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.mayaTaraQaPacketHistory[0].Packet.ArtifactSha256='0'*64;$t}|Out-Null
    Reject 'altered packet candidate hash' $badPacket {param($s)Invoke-Request $s} 'Expired attempt recovery lineage packet evidence is missing or altered.'
    $wrongWorkflow=New-State;Invoke-RepatoStoreMutation $wrongWorkflow.Store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.mayaTaraExecutionHistory[1].WorkflowId='other-workflow';$t}|Out-Null
    Reject 'mismatched workflow lineage' $wrongWorkflow {param($s)Invoke-Request $s} 'Expired attempt recovery lineage identity mismatch.'
    $wrongTask=New-State;Invoke-RepatoStoreMutation $wrongTask.Store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.mayaTaraExecutionHistory[1].TaskId='other-task';$t}|Out-Null
    Reject 'mismatched task lineage' $wrongTask {param($s)Invoke-Request $s} 'Expired attempt recovery lineage identity mismatch.'
    Reject 'unexpired approval reuse' (New-State -ValidApproval) {param($s)Invoke-Request $s} 'Historical user approval is still valid.'
    Reject 'unrelated approval' (New-State -UnrelatedApproval) {param($s)Invoke-Request $s} 'An unrelated approved qa-run request prevents expired-attempt recovery.'
    [pscustomobject]@{Success=$true;ValidMultiStepLineage=$true;PriorApprovalUnchanged=$true;WrongFailureCodeRejected=$true;BrokenLineageRejected=$true;AlteredPacketHashRejected=$true;MismatchedTaskWorkflowRejected=$true;UnexpiredAndUnrelatedApprovalsRejected=$true;MismatchesRejected=$true;StaleRevisionRejected=$true;DuplicatePendingRejected=$true;RejectionsHadNoMutation=$true}|ConvertTo-Json -Compress
} finally {if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}}
