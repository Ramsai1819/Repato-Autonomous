$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaStartupRetest.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue

$workflowModule = Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -PassThru -WarningAction SilentlyContinue
$store = Join-Path ([IO.Path]::GetTempPath()) ('cpv-startup-retest-' + [guid]::NewGuid().ToString('N'))
Copy-Item -LiteralPath (Join-Path $repo 'QA/MayaRuns') -Destination $store -Recurse
try {
    $taskId = 'task-bf61fe7f22d74df7a92599681da5919e'
    $failedAttempt = 'd609705ad1bb46f9b5eddc4a81fd1872'
    $releaseManifest = Join-Path $repo 'DeploymentCandidates/AgentReleases/Repato.QaLaunchAgent-1.0.15+4cf5b76be987/Repato.QaLaunchAgent.release.json'
    $releaseHash = (Get-FileHash -LiteralPath $releaseManifest).Hash
    $before = Find-RepatoTask (Read-RepatoTaskStore $store) $taskId
    $oldAttemptCount = @($before.mayaTaraAttemptHistory).Count
    $oldExecutionCount = @($before.mayaTaraExecutionHistory).Count

    $fresh = New-MayaQaStartupFailureRetest -StoreRoot $store -TaskId $taskId -FailedAttemptId $failedAttempt -ExpectedTaskRevision ([long]$before.revision) -RuntimeReleaseManifestPath $releaseManifest -RuntimeReleaseManifestSha256 $releaseHash
    $prepared = Find-RepatoTask (Read-RepatoTaskStore $store) $taskId
    $oldApproval = @($prepared.approvalRequests | Where-Object requestId -ceq 'c01a2efa2d704d64ac0a03bca155ffc2')[0]
    $request = @($prepared.approvalRequests | Where-Object requestId -ceq $fresh.ApprovalRequestId)[0]
    $binding = $request.recoveryBinding
    if ($prepared.revision -ne $fresh.TaskRevision -or $prepared.status -ne 'awaiting-approval' -or $prepared.workflowStage -ne 'approval' -or $request.status -ne 'pending' -or $fresh.RevitLaunched) { throw 'Fresh retest did not stop at pending human approval.' }
    if ($oldApproval.status -ne 'approved' -or !$oldApproval.consumedUtc -or $oldApproval.consumedAttemptId -ne $failedAttempt) { throw 'Previous approval history was not preserved and consumed.' }
    if (@($prepared.mayaTaraAttemptHistory).Count -ne $oldAttemptCount + 1 -or @($prepared.mayaTaraExecutionHistory).Count -ne $oldExecutionCount + 1) { throw 'Previous failed attempt evidence was not archived.' }
    if ($binding.AttemptId -ne $fresh.AttemptId -or $binding.RunId -ne $fresh.RunId -or $binding.CandidateSha256 -ne $before.mayaTaraExecution.ArtifactSha256 -or $binding.ModelSha256 -ne $before.mayaTaraExecution.DisposableModelSha256 -or $binding.Runtime.ReleaseManifestSha256 -ne $releaseHash -or $binding.ResultTimeoutSeconds -ne 7200) { throw 'Fresh approval binding does not cover the exact attempt, candidate, model, and runtime.' }
    if ((Get-FileHash -LiteralPath $binding.ModelPath).Hash -ne $binding.ModelSha256 -or $binding.FixturePreparationEvidence.ResultSha256 -ne $before.mayaTaraExecution.FixturePreparationEvidence.ResultSha256) { throw 'Prepared model or authenticated fixture evidence was not reused intact.' }
    if ($prepared.mayaTaraExecution.NativeRequestId -or $prepared.mayaTaraExecution.ClaimId -or $prepared.mayaTaraExecution.RequestPath) { throw 'Recovery dispatched or claimed native QA before approval.' }

    $nativeId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $requestPath = Join-Path $store 'security-prompt.request.json'
    [pscustomobject]@{ schemaVersion = 2; requestId = $nativeId; TaskId = $taskId; WorkflowId = $before.mayaTaraExecution.WorkflowId; QaWorkflowId = 'create-plan-views-v1'; TestId = 'create-plan-views-v1'; HandoffId = 'handoff-test'; AttemptId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'; RunId = 'cccccccccccccccccccccccccccccccc'; ClaimId = 'dddddddddddddddddddddddddddddddd' } | ConvertTo-Json | Set-Content -LiteralPath $requestPath
    $identity = [pscustomobject]@{ NativeRequestId = $nativeId; TaskId = $taskId; WorkflowId = $before.mayaTaraExecution.WorkflowId; QaWorkflowId = 'create-plan-views-v1'; TestId = 'create-plan-views-v1'; HandoffId = 'handoff-test'; AttemptId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'; RunId = 'cccccccccccccccccccccccccccccccc'; ClaimId = 'dddddddddddddddddddddddddddddddd' }
    $promptCount = @{ Value = 0 }
    $promptProvider = { $promptCount.Value++; [pscustomobject]@{ Title = 'Security - Unsigned Add-In'; Text = 'Repato Create Plan Views QA' } }.GetNewClosure()
    $promptStopped = $false
    $promptError = $null
    try { & $workflowModule { param($rp, $ident, $provider) Get-MayaQaCanonicalNativeResult -RequestPath $rp -Identity $ident -TimeoutSeconds 7200 -SecurityPromptProvider $provider } $requestPath $identity $promptProvider | Out-Null }
    catch { $promptError = $_.Exception.Message; $promptStopped = $promptError -match 'requires a human decision' }
    if (!$promptStopped -or $promptCount.Value -ne 1) { throw "Canonical result wait did not stop immediately on a trust prompt without interaction. calls=$($promptCount.Value); error=$promptError" }

    # Exercise the approval CAS only inside this disposable synthetic task store.
    $approved = Resolve-MayaQaStartupRetestApproval -StoreRoot $store -TaskId $taskId -RequestId $fresh.ApprovalRequestId -ExpectedTaskRevision ([long]$fresh.TaskRevision) -Decision approve
    $afterApproval = Find-RepatoTask (Read-RepatoTaskStore $store) $taskId
    $approvedRequest = @($afterApproval.approvalRequests | Where-Object requestId -ceq $fresh.ApprovalRequestId)[0]
    if ($approved.revision -ne $afterApproval.revision -or $approvedRequest.status -ne 'approved' -or !$approvedRequest.approvedRevision -or $afterApproval.mayaTaraExecution.ClaimId -or $afterApproval.mayaTaraExecution.NativeRequestId) { throw 'Synthetic approval did not preserve the prelaunch boundary.' }
    [pscustomobject]@{ Status = 'PASS'; FreshPendingApproval = $true; PreviousApprovalPreserved = $true; FailedAttemptArchived = $true; PreparedModelReused = $true; FixtureEvidenceReused = $true; ExactRuntimeBound = $true; PromptStopsWithoutInteraction = $true; SyntheticApprovalDidNotDispatch = $true; RevitLaunched = $false } | ConvertTo-Json -Compress
}
finally {
    Remove-Item -LiteralPath $store -Recurse -Force -ErrorAction SilentlyContinue
}
