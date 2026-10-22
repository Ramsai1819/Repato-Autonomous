Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvRecoveredProvenance.psm1') -WarningAction SilentlyContinue
$ErrorActionPreference = 'Stop'
# Reuse loaded dependencies. Forcing their reload here unloads the installer's
# already imported Maya health API when the retained-reservation gate is reached.
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationRecovery.psm1') -WarningAction SilentlyContinue

$script:CpvOutcomeRecoveryOperation = 'cpv-preparation-recover-completed'
$script:CpvOutcomeRecoveryStatusOperation = 'cpv-preparation-recover-completed-status'
$script:CpvOutcomeRecoveryReconcileOperation = 'cpv-preparation-recover-completed-reconcile'
$script:CpvOutcomeRecoveryApprovalAction = 'cpv-preparation-outcome-recovery'
$script:CpvOutcomeRecoveryFixtureHash = '92CC9E434E2C4DD6720A2AA564E19F4E1A30EB3DA63CEA73CF737F875B9EDD45'
$script:CpvOutcomeRecoveryUser = 'RAMSAI\RepatoQA'
$script:CpvOutcomeRecoverySid = 'S-1-5-21-1031246752-3872016183-2454652381-1015'
$script:CpvOutcomeRecoveryAgentRoot = 'C:\Users\RepatoQA\AppData\Local\Repato\QaLaunchAgent\Logs\CpvPreparation'

