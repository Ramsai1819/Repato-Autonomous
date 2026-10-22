$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
$module=Get-Module Repato.MayaQaWorkflow
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('maya-cpv-duplicate-recovery-'+[guid]::NewGuid().ToString('N'))
$taskId='task-cpv-duplicate-recovery';$workflowId='workflow-cpv-duplicate-recovery'

function Get-ObjectHash($Value) {
    $json=ConvertTo-Json -InputObject $Value -Depth 50 -Compress
    $sha=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','') }
    finally { $sha.Dispose() }
}

function New-Fixture {
    $qa=Join-Path $scratch 'QA';$runs=Join-Path $qa 'TestRuns';$reports=Join-Path $qa 'Reports'
    New-Item -ItemType Directory -Path $runs,$reports -Force|Out-Null
    & $module {param($root)$script:MayaQaRootOverrideForTests=$root} $qa
    $attempt='a'*32;$run='b'*32;$claim='c'*32;$native='d'*32;$approvalId='e'*32
    $runtime=Join-Path $runs ($run+'-qa');New-Item -ItemType Directory -Path $runtime -Force|Out-Null
    $model=Join-Path $runtime 'model.rvt';[IO.File]::WriteAllBytes($model,[byte[]](1,2,3,4))
    $fixture=Join-Path $qa 'Fixtures\CreatePlanViewsEmpty.rvt';New-Item -ItemType Directory -Path (Split-Path $fixture) -Force|Out-Null;[IO.File]::WriteAllBytes($fixture,[byte[]](5,6,7,8));$fixtureHash=(Get-FileHash $fixture -Algorithm SHA256).Hash
    $sidecar=$model+'.fixture.json';[ordered]@{fixtureId='CreatePlanViewsEmpty';sourceSha256=$fixtureHash}|ConvertTo-Json|Set-Content -LiteralPath $sidecar
    $prepRequest=Join-Path $runs 'fixture-preparation.request.json';$prepResult=$prepRequest+'.preparation.json'
    [IO.File]::WriteAllText($prepRequest,'{"operation":"prepare-fixture"}');[IO.File]::WriteAllText($prepResult,'{"Status":"Passed"}')
    $requestPath=Join-Path $runtime 'maya-tara.request.json';$resultPath=$requestPath+'.result.json';$reportPath=Join-Path $reports ($run+'.json');$journalPath=Join-Path $runtime 'journal.txt'
    $expires=[DateTimeOffset]::UtcNow.AddHours(-2).ToString('O');$modelHash=(Get-FileHash $model -Algorithm SHA256).Hash;$candidateHash='F'*64
    $request=[ordered]@{operation='launch-revit-qa';requestId=$native;taskId=$taskId;workflowId=$workflowId;testId='create-plan-views-v1';attemptId=$attempt;runId=$run;claimId=$claim;modelPath=$model;modelSha256=$modelHash;expiresUtc=$expires}
    $request|ConvertTo-Json -Compress|Set-Content -LiteralPath $requestPath
    $report=[ordered]@{SchemaVersion=1;RunId=$run;TestId='create-plan-views-v1';RequestId=$native;TaskId=$taskId;WorkflowId=$workflowId;AttemptId=$attempt;ClaimId=$claim;Status='Failed';DocumentPath=$model;CreatedIds=@();ChangedIds=@();DeletedIds=@();Assertions=@([pscustomobject]@{Id='request-identity';Passed=$true});Errors=@("Create Plan Views runner failure: System.InvalidOperationException: Sequence contains more than one matching element`n   at Repato.Revit.TestRunner.CreatePlanViewsQaApplication.Execute(Document document, TestRunReport report)");RollbackStatus='NotStarted';AssemblyIdentity=[pscustomobject]@{Sha256=$candidateHash}}
    $report|ConvertTo-Json -Depth 15|Set-Content -LiteralPath $reportPath
    $receipt=[ordered]@{Status='Failed';RequestId=$native;TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId='create-plan-views-v1';TestId='create-plan-views-v1';AttemptId=$attempt;RunId=$run;ClaimId=$claim;ReportPath=$reportPath}
    $receipt|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $resultPath
    [IO.File]::WriteAllText($journalPath,'Application shutdown completed')
    $resultHash=(Get-FileHash $resultPath -Algorithm SHA256).Hash;$reportHash=(Get-FileHash $reportPath -Algorithm SHA256).Hash;$journalHash=(Get-FileHash $journalPath -Algorithm SHA256).Hash
    $prep=[pscustomobject]@{RequestPath=$prepRequest;RequestSha256=(Get-FileHash $prepRequest -Algorithm SHA256).Hash;ResultPath=$prepResult;ResultSha256=(Get-FileHash $prepResult -Algorithm SHA256).Hash;AttemptId=$attempt;RunId=$run;PreparedModelPath=$model;PreparedModelSha256=$modelHash}
    $binding=[ordered]@{TaskId=$taskId;WorkflowId=$workflowId;AttemptId=$attempt;RunId=$run;CandidateSha256=$candidateHash;ModelPath=$model;ModelSha256=$modelHash}
    $approval=[pscustomobject][ordered]@{requestId=$approvalId;action='qa-run';attemptId=$attempt;runId=$run;requiredLevel='user';status='approved';decidedBy='user';decidedUtc=[DateTimeOffset]::UtcNow.AddHours(-3).ToString('O');expiresUtc=$expires;consumedUtc=$null;executionBinding=$binding;bindingHash=(Get-ObjectHash $binding)}
    $cleanup=[pscustomobject]@{TaskId=$taskId;AttemptId=$attempt;RunId=$run;ClaimId=$claim;NativeRequestId=$native;NativeProcessId=7824;ProcessExitConfirmed=$true;Forced=$false;ModelUnlocked=$true;RetryAuthorized=$false;FailureClass='duplicate-floor-plan-view-family-type';TransactionStatus='NotStarted';RollbackStatus='NotRequired';ModelSha256=$modelHash;RequestPath=$requestPath;RequestSha256=(Get-FileHash $requestPath -Algorithm SHA256).Hash;ReceiptPath=$resultPath;ReceiptSha256=$resultHash;ReportPath=$reportPath;ReportSha256=$reportHash;JournalPath=$journalPath;JournalSha256=$journalHash;ExitVerification='terminal-journal-no-process-model-unlocked'}
    $execution=[pscustomobject]@{TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId='create-plan-views-v1';TestId='create-plan-views-v1';AttemptId=$attempt;RunId=$run;FailedClaimId=$claim;ClaimId=$null;ClaimOwner=$null;ClaimStatus='released';NativeRequestId=$native;NativeProcessId=7824;Stage='qa-failed';ExecutionStatus='QaFailed';FailureCode='duplicate-floor-plan-view-family-type';TransactionStatus='NotStarted';RollbackStatus='NotRequired';VerificationStatus='Failed';CompletionStatus='Failed';SideEffectsPerformed=$false;LaunchedUtc=[DateTimeOffset]::UtcNow.AddHours(-2.5).ToString('O');RequestPath=$requestPath;ResultPath=$resultPath;ReceiptPath=$resultPath;ReportPath=$reportPath;ResultSha256=$resultHash;ReportSha256=$reportHash;DisposableModelPath=$model;DisposableModelSha256=$modelHash;ArtifactSha256=$candidateHash;AuthoritativeFixturePath=$fixture;AuthoritativeFixtureSha256=(Get-FileHash $fixture -Algorithm SHA256).Hash;FixturePreparationEvidence=$prep;CleanupStatus='Verified';CleanupEvidence=$cleanup}
    $handoffId='handoff-'+[guid]::NewGuid().ToString('N')
    $workflowPlan=[pscustomobject]@{qaRunId=$run;qaModelPath=$model;qaSidecarPath=$sidecar;qaFixtureId='CreatePlanViewsEmpty';qaFixtureSha256=$fixtureHash;qaFixtureSpecSha256='';qaTestId='create-plan-views-v1';qaDisposableModelSha256=$modelHash;qaFixturePreparationEvidence=$prep;qaReportPath=$reportPath;qaReportSha256=$reportHash;qaEvidence=$null;qaVerificationStatus='Failed';qaCompletionStatus='Failed';qaCompletedUtc=$null;qaHandoffId=$handoffId;qaHandoff=[pscustomobject]@{HandoffId=$handoffId;HandoffStatus='ready';TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId='create-plan-views-v1';ModelPath=$model;SidecarPath=$sidecar};qaApprovalId=$approvalId;qaApprovalStatus='approved'}
    $store=Join-Path $scratch ('Store-'+[guid]::NewGuid().ToString('N'));New-RepatoTask $store $taskId 'CPV retest recovery' 'synthetic duplicate FloorPlan failure recovery' 'qa/cpv-duplicate-recovery' -RequiredApprovalLevel user|Out-Null
    Invoke-RepatoStoreMutation $store {
        param($data,$preview)
        $t=Find-RepatoTask $data $taskId;$t.status='blocked';$t.workflowStage='qa';$t.revision=[long]9
        $t|Add-Member NoteProperty mayaPlan ([pscustomobject]@{WorkflowId=$workflowId}) -Force
        $t|Add-Member NoteProperty mayaTaraAttempt ([pscustomobject]@{AttemptId=$attempt;RunId=$run;Stage='qa-failed';RequestExpiresUtc=$expires}) -Force
        $t|Add-Member NoteProperty mayaTaraExecution $execution -Force
        $t|Add-Member NoteProperty mayaTaraQaPacket ([pscustomobject]@{TaskId=$taskId;WorkflowId=$workflowId;AttemptId=$attempt;RunId=$run;ModelPath=$model}) -Force
        $t|Add-Member NoteProperty approvalRequests ([object[]]@($approval)) -Force
        $workflow=[pscustomobject]@{taskId=$taskId;workflowId=$workflowId;workflowRevision=1;taskRevision=9;stage='planned';qaWorkflowId='create-plan-views-v1';qaBuildStatus='succeeded';qaBuildRequest=[pscustomobject]@{BuildRequestId='previous-build'};qaBuildEvidence=[pscustomobject]@{BuildRequestId='previous-build';ArtifactSha256=$candidateHash}}
        foreach($property in $workflowPlan.PSObject.Properties){$workflow|Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force}
        $t|Add-Member NoteProperty deploymentWorkflows ([object[]]@($workflow)) -Force
        $t
    }|Out-Null
    [pscustomobject]@{Store=$store;TaskId=$taskId;WorkflowId=$workflowId;Attempt=$attempt;Run=$run;Claim=$claim;Native=$native;Approval=$approvalId;ResultHash=$resultHash;ReportHash=$reportHash;ModelHash=$modelHash}
}

