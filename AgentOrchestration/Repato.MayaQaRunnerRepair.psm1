Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -WarningAction SilentlyContinue

function New-MayaQaCanonicalRunId {
    [guid]::NewGuid().ToString('N')
}

function New-MayaQaRunnerRepairBuildRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$FailedAttemptId,
        [string]$UserRequest='Repair missing Create Plan Views QA runner',
        [switch]$DryRun
    )
    $data=Read-RepatoTaskStore $StoreRoot
    $task=Find-RepatoTask $data $TaskId
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $attempt=$task.mayaTaraAttempt
    $execution=$task.mayaTaraExecution
    if(!$task -or $task.status -cne 'blocked' -or $task.workflowStage -cne 'qa' -or !$attempt -or !$execution -or
       $attempt.AttemptId -cne $FailedAttemptId -or $execution.AttemptId -cne $FailedAttemptId -or
       $attempt.Stage -cne 'runner-startup-failed' -or $execution.Stage -cne 'runner-startup-failed' -or
       $execution.ExecutionStatus -cne 'RunnerStartupFailed' -or $execution.FailureCode -cne 'runner-startup-failed')
        { throw 'Repair build request requires the exact terminal runner-startup-failed attempt.' }
    $evidence=$execution.RunnerStartupEvidence
    if(!$evidence -or $evidence.Disposition -cne 'Revit launched; runner startup failed; no QA result' -or
       !$evidence.ProcessExitConfirmed -or !$evidence.ResultAbsent -or !$evidence.ManualLoadOnceAcknowledged -or
       [string]$evidence.AttemptId -cne $FailedAttemptId -or [string]$evidence.TaskId -cne $TaskId)
        { throw 'Audited startup-failure evidence is incomplete or not bound to this attempt.' }
    if($execution.ReportPath -or $execution.ReceiptPath -or (Test-Path -LiteralPath ([string]$execution.ResultPath)))
        { throw 'Request-bound QA result evidence exists; this repair-build path is not eligible.' }
    if(@(Get-Process -Name Revit -ErrorAction SilentlyContinue).Count) { throw 'A Revit process is present; repair build preparation is blocked.' }

    $oldBuild=$workflow.qaBuildEvidence
    if($workflow.qaBuildStatus -cne 'succeeded' -or !$oldBuild -or $oldBuild.EvidenceSource -cne 'FrozenCandidate' -or
       $oldBuild.CandidateSourceCommit -cne 'fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3' -or
       $oldBuild.ArtifactSha256 -cne '7EC1C819C771DCE4EC4ADCADB93B0245D243F6675EC0F0B070B03303B1F412C2')
        { throw 'Persisted prior candidate is not the confirmed frozen candidate.' }
    if(!$workflow.qaBuildRequest -or !$workflow.qaBuildRequest.BuildRequestId -or
       !$workflow.qaBuildRequest.AuthenticatedBuildSource -or
       [string]$workflow.qaBuildRequest.AuthenticatedBuildSource.ExpectedSourceCommit -cne 'fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3')
        { throw 'Prior persisted build request is not bound to the confirmed frozen source.' }
    foreach($name in 'qaReportPath','qaReceiptPath','qaEvidence','qaVerificationStatus','qaCompletionStatus') {
        if($workflow.PSObject.Properties.Name -contains $name -and $workflow.$name) { throw "Repair build found terminal QA evidence: $name." }
    }

    $repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $project=[IO.Path]::GetFullPath((Join-Path $repo 'Forma.RevitConnector.csproj'))
    $sourceCommit=Get-MayaQaTrustedBuildSourceCommit -RepositoryRoot $repo -ProjectPath $project
    $branch=(& git -C $repo branch --show-current 2>$null).Trim()
    if($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) { throw 'Repair build source branch could not be resolved.' }
    $requestId='build-'+[guid]::NewGuid().ToString('N')
    $replacement=[pscustomobject][ordered]@{
        BuildRequestId=$requestId; SourceBranch=$branch; ProjectPath='Forma.RevitConnector.csproj'
        AuthenticatedBuildSource=$null; RequestedArtifact='bin\Release\net8.0-windows\Repato.Revit.dll'
        BuildStatus='requested'; RequestedUtc=(Get-Date).ToUniversalTime().ToString('O')
    }
    if($DryRun) {
        return [pscustomobject]@{Mode='DryRun';TaskId=$TaskId;WorkflowId=$WorkflowId;FailedAttemptId=$FailedAttemptId;
            PreviousBuildRequestId=$workflow.qaBuildRequest.BuildRequestId;ReplacementBuildRequestId=$requestId;
            SourceBranch=$branch;SourceCommit=$sourceCommit;ProjectPath=$project;CandidateEvidencePreserved=$true;
            StoreMutationPerformed=$false;CandidateBuilt=$false;DeploymentPerformed=$false;QaAttemptCreated=$false}
    }
    $oldWorkflowRevision=[long]$workflow.workflowRevision
    $oldTaskRevision=[long]$task.revision
    $prior=[pscustomobject][ordered]@{BuildRequest=$workflow.qaBuildRequest;BuildEvidence=$oldBuild;
        SupersededByBuildRequestId=$requestId;SupersededUtc=(Get-Date).ToUniversalTime().ToString('O');
        Reason='Confirmed runner-startup-failed; rebuild source contains the restored manifest-bound runner.'}
    $mutation=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $oldWorkflowRevision $oldTaskRevision {
        param($current)
        if($current.qaBuildRequest.BuildRequestId -cne $workflow.qaBuildRequest.BuildRequestId -or
           $current.qaBuildStatus -cne 'succeeded' -or $current.qaBuildEvidence.CandidateSourceCommit -cne $oldBuild.CandidateSourceCommit)
            { throw 'Repair build request compare-and-swap failed.' }
        if($current.PSObject.Properties.Name -notcontains 'qaBuildHistory') { $current|Add-Member NoteProperty qaBuildHistory ([object[]]@()) -Force }
        $current.qaBuildHistory=[object[]]@($current.qaBuildHistory)+$prior
        $current.qaBuildRequestId=$requestId
        $current.qaBuildRequest=$replacement
        $current.qaBuildStatus='requested'
        $current.qaBuildEvidence=$null
        return $current
    })[-1]
    [pscustomobject]@{Mode='Superseded';TaskId=$TaskId;WorkflowId=$WorkflowId;FailedAttemptId=$FailedAttemptId;
        PreviousBuildRequestId=$workflow.qaBuildRequest.BuildRequestId;BuildRequestId=$requestId;SourceBranch=$branch;
        SourceCommit=$sourceCommit;WorkflowRevision=$mutation.Workflow.workflowRevision;TaskRevision=$mutation.TaskRevision;
        PriorCandidateEvidenceRetained=$true;QaAttemptCreated=$false;DeploymentPerformed=$false}
}

