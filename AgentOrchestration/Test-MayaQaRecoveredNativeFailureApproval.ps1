$ErrorActionPreference='Stop'
$here=$PSScriptRoot
Import-Module (Join-Path $here 'Repato.AgentOrchestration.psm1') -Force
Import-Module (Join-Path $here 'Repato.Deployment.psm1') -Force
Import-Module (Join-Path $here 'Repato.MayaQaWorkflow.psm1') -Force

$failedAttempt='caf371390d2847e591c1e74fc93b2f25';$failedRun='d30688cb58e44eacb484a417dc808a61'
$attemptId='09b24086fb72412f901dc82f5525f95c';$runId='cd1aff614c5c4bf7a89fe3fc538be7c8'
$commit='e2b5bcf889657b82cc10fd46909d145cd27ff2e0';$artifactHash='56B6E70E42FBFEAF8DA502E53C31C5CC1DAE1CA6A56A7CD3AC258CA573C5D9F5'
$runtime='1.0.10+50d5d752d9a8';$taskId='task-native-failure-approval';$workflowId='workflow-native-failure-approval';$buildId='build-native-failure-approval';$revision=[long]42
$root=Join-Path ([IO.Path]::GetTempPath()) ('maya-native-failure-approval-'+[guid]::NewGuid().ToString('N'))