function Invoke-Recovery($fixture,[long]$revision=9,[string]$claim=$fixture.Claim,[string]$resultHash=$fixture.ResultHash,[string]$reportHash=$fixture.ReportHash,[switch]$DryRun) {
    Recover-MayaQaReconciledDuplicateFloorPlanFailureForCandidateReplacement -StoreRoot $fixture.Store -TaskId $fixture.TaskId -WorkflowId $fixture.WorkflowId -ExpectedTaskRevision $revision -FailedAttemptId $fixture.Attempt -FailedRunId $fixture.Run -FailedClaimId $claim -NativeRequestId $fixture.Native -ApprovalRequestId $fixture.Approval -ExpectedResultSha256 $resultHash -ExpectedReportSha256 $reportHash -ExpectedModelSha256 $fixture.ModelHash -DryRun:$DryRun
}

function Get-ActiveApprovals($approvals) {
    & $module {param($items) @(Get-MayaQaActiveCanonicalExecutionApprovals -Approvals $items)} $approvals
}

function Invoke-WorkflowPlanReset($fixture,[long]$revision=$null,[string]$attempt=$fixture.Attempt,[string]$run=$fixture.Run,[string]$claim=$fixture.Claim,[string]$native=$fixture.Native,[string]$approval=$fixture.Approval,[string]$resultHash=$fixture.ResultHash,[string]$reportHash=$fixture.ReportHash,[string]$modelHash=$fixture.ModelHash,[switch]$DryRun) {
    if(!$revision){$revision=[long](Find-RepatoTask (Read-RepatoTaskStore $fixture.Store) $fixture.TaskId).revision}
    Reset-MayaQaReconciledDuplicateFloorPlanWorkflowPlan -StoreRoot $fixture.Store -TaskId $fixture.TaskId -WorkflowId $fixture.WorkflowId -ExpectedTaskRevision $revision -FailedAttemptId $attempt -FailedRunId $run -FailedClaimId $claim -NativeRequestId $native -ApprovalRequestId $approval -ExpectedResultSha256 $resultHash -ExpectedReportSha256 $reportHash -ExpectedModelSha256 $modelHash -DryRun:$DryRun
}