function Reset-MayaQaRunnerRepairForCanonicalValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$FailedAttemptId,
        [Parameter(Mandatory)][string]$BuildRequestId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$CandidateDirectory,
        [string]$CandidateDllPath,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedCandidateSha256,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{40}$')][string]$ExpectedCandidateSourceCommit,
        [scriptblock]$RevitProcessProvider,
        [switch]$DryRun
    )
    $verified=Test-MayaQaFrozenCandidate -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedSha256 $ExpectedCandidateSha256 -ExpectedSourceCommit $ExpectedCandidateSourceCommit -QaWorkflowId $QaWorkflowId
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    if(!$task -or $task.status -cne 'blocked' -or $task.workflowStage -cne 'qa'){throw 'Runner-repair reset requires the blocked QA task.'}
    $workflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId);if($workflows.Count -ne 1){throw 'Runner-repair reset requires the exact workflow.'};$workflow=$workflows[0]
    $attempt=$task.mayaTaraAttempt;$execution=$task.mayaTaraExecution;$evidence=$execution.RunnerStartupEvidence
    $startupFailure=($attempt.Stage -ceq 'runner-startup-failed' -and $execution.Stage -ceq 'runner-startup-failed' -and $execution.ExecutionStatus -ceq 'RunnerStartupFailed' -and $evidence -and $evidence.ProcessExitConfirmed -and $evidence.ResultAbsent -and $evidence.ManualLoadOnceAcknowledged -and $evidence.AttemptId -ceq $FailedAttemptId -and $evidence.TaskId -ceq $TaskId)
    $invalidRequestFailure=($attempt.Stage -ceq 'qa-failed' -and $execution.Stage -ceq 'qa-failed' -and $execution.ExecutionStatus -ceq 'QaFailed' -and $execution.FailureCode -ceq 'canonical-request-invalid' -and $execution.RollbackStatus -ceq 'NotStartedNoDocumentOpened' -and !$execution.SideEffectsPerformed -and $execution.TaskId -ceq $TaskId -and $execution.ManualLoadOnceEvidence -and $execution.ManualLoadOnceEvidence.AttemptId -ceq $FailedAttemptId -and $execution.ManualLoadOnceEvidence.RunId -ceq $execution.RunId -and $execution.ManualLoadOnceEvidence.ClaimId -ceq $execution.ClaimId -and $execution.ManualLoadOnceEvidence.NativeRequestId -ceq $execution.NativeRequestId)
    if(!$attempt -or !$execution -or $attempt.AttemptId -cne $FailedAttemptId -or $execution.AttemptId -cne $FailedAttemptId -or $attempt.RunId -cne $execution.RunId -or (!$startupFailure -and !$invalidRequestFailure))
        {throw 'Recovery requires exact preserved terminal attempt and execution identity.'}
    if($invalidRequestFailure){
        $resultExists=![string]::IsNullOrWhiteSpace([string]$execution.ResultPath) -and (Test-Path -LiteralPath ([string]$execution.ResultPath))
        if(!$execution.ReportPath -or !(Test-Path -LiteralPath $execution.ReportPath -PathType Leaf) -or (Get-FileHash -LiteralPath $execution.ReportPath -Algorithm SHA256).Hash -ine $execution.ReportSha256 -or !$execution.FailureDetails -or $execution.ReceiptPath -or $resultExists){throw 'Terminal invalid-request report identity or absence-of-result evidence is invalid.'}
        $report=Get-Content -LiteralPath $execution.ReportPath -Raw|ConvertFrom-Json
        if($report.Status -cne 'Failed' -or @($report.Assertions).Count -ne 0 -or @($report.Errors).Count -ne 1 -or $report.Errors[0] -cne $execution.FailureDetails -or $report.RollbackStatus -cne 'NotStarted'){throw 'Terminal invalid-request report does not match preserved failure evidence.'}
    } elseif($execution.ReportPath -or $execution.ReceiptPath -or (![string]::IsNullOrWhiteSpace([string]$execution.ResultPath) -and (Test-Path -LiteralPath ([string]$execution.ResultPath)))){throw 'QA result evidence exists; runner-repair reset is not eligible.'}
    $revit=if($RevitProcessProvider){@(& $RevitProcessProvider)}else{@(Get-Process Revit -ErrorAction SilentlyContinue)};if($revit.Count){throw 'A Revit process is present; runner-repair reset is blocked.'}
    if($workflow.qaWorkflowId -cne $QaWorkflowId -or !$workflow.qaBuildRequest -or $workflow.qaBuildRequest.BuildRequestId -cne $BuildRequestId -or $workflow.qaBuildStatus -cne 'succeeded')
        {throw 'Replacement repair build request identity or status is invalid.'}
    $build=$workflow.qaBuildEvidence
    if(!$build -or $build.BuildRequestId -cne $BuildRequestId -or $build.BuildStatus -cne 'succeeded' -or $build.SourceCommit -cne $ExpectedCandidateSourceCommit -or
       $build.ArtifactSha256 -ine $ExpectedCandidateSha256 -or $verified.SourceCommit -cne $ExpectedCandidateSourceCommit -or $verified.ArtifactSha256 -ine $ExpectedCandidateSha256)
        {throw 'Replacement repair build/candidate identity mismatch.'}
    if(@($task.mayaTaraRepairRecoveryHistory|Where-Object FailedAttemptId -ceq $FailedAttemptId).Count){throw 'Terminal runner-startup repair has already been reset.'}
    $now=(Get-Date).ToUniversalTime().ToString('O')
    $bound=[pscustomobject][ordered]@{BuildRequestId=$BuildRequestId;StartedUtc=$build.StartedUtc;FinishedUtc=$build.FinishedUtc;Command='FrozenCandidate integrity and provenance validation (no compilation)';Configuration='Release';SourceCommit=$verified.SourceCommit;ExitCode=0;ArtifactPath=$verified.ArtifactPath;ArtifactSha256=$verified.ArtifactSha256;ManifestPath=$verified.ManifestPath;ManifestSha256=$verified.ManifestSha256;BuildStatus='succeeded';WarningCount=0;ErrorCount=0;ErrorLines=@();EvidenceSource='FrozenCandidate';CandidateDirectory=$verified.CandidateDirectory;CandidateProvenancePath=$verified.ProvenancePath;CandidateProvenanceSha256=$verified.ProvenanceSha256;CandidateSourceCommit=$verified.SourceCommit;QaWorkflowId=$QaWorkflowId;DeploymentValidation=$false;ManifestIntegrityValidation=$false;QaIsolation=$false}
    $archive=[pscustomobject][ordered]@{SchemaVersion=1;FailedAttemptId=$FailedAttemptId;RunId=$execution.RunId;ArchivedUtc=$now;Reason=if($invalidRequestFailure){'Terminal canonical-request-invalid attempt archived before fresh canonical preparation'}else{'Terminal runner-startup failure repaired by exact replacement candidate'};MayaPlan=$task.mayaPlan;QaPacket=$task.mayaTaraQaPacket;Attempt=$attempt;Execution=$execution;WorkflowHandoff=$workflow.qaHandoff;WorkflowHandoffId=$workflow.qaHandoffId;ReportPath=$execution.ReportPath;ReportSha256=$execution.ReportSha256;ManualEvidencePreserved=$true;ReplacementBuildRequestId=$BuildRequestId;ReplacementSourceCommit=$verified.SourceCommit;ReplacementArtifactSha256=$verified.ArtifactSha256}
    if($DryRun){return [pscustomobject]@{Status='DryRun';TaskId=$TaskId;WorkflowId=$WorkflowId;FailedAttemptId=$FailedAttemptId;BuildRequestId=$BuildRequestId;CandidateSourceCommit=$verified.SourceCommit;CandidateSha256=$verified.ArtifactSha256;EvidencePreserved=$true;RevitLaunched=$false;SideEffectsPerformed=$false}}
    $expectedTaskRevision=[long]$task.revision;$expectedWorkflowRevision=[long]$workflow.workflowRevision
    $result=Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)
        $t=Find-RepatoTask $d $TaskId;if([long]$t.revision -ne $expectedTaskRevision){throw 'Runner-repair reset task compare-and-swap failed.'}
        $ws=@($t.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId);if($ws.Count -ne 1 -or [long]$ws[0].workflowRevision -ne $expectedWorkflowRevision){throw 'Runner-repair reset workflow compare-and-swap failed.'};$w=$ws[0]
        if($t.mayaTaraExecution.AttemptId -cne $FailedAttemptId -or $w.qaBuildRequest.BuildRequestId -cne $BuildRequestId){throw 'Runner-repair reset identity changed.'}
        if($t.PSObject.Properties.Name -notcontains 'mayaTaraRepairRecoveryHistory'){$t|Add-Member NoteProperty mayaTaraRepairRecoveryHistory ([object[]]@()) -Force};$t.mayaTaraRepairRecoveryHistory=[object[]]@($t.mayaTaraRepairRecoveryHistory)+$archive
        foreach($n in 'mayaPlan','mayaTaraQaPacket','mayaTaraAttempt','mayaTaraExecution','mayaTaraExecutionEvidence'){$t.PSObject.Properties.Remove($n)}
        foreach($n in 'qaHandoffId','qaHandoff','qaApprovalId','qaApprovalStatus','qaRunId','qaModelPath','qaSidecarPath','qaFixtureId','qaFixtureSha256','qaTestId','qaReportPath','qaReportSha256','qaEvidence','qaVerificationStatus','qaCompletionStatus','qaCompletedUtc'){$w.PSObject.Properties.Remove($n)}
        $w.qaBuildEvidence=$bound;$w.qaBuildStatus='succeeded';$w.workflowRevision=[long]$w.workflowRevision+1;$w.taskRevision=[long]$t.revision
        foreach($q in @($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -in @('pending','approved')})){$q.status='superseded';$q.reason='Superseded by audited runner-repair recovery.'}
        $q=[pscustomobject]@{requestId=[guid]::NewGuid().ToString('N');action='qa-run';requiredLevel='maya';status='pending';bindingHash='';previousStatus='passed';requestedRevision=[long]$t.revision;approvedRevision=$null;requestedUtc=$now;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(30).ToString('O');decidedUtc=$null;decidedBy=$null;reason=$null;consumedUtc=$null}
        $t.approvalRequests=[object[]]@($t.approvalRequests)+$q;$t.status='awaiting-approval';$t.workflowStage='approval';$t.errorDetails=$null
        Add-RepatoHistory $t 'maya-tara-runner-repair-reset' 'Maya' "failedAttempt=$FailedAttemptId; build=$BuildRequestId; candidate=$($verified.ArtifactSha256)"
        $q.requestedRevision=[long]$t.revision
        [pscustomobject]@{Task=$t;Workflow=$w;Approval=$q}
    }
    [pscustomobject]@{Status='ReadyForCanonicalDeploymentValidation';TaskId=$TaskId;WorkflowId=$WorkflowId;FailedAttemptId=$FailedAttemptId;BuildRequestId=$BuildRequestId;CandidateSourceCommit=$verified.SourceCommit;CandidateSha256=$verified.ArtifactSha256;TaskRevision=$result.Task.revision;WorkflowRevision=$result.Workflow.workflowRevision;ApprovalId=$result.Approval.requestId;EvidencePreserved=$true;TaraState='absent';RevitLaunched=$false;SideEffectsPerformed=$true}
}

function Record-MayaQaUnresolvedStagingRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{32}$')][string]$RequestId)
    $record=[pscustomobject][ordered]@{RequestId=$RequestId;Disposition='unresolved-task-binding';RecordedUtc=(Get-RepatoUtc)}
    Invoke-RepatoStoreMutation $StoreRoot {
        param($data,$preview)
        if($data.PSObject.Properties.Name -notcontains 'stagingRequestDispositions'){$data|Add-Member NoteProperty stagingRequestDispositions ([object[]]@())}
        $matches=@($data.stagingRequestDispositions|Where-Object RequestId -ceq $RequestId)
        if($matches.Count -gt 1){throw 'Staging request disposition is not unique.'}
        if($matches.Count -eq 1){if($matches[0].Disposition -cne 'unresolved-task-binding' -or $matches[0].PSObject.Properties.Name -contains 'TaskId' -or $matches[0].PSObject.Properties.Name -contains 'WorkflowId'){throw 'Staging request already has a conflicting disposition.'};return $matches[0]}
        $data.stagingRequestDispositions=[object[]]@($data.stagingRequestDispositions)+$record
        $record
    }
}

function Assert-MayaQaAuthenticatedStagingReceiptBinding {
    param([Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)][string]$RequestId,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId)
    if(!$Receipt.PSObject.Properties['AuthenticatedRequestBinding'] -or $Receipt.AuthenticatedRequestBinding -ne $true -or
       !$Receipt.PSObject.Properties['TaskId'] -or !$Receipt.PSObject.Properties['WorkflowId'] -or !$Receipt.PSObject.Properties['RequestId'] -or
       [string]$Receipt.RequestId -cne $RequestId -or [string]$Receipt.TaskId -cne $TaskId -or [string]$Receipt.WorkflowId -cne $WorkflowId){
        throw 'Staging receipt lacks authenticated request-to-task/workflow binding.'
    }
    $true
}

