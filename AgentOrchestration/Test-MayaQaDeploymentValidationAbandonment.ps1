$ErrorActionPreference='Stop'
$store=Join-Path ([IO.Path]::GetTempPath()) ('repato-validation-abandon-'+[guid]::NewGuid().ToString('N'))
try {
    Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force
    $taskId='task-synthetic';$workflowId='workflow-synthetic';$buildId='build-synthetic';$commit='A'*40;$hash='B'*64;$qa='create-plan-views-v1'
    Initialize-RepatoTaskStore $store|Out-Null
    New-RepatoTask $store $taskId 'synthetic' 'validation abandonment' 'qa/test' 'maya'|Out-Null
    Invoke-RepatoStoreMutation $store {param($d,$p)$t=Find-RepatoTask $d $taskId;$t|Add-Member NoteProperty deploymentWorkflows ([object[]]@([pscustomobject]@{workflowId=$workflowId;taskId=$taskId;qaBuildEvidence=[pscustomobject]@{BuildRequestId=$buildId;CandidateSourceCommit=$commit;ArtifactSha256=$hash}})) -Force;$t}|Out-Null
    $revision=[long](Find-RepatoTask (Read-RepatoTaskStore $store) $taskId).revision
    $operation=New-MayaQaDeploymentValidationOperation $store $taskId $workflowId $revision $buildId $commit $hash $qa $qa
    Invoke-RepatoStoreMutation $store {param($d,$p)$t=Find-RepatoTask $d $taskId;$x=$t.deploymentValidationOperations[0];$x.PSObject.Properties.Remove('RequestId');$x.RequestDisposition='transmitting';Add-RepatoHistory $t 'deployment-validation-transmitting' 'Maya' "operation=$($x.OperationId)";$x.TransmittingTaskRevision=[long]$t.revision;$t}|Out-Null
    $before=Find-RepatoTask (Read-RepatoTaskStore $store) $taskId;$operation=@($before.deploymentValidationOperations)[0];$expected=[long]$before.revision
    $blocked=$false;try{New-MayaQaDeploymentValidationOperation $store $taskId $workflowId $expected $buildId $commit $hash $qa $qa|Out-Null}catch{$blocked=$true};if(!$blocked){throw 'Fresh validation was permitted before terminal abandonment.'}
    $dry=Abandon-MayaQaUnresolvedDeploymentValidation -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -OperationId $operation.OperationId -ExpectedTaskRevision $expected -Reason 'Synthetic read-only ambiguity' -ConfirmReadOnlyValidationPath -RevitProcessProvider { @() } -DryRun
    if($dry.Status -cne 'DryRun' -or $dry.FreshValidationPermittedAfterApply){throw 'Abandonment dry-run contract failed.'}
    $afterDry=Find-RepatoTask (Read-RepatoTaskStore $store) $taskId;if($afterDry.revision -ne $expected -or $afterDry.deploymentValidationOperations[0].RequestDisposition -cne 'transmitting'){throw 'Abandonment dry-run mutated state.'}
    $result=Abandon-MayaQaUnresolvedDeploymentValidation -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -OperationId $operation.OperationId -ExpectedTaskRevision $expected -Reason 'Synthetic read-only ambiguity' -ConfirmReadOnlyValidationPath -RevitProcessProvider { @() } -Confirm:$false
    $after=Find-RepatoTask (Read-RepatoTaskStore $store) $taskId;$closed=@($after.deploymentValidationOperations|Where-Object OperationId -ceq $operation.OperationId)[0]
    if($result.Status -cne 'AbandonedUnresolved' -or $closed.RequestDisposition -cne 'abandoned' -or $closed.TerminalStatus -cne 'AbandonedUnresolved' -or $closed.Response -or $closed.AbandonmentEvidence.SuccessClaimed -or !$closed.AbandonmentEvidence.ValidationPathReadOnlyConfirmed){throw 'Terminal abandonment evidence contract failed.'}
    if($closed.TaskId -cne $taskId -or $closed.WorkflowId -cne $workflowId -or $closed.BuildRequestId -cne $buildId -or $closed.CandidateSourceCommit -cne $commit -or $closed.CandidateSha256 -cne $hash){throw 'Legacy operation evidence was not retained.'}
    $fresh=New-MayaQaDeploymentValidationOperation $store $taskId $workflowId ([long]$after.revision) $buildId $commit $hash $qa $qa
    $afterFresh=Find-RepatoTask (Read-RepatoTaskStore $store) $taskId
    if(!$fresh.RequestId -or $fresh.RequestDisposition -cne 'confirmed-unsent' -or @($afterFresh.deploymentValidationOperations).Count -ne 2 -or @($afterFresh.deploymentValidationOperations|Where-Object OperationId -ceq $operation.OperationId)[0].RequestDisposition -cne 'abandoned'){throw 'Fresh validation operation contract failed.'}
    $boundRejected=$false;try{Abandon-MayaQaUnresolvedDeploymentValidation -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -OperationId $fresh.OperationId -ExpectedTaskRevision $fresh.ExpectedTaskRevision -Reason 'must reject bound operation' -ConfirmReadOnlyValidationPath -RevitProcessProvider { @() } -Confirm:$false}catch{$boundRejected=$true};if(!$boundRejected){throw 'Request-bound operation was eligible for legacy abandonment.'}
    [pscustomobject]@{LegacyEvidenceRetained='PASS';DryRunNoMutation='PASS';UnresolvedGuard='PASS';TerminalAbandonment='PASS';NoSuccessClaim='PASS';FreshValidationPermitted='PASS';FutureRequestIdPersisted='PASS';RequestBoundAbandonmentRejected='PASS';RevitLaunched=$false;LiveStoreTouched=$false}|ConvertTo-Json -Compress
} finally {if(Test-Path -LiteralPath $store){Remove-Item -LiteralPath $store -Recurse -Force}}