function New-State([switch]$Pending,[switch]$WrongFailureCode,[switch]$PassedTask,[switch]$UnexpiredApproved,[switch]$ConsumedApproved) {
    $store=Join-Path $root ([guid]::NewGuid().ToString('N'));New-RepatoTask $store $taskId 'Recovered QA' 'approval continuation test' 'qa/native-failure'|Out-Null
    $result=Join-Path $store 'failed.result.json';$report=Join-Path $store 'failed.report.json';Set-Content -LiteralPath $result -Value '{"Status":"Failed"}' -Encoding UTF8;Set-Content -LiteralPath $report -Value '{"Status":"Failed"}' -Encoding UTF8
    $resultHash=(Get-FileHash $result -Algorithm SHA256).Hash;$reportHash=(Get-FileHash $report -Algorithm SHA256).Hash
    Invoke-RepatoStoreMutation $store {
        param($d,$preview)
        $t=Find-RepatoTask $d $taskId;$t.status=if($PassedTask){'passed'}else{'in-progress'};$t.workflowStage='approval';$t.revision=$revision
        $t|Add-Member NoteProperty mayaPlan ([pscustomobject]@{WorkflowId=$workflowId;QaWorkflowId='create-plan-views-v1'}) -Force
        $archive=[pscustomobject]@{AttemptId=$failedAttempt;RunId=$failedRun;Stage='qa-failed';ExecutionStatus='QaFailed';FailureCode=$(if($WrongFailureCode){'request-expired'}else{'native-qa-failed'});ReplacementAttemptId=$attemptId;ReplacementRunId=$runId;ResultPath=$result;ResultSha256=$resultHash;ReportPath=$report;ReportSha256=$reportHash}
        $t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@($archive)) -Force
        $t|Add-Member NoteProperty mayaTaraAttempt ([pscustomobject]@{AttemptId=$attemptId;RunId=$runId;Stage='prepared'}) -Force
        $t|Add-Member NoteProperty mayaTaraExecution ([pscustomobject]@{TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId='create-plan-views-v1';AttemptId=$attemptId;RunId=$runId;ArtifactSha256=$artifactHash;Stage='prepared';ExecutionStatus='Prepared';ClaimId=$null;ClaimOwner=$null;NativeProcessId=$null;RequestPath=$null;ResultPath=$null;ReportPath=$null;ReceiptPath=$null;SideEffectsPerformed=$false}) -Force
        $oldExpiry=if($UnexpiredApproved -or $ConsumedApproved){'2099-01-02T00:00:00Z'}else{'2026-01-02T00:00:00Z'};$oldConsumedUtc=if($ConsumedApproved){'2026-01-01T00:02:00Z'}else{$null}
        $old=[pscustomobject]@{requestId='expired-old-approval';action='qa-run';requiredLevel='user';status='approved';bindingHash='';previousStatus='in-progress';requestedRevision=40;approvedRevision=41;requestedUtc='2026-01-01T00:00:00Z';expiresUtc=$oldExpiry;decidedUtc='2026-01-01T00:01:00Z';decidedBy='user';reason=$null;consumedUtc=$oldConsumedUtc}
        $t.approvalRequests=[object[]]@($old)
        if($Pending){$t.approvalRequests=[object[]]@($t.approvalRequests)+[pscustomobject]@{requestId='pending-existing';action='qa-run';requiredLevel='user';status='pending';bindingHash='';previousStatus='in-progress';requestedRevision=41;approvedRevision=$null;requestedUtc='2026-01-01T00:00:00Z';expiresUtc='2099-01-01T00:00:00Z';decidedUtc=$null;decidedBy=$null;reason=$null;consumedUtc=$null}}
        $t|Add-Member NoteProperty deploymentWorkflows ([object[]]@([pscustomobject]@{workflowId=$workflowId;qaWorkflowId='create-plan-views-v1';qaBuildStatus='succeeded';qaBuildRequest=[pscustomobject]@{BuildRequestId=$buildId};qaBuildEvidence=[pscustomobject]@{BuildRequestId=$buildId;BuildStatus='succeeded';EvidenceSource='FrozenCandidate';SourceCommit=$commit;CandidateSourceCommit=$commit;ArtifactSha256=$artifactHash;DeploymentValidation=$true;ManifestIntegrityValidation=$true;QaIsolation=$true}})) -Force
        $t
    }|Out-Null
    [pscustomobject]@{Store=$store;Result=$result;Report=$report}
}
function Request([object]$state,[string]$expectedAttempt=$attemptId,[string]$expectedRun=$runId,[string]$expectedCommit=$commit,[string]$expectedHash=$artifactHash,[long]$expectedRevision=$revision) {
    Request-MayaQaRecoveredNativeFailureApproval -StoreRoot $state.Store -TaskId $taskId -WorkflowId $workflowId -FailedAttemptId $failedAttempt -RecoveredAttemptId $expectedAttempt -RecoveredRunId $expectedRun -ExpectedTaskRevision $expectedRevision -ExpectedCandidateSourceCommit $expectedCommit -ExpectedCandidateSha256 $expectedHash -LaunchAgentRuntimeVersion $runtime
}
function Snapshot([string]$store) {@(Get-ChildItem -LiteralPath $store -File -Recurse|Sort-Object FullName|ForEach-Object {"$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"}) -join "`n"}
function RejectWithoutMutation([string]$name,[object]$state,[scriptblock]$invoke,[string]$message) {
    $before=Snapshot $state.Store
    try{& $invoke $state|Out-Null;throw "$name unexpectedly accepted."}catch{if($_.Exception.Message -eq "$name unexpectedly accepted."){throw};if($_.Exception.Message -notmatch [regex]::Escape($message)){throw "$name returned unexpected guard: $($_.Exception.Message)"}}
    if((Snapshot $state.Store) -cne $before){throw "$name mutated the task store on rejection."}
}
try {
    $valid=New-State
    $result=Request $valid
    $task=Find-RepatoTask (Read-RepatoTaskStore $valid.Store) $taskId
    $pending=@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})
    if($task.status -cne 'awaiting-approval' -or $task.workflowStage -cne 'approval' -or $pending.Count -ne 1 -or $pending[0].requiredLevel -cne 'user' -or $pending[0].previousStatus -cne 'in-progress' -or $pending[0].attemptId -cne $attemptId -or $pending[0].runId -cne $runId -or $pending[0].candidate.SourceCommit -cne $commit -or $pending[0].candidate.ArtifactSha256 -ine $artifactHash -or $pending[0].runtime.Version -cne $runtime -or $pending[0].requestId -eq 'expired-old-approval' -or [long]$pending[0].requestedRevision -ne [long]$task.revision){throw 'Valid recovered native-failure approval transition failed.'}
    if(@($task.approvalRequests|Where-Object requestId -ceq 'expired-old-approval')[0].status -cne 'superseded'){throw 'Expired approval was not superseded.'}
    if(!(Test-Path $valid.Result) -or !(Test-Path $valid.Report)){throw 'Archived failure evidence was not preserved.'}
    Resolve-RepatoTaskApproval -StoreRoot $valid.Store -TaskId $taskId -Decision approve -Actor user -Reason 'Synthetic approval-state transition validation'|Out-Null
    $approvedTask=Find-RepatoTask (Read-RepatoTaskStore $valid.Store) $taskId
    if($approvedTask.status -cne 'in-progress' -or $approvedTask.workflowStage -cne 'approval'){throw 'Human approval did not return to the correct in-progress QA state.'}

    $consumed=New-State -ConsumedApproved
    $consumedBefore=(@((Find-RepatoTask (Read-RepatoTaskStore $consumed.Store) $taskId).approvalRequests|Where-Object requestId -ceq 'expired-old-approval')[0].consumedUtc)
    $null=Request $consumed
    $consumedAfterTask=Find-RepatoTask (Read-RepatoTaskStore $consumed.Store) $taskId;$consumedRecord=@($consumedAfterTask.approvalRequests|Where-Object requestId -ceq 'expired-old-approval')[0]
    if($consumedRecord.status -cne 'approved' -or $consumedRecord.consumedUtc -cne $consumedBefore){throw 'Consumed approved authorization was modified during fresh approval recovery.'}

    $cases=@(
        @{Name='wrong failure code';State=(New-State -WrongFailureCode);Invoke={param($s)Request $s};Guard='Exact archived native-qa-failed recovery identity is required.'},
        @{Name='active unconsumed approval';State=(New-State -UnexpiredApproved);Invoke={param($s)Request $s};Guard='An existing unconsumed qa-run approval has not expired.'},
        @{Name='passed status is not recovery-ready';State=(New-State -PassedTask);Invoke={param($s)Request $s};Guard='Recovered task is not in the canonical in-progress approval state.'},
        @{Name='mismatched attempt';State=(New-State);Invoke={param($s)Request $s 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'};Guard='Exact archived native-qa-failed recovery identity is required.'},
        @{Name='mismatched run';State=(New-State);Invoke={param($s)Request $s $attemptId 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'};Guard='Exact archived native-qa-failed recovery identity is required.'},
        @{Name='mismatched candidate';State=(New-State);Invoke={param($s)Request $s $attemptId $runId ('F'*40) $artifactHash};Guard='Recovered attempt candidate evidence does not match the expected QA product candidate.'},
        @{Name='stale revision';State=(New-State);Invoke={param($s)Request $s $attemptId $runId $commit $artifactHash ($revision-1)};Guard='Recovered task revision is stale.'},
        @{Name='duplicate pending approval';State=(New-State -Pending);Invoke={param($s)Request $s};Guard='A pending qa-run approval already exists.'}
    )
    foreach($case in $cases){RejectWithoutMutation $case.Name $case.State $case.Invoke $case.Guard}
    [pscustomobject]@{Success=$true;ValidTransition=$true;PassedStatusRejected=$true;ApprovalReturnsToInProgress=$true;ConsumedUnexpiredApprovalPreserved=$true;ActiveUnconsumedApprovalRejected=$true;WrongFailureCodeRejected=$true;MismatchedAttemptRejected=$true;MismatchedRunRejected=$true;MismatchedCandidateRejected=$true;StaleRevisionRejected=$true;DuplicatePendingRejected=$true;RejectionsHadNoMutation=$true}|ConvertTo-Json -Compress
} finally {if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}}