function Complete-MayaQaAmbiguousStagingReconciliation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$BuildRequestId,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$TestId,
        [Parameter(Mandatory)][string]$CandidateSourceCommit,[Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$CandidateSha256,
        [Parameter(Mandatory)][string]$RequestId,[Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$PayloadHash,
        [Parameter(Mandatory)][string]$ExpectedSeenUtc,[Parameter(Mandatory)][string]$LedgerPath,
        [Parameter(Mandatory)][string]$DeployedDllPath,[Parameter(Mandatory)][string]$RunnerManifestPath,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$RunnerManifestSha256,
        [scriptblock]$RevitProcessProvider,[switch]$DryRun
    )
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    if(!$task -or $task.status -cne 'awaiting-approval' -or $task.workflowStage -cne 'approval'){throw 'Ambiguous staging reconciliation requires the canonical approval gate.'}
    if(($task.PSObject.Properties.Name -contains 'mayaTaraAttempt' -and $task.mayaTaraAttempt) -or ($task.PSObject.Properties.Name -contains 'mayaTaraExecution' -and $task.mayaTaraExecution)){throw 'Tara execution state exists; staging reconciliation is not eligible.'}
    $ws=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId);if($ws.Count -ne 1){throw 'Ambiguous staging workflow identity is invalid.'};$w=$ws[0];$e=$w.qaBuildEvidence
    if($w.qaWorkflowId -cne $QaWorkflowId -or $w.qaBuildRequest.BuildRequestId -cne $BuildRequestId -or $w.qaBuildStatus -cne 'succeeded' -or !$e -or
       $e.BuildRequestId -cne $BuildRequestId -or $e.EvidenceSource -cne 'FrozenCandidate' -or $e.CandidateSourceCommit -cne $CandidateSourceCommit -or $e.ArtifactSha256 -ine $CandidateSha256 -or $e.DeploymentValidation)
        {throw 'Ambiguous staging candidate identity or state is invalid.'}
    if(@($task.mayaQaStagingReconciliations|Where-Object RequestId -ceq $RequestId).Count){throw 'Ambiguous staging request has already been reconciled.'}
    $revit=if($RevitProcessProvider){@(& $RevitProcessProvider)}else{@(Get-Process Revit -ErrorAction SilentlyContinue)};if($revit.Count){throw 'Revit is running; ambiguous staging reconciliation is blocked.'}
    foreach($path in $LedgerPath,$DeployedDllPath,$RunnerManifestPath){if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Required reconciliation evidence is missing: $path"}}
    try{$ledger=Get-Content -LiteralPath $LedgerPath -Raw|ConvertFrom-Json -ErrorAction Stop}catch{throw 'Launch Agent replay ledger is invalid JSON.'}
    $receipts=@($ledger|Where-Object {[string]$_.RequestId -ceq $RequestId});if($receipts.Count -ne 1){throw 'Launch Agent replay ledger does not contain exactly one staging receipt.'};$receipt=$receipts[0]
    $expectedSeen=[DateTimeOffset]::Parse($ExpectedSeenUtc);$actualSeen=[DateTimeOffset]::Parse([string]$receipt.SeenUtc)
    if([string]$receipt.RunId -cne $RequestId -or [string]$receipt.PayloadHash -ine $PayloadHash -or $actualSeen -ne $expectedSeen){throw 'Launch Agent staging receipt identity, payload, or time is invalid.'}
    Assert-MayaQaAuthenticatedStagingReceiptBinding -Receipt $receipt -RequestId $RequestId -TaskId $TaskId -WorkflowId $WorkflowId|Out-Null
    $dll=[IO.Path]::GetFullPath($DeployedDllPath);$manifest=[IO.Path]::GetFullPath($RunnerManifestPath)
    if((Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash -ine $CandidateSha256 -or (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash -ine $RunnerManifestSha256){throw 'Deployed staging artifact or runner manifest hash mismatch.'}
    if($e.RunnerManifestSha256 -ine $RunnerManifestSha256){throw 'Deployed runner manifest does not match authenticated source evidence.'}
    $now=(Get-Date).ToUniversalTime().ToString('O');$audit=[pscustomobject][ordered]@{SchemaVersion=1;Disposition='ObservedAppliedResponseUnavailable';TaskId=$TaskId;WorkflowId=$WorkflowId;BuildRequestId=$BuildRequestId;QaWorkflowId=$QaWorkflowId;TestId=$TestId;RequestId=$RequestId;LedgerPath=[IO.Path]::GetFullPath($LedgerPath);LedgerSha256=(Get-FileHash -LiteralPath $LedgerPath -Algorithm SHA256).Hash;LedgerReceipt=$receipt;CandidateSourceCommit=$CandidateSourceCommit;CandidateSha256=$CandidateSha256;DeployedDllPath=$dll;DeployedDllSha256=$CandidateSha256;RunnerManifestPath=$manifest;RunnerManifestSha256=$RunnerManifestSha256;RevitAbsent=$true;ResponseUnavailable=$true;ResendPermitted=$false;RecordedUtc=$now}
    $response=[pscustomobject][ordered]@{succeeded=$true;candidateCommit=$CandidateSourceCommit;candidateSha256=$CandidateSha256;qaWorkflowId=$QaWorkflowId;testId=$TestId;isolationPassed=$true;taskId=$TaskId;workflowId=$WorkflowId;qaAddinRoot=[IO.Path]::GetDirectoryName($dll);runnerManifestPath=$manifest;runnerManifestSha256=$RunnerManifestSha256;reconciliationDisposition='ObservedAppliedResponseUnavailable';requestId=$RequestId}
    if($DryRun){return $response}
    $expectedRevision=[long]$task.revision
    Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)$t=Find-RepatoTask $d $TaskId;if([long]$t.revision -ne $expectedRevision){throw 'Ambiguous staging reconciliation compare-and-swap failed.'};if(@($t.mayaQaStagingReconciliations|Where-Object RequestId -ceq $RequestId).Count){throw 'Ambiguous staging request was concurrently reconciled.'};if($t.PSObject.Properties.Name -notcontains 'mayaQaStagingReconciliations'){$t|Add-Member NoteProperty mayaQaStagingReconciliations ([object[]]@()) -Force};$t.mayaQaStagingReconciliations=[object[]]@($t.mayaQaStagingReconciliations)+$audit;Add-RepatoHistory $t 'maya-qa-staging-reconciled' 'Maya' "request=$RequestId; disposition=observed-applied-response-unavailable; resend=false";$audit}|Out-Null
    $response
}