try {
    New-Item -ItemType Directory -Path $scratch -Force|Out-Null
    $good=New-Fixture
    $before=Find-RepatoTask (Read-RepatoTaskStore $good.Store) $good.TaskId
    $dry=Invoke-Recovery $good -revision 9 -DryRun
    if($dry.Status -cne 'DryRun' -or (Find-RepatoTask (Read-RepatoTaskStore $good.Store) $good.TaskId).revision -ne 9){throw 'Dry run changed canonical state.'}
    $approvalBefore=Get-ObjectHash $before.approvalRequests[0]
    $done=Invoke-Recovery $good -revision 9
    $after=Find-RepatoTask (Read-RepatoTaskStore $good.Store) $good.TaskId
    if($done.Status -cne 'Recovered' -or $after.status -cne 'in-progress' -or $after.workflowStage -cne 'build-checks' -or $after.mayaTaraExecution -or $after.mayaTaraAttempt){throw 'Successful recovery did not archive the failure and clear active pointers.'}
    if(@($after.mayaTaraExecutionHistory|Where-Object {$_.AttemptId -ceq $good.Attempt -and $_.FailureCode -ceq 'duplicate-floor-plan-view-family-type'}).Count -ne 1){throw 'Original failed execution was not preserved.'}
    if((Get-ObjectHash $after.approvalRequests[0]) -cne $approvalBefore -or $after.approvalRequests[0].consumedUtc){throw 'Historical approval was altered or falsely marked consumed.'}
    $planDry=Invoke-WorkflowPlanReset $good -revision ([long]$after.revision) -DryRun
    if($planDry.Status -cne 'DryRun' -or [long](Find-RepatoTask (Read-RepatoTaskStore $good.Store) $good.TaskId).revision -ne [long]$after.revision){throw 'Workflow-plan reset dry run mutated task state.'}
    $planReset=Invoke-WorkflowPlanReset $good -revision ([long]$after.revision)
    $after=Find-RepatoTask (Read-RepatoTaskStore $good.Store) $good.TaskId
    $workflowAfter=@($after.deploymentWorkflows|Where-Object workflowId -ceq $good.WorkflowId)[0]
    if($planReset.Status -cne 'Archived' -or $workflowAfter.qaRunId -or $workflowAfter.qaModelPath -or $workflowAfter.qaSidecarPath -or $workflowAfter.qaFixturePreparationEvidence -or $workflowAfter.qaHandoff -or $workflowAfter.qaApprovalId){throw 'Reconciled workflow plan was not archived and cleared.'}
    if(@($workflowAfter.qaRunHistory|Where-Object {$_.RunId -ceq $good.Run}).Count -ne 1 -or $workflowAfter.qaRunHistory[0].FixturePreparationEvidence.ResultSha256 -cne $after.mayaTaraExecutionHistory[0].FixturePreparationEvidence.ResultSha256){throw 'Prior run and fixture-preparation evidence were not preserved in workflow history.'}
    if((Get-ObjectHash $after.approvalRequests[0]) -cne $approvalBefore -or $after.approvalRequests[0].consumedUtc){throw 'Workflow-plan reset altered or consumed the expired historical approval.'}
    $resetRevision=[long]$after.revision;$resetReplay=Invoke-WorkflowPlanReset $good -revision $resetRevision
    if($resetReplay.Status -cne 'AlreadyArchived' -or [long](Find-RepatoTask (Read-RepatoTaskStore $good.Store) $good.TaskId).revision -ne $resetRevision){throw 'Workflow-plan reset replay was not idempotent.'}
    $resetRejected=$false;try{Invoke-WorkflowPlanReset $good -revision $resetRevision -modelHash ('0'*64)|Out-Null}catch{$resetRejected=$true}
    if(!$resetRejected -or [long](Find-RepatoTask (Read-RepatoTaskStore $good.Store) $good.TaskId).revision -ne $resetRevision){throw 'Mismatched-model workflow-plan reset was accepted or mutated task state.'}
    $nullPointers=[pscustomobject]@{mayaTaraAttempt=$null;mayaTaraExecution=$null;mayaTaraQaPacket=$null;mayaTaraExecutionEvidence=$null}
    $hasNullState=& $module {param($value)Test-MayaQaTaskHasTaraExecutionState -Task $value} $nullPointers
    $hasActiveState=& $module {param($value)Test-MayaQaTaskHasTaraExecutionState -Task $value} ([pscustomobject]@{mayaTaraExecution=[pscustomobject]@{ExecutionStatus='QaFailed'}})
    if($hasNullState -or !$hasActiveState){throw 'Tara execution-state guard did not distinguish null placeholders from an active record.'}
    $head=(& git -C (Split-Path $PSScriptRoot -Parent) rev-parse HEAD).Trim()
    $buildSource=[pscustomobject]@{RepositoryRoot=(Split-Path $PSScriptRoot -Parent);ExpectedSourceCommit=$head;ProjectRelativePath='Forma.RevitConnector.csproj'}
    $buildPlan=New-MayaQaCandidateReplacementBuildRequest -StoreRoot $good.Store -TaskId $good.TaskId -WorkflowId $good.WorkflowId -QaWorkflowId 'create-plan-views-v1' -AuthenticatedBuildSource $buildSource -SourceBranch 'fix/cpv-native-retest-20261020' -ProjectPath 'Forma.RevitConnector.csproj' -DryRun
    if($buildPlan.BuildStatus -cne 'planned' -or $buildPlan.SideEffectsPerformed -or (Find-RepatoTask (Read-RepatoTaskStore $good.Store) $good.TaskId).revision -ne $after.revision){throw 'Supported replacement-build planning rejected the exact reconciled failure or mutated state.'}
    $revisionAfter=[long]$after.revision;$replay=Invoke-Recovery $good -revision $revisionAfter
    if($replay.Status -cne 'AlreadyRecovered' -or (Find-RepatoTask (Read-RepatoTaskStore $good.Store) $good.TaskId).revision -ne $revisionAfter){throw 'Recovery replay was not idempotent.'}

    $cases=@(
        @{Name='mismatched-claim';Mutate={param($f,$t)$t.mayaTaraExecution.FailedClaimId='f'*32};Invoke={param($f)Invoke-Recovery $f -revision 9}},
        @{Name='mismatched-report-hash';Mutate={param($f,$t)$t.mayaTaraExecution.ReportSha256='0'*64};Invoke={param($f)Invoke-Recovery $f -revision 9}},
        @{Name='incomplete-cleanup';Mutate={param($f,$t)$t.mayaTaraExecution.CleanupEvidence.ProcessExitConfirmed=$false};Invoke={param($f)Invoke-Recovery $f -revision 9}},
        @{Name='approval-consumption-fabricated';Mutate={param($f,$t)$t.approvalRequests[0].consumedUtc=[DateTimeOffset]::UtcNow.ToString('O')};Invoke={param($f)Invoke-Recovery $f -revision 9}},
        @{Name='duplicate-approval-record';Mutate={param($f,$t)$t.approvalRequests=[object[]]@($t.approvalRequests)+$t.approvalRequests[0]};Invoke={param($f)Invoke-Recovery $f -revision 9}},
        @{Name='duplicate-execution-history';Mutate={param($f,$t)$t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@([pscustomobject]$t.mayaTaraExecution)) -Force};Invoke={param($f)Invoke-Recovery $f -revision 9}}
    )
    foreach($case in $cases) {
        $f=New-Fixture
        Invoke-RepatoStoreMutation $f.Store {param($data,$preview)$t=Find-RepatoTask $data $f.TaskId;& $case.Mutate $f $t}|Out-Null
        $state=Find-RepatoTask (Read-RepatoTaskStore $f.Store) $f.TaskId;$rev=[long]$state.revision
        $rejected=$false;try{& $case.Invoke $f|Out-Null}catch{$rejected=$true}
        $afterFailure=Find-RepatoTask (Read-RepatoTaskStore $f.Store) $f.TaskId
        if(!$rejected -or [long]$afterFailure.revision -ne $rev -or $afterFailure.status -cne 'blocked'){throw "Negative case was accepted or mutated state: $($case.Name)"}
    }
    $active=Get-ActiveApprovals @(
        [pscustomobject]@{action='qa-run';status='approved';consumedUtc=$null;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('O')},
        [pscustomobject]@{action='qa-run';status='approved';consumedUtc=$null;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(10).ToString('O')},
        [pscustomobject]@{action='qa-run';status='approved';consumedUtc=[DateTimeOffset]::UtcNow.ToString('O');expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(10).ToString('O')}
    )
    if($active.Count -ne 1){throw 'Only the unexpired, unconsumed user approval should block a fresh request.'}
    $badExpiryRejected=$false;try{Get-ActiveApprovals @([pscustomobject]@{action='qa-run';status='pending';expiresUtc='invalid'})|Out-Null}catch{$badExpiryRejected=$true}
    if(!$badExpiryRejected){throw 'Malformed approval expiry was accepted.'}
    [pscustomobject]@{Success=$true;DryRunReadOnly=$true;ExactEvidenceRequired=$true;ExpiredApprovalPreservedUnconsumed=$true;OriginalFailurePreserved=$true;WorkflowPlanArchived=$true;ReplacementBuildPathEligible=$true;ReplayIdempotent=$true;NegativeCases=($cases.Count+1);ApprovalExpiryGating=$true;NullTaraStateHandled=$true;NativeLaunchPerformed=$false}|ConvertTo-Json -Compress
}
finally {
    & $module {$script:MayaQaRootOverrideForTests=$null}
    if(Test-Path -LiteralPath $scratch){Remove-Item -LiteralPath $scratch -Recurse -Force}
}
