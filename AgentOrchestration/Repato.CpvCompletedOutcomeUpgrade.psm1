Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -Global -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationUpgrade.psm1') -Force -Global -WarningAction SilentlyContinue

$script:RequestId='c11b311638a54bfc9ebdd1803671ec40'
$script:TaskId='task-bf61fe7f22d74df7a92599681da5919e'
$script:User='RAMSAI\RepatoQA'
$script:Sid='S-1-5-21-1031246752-3872016183-2454652381-1015'
$script:FixtureSha256='92CC9E434E2C4DD6720A2AA564E19F4E1A30EB3DA63CEA73CF737F875B9EDD45'
$script:StaleReservationApprovalId='590da474d11d42e2b2fedbf99edaba03'
$script:StaleReservationAction='cpv-preparation-outcome-recovery'
$script:RuntimeFiles=@('Repato.QaLaunchAgent.exe','Repato.QaLaunchAgent.dll','Repato.QaLaunchAgent.deps.json','Repato.QaLaunchAgent.runtimeconfig.json')
function Get-CpvCompletedUpgradeHash($Value) {
    $json=$Value|ConvertTo-Json -Depth 20 -Compress
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $bytes=[Text.Encoding]::UTF8.GetBytes($json); ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}
function ConvertTo-CpvCompletedUpgradeUtc([object]$Value) {
    if($Value -is [DateTimeOffset]){return $Value.ToUniversalTime()}
    if($Value -is [DateTime]){return ([DateTimeOffset]$Value).ToUniversalTime()}
    [DateTimeOffset]::Parse([string]$Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)
}