function Repair-MayaQaPreparedHandoffCoordinatorRunId {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$HandoffId,[Parameter(Mandatory)][string]$AttemptId,[Parameter(Mandatory)][string]$ExpectedRunId,
        [scriptblock]$RevitProcessProvider,[switch]$DryRun)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$ws=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId)
    if(!$task -or $ws.Count -ne 1){throw 'Prepared handoff repair task/workflow identity is invalid.'};$w=$ws[0];$h=$w.qaHandoff;$packet=$task.mayaTaraQaPacket;$attempt=$task.mayaTaraAttempt
    if(($task.PSObject.Properties.Name -contains 'mayaTaraExecution' -and $task.mayaTaraExecution) -or ($attempt.PSObject.Properties.Name -contains 'ClaimId' -and $attempt.ClaimId) -or $attempt.RequestPath){throw 'Prepared handoff repair requires no execution, claim, or native request.'}
    if(!$h -or !$packet -or !$attempt -or $h.HandoffId -cne $HandoffId -or $w.qaHandoffId -cne $HandoffId -or $packet.HandoffId -cne $HandoffId -or
       $h.TaskId -cne $TaskId -or $packet.TaskId -cne $TaskId -or $packet.WorkflowId -cne $WorkflowId -or $attempt.WorkflowId -cne $WorkflowId -or
       $packet.AttemptId -cne $AttemptId -or $attempt.AttemptId -cne $AttemptId -or $packet.RunId -cne $ExpectedRunId -or $attempt.RunId -cne $ExpectedRunId -or $w.qaRunId -cne $ExpectedRunId -or
       $packet.Stage -cne 'prepared' -or $attempt.Stage -cne 'prepared' -or $h.HandoffStatus -cne 'ready')
        {throw 'Prepared handoff repair canonical identity or stage is invalid.'}
    if($h.CoordinatorRunId -ceq $ExpectedRunId){throw 'Prepared handoff CoordinatorRunId is already canonical.'}
    if([string]::IsNullOrWhiteSpace([string]$h.CoordinatorRunId) -or [string]$h.CoordinatorRunId -notmatch '^qa-run-[a-f0-9]{32}$'){throw 'Prepared handoff has no narrowly repairable mismatched CoordinatorRunId.'}
    $revit=if($RevitProcessProvider){@(& $RevitProcessProvider)}else{@(Get-Process Revit -ErrorAction SilentlyContinue)};if($revit.Count){throw 'Revit is running; prepared handoff repair is blocked.'}
    if($DryRun){return [pscustomobject]@{Status='DryRun';TaskId=$TaskId;WorkflowId=$WorkflowId;HandoffId=$HandoffId;AttemptId=$AttemptId;PreviousCoordinatorRunId=$h.CoordinatorRunId;CoordinatorRunId=$ExpectedRunId;SideEffectsPerformed=$false}}
    $taskRevision=[long]$task.revision;$workflowRevision=[long]$w.workflowRevision;$old=[string]$h.CoordinatorRunId
    $m=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflowRevision $taskRevision {param($current)
        if($current.qaHandoffId -cne $HandoffId -or $current.qaRunId -cne $ExpectedRunId -or $current.qaHandoff.CoordinatorRunId -cne $old){throw 'Prepared handoff repair compare-and-swap failed.'}
        $current.qaHandoff.CoordinatorRunId=$ExpectedRunId;$current
    })[-1]
    [pscustomobject]@{Status='Repaired';TaskId=$TaskId;WorkflowId=$WorkflowId;HandoffId=$HandoffId;AttemptId=$AttemptId;PreviousCoordinatorRunId=$old;CoordinatorRunId=$ExpectedRunId;TaskRevision=$m.TaskRevision;WorkflowRevision=$m.WorkflowRevision;ExecutionCreated=$false;RevitLaunched=$false;SideEffectsPerformed=$true}
}