function Get-CpvOutcomeRecoveryHash($Value) {
    $json = ConvertTo-Json -InputObject $Value -Depth 25 -Compress
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-', '') }
    finally { $sha.Dispose() }
}
function Get-CpvOutcomeRecoveryFileHash([string]$Path) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Recovery evidence file is missing: $Path" }
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}
function ConvertFrom-CpvOutcomeRecoveryJson([string]$Json) {
    # PS7 otherwise materializes ISO timestamps as DateTime. A later string cast
    # loses fractional seconds and depends on culture; PS5.1 already keeps strings.
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
        ConvertFrom-Json -InputObject $Json -DateKind String
    } else {
        ConvertFrom-Json -InputObject $Json
    }
}
function Assert-CpvOutcomeRecoveryResult($Task, $Recovery, [long]$ExpectedTaskRevision, $Transport) {
    $request = $Recovery.Request
    if (!$request -or (Get-CpvOutcomeRecoveryHash $request) -ine $Recovery.RequestHash -or
        $request.operation -cne 'prepare-cpv-fixture' -or $request.taskId -cne $Task.taskId -or
        $request.requestId -cne $Recovery.PreparationBinding.RequestId -or $request.timeoutSeconds -lt 7200) {
        throw 'The dispatched preparation request identity or hash is invalid.'
    }
    $cap = Get-CpvPreparationCapabilities -Transport $Transport
    if ($cap.PSObject.Properties.Name -notcontains 'recoveryOperation' -or $cap.recoveryOperation -cne $script:CpvOutcomeRecoveryOperation -or
        $cap.PSObject.Properties.Name -notcontains 'recoveryStatusOperation' -or $cap.recoveryStatusOperation -cne 'cpv-preparation-recover-completed-status' -or
        $cap.user -ine $script:CpvOutcomeRecoveryUser -or $cap.sid -cne $script:CpvOutcomeRecoverySid -or $cap.sessionId -le 0) {
        throw 'The installed Launch Agent does not expose the authenticated completed-outcome recovery protocol.'
    }
    $status = Get-CpvPreparationRecoveryStatus -StoreRoot $Recovery.PreparationBinding.StoreRoot -TaskId $Task.taskId -Transport $Transport
    foreach ($name in 'requestId','taskId','workflowId','attemptId','runId') {
        if ($status.$name -cne $request.$name) { throw "Authenticated status binding changed: $name" }
    }
    if ($status.status -cne 'OutcomeUnknown' -or $status.failureCode -cne 'preparation-failed-reconcile-required' -or
        $status.user -ine $script:CpvOutcomeRecoveryUser -or $status.sid -cne $script:CpvOutcomeRecoverySid -or $status.sessionId -le 0 -or
        $status.cleanupVerified -ne $false -or $status.rollbackStatus -cne 'Unknown') { throw 'The current authenticated status is not the expected unresolved preparation outcome.' }
    $activePath = Join-Path $script:CpvOutcomeRecoveryAgentRoot 'active.json'
    $originalPath = Join-Path $script:CpvOutcomeRecoveryAgentRoot ($request.requestId + '.json')
    $preparationRequestPath = Join-Path $script:CpvOutcomeRecoveryAgentRoot ($request.requestId + '.request.json')
    $failurePath = Join-Path $script:CpvOutcomeRecoveryAgentRoot ($request.requestId + '.failure.txt')
    if (!(Test-Path -LiteralPath $activePath -PathType Leaf)) { throw 'The matching active preparation marker is absent.' }
    $active = ConvertFrom-CpvOutcomeRecoveryJson (Get-Content -LiteralPath $activePath -Raw)
    foreach ($name in 'requestId','taskId','workflowId','attemptId','runId','operation') {
        if ([string]$active.$name -cne [string]$request.$name) { throw "Active marker binding changed: $name" }
    }
    if ([DateTimeOffset]::Parse([string]$active.expiresUtc) -ne [DateTimeOffset]::Parse([string]$request.expiresUtc) -or
        $active.candidateEvidence.candidateDllSha256 -ine $request.candidateEvidence.CandidateDllSha256 -or
        $active.candidateEvidence.runnerManifestSha256 -ine $request.candidateEvidence.RunnerManifestSha256) { throw 'Active marker candidate or expiry binding changed.' }
    $modelRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\QA\TestRuns')).TrimEnd('\') + '\'
    $runRoot = [IO.Path]::GetFullPath((Join-Path $modelRoot ('cpv-preparation-' + $request.runId)))
    $modelPath = Join-Path $runRoot 'model.rvt'
    $runnerPath = Join-Path $runRoot ('tara-' + $request.attemptId + '.request.json')
    $resultPath = $runnerPath + '.preparation.json'
    if ([IO.Path]::GetFullPath($status.modelPath) -ine [IO.Path]::GetFullPath($modelPath) -or
        [IO.Path]::GetFullPath($status.requestPath) -ine [IO.Path]::GetFullPath($runnerPath) -or
        [IO.Path]::GetFullPath($modelPath).StartsWith($modelRoot, [StringComparison]::OrdinalIgnoreCase) -ne $true -or
        !(Test-Path -LiteralPath $resultPath -PathType Leaf) -or (Test-Path -LiteralPath ($modelPath + '.slog')) -or
        (Test-Path -LiteralPath ($modelPath + '.lck')) -or (Get-Process -Name Revit -ErrorAction SilentlyContinue)) {
        throw 'Prepared model, runner output, fixed destination, lock, or Revit process evidence is unsafe.'
    }
    $modelHash = Get-CpvOutcomeRecoveryFileHash $modelPath
    $resultHash = Get-CpvOutcomeRecoveryFileHash $resultPath
    $runnerHash = Get-CpvOutcomeRecoveryFileHash $runnerPath
    $agentRequestHash = Get-CpvOutcomeRecoveryFileHash $preparationRequestPath
    $originalReceiptHash = Get-CpvOutcomeRecoveryFileHash $originalPath
    $failureEvidenceHash = Get-CpvOutcomeRecoveryFileHash $failurePath
    $runner = Get-Content -LiteralPath $runnerPath -Raw | ConvertFrom-Json
    if ($runner.operation -cne 'prepare-disposable-create-plan-views-fixture' -or $runner.taskId -cne $Task.taskId -or
        $runner.workflowId -cne $request.workflowId -or $runner.attemptId -cne $request.attemptId -or $runner.runId -cne $request.runId -or
        $runner.modelPath -ine $modelPath -or $runner.requestPath -ine $runnerPath -or $runner.outputPath -ine $resultPath -or
        $runner.modelSha256 -ine $script:CpvOutcomeRecoveryFixtureHash -or
        $runner.selectedManifestSha256 -ine $request.candidateEvidence.RunnerManifestSha256) { throw 'Runner request binding is invalid.' }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if ($result.Status -cne 'Passed' -or $result.Operation -cne 'prepare-disposable-create-plan-views-fixture' -or
        $result.TaskId -cne $Task.taskId -or $result.WorkflowId -cne $request.workflowId -or $result.AttemptId -cne $request.attemptId -or
        $result.RunId -cne $request.runId -or $result.ModelPath -ine $modelPath -or
        $result.SourceModelSha256 -ine $script:CpvOutcomeRecoveryFixtureHash -or $result.PreparedModelSha256 -ine $modelHash) {
        throw 'Persisted runner result is failed, incomplete, or mismatched.'
    }
    $levels = @($result.Levels | Sort-Object Name); $expected = @(0.0, 4.0, 7.8)
    if ($levels.Count -ne 3 -or @($levels.ElementId | Select-Object -Unique).Count -ne 3) { throw 'Runner result level inventory is incomplete or duplicated.' }
    for ($i = 0; $i -lt 3; $i++) {
        if ($levels[$i].Name -cne [string]$i -or [double]::IsNaN([double]$levels[$i].ElevationMeters) -or
            [double]::IsInfinity([double]$levels[$i].ElevationMeters) -or [math]::Abs([double]$levels[$i].ElevationMeters - $expected[$i]) -gt 0.0000001 -or
            [long]$levels[$i].ElementId -le 0) { throw 'Runner result level names, elevations, or element IDs are invalid.' }
    }
    $binding = $Recovery.PreparationBinding
    $candidate = $request.candidateEvidence
    foreach ($pair in @(@($candidate.CandidateDllPath, $candidate.CandidateDllSha256), @($candidate.CandidateProvenancePath, $binding.CandidateProvenanceSha256),
        @($candidate.RunnerManifestPath, $candidate.RunnerManifestSha256), @($binding.FixturePath, $binding.FixtureSha256),
        @($binding.FixtureProvenancePath, $binding.FixtureProvenanceSha256))) {
        if ((Get-CpvOutcomeRecoveryFileHash $pair[0]) -ine $pair[1]) { throw 'A frozen candidate, fixture, or runner artifact hash changed.' }
    }
    $oldApproval = @($Task.approvalRequests | Where-Object { $_.requestId -ceq $Recovery.PreparationApprovalId -and $_.action -ceq 'cpv-prepare-fixture' })
    if ($oldApproval.Count -ne 1 -or $oldApproval[0].status -cne 'approved' -or !$oldApproval[0].consumedUtc -or
        $oldApproval[0].requiredLevel -cne 'user' -or $oldApproval[0].bindingHash -ine (Get-CpvOutcomeRecoveryHash $oldApproval[0].preparationBinding) -or
        $oldApproval[0].preparationBinding.RequestId -cne $request.requestId -or $oldApproval[0].preparationBinding.TaskId -cne $Task.taskId) {
        throw 'Original preparation approval identity or consumption evidence is invalid.'
    }
    if ([DateTimeOffset]::Parse([string]$oldApproval[0].consumedUtc) -gt [DateTimeOffset]::Parse([string]$oldApproval[0].expiresUtc)) {
        throw 'Original preparation approval was consumed after its recorded expiry.'
    }
    $workflows=@($Task.deploymentWorkflows|Where-Object {$_.workflowId -ceq $request.workflowId -and $_.taskId -ceq $Task.taskId -and $_.qaWorkflowId -ceq 'create-plan-views-v1'})
    if ($workflows.Count -ne 1 -or $workflows[0].qaBuildStatus -cne 'succeeded' -or
        $workflows[0].qaBuildEvidence.BuildRequestId -cne $binding.BuildRequestId -or
        $workflows[0].qaBuildEvidence.CandidateSourceCommit -cne $candidate.CandidateSourceCommit -or
        $workflows[0].qaBuildEvidence.ArtifactSha256 -ine $candidate.CandidateDllSha256 -or
        $workflows[0].qaBuildEvidence.RunnerManifestSha256 -ine $candidate.RunnerManifestSha256 -or
        !$workflows[0].qaBuildEvidence.DeploymentValidation -or !$workflows[0].qaBuildEvidence.ManifestIntegrityValidation -or
        !$workflows[0].qaBuildEvidence.QaIsolation) { throw 'Current task workflow no longer matches the frozen preparation candidate.' }
    $deployment=Get-RepatoCanonicalQaDeploymentApprovalEvidence -Task $Task -Workflow $workflows[0] -BuildRequestId $binding.BuildRequestId `
        -CandidateSourceCommit $candidate.CandidateSourceCommit -CandidateSha256 $candidate.CandidateDllSha256 `
        -RunnerManifestPath $candidate.RunnerManifestPath -RunnerManifestSha256 $candidate.RunnerManifestSha256
    if ((ConvertTo-Json -InputObject $deployment -Depth 20 -Compress) -cne
        (ConvertTo-Json -InputObject $binding.DeploymentValidationEvidence -Depth 20 -Compress)) { throw 'Current authenticated deployment evidence changed.' }
    [pscustomobject][ordered]@{
        TaskId = $Task.taskId; TaskRevision = $ExpectedTaskRevision; WorkflowId = $request.workflowId
        RequestId = $request.requestId; AttemptId = $request.attemptId; RunId = $request.runId; RequestHash = $Recovery.RequestHash
        RequestExpiresUtc = [DateTimeOffset]::Parse([string]$request.expiresUtc).ToUniversalTime().ToString('O')
        ActiveMarkerSha256 = Get-CpvOutcomeRecoveryFileHash $activePath
        PreparationRequestSha256 = $agentRequestHash; OriginalReceiptSha256 = $originalReceiptHash; FailureEvidenceSha256 = $failureEvidenceHash
        RunnerRequestPath = $runnerPath; RunnerRequestSha256 = $runnerHash; ResultPath = $resultPath; ResultSha256 = $resultHash
        ModelPath = $modelPath; ModelSha256 = $modelHash; CandidatePath = $candidate.CandidateDllPath
        CandidateSha256 = $candidate.CandidateDllSha256; CandidateProvenancePath = $candidate.CandidateProvenancePath
        CandidateProvenanceSha256 = Get-CpvOutcomeRecoveryFileHash $candidate.CandidateProvenancePath
        CandidateSourceCommit = $candidate.CandidateSourceCommit; RunnerManifestPath = $candidate.RunnerManifestPath
        RunnerManifestSha256 = $candidate.RunnerManifestSha256; FixturePath = $binding.FixturePath
        FixtureSha256 = $binding.FixtureSha256; FixtureProvenancePath = $binding.FixtureProvenancePath
        FixtureProvenanceSha256 = Get-CpvOutcomeRecoveryFileHash $binding.FixtureProvenancePath
        PreparationApprovalId = $oldApproval[0].requestId; PreparationApprovalBindingHash = $oldApproval[0].bindingHash
        PreparationApprovalExpiresUtc = [DateTimeOffset]::Parse([string]$oldApproval[0].expiresUtc).ToUniversalTime().ToString('O')
        AgentVersion = [string]$cap.runtimeVersion; AgentSessionId = [int]$cap.sessionId
        User = $script:CpvOutcomeRecoveryUser; Sid = $script:CpvOutcomeRecoverySid
    }
}
function Request-CpvPreparationOutcomeRecoveryApproval {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][long]$ExpectedTaskRevision,[Parameter(Mandatory)][string]$ExpectedAgentVersion,
        [ValidateRange(1,240)][int]$ExpiryMinutes=30,[scriptblock]$Transport)
    $task = Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    if ($task.revision -ne $ExpectedTaskRevision -or $task.status -cne 'in-progress' -or $task.workflowStage -cne 'qa' -or
        !$task.cpvPreparationRecovery -or $task.cpvPreparationRecovery.Status -cne 'Dispatching') { throw 'Recovery approval task state or revision is stale.' }
    if ($task.cpvPreparationRecovery.OutcomeRecoveryApprovalId) { throw 'A recovery authorization is already reserved; query its outcome before proceeding.' }
    if (@($task.approvalRequests | Where-Object { $_.status -ceq 'pending' }).Count -ne 0) { throw 'Another approval is pending.' }
    $recovery = $task.cpvPreparationRecovery
    $snapshot = Assert-CpvOutcomeRecoveryResult $task $recovery $ExpectedTaskRevision $Transport
    if ($snapshot.TaskRevision -ne $ExpectedTaskRevision -or $snapshot.AgentVersion -cne $ExpectedAgentVersion) { throw 'The recovery runtime or task revision differs from the authorized snapshot.' }
    $approvalId = [guid]::NewGuid().ToString('N')
    $binding = [pscustomobject][ordered]@{
        SchemaVersion='cpv-preparation-outcome-recovery-approval-v1'; ApprovalId=$approvalId; TaskId=$TaskId
        TaskRevision=$ExpectedTaskRevision; Operation=$script:CpvOutcomeRecoveryOperation; RecoveryStatusOperation='cpv-preparation-recover-completed-status'
        RecoveryRequestId=$recovery.Request.requestId; RecoveryApprovalId=$recovery.PreparationApprovalId
        ExpectedTaskRevision=$ExpectedTaskRevision; PermittedUser=$script:CpvOutcomeRecoveryUser; PermittedSid=$script:CpvOutcomeRecoverySid
        ExpiresUtc=[DateTimeOffset]::UtcNow.AddMinutes($ExpiryMinutes).ToString('O'); Snapshot=$snapshot; SnapshotHash=(Get-CpvOutcomeRecoveryHash $snapshot)
    }
    $approval = [pscustomobject][ordered]@{requestId=$approvalId;action=$script:CpvOutcomeRecoveryApprovalAction;requiredLevel='user';status='pending'
        bindingHash=(Get-CpvOutcomeRecoveryHash $binding);outcomeRecoveryBinding=$binding;previousStatus=[string]$task.status
        previousWorkflowStage=[string]$task.workflowStage;requestedRevision=[long]($task.revision+1);approvedRevision=$null
        requestedUtc=Get-RepatoUtc;expiresUtc=$binding.ExpiresUtc;decidedUtc=$null;decidedBy=$null;reason=$null;consumedUtc=$null}
    Invoke-RepatoStoreMutation $StoreRoot { param($data,$preview)
        $t=Find-RepatoTask $data $TaskId
        if ($t.revision -ne $ExpectedTaskRevision -or $t.status -cne 'in-progress' -or $t.workflowStage -cne 'qa' -or
            $t.cpvPreparationRecovery.Status -cne 'Dispatching' -or @($t.approvalRequests | Where-Object status -ceq 'pending').Count) {
            throw 'Outcome-recovery approval compare-and-swap failed.'
        }
        $t.approvalRequests=[object[]]@($t.approvalRequests)+$approval;$t.status='awaiting-approval';$t.workflowStage='approval'
        Add-RepatoHistory $t 'cpv-outcome-recovery-approval-requested' 'Maya' "approval=$approvalId; request=$($recovery.Request.requestId)"
        $approval.requestedRevision=[long]$t.revision;$approval
    }
}
function Expire-CpvPreparationOutcomeRecoveryApproval {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][long]$ExpectedTaskRevision)
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)
        $t=Find-RepatoTask $data $TaskId
        $pending=@($t.approvalRequests|Where-Object {$_.action -ceq $script:CpvOutcomeRecoveryApprovalAction -and $_.status -ceq 'pending'})
        if($t.revision -ne $ExpectedTaskRevision -or $t.status -cne 'awaiting-approval' -or $t.workflowStage -cne 'approval' -or $pending.Count -ne 1){throw 'Outcome-recovery approval expiry state or revision is stale.'}
        if(!$t.cpvPreparationRecovery -or $t.cpvPreparationRecovery.Status -cne 'Dispatching' -or $t.cpvPreparationRecovery.OutcomeRecoveryApprovalId){throw 'Outcome-recovery approval expiry requires an un-reserved dispatching recovery.'}
        $q=$pending[0];$b=$q.outcomeRecoveryBinding
        if($q.requiredLevel -cne 'user' -or !$b -or $b.SchemaVersion -cne 'cpv-preparation-outcome-recovery-approval-v1' -or
            $b.TaskId -cne $TaskId -or $b.ApprovalId -cne $q.requestId -or (Get-CpvOutcomeRecoveryHash $b) -ine $q.bindingHash -or
            $b.Snapshot.TaskId -cne $TaskId -or $b.RecoveryRequestId -cne $t.cpvPreparationRecovery.Request.requestId){throw 'Outcome-recovery approval binding integrity failed.'}
        try{if([DateTimeOffset]::Parse([string]$q.expiresUtc) -gt [DateTimeOffset]::UtcNow){throw 'Outcome-recovery approval has not expired.'}}catch{if($_.Exception.Message -eq 'Outcome-recovery approval has not expired.'){throw};throw 'Outcome-recovery approval expiry is invalid.'}
        if([DateTimeOffset]::Parse([string]$q.expiresUtc) -ne [DateTimeOffset]::Parse([string]$b.ExpiresUtc)){throw 'Outcome-recovery approval expiry differs from its binding.'}
        $q.status='expired';$q.reason='Expired without a human decision; retained for audit.'
        $t.status=[string]$q.previousStatus;$t.workflowStage=[string]$q.previousWorkflowStage
        Add-RepatoHistory $t 'cpv-outcome-recovery-approval-expired' 'Maya' "approval=$($q.requestId); request=$($b.RecoveryRequestId); no dispatch occurred";$q
    }
}
function Assert-CpvPreparationOutcomeRecoveryApprovalBinding {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Task,[Parameter(Mandatory)]$Approval,[scriptblock]$Transport)
    $binding=$Approval.outcomeRecoveryBinding
    $null=Assert-CpvOutcomeRecoveryApprovalEnvelope -Task $Task -Approval $Approval
    $expectedTaskRevision=[long]$binding.TaskRevision
    $current=Assert-CpvOutcomeRecoveryResult $Task $Task.cpvPreparationRecovery $expectedTaskRevision $Transport
    if ((Get-CpvOutcomeRecoveryHash $current) -ine $binding.SnapshotHash) { throw 'Outcome-recovery evidence changed after approval request.' }
    $true
}
function Assert-CpvOutcomeRecoveryApprovalEnvelope {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Task,[Parameter(Mandatory)]$Approval)
    $binding=$Approval.outcomeRecoveryBinding
    if ($Approval.action -cne $script:CpvOutcomeRecoveryApprovalAction -or $Approval.requiredLevel -cne 'user' -or
        $Approval.status -notin @('pending','approved') -or !$binding -or $binding.SchemaVersion -cne 'cpv-preparation-outcome-recovery-approval-v1' -or
        $binding.ApprovalId -cne $Approval.requestId -or $binding.TaskId -cne $Task.taskId -or
        $binding.Operation -cne $script:CpvOutcomeRecoveryOperation -or $binding.RecoveryStatusOperation -cne 'cpv-preparation-recover-completed-status' -or
        $binding.RecoveryRequestId -cne $Task.cpvPreparationRecovery.Request.requestId -or
        $binding.RecoveryApprovalId -cne $Task.cpvPreparationRecovery.PreparationApprovalId -or
        $binding.TaskRevision -ne $binding.ExpectedTaskRevision -or $binding.PermittedUser -ine $script:CpvOutcomeRecoveryUser -or
        $binding.PermittedSid -cne $script:CpvOutcomeRecoverySid -or (Get-CpvOutcomeRecoveryHash $binding) -ine $Approval.bindingHash -or
        !$binding.Snapshot -or (Get-CpvOutcomeRecoveryHash $binding.Snapshot) -ine $binding.SnapshotHash -or
        $binding.Snapshot.TaskId -cne $Task.taskId -or $binding.Snapshot.TaskRevision -ne $binding.TaskRevision -or
        $binding.Snapshot.RequestId -cne $binding.RecoveryRequestId -or $binding.Snapshot.PreparationApprovalId -cne $binding.RecoveryApprovalId) {
        throw 'Outcome-recovery approval binding integrity failed.'
    }
    $expectedTaskRevision=[long]$binding.TaskRevision
    if ([long]$Approval.requestedRevision -ne ($expectedTaskRevision+1) -or
        ($Approval.status -ceq 'pending' -and [long]$Task.revision -ne [long]$Approval.requestedRevision) -or
        ($Approval.status -ceq 'approved' -and [long]$Task.revision -ne [long]$Approval.approvedRevision)) {
        throw 'Outcome-recovery approval task revision is stale.'
    }
    try {
        $expiry=[DateTimeOffset]::Parse([string]$Approval.expiresUtc)
        if($expiry -le [DateTimeOffset]::UtcNow -or $expiry -gt [DateTimeOffset]::UtcNow.AddHours(4) -or
            $expiry -ne [DateTimeOffset]::Parse([string]$binding.ExpiresUtc)){throw 'Outcome-recovery approval expired or has an invalid expiry.'}
    } catch { if($_.Exception.Message -match 'expired or has an invalid expiry'){throw};throw 'Outcome-recovery approval expiry is invalid.' }
    $true
}
function Save-CpvPreparationOutcomeRecoveryEvidence {
    param([string]$StoreRoot,[string]$TaskId,[long]$ExpectedTaskRevision,$Commit)
    if ($Commit.Receipt.Status -cne 'Passed' -or $Commit.Receipt.operation -cne 'prepare-cpv-fixture' -or
        $Commit.Receipt.user -ine $script:CpvOutcomeRecoveryUser -or $Commit.Receipt.sid -cne $script:CpvOutcomeRecoverySid -or
        $Commit.Receipt.sessionId -le 0 -or $Commit.Receipt.cleanupVerified -ne $true -or
        $Commit.Receipt.rollbackStatus -cne 'CommittedDisposableFixtureOnly') { throw 'Recovered preparation receipt is not an authenticated clean success.' }
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId;$recovery=$task.cpvPreparationRecovery;$request=$recovery.Request;$receipt=$Commit.Receipt
    foreach($name in 'requestId','taskId','workflowId','attemptId','runId') {if($receipt.$name -cne $request.$name){throw "Recovered receipt identity mismatch: $name"}}
    if($receipt.taskId -cne $TaskId -or $receipt.candidateSha256 -ine $request.candidateEvidence.CandidateDllSha256 -or
       $receipt.manifestSha256 -ine $request.candidateEvidence.RunnerManifestSha256 -or
       [DateTimeOffset]::Parse([string]$receipt.expiresUtc) -ne [DateTimeOffset]::Parse([string]$request.expiresUtc)) {throw 'Recovered receipt candidate or original request expiry changed.'}
    foreach($pair in @(@($receipt.modelPath,$receipt.modelSha256),@($receipt.requestPath,$receipt.requestSha256),@($receipt.resultPath,$receipt.resultSha256))) {
        if((Get-CpvOutcomeRecoveryFileHash $pair[0]) -ine $pair[1]) {throw 'Recovered model, runner request, or runner result bytes changed.'}
    }
    if(!$Commit.PSObject.Properties['RecoveredProvenancePath'] -or !$Commit.PSObject.Properties['RecoveredProvenanceSha256'] -or
        [string]$Commit.RecoveredProvenancePath -ine ($receipt.modelPath+'.recovered.fixture.json') -or
        [string]$Commit.RecoveredProvenanceSha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Recovered preparation provenance commit binding is missing or invalid.'}
    $sidecar=Read-CpvFixtureProvenance -SidecarPath ($receipt.modelPath+'.fixture.json') -ExpectedRecoveredProvenanceSha256 $Commit.RecoveredProvenanceSha256
    foreach($pair in @(@('approvalBindingHash','ApprovalBindingHash'),@('originalReceiptSha256','OriginalReceiptSha256'),@('activeMarkerSha256','ActiveMarkerSha256'),@('failureEvidenceSha256','FailureEvidenceSha256'),@('requestSha256','RequestSha256'))){
        if([string]$sidecar.($pair[0]) -ine [string]$Commit.($pair[1])){throw 'Recovered preparation provenance approval/evidence binding mismatch.'}
    }
    if($sidecar.requestId -cne $request.requestId -or $sidecar.taskId -cne $TaskId -or $sidecar.workflowId -cne $request.workflowId){throw 'Recovered preparation provenance request identity mismatch.'}
    if($sidecar.fixtureId -cne 'CreatePlanViewsEmpty' -or $sidecar.sourceSha256 -ine $script:CpvOutcomeRecoveryFixtureHash -or
       $sidecar.preparedModelSha256 -ine $receipt.modelSha256 -or $sidecar.fixturePreparationRequestPath -ine $receipt.requestPath -or
       $sidecar.fixturePreparationRequestSha256 -ine $receipt.requestSha256 -or $sidecar.fixturePreparationResultPath -ine $receipt.resultPath -or
       $sidecar.fixturePreparationResultSha256 -ine $receipt.resultSha256 -or $sidecar.fixturePreparationAttemptId -cne $request.attemptId -or
       $sidecar.fixturePreparationRunId -cne $request.runId -or $sidecar.recoveredFromOutcomeUnknown -ne $true -or
       $sidecar.recoveryApprovalId -cne $Commit.RecoveryApprovalId) {throw 'Recovered preparation sidecar provenance is incomplete or mismatched.'}
    if(Test-Path -LiteralPath (Join-Path $script:CpvOutcomeRecoveryAgentRoot 'active.json')) {throw 'Recovered outcome still has an unresolved active marker.'}
    if(Get-Process -Name Revit -ErrorAction SilentlyContinue) {throw 'Revit is running during outcome recovery verification.'}
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)
        $t=Find-RepatoTask $data $TaskId;$r=$t.cpvPreparationRecovery
        if($r.Status -ceq 'RecoveredVerified') {
            if((Get-CpvOutcomeRecoveryHash $r.OutcomeRecoveryReceipt) -ine (Get-CpvOutcomeRecoveryHash $Commit)){throw 'Persisted recovered preparation evidence changed.'}
            return $t
        }
        if($t.revision -ne $ExpectedTaskRevision -or $r.Status -cne 'Dispatching' -or
            $r.OutcomeRecoveryApprovalId -cne $Commit.RecoveryApprovalId -or
            (Get-CpvOutcomeRecoveryHash $r.OutcomeRecoveryRequest) -cne $r.OutcomeRecoveryRequestHash) { throw 'Recovered preparation store compare-and-swap failed.' }
        $w=@($t.deploymentWorkflows|Where-Object {$_.workflowId -ceq $r.Request.workflowId -and $_.taskId -ceq $TaskId -and $_.qaWorkflowId -ceq 'create-plan-views-v1'})
        if($w.Count -ne 1){throw 'Recovered preparation workflow binding is missing or ambiguous.'}
        $workflow=$w[0];$prep=[pscustomobject]@{RequestPath=$Commit.Receipt.requestPath;RequestSha256=$Commit.Receipt.requestSha256
            ResultPath=$Commit.Receipt.resultPath;ResultSha256=$Commit.Receipt.resultSha256;AttemptId=$r.Request.attemptId;RunId=$r.Request.runId
            ExpiresUtc=$r.Request.expiresUtc;SourceSha256=$r.PreparationBinding.FixtureSha256
            PreparedModelPath=$Commit.Receipt.modelPath;PreparedModelSha256=$Commit.Receipt.modelSha256
            RecoveredProvenancePath=$Commit.RecoveredProvenancePath;RecoveredProvenanceSha256=$Commit.RecoveredProvenanceSha256}
        foreach($entry in @(@('qaRunId',$r.Request.runId),@('qaModelPath',$Commit.Receipt.modelPath),
            @('qaSidecarPath',($Commit.Receipt.modelPath+'.fixture.json')),@('qaDisposableModelSha256',$Commit.Receipt.modelSha256),
            @('qaFixturePreparationEvidence',$prep))){$workflow|Add-Member NoteProperty $entry[0] $entry[1] -Force}
        foreach($name in 'qaHandoff','qaHandoffId','qaApprovalId','qaApprovalStatus','qaReportPath','qaReportSha256','qaEvidence','qaVerificationStatus','qaCompletionStatus','qaCompletedUtc'){$workflow|Add-Member NoteProperty $name $null -Force}
        $workflow.workflowRevision=[long]$workflow.workflowRevision+1
        $r.OutcomeRecoveryReceipt=$Commit;$r.Status='RecoveredVerified';$t.status='in-progress';$t.workflowStage='qa'
        Add-RepatoHistory $t 'cpv-preparation-outcome-recovered' 'Maya' $r.Request.requestId;$t
    }
}
function Invoke-CpvPreparationCompletedOutcomeRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][long]$ExpectedTaskRevision,[Parameter(Mandatory)][string]$ApprovalId,[scriptblock]$Transport)
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    if ($task.revision -ne $ExpectedTaskRevision -or $task.status -cne 'in-progress' -or $task.workflowStage -cne 'qa') { throw 'Approved outcome-recovery task state or revision is stale.' }
    $approvals=@($task.approvalRequests|Where-Object {$_.requestId -ceq $ApprovalId -and $_.action -ceq $script:CpvOutcomeRecoveryApprovalAction})
    if ($approvals.Count -ne 1 -or $approvals[0].status -cne 'approved' -or $approvals[0].decidedBy -cne 'user' -or
        !$approvals[0].approvedRevision -or $approvals[0].approvedRevision -ne $task.revision -or $approvals[0].consumedUtc) { throw 'One exact, unexpired, unconsumed human recovery approval is required.' }
    $approval=$approvals[0]
    $null=Assert-CpvPreparationOutcomeRecoveryApprovalBinding -Task $task -Approval $approval -Transport $Transport
    $binding=$approval.outcomeRecoveryBinding;$r=$task.cpvPreparationRecovery.Request
    $payload=[pscustomobject][ordered]@{schemaVersion=1;operation=$script:CpvOutcomeRecoveryOperation;requestId=$r.requestId;taskId=$TaskId
        workflowId=$r.workflowId;attemptId=$r.attemptId;runId=$r.runId;recoveryApprovalId=$ApprovalId
        expectedTaskRevision=[long]$binding.ExpectedTaskRevision;approvalBindingHash=[string]$approval.bindingHash
        authorizationExpiresUtc=[string]$approval.expiresUtc;originalReceiptSha256=[string]$binding.Snapshot.OriginalReceiptSha256
        activeMarkerSha256=[string]$binding.Snapshot.ActiveMarkerSha256;failureEvidenceSha256=[string]$binding.Snapshot.FailureEvidenceSha256
        requestSha256=[string]$binding.Snapshot.PreparationRequestSha256;resultSha256=[string]$binding.Snapshot.ResultSha256
        modelSha256=[string]$binding.Snapshot.ModelSha256}
    $reserve=Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)
        $t=Find-RepatoTask $data $TaskId;$a=@($t.approvalRequests|Where-Object {$_.requestId -ceq $ApprovalId -and $_.action -ceq $script:CpvOutcomeRecoveryApprovalAction -and $_.status -ceq 'approved' -and !$_.consumedUtc})
        if($t.revision -ne $ExpectedTaskRevision -or $a.Count -ne 1 -or $t.cpvPreparationRecovery.Status -cne 'Dispatching' -or
            (Get-CpvOutcomeRecoveryHash $a[0].outcomeRecoveryBinding) -ine $a[0].bindingHash){throw 'Outcome-recovery dispatch compare-and-swap failed.'}
        $a[0].consumedUtc=Get-RepatoUtc;$t.cpvPreparationRecovery.OutcomeRecoveryApprovalId=$ApprovalId
        $t.cpvPreparationRecovery.OutcomeRecoveryRequest=$payload;$t.cpvPreparationRecovery.OutcomeRecoveryRequestHash=Get-CpvOutcomeRecoveryHash $payload
        Add-RepatoHistory $t 'cpv-outcome-recovery-dispatch-reserved' 'Maya' $r.requestId;$payload
    }
    $response=if($Transport){& $Transport $reserve}else{Invoke-CpvPreparationTransport $reserve}
    $null=Assert-CpvPreparationCompletedOutcomeRecoveryResponse -Response $response
    if ($response.Receipt.Status -cne 'Passed' -or $response.RecoveryApprovalId -cne $ApprovalId -or
        $response.ExpectedTaskRevision -ne $binding.ExpectedTaskRevision -or $response.ApprovalBindingHash -ine $approval.bindingHash -or
        $response.OriginalReceiptSha256 -ine $binding.Snapshot.OriginalReceiptSha256 -or $response.RequestSha256 -ine $binding.Snapshot.PreparationRequestSha256 -or
        $response.FailureEvidenceSha256 -ine $binding.Snapshot.FailureEvidenceSha256 -or $response.ActiveMarkerSha256 -ine $binding.Snapshot.ActiveMarkerSha256 -or
        $response.ResultSha256 -ine $binding.Snapshot.ResultSha256 -or $response.ModelSha256 -ine $binding.Snapshot.ModelSha256) {
        throw 'Authenticated completed-outcome recovery response does not match the approved evidence binding.'
    }
    Save-CpvPreparationOutcomeRecoveryEvidence -StoreRoot $StoreRoot -TaskId $TaskId -ExpectedTaskRevision ($ExpectedTaskRevision+1) -Commit $response
}
function Get-CpvPreparationCompletedOutcomeRecoveryStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[scriptblock]$Transport)
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId;$r=$task.cpvPreparationRecovery
    if (!$r.OutcomeRecoveryApprovalId -or !$r.OutcomeRecoveryRequest -or
        (Get-CpvOutcomeRecoveryHash $r.OutcomeRecoveryRequest) -ine $r.OutcomeRecoveryRequestHash) { throw 'No exact reserved outcome-recovery request exists.' }
    $query=[pscustomobject]@{schemaVersion=1;operation='cpv-preparation-recover-completed-status';requestId=$r.Request.requestId}
    $response=if($Transport){& $Transport $query}else{Invoke-CpvPreparationTransport $query}
    if ($response.status -ceq 'NotFound') { return [pscustomobject]@{Status='OutcomeUnknown';DispatchCount=1;RecoveryCommit=$null} }
    $null=Assert-CpvPreparationCompletedOutcomeRecoveryResponse -Response $response
    $approval=@($task.approvalRequests|Where-Object {$_.requestId -ceq $r.OutcomeRecoveryApprovalId -and $_.action -ceq $script:CpvOutcomeRecoveryApprovalAction})
    if ($approval.Count -ne 1 -or $response.RecoveryApprovalId -cne $approval[0].requestId -or
        $response.ExpectedTaskRevision -ne $approval[0].outcomeRecoveryBinding.ExpectedTaskRevision -or
        $response.ApprovalBindingHash -ine $approval[0].bindingHash -or
        $response.OriginalReceiptSha256 -ine $approval[0].outcomeRecoveryBinding.Snapshot.OriginalReceiptSha256 -or
        $response.FailureEvidenceSha256 -ine $approval[0].outcomeRecoveryBinding.Snapshot.FailureEvidenceSha256 -or
        $response.ActiveMarkerSha256 -ine $approval[0].outcomeRecoveryBinding.Snapshot.ActiveMarkerSha256 -or
        $response.RequestSha256 -ine $approval[0].outcomeRecoveryBinding.Snapshot.PreparationRequestSha256 -or
        $response.ResultSha256 -ine $approval[0].outcomeRecoveryBinding.Snapshot.ResultSha256 -or
        $response.ModelSha256 -ine $approval[0].outcomeRecoveryBinding.Snapshot.ModelSha256 -or
        $response.Receipt.Status -cne 'Passed') { throw 'Authenticated recovery status does not match the reserved user approval.' }
    if ($r.Status -eq 'RecoveredVerified') {
        if ((Get-CpvOutcomeRecoveryHash $r.OutcomeRecoveryReceipt) -ine (Get-CpvOutcomeRecoveryHash $response)) { throw 'Persisted task recovery receipt differs from authenticated recovery status.' }
        return [pscustomobject]@{Status='RecoveredVerified';DispatchCount=1;RecoveryCommit=$response}
    }
    $revision=[long]$task.revision
    $updated=Save-CpvPreparationOutcomeRecoveryEvidence -StoreRoot $StoreRoot -TaskId $TaskId -ExpectedTaskRevision $revision -Commit $response
    $final=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    [pscustomobject]@{Status='RecoveredVerified';DispatchCount=1;RecoveryCommit=$response;TaskRevision=$final.revision}
}
function Assert-CpvOutcomeRecoveryReservationResettable {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Task,[Parameter(Mandatory)][string]$ApprovalId)
    $recovery=$Task.cpvPreparationRecovery
    if (!$recovery -or $recovery.Status -cne 'Dispatching') { throw 'Reservation reset requires a dispatching recovery.' }
    if ($recovery.OutcomeRecoveryApprovalId -cne $ApprovalId) { throw 'Reservation reset approval identity changed.' }
    $payload=$recovery.OutcomeRecoveryRequest
    if (!$payload -or (Get-CpvOutcomeRecoveryHash $payload) -ine $recovery.OutcomeRecoveryRequestHash) { throw 'Reservation reset request hash changed.' }
    $request=$recovery.Request
    if ($payload.schemaVersion -ne 1 -or $payload.operation -cne $script:CpvOutcomeRecoveryOperation -or
        $payload.requestId -cne $request.requestId -or $payload.taskId -cne $Task.taskId -or
        $payload.workflowId -cne $request.workflowId -or $payload.attemptId -cne $request.attemptId -or $payload.runId -cne $request.runId -or
        $payload.recoveryApprovalId -cne $ApprovalId) { throw 'Reservation reset request identity is invalid.' }
    $approval=@($Task.approvalRequests|Where-Object {$_.requestId -ceq $ApprovalId -and $_.action -ceq $script:CpvOutcomeRecoveryApprovalAction})
    if ($approval.Count -ne 1) { throw 'The reserved outcome-recovery approval is missing or ambiguous.' }
    $a=$approval[0];$b=$a.outcomeRecoveryBinding
    if ($a.requiredLevel -cne 'user' -or $a.status -cne 'approved' -or $a.decidedBy -cne 'user' -or !$a.consumedUtc -or
        !$a.approvedRevision -or [long]$a.approvedRevision -ne ([long]$Task.revision - 1) -or
        !$b -or $b.SchemaVersion -cne 'cpv-preparation-outcome-recovery-approval-v1' -or
        $b.ApprovalId -cne $ApprovalId -or $b.TaskId -cne $Task.taskId -or
        (Get-CpvOutcomeRecoveryHash $b) -ine $a.bindingHash -or (Get-CpvOutcomeRecoveryHash $b.Snapshot) -ine $b.SnapshotHash -or
        $b.Snapshot.TaskId -cne $Task.taskId -or $b.RecoveryRequestId -cne $request.requestId) {
        throw 'The reserved outcome-recovery approval is not a consumed human authorization.'
    }
    if ($payload.expectedTaskRevision -ne [long]$b.ExpectedTaskRevision -or $payload.approvalBindingHash -cne $a.bindingHash -or
        $payload.authorizationExpiresUtc -ne [string]$a.expiresUtc -or
        $payload.originalReceiptSha256 -ine $b.Snapshot.OriginalReceiptSha256 -or
        $payload.activeMarkerSha256 -ine $b.Snapshot.ActiveMarkerSha256 -or
        $payload.failureEvidenceSha256 -ine $b.Snapshot.FailureEvidenceSha256 -or
        $payload.requestSha256 -ine $b.Snapshot.PreparationRequestSha256 -or
        $payload.resultSha256 -ine $b.Snapshot.ResultSha256 -or
        $payload.modelSha256 -ine $b.Snapshot.ModelSha256) {
        throw 'The reserved outcome-recovery payload differs from its approved snapshot.'
    }
    if (@($Task.approvalRequests|Where-Object {$_.status -ceq 'pending'}).Count) { throw 'An approval is pending during reservation reset.' }
    foreach ($other in @($Task.approvalRequests|Where-Object {$_.status -ceq 'approved' -and !$_.consumedUtc -and $_.requestId -cne $ApprovalId})) {
        if ([DateTimeOffset]::Parse([string]$other.expiresUtc) -gt [DateTimeOffset]::UtcNow) { throw 'Another unconsumed approval is active during reservation reset.' }
    }
    $a
}
function Assert-CpvOutcomeRecoveryNonExecutionProof {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$Proof,[Parameter(Mandatory)]$Approval,[Parameter(Mandatory)]$Request)
    $binding=$Approval.outcomeRecoveryBinding
    if ($null -eq $Proof -or $Proof.PSObject.Properties.Name -notcontains 'status') {
        throw 'The Launch Agent did not provide authenticated proof of definitive non-execution; the reservation cannot be reset.'
    }
    if ($Proof.status -ceq 'Executed') {
        throw 'The Launch Agent reports the reserved recovery executed; reconcile it with the read-only status operation instead of resetting.'
    }
    $field={param($o,$n) if ($o.PSObject.Properties.Name -ccontains $n) { [string]$o.PSObject.Properties[$n].Value } else { $null }}
    $correlated=$true
    foreach ($n in @('taskId','workflowId','attemptId','runId')) {
        $mine=& $field $Proof $n
        if ($null -ne $mine) { $correlated=$correlated -and ($mine -ceq [string]$Request.PSObject.Properties[$n].Value) }
    }
    if ((& $field $Proof 'status') -cne 'NotExecuted' -or (& $field $Proof 'operation') -cne $script:CpvOutcomeRecoveryReconcileOperation -or
        (& $field $Proof 'requestId') -cne [string]$Request.requestId -or !$correlated -or
        (& $field $Proof 'recoveryApprovalId') -cne [string]$Approval.requestId -or
        (& $field $Proof 'approvalBindingHash') -ine [string]$Approval.bindingHash -or
        (& $field $Proof 'originalReceiptSha256') -ine [string]$binding.Snapshot.OriginalReceiptSha256 -or
        (& $field $Proof 'activeMarkerSha256') -ine [string]$binding.Snapshot.ActiveMarkerSha256 -or
        (& $field $Proof 'failureEvidenceSha256') -ine [string]$binding.Snapshot.FailureEvidenceSha256 -or
        (& $field $Proof 'requestSha256') -ine [string]$binding.Snapshot.PreparationRequestSha256) {
        throw 'The Launch Agent did not provide authenticated proof of definitive non-execution; the reservation cannot be reset.'
    }
    $true
}
function Assert-CpvOutcomeRecoveryApprovedSnapshotCurrent {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Binding,[Parameter(Mandatory)]$Current)
    $currentVersion=if ($Current.PSObject.Properties['AgentVersion']) { [string]$Current.PSObject.Properties['AgentVersion'].Value } else { '' }
    $expectedEvidence=[ordered]@{}
    foreach ($p in $Binding.Snapshot.PSObject.Properties) {
        $expectedEvidence[$p.Name]=if ($p.Name -ceq 'AgentVersion') { $currentVersion } else { $p.Value }
    }
    if ((Get-CpvOutcomeRecoveryHash $Current) -ine (Get-CpvOutcomeRecoveryHash ([pscustomobject]$expectedEvidence))) {
        throw 'Current authenticated recovery evidence differs from the approved snapshot; reservation cannot be reset.'
    }
    $true
}
function Reset-CpvPreparationOutcomeRecoveryReservation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][long]$ExpectedTaskRevision,[Parameter(Mandatory)][string]$ApprovalId,[scriptblock]$Transport)
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    if ($task.revision -ne $ExpectedTaskRevision -or $task.status -cne 'in-progress' -or $task.workflowStage -cne 'qa' -or
        !$task.cpvPreparationRecovery -or $task.cpvPreparationRecovery.Status -cne 'Dispatching') {
        throw 'Outcome-recovery reservation reset task state or revision is stale.'
    }
    $approval=Assert-CpvOutcomeRecoveryReservationResettable -Task $task -ApprovalId $ApprovalId
    $binding=$approval.outcomeRecoveryBinding
    $cap=Get-CpvPreparationCapabilities -Transport $Transport
    if ($cap.PSObject.Properties.Name -notcontains 'recoveryReconcileOperation' -or $cap.recoveryReconcileOperation -cne $script:CpvOutcomeRecoveryReconcileOperation) {
        throw 'The installed Launch Agent cannot provide authenticated proof of non-execution; the reservation cannot be reset.'
    }
    $current=Assert-CpvOutcomeRecoveryResult -Task $task -Recovery $task.cpvPreparationRecovery -ExpectedTaskRevision ([long]$binding.ExpectedTaskRevision) -Transport $Transport
    $null=Assert-CpvOutcomeRecoveryApprovedSnapshotCurrent -Binding $binding -Current $current
    $agentTransition="[$($binding.Snapshot.AgentVersion)]->[$($current.AgentVersion)]"
    $request=$task.cpvPreparationRecovery.Request
    $query=[pscustomobject]@{schemaVersion=1;operation=$script:CpvOutcomeRecoveryReconcileOperation;requestId=$request.requestId;taskId=$TaskId
        workflowId=$request.workflowId;attemptId=$request.attemptId;runId=$request.runId;recoveryApprovalId=$ApprovalId
        approvalBindingHash=[string]$approval.bindingHash;originalReceiptSha256=[string]$binding.Snapshot.OriginalReceiptSha256
        activeMarkerSha256=[string]$binding.Snapshot.ActiveMarkerSha256;failureEvidenceSha256=[string]$binding.Snapshot.FailureEvidenceSha256
        requestSha256=[string]$binding.Snapshot.PreparationRequestSha256}
    $proof=if($Transport){& $Transport $query}else{Invoke-CpvPreparationTransport $query}
    $null=Assert-CpvOutcomeRecoveryNonExecutionProof -Proof $proof -Approval $approval -Request $request
    $proofHash=Get-CpvOutcomeRecoveryHash $proof
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)
        $t=Find-RepatoTask $data $TaskId;$r=$t.cpvPreparationRecovery
        if ($t.revision -ne $ExpectedTaskRevision -or $t.status -cne 'in-progress' -or $t.workflowStage -cne 'qa' -or
            !$r -or $r.Status -cne 'Dispatching' -or $r.OutcomeRecoveryApprovalId -cne $ApprovalId -or
            (Get-CpvOutcomeRecoveryHash $r.OutcomeRecoveryRequest) -ine $r.OutcomeRecoveryRequestHash -or
            @($t.approvalRequests|Where-Object {$_.status -ceq 'pending'}).Count) { throw 'Outcome-recovery reservation reset compare-and-swap failed.' }
        $a=@($t.approvalRequests|Where-Object {$_.requestId -ceq $ApprovalId -and $_.action -ceq $script:CpvOutcomeRecoveryApprovalAction -and $_.status -ceq 'approved' -and $_.decidedBy -ceq 'user' -and $_.consumedUtc})
        if ($a.Count -ne 1 -or !$a[0].outcomeRecoveryBinding -or (Get-CpvOutcomeRecoveryHash $a[0].outcomeRecoveryBinding) -ine $a[0].bindingHash) {
            throw 'Outcome-recovery reservation approval changed during reset.'
        }
        $r.OutcomeRecoveryApprovalId=$null;$r.OutcomeRecoveryRequest=$null;$r.OutcomeRecoveryRequestHash=$null
        Add-RepatoHistory $t 'cpv-outcome-recovery-reservation-reset' 'Maya' "approval=$ApprovalId; request=$($r.Request.requestId); agent=$agentTransition; nonExecutionProof=$proofHash"
        [pscustomobject][ordered]@{Status='Reset';TaskRevision=[long]$t.revision;ApprovalId=$ApprovalId;RequestId=$r.Request.requestId;NonExecutionProofHash=$proofHash}
    }
}
function Assert-CpvPreparationCompletedOutcomeRecoveryResponse {
    [CmdletBinding()]
    param([object]$Response)
    if ($null -eq $Response -or $Response.PSObject.Properties.Name -notcontains 'Receipt' -or !$Response.Receipt) {
        $status = if ($Response -and $Response.PSObject.Properties.Name -contains 'status') { [string]$Response.status } else { 'unknown' }
        $code = if ($Response -and $Response.PSObject.Properties.Name -contains 'failureCode') { [string]$Response.failureCode } else { 'none' }
        throw "Completed-outcome recovery was rejected by the agent (status='$status'; failureCode='$code'). Reconcile through the read-only status operation; never redispatch."
    }
    $Response
}
Export-ModuleMember -Function Request-CpvPreparationOutcomeRecoveryApproval,Expire-CpvPreparationOutcomeRecoveryApproval,Assert-CpvPreparationOutcomeRecoveryApprovalBinding,Assert-CpvPreparationCompletedOutcomeRecoveryResponse,Invoke-CpvPreparationCompletedOutcomeRecovery,Get-CpvPreparationCompletedOutcomeRecoveryStatus,Reset-CpvPreparationOutcomeRecoveryReservation