function Assert-CpvCompletedOutcomeUpgrade {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$EvidenceRoot,[Parameter(Mandatory)][string]$RuntimeRoot,
        [Parameter(Mandatory)][string]$RequestId,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][long]$ExpectedTaskRevision,[Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)]$Capabilities,[Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)]$InstalledAgent,
        [Parameter(Mandatory)][string]$ProcessSid,[Parameter(Mandatory)][string]$ExpectedExecutable,
        [Parameter(Mandatory)][string]$ExpectedInstalledVersion,[Parameter(Mandatory)][string]$CandidateRoot,
        [Parameter(Mandatory)][string]$CandidateManifestPath,[Parameter(Mandatory)][string]$CandidateManifestSha256,
        [Parameter(Mandatory)][object[]]$PriorRuntimeFiles,[Parameter(Mandatory)][bool]$PriorTaskContractValid,
        [Parameter(Mandatory)][bool]$NoRevitProcesses,[Parameter(Mandatory)]$BootstrapModule,
        $NonExecutionProof,$CurrentApprovedSnapshot)
    Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Global -WarningAction SilentlyContinue
    $currentTransition=$ExpectedInstalledVersion -ceq '1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f'
    $candidatePattern=if($currentTransition){'1\.0\.22\+[A-Fa-f0-9]{12,40}'}else{'1\.0\.21\+[A-Fa-f0-9]{12,40}'}
    $reservationId=if($currentTransition){'acfd8643ed2846b8a43b98d3a74c3217'}else{$script:StaleReservationApprovalId}
    if($RequestId -cne $script:RequestId -or $TaskId -cne $script:TaskId -or ($ExpectedInstalledVersion -cne '1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e' -and !$currentTransition)){
        throw 'Completed-outcome upgrade is restricted to the exact active request and pinned installed runtime.'
    }
    if(!$Capabilities -or $Capabilities.operation -cne 'cpv-preparation-capabilities' -or $Capabilities.supported -ne $true -or
        $Capabilities.user -ine $script:User -or $Capabilities.sid -cne $script:Sid -or $Capabilities.sessionId -le 0){throw 'Authenticated RepatoQA capability identity is invalid.'}
    if(!$InstalledAgent -or $InstalledAgent.ProcessName -cne 'Repato.QaLaunchAgent' -or
        [IO.Path]::GetFullPath($InstalledAgent.Path) -ine [IO.Path]::GetFullPath($ExpectedExecutable) -or
        $InstalledAgent.ProductVersion -cne $ExpectedInstalledVersion -or $InstalledAgent.User -ine $script:User -or
        $InstalledAgent.Sid -cne $script:Sid -or $ProcessSid -cne $script:Sid -or $InstalledAgent.SessionId -ne $Capabilities.sessionId -or
        $InstalledAgent.Id -le 0 -or !$InstalledAgent.StartTime){throw 'Installed agent process owner, version, path, or session is invalid.'}
    if(!$NoRevitProcesses -or !$PriorTaskContractValid -or @($PriorRuntimeFiles).Count -ne 4 -or
        @($PriorRuntimeFiles|Where-Object {$_.name -notin $script:RuntimeFiles -or $_.sha256 -notmatch '^[A-Fa-f0-9]{64}'}).Count -or
        @($PriorRuntimeFiles.name|Select-Object -Unique).Count -ne 4){throw 'No-Revit or exact rollback prerequisites failed.'}
    foreach($entry in $PriorRuntimeFiles){$installed=Join-Path (Split-Path $ExpectedExecutable -Parent) $entry.name;if(!(Test-Path -LiteralPath $installed -PathType Leaf) -or (Get-FileHash $installed -Algorithm SHA256).Hash -ine $entry.sha256){throw "Current runtime rollback hash mismatch: $($entry.name)"}}
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId;$recovery=$task.cpvPreparationRecovery
    if($task.revision -ne $ExpectedTaskRevision){throw "Authoritative task revision changed: expected $ExpectedTaskRevision, found $($task.revision)."}
    if($task.status -cne 'in-progress' -or $task.workflowStage -cne 'qa'){throw 'Authoritative task is not in the expected QA state.'}
    if(!$recovery -or $recovery.Status -cne 'Dispatching'){throw 'Authoritative preparation is not in the expected single-dispatch state.'}
    $storedRequestHash=Get-CpvCompletedUpgradeHash $recovery.Request
    if($storedRequestHash -ine $recovery.RequestHash){throw "Authoritative preparation request hash changed: stored $($recovery.RequestHash), computed $storedRequestHash."}
    if($recovery.OutcomeRecoveryApprovalId){
        if($recovery.OutcomeRecoveryApprovalId -cne $reservationId -or !$recovery.PSObject.Properties['OutcomeRecoveryRequest'] -or
            !$recovery.OutcomeRecoveryRequest -or !$recovery.PSObject.Properties['OutcomeRecoveryRequestHash'] -or
            [string]$recovery.OutcomeRecoveryRequestHash -notmatch '^[A-Fa-f0-9]{64}$' -or
            [string]$recovery.OutcomeRecoveryRequest.requestId -cne $RequestId -or [string]$recovery.OutcomeRecoveryRequest.taskId -cne $TaskId){
            throw 'An unexpected outcome recovery reservation blocks the guarded runtime upgrade.'
        }
        $reservation=@($task.approvalRequests|Where-Object {$_.requestId -ceq $reservationId -and $_.action -ceq $script:StaleReservationAction -and $_.status -ceq 'approved' -and $_.consumedUtc})
        if($reservation.Count -ne 1){throw 'The expected consumed outcome recovery reservation is unavailable or changed.'}
    }
    if($currentTransition){
        if($ExpectedTaskRevision -ne 122 -or $recovery.OutcomeRecoveryApprovalId -cne $reservationId){throw 'Revision-122 retained reservation is required for the 1.0.22 transition.'}
        if(!$Capabilities.PSObject.Properties['runtimeVersion'] -or $Capabilities.runtimeVersion -cne $ExpectedInstalledVersion -or
            !$CurrentApprovedSnapshot -or $CurrentApprovedSnapshot.AgentVersion -cne $ExpectedInstalledVersion -or
            $CurrentApprovedSnapshot.AgentSessionId -ne $Capabilities.sessionId){throw 'Current authenticated snapshot runtime or session differs from the installed agent.'}
        $recoveryModule=Import-Module (Join-Path $PSScriptRoot 'Repato.CpvCompletedOutcomeRecovery.psm1') -PassThru -WarningAction SilentlyContinue
        & $recoveryModule {param($t,$id,$proof,$snapshot)
            $a=Assert-CpvOutcomeRecoveryReservationResettable -Task $t -ApprovalId $id
            $null=Assert-CpvOutcomeRecoveryApprovedSnapshotCurrent -Binding $a.outcomeRecoveryBinding -Current $snapshot
            $null=Assert-CpvOutcomeRecoveryNonExecutionProof -Proof $proof -Approval $a -Request $t.cpvPreparationRecovery.Request
        } $task $reservationId $NonExecutionProof $CurrentApprovedSnapshot
    }
    if(@($task.approvalRequests|Where-Object status -ceq 'pending').Count){throw 'A pending approval blocks the guarded runtime upgrade.'}
    if(@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.PSObject.Properties['executionBinding'] -and $_.executionBinding -and $_.executionBinding.RunId -ceq $recovery.Request.runId}).Count){throw 'A native QA approval already exists for this preparation run.'}
    if(!$Receipt -or $Receipt.operation -cne 'prepare-cpv-fixture' -or $Receipt.status -cne 'OutcomeUnknown' -or
        $Receipt.failureCode -cne 'preparation-failed-reconcile-required' -or $Receipt.requestId -cne $RequestId -or
        $Receipt.taskId -cne $TaskId -or $Receipt.user -ine $script:User -or $Receipt.sid -cne $script:Sid -or
        $Receipt.sessionId -ne 2 -or $Receipt.cleanupVerified -ne $false -or $Receipt.modelSha256 -or $Receipt.resultPath -or
        $Receipt.resultSha256 -or $Receipt.rollbackStatus -cne 'Unknown'){throw 'Authenticated status is not the exact unresolved preparation result.'}
    $activePath=Join-Path $EvidenceRoot 'active.json';$requestPath=Join-Path $EvidenceRoot ($RequestId+'.request.json')
    $receiptPath=Join-Path $EvidenceRoot ($RequestId+'.json');$failurePath=Join-Path $EvidenceRoot ($RequestId+'.failure.txt')
    foreach($path in @($activePath,$requestPath,$receiptPath,$failurePath)){if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Required protected evidence is missing: $path"}}
    $active=Get-Content $activePath -Raw|ConvertFrom-Json;$request=Get-Content $requestPath -Raw|ConvertFrom-Json;$disk=Get-Content $receiptPath -Raw|ConvertFrom-Json
    if($active.requestId -cne $RequestId -or $request.requestId -cne $RequestId -or $active.taskId -cne $TaskId -or $request.taskId -cne $TaskId -or
        $active.workflowId -cne $request.workflowId -or $active.attemptId -cne $request.attemptId -or $active.runId -cne $request.runId -or
        (ConvertTo-CpvCompletedUpgradeUtc $active.expiresUtc) -ne (ConvertTo-CpvCompletedUpgradeUtc $request.expiresUtc) -or
        $active.candidateEvidence.candidateDllSha256 -ine $request.candidateEvidence.CandidateDllSha256 -or
        $active.candidateEvidence.runnerManifestSha256 -ine $request.candidateEvidence.RunnerManifestSha256 -or
        [string]::IsNullOrWhiteSpace((Get-Content $failurePath -Raw))){throw 'Active marker and original request/failure identities differ.'}
    foreach($name in 'requestId','taskId','workflowId','attemptId','runId','status','failureCode','candidateSha256','manifestSha256','expiresUtc'){
        if($disk.$name -cne $Receipt.$name){throw "Authenticated and persisted receipt mismatch: $name"}
    }
    $run=[IO.Path]::GetFullPath((Join-Path $RuntimeRoot ('cpv-preparation-'+$active.runId)))
    $model=Join-Path $run 'model.rvt';$runnerPath=Join-Path $run ('tara-'+$active.attemptId+'.request.json');$resultPath=$runnerPath+'.preparation.json'
    if([IO.Path]::GetFullPath($Receipt.modelPath) -ine [IO.Path]::GetFullPath($model) -or
       [IO.Path]::GetFullPath($Receipt.requestPath) -ine [IO.Path]::GetFullPath($runnerPath) -or
       !(Test-Path $model -PathType Leaf) -or !(Test-Path $runnerPath -PathType Leaf) -or !(Test-Path $resultPath -PathType Leaf) -or
       (Test-Path ($model+'.slog')) -or (Test-Path ($model+'.lck'))){throw 'Existing model/result files or lock evidence are unsafe.'}
    $runner=Get-Content $runnerPath -Raw|ConvertFrom-Json;$result=Get-Content $resultPath -Raw|ConvertFrom-Json
    $modelHash=(Get-FileHash $model -Algorithm SHA256).Hash
    if($runner.operation -cne 'prepare-disposable-create-plan-views-fixture' -or $runner.taskId -cne $TaskId -or
       $runner.workflowId -cne $active.workflowId -or $runner.attemptId -cne $active.attemptId -or $runner.runId -cne $active.runId -or
       [IO.Path]::GetFullPath($runner.modelPath) -ine [IO.Path]::GetFullPath($model) -or
       [IO.Path]::GetFullPath($runner.requestPath) -ine [IO.Path]::GetFullPath($runnerPath) -or
       [IO.Path]::GetFullPath($runner.outputPath) -ine [IO.Path]::GetFullPath($resultPath) -or
       (Split-Path $runner.selectedManifestPath -Leaf) -cne (Split-Path $request.candidateEvidence.RunnerManifestPath -Leaf) -or
       $runner.selectedManifestSha256 -ine $request.candidateEvidence.RunnerManifestSha256 -or
       $runner.modelSha256 -ine $script:FixtureSha256 -or
       $result.Status -cne 'Passed' -or $result.Operation -cne 'prepare-disposable-create-plan-views-fixture' -or
       $result.ModelPath -ine $model -or $result.SourceModelSha256 -ine $script:FixtureSha256 -or
       $result.TaskId -cne $TaskId -or $result.WorkflowId -cne $active.workflowId -or
       $result.AttemptId -cne $active.attemptId -or $result.RunId -cne $active.runId -or $result.PreparedModelSha256 -ine $modelHash){
        throw 'Frozen fixture or persisted runner output is inconsistent; upgrade is refused.'
    }
    $oldApproval=@($task.approvalRequests|Where-Object {$_.requestId -ceq $recovery.PreparationApprovalId -and $_.action -ceq 'cpv-prepare-fixture'})
    if($oldApproval.Count -ne 1 -or $oldApproval[0].status -cne 'approved' -or !$oldApproval[0].consumedUtc -or
       $oldApproval[0].bindingHash -ine (Get-CpvCompletedUpgradeHash $oldApproval[0].preparationBinding) -or
       $oldApproval[0].preparationBinding.RequestId -cne $RequestId -or
       $oldApproval[0].preparationBinding.CandidateSha256 -ine $request.candidateEvidence.CandidateDllSha256 -or
       $oldApproval[0].preparationBinding.RunnerManifestSha256 -ine $request.candidateEvidence.RunnerManifestSha256 -or
       $oldApproval[0].preparationBinding.FixtureSha256 -ine $script:FixtureSha256){throw 'The exact consumed preparation approval is unavailable or changed.'}
    $candidate=[IO.Path]::GetFullPath($CandidateRoot).TrimEnd('\');$manifestPath=[IO.Path]::GetFullPath($CandidateManifestPath)
    $releaseRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\DeploymentCandidates\AgentReleases')).TrimEnd('\')+'\'
    if(!$candidate.StartsWith($releaseRoot,[StringComparison]::OrdinalIgnoreCase) -or
       (Split-Path $manifestPath -Leaf) -cne 'Repato.QaLaunchAgent.release.json' -or
       (Split-Path $candidate -Leaf) -notmatch ('^Repato\.QaLaunchAgent-'+$candidatePattern+'$')){
        throw 'Release candidate root is outside the pinned agent-release catalog.'
    }
    if(!$manifestPath.StartsWith($candidate+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $manifestPath -Algorithm SHA256).Hash -ine $CandidateManifestSha256){throw 'Release manifest is not pinned to the candidate root.'}
    $manifest=Get-Content $manifestPath -Raw|ConvertFrom-Json
    if($manifest.product -cne 'Repato.QaLaunchAgent' -or $manifest.account -cne $script:User -or $manifest.sid -cne $script:Sid -or
       $manifest.productVersion -notmatch ('^'+$candidatePattern+'$') -or @($manifest.files).Count -ne 4 -or
       @($manifest.files.name|Select-Object -Unique).Count -ne 4 -or @($script:RuntimeFiles|Where-Object {$_ -notin @($manifest.files.name)}).Count){throw 'Candidate release identity or version is not the required recovery release.'}
    foreach($entry in $manifest.files){$path=Join-Path $candidate $entry.name;if($entry.name -notin $script:RuntimeFiles -or $entry.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or !(Test-Path $path -PathType Leaf) -or (Get-FileHash $path -Algorithm SHA256).Hash -ine $entry.sha256){throw 'Candidate runtime file manifest or bytes are invalid.'}}
    $agentRoot=Split-Path $ExpectedExecutable -Parent;$journalPath=Join-Path (Split-Path $agentRoot -Parent) '.QaLaunchAgent.install-journal.json'
    $journal=& $BootstrapModule {param($path,$target) Read-InstallJournal $path $target} $journalPath $agentRoot
    $baselineOk = ($journal.state -eq 'Committed' -and $journal.generation -eq 13 -and $journal.candidateVersion -eq $ExpectedInstalledVersion -and $journal.requestId -in @('9953e14c15524fe09440d1c7d7353950','c11b311638a54bfc9ebdd1803671ec40') -and $journal.taskId -eq $TaskId)
    if($currentTransition){$baselineOk=($journal.state -ceq 'Committed' -and $journal.generation -eq 13 -and $journal.candidateVersion -ceq $ExpectedInstalledVersion -and $journal.priorVersion -ceq '1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e' -and $journal.requestId -ceq $RequestId -and $journal.taskId -ceq $TaskId)}
    if(!$baselineOk -and !$currentTransition) {
      $baselineOk = ($journal.state -eq 'RolledBack' -and $journal.priorVersion -eq $ExpectedInstalledVersion -and $journal.taskId -eq $TaskId)
    }
    if(!$baselineOk){throw 'Committed generation-13 rollback journal is not the expected installed baseline.'}
    [pscustomobject]@{Request=$active;RunDirectory=$run;PriorFiles=@($PriorRuntimeFiles);CandidateVersion=$manifest.productVersion;JournalGeneration=[long]$journal.generation;JournalSha256=$journal.journalSha256}
}
Export-ModuleMember -Function Assert-CpvCompletedOutcomeUpgrade