function Repair-MayaQaPreparedIsolationPolicyEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$HandoffId,[Parameter(Mandatory)][string]$AttemptId,[Parameter(Mandatory)][string]$ExpectedRunId,
        [Parameter(Mandatory)][string]$PolicyPath,[Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedPolicySha256,
        [scriptblock]$RevitProcessProvider,[switch]$DryRun)
    $canonical=[IO.Path]::GetFullPath((Join-Path (Join-Path $PSScriptRoot '..\QA') 'MachineWideAddins.allowlist.json'));$policy=[IO.Path]::GetFullPath($PolicyPath)
    if($policy -ine $canonical -or !(Test-Path -LiteralPath $policy -PathType Leaf) -or (Get-FileHash -LiteralPath $policy -Algorithm SHA256).Hash -ine $ExpectedPolicySha256){throw 'Prepared isolation repair policy identity or hash is invalid.'}
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$ws=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId);if(!$task -or $ws.Count -ne 1){throw 'Prepared isolation repair task/workflow identity is invalid.'};$w=$ws[0];$h=$w.qaHandoff;$a=$task.mayaTaraAttempt;$p=$task.mayaTaraQaPacket
    if(($task.PSObject.Properties.Name -contains 'mayaTaraExecution' -and $task.mayaTaraExecution) -or $a.RequestPath -or ($a.PSObject.Properties.Name -contains 'ClaimId' -and $a.ClaimId)){throw 'Prepared isolation repair requires no execution, claim, or native request.'}
    if(!$h -or !$a -or !$p -or $w.qaHandoffId -cne $HandoffId -or $h.HandoffId -cne $HandoffId -or $p.HandoffId -cne $HandoffId -or $a.AttemptId -cne $AttemptId -or $p.AttemptId -cne $AttemptId -or $w.qaRunId -cne $ExpectedRunId -or $a.RunId -cne $ExpectedRunId -or $p.RunId -cne $ExpectedRunId -or $h.CoordinatorRunId -cne $ExpectedRunId -or $a.Stage -cne 'prepared' -or $p.Stage -cne 'prepared' -or $h.HandoffStatus -cne 'ready'){throw 'Prepared isolation repair canonical identity or stage is invalid.'}
    $bi=$w.qaBuildEvidence.Isolation;$hi=$h.Isolation
    if(!$bi -or !$hi -or !$bi.Allowed -or !$hi.Allowed -or @($bi.PSObject.Properties).Count -ne 1 -or @($hi.PSObject.Properties).Count -ne 1){throw 'Prepared isolation evidence is not the narrowly repairable Allowed-only shape.'}
    $revit=if($RevitProcessProvider){@(& $RevitProcessProvider)}else{@(Get-Process Revit -ErrorAction SilentlyContinue)};if($revit.Count){throw 'Revit is running; prepared isolation repair is blocked.'}
    $replacement=[pscustomobject][ordered]@{PolicyPath=$canonical;PolicySha256=$ExpectedPolicySha256;Allowed=$true}
    if($DryRun){return [pscustomobject]@{Status='DryRun';PolicyPath=$canonical;PolicySha256=$ExpectedPolicySha256;SideEffectsPerformed=$false}}
    $tr=[long]$task.revision;$wr=[long]$w.workflowRevision;$m=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $wr $tr {param($current)
        if($current.qaHandoffId -cne $HandoffId -or $current.qaBuildEvidence.Isolation.PSObject.Properties.Count -ne 1 -or $current.qaHandoff.Isolation.PSObject.Properties.Count -ne 1){throw 'Prepared isolation repair compare-and-swap failed.'}
        $current.qaBuildEvidence.Isolation=$replacement;$current.qaHandoff.Isolation=$replacement;$current
    })[-1]
    [pscustomobject]@{Status='Repaired';TaskId=$TaskId;WorkflowId=$WorkflowId;HandoffId=$HandoffId;AttemptId=$AttemptId;RunId=$ExpectedRunId;PolicyPath=$canonical;PolicySha256=$ExpectedPolicySha256;TaskRevision=$m.TaskRevision;WorkflowRevision=$m.WorkflowRevision;ExecutionCreated=$false;RevitLaunched=$false;SideEffectsPerformed=$true}
}

Export-ModuleMember -Function New-MayaQaCanonicalRunId,New-MayaQaRunnerRepairBuildRequest,Reset-MayaQaRunnerRepairForCanonicalValidation,Record-MayaQaUnresolvedStagingRequest,Assert-MayaQaAuthenticatedStagingReceiptBinding,Complete-MayaQaAmbiguousStagingReconciliation,Repair-MayaQaPreparedHandoffCoordinatorRunId,Repair-MayaQaPreparedIsolationPolicyEvidence
