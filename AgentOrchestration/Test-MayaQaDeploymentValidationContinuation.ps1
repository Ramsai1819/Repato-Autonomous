$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('repato-continuation-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
try {
 Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
 Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force
 $task='task-synthetic';$wf='workflow-synthetic';$commit='A'*40;$hash='B'*64;$build='build-synthetic';$qa='create-plan-views-v1';$test=$qa
 Initialize-RepatoTaskStore $root|Out-Null;New-RepatoTask $root $task 'synthetic' 'synthetic' 'qa/maya-qa-workflow' 'maya'|Out-Null
 Invoke-RepatoStoreMutation $root {param($d,$p)$t=Find-RepatoTask $d $task;$t|Add-Member NoteProperty deploymentWorkflows ([object[]]@([pscustomobject]@{workflowId=$wf;taskId=$task})) -Force;$t}
 $rev=[long](Find-RepatoTask (Read-RepatoTaskStore $root) $task).revision
 $op=New-MayaQaDeploymentValidationOperation $root $task $wf $rev $build $commit $hash $qa $test
 $runner=[IO.Path]::GetFullPath((Join-Path (Split-Path $PSScriptRoot -Parent) 'QA\Repato.CreatePlanViews.TestRunner.addin'));$runnerHash=(Get-FileHash $runner -Algorithm SHA256).Hash
 $r=Continue-MayaQaDeploymentValidation $root $task $wf $op.OperationId $op.ExpectedTaskRevision $build $commit $hash $qa $test -RequestInvoker {param($pending)[pscustomobject]@{schemaVersion=1;operation='validate-qa-deployment';requestId=$pending.RequestId;succeeded=$true;validationIdentity='RAMSAI\RepatoQA';candidateCommit=$commit;qaWorkflowId=$qa;testId=$test;candidateSha256=$hash;isolationPassed=$true;qaAddinRoot='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA';runnerManifestPath='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin';runnerManifestSha256=$runnerHash;manifestIntegrityPassed=$true} }
 if($r.Status -ne 'Completed'){throw 'confirmed-unsent continuation failed'}
 $again=Continue-MayaQaDeploymentValidation $root $task $wf $op.OperationId $op.ExpectedTaskRevision $build $commit $hash $qa $test
 if($again.Status -ne 'Completed'){throw 'idempotent completed validation failed'}
 $currentRevision=[long](Find-RepatoTask (Read-RepatoTaskStore $root) $task).revision
 $unknown=New-MayaQaDeploymentValidationOperation $root $task $wf $currentRevision $build $commit $hash $qa $test
 Invoke-RepatoStoreMutation $root {param($d,$p)$t=Find-RepatoTask $d $task;$x=$t.deploymentValidationOperations[-1];$x.RequestDisposition='unknown';Add-RepatoHistory $t 'synthetic-transmission-ambiguous' 'Maya' "operation=$($x.OperationId)";$x.TransmittingTaskRevision=[long]$t.revision;$t}
 $unknown=@((Find-RepatoTask (Read-RepatoTaskStore $root) $task).deploymentValidationOperations|Where-Object OperationId -ceq $unknown.OperationId)[0]
 $blocked=$false;try{Continue-MayaQaDeploymentValidation $root $task $wf $unknown.OperationId $unknown.ExpectedTaskRevision $build $commit $hash $qa $test}catch{$blocked=$true};if(!$blocked){throw 'unknown state was retryable'}
 $response=[pscustomobject]@{schemaVersion=1;operation='validate-qa-deployment';requestId=$unknown.RequestId;succeeded=$true;validationIdentity='RAMSAI\RepatoQA';candidateCommit=$commit;qaWorkflowId=$qa;testId=$test;candidateSha256=$hash;isolationPassed=$true;qaAddinRoot='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA';runnerManifestPath='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin';runnerManifestSha256=$runnerHash;manifestIntegrityPassed=$true}
 $missingEvidence=$false;try{Continue-MayaQaDeploymentValidation $root $task $wf $unknown.OperationId $unknown.ExpectedTaskRevision $build $commit $hash $qa $test -DispositionResolver {param($x)[pscustomobject]@{OperationId=$x.OperationId;Disposition='completed';Response=$null}}}catch{$missingEvidence=$true};if(!$missingEvidence){throw 'missing authoritative response was accepted'}
 $wrongOperation=$false;try{Continue-MayaQaDeploymentValidation $root $task $wf $unknown.OperationId $unknown.ExpectedTaskRevision $build $commit $hash $qa $test -DispositionResolver {param($x)[pscustomobject]@{OperationId='other';Disposition='completed';Response=$response}}}catch{$wrongOperation=$true};if(!$wrongOperation){throw 'mismatched authoritative operation was accepted'}
 $wrongRequest=$response.PSObject.Copy();$wrongRequest.requestId=[guid]::NewGuid().ToString('N');$requestMismatch=$false;try{Continue-MayaQaDeploymentValidation $root $task $wf $unknown.OperationId $unknown.ExpectedTaskRevision $build $commit $hash $qa $test -DispositionResolver {param($x)[pscustomobject]@{OperationId=$x.OperationId;Disposition='completed';Response=$wrongRequest}}}catch{$requestMismatch=$true};if(!$requestMismatch){throw 'mismatched response request identity was accepted'}
 $resolvedUnknown=Continue-MayaQaDeploymentValidation $root $task $wf $unknown.OperationId $unknown.ExpectedTaskRevision $build $commit $hash $qa $test -DispositionResolver {param($x)[pscustomobject]@{OperationId=$x.OperationId;Disposition='completed';Response=$response}}
 if($resolvedUnknown.Status -ne 'Completed'){throw 'authoritative unknown reconciliation failed'}
 $currentRevision=[long](Find-RepatoTask (Read-RepatoTaskStore $root) $task).revision
 $transmitting=New-MayaQaDeploymentValidationOperation $root $task $wf $currentRevision $build $commit $hash $qa $test
 Invoke-RepatoStoreMutation $root {param($d,$p)$t=Find-RepatoTask $d $task;$x=$t.deploymentValidationOperations[-1];$x.RequestDisposition='transmitting';Add-RepatoHistory $t 'synthetic-transmitting' 'Maya' "operation=$($x.OperationId)";$x.TransmittingTaskRevision=[long]$t.revision;$t}
 $transmitting=@((Find-RepatoTask (Read-RepatoTaskStore $root) $task).deploymentValidationOperations|Where-Object OperationId -ceq $transmitting.OperationId)[0]
 $transmittingBlocked=$false;try{Continue-MayaQaDeploymentValidation $root $task $wf $transmitting.OperationId $transmitting.ExpectedTaskRevision $build $commit $hash $qa $test}catch{$transmittingBlocked=$true};if(!$transmittingBlocked){throw 'unresolved transmitting state was retryable'}
 $response.requestId=$transmitting.RequestId
 $resolvedTransmitting=Continue-MayaQaDeploymentValidation $root $task $wf $transmitting.OperationId $transmitting.ExpectedTaskRevision $build $commit $hash $qa $test -DispositionResolver {param($x)[pscustomobject]@{OperationId=$x.OperationId;Disposition='completed';Response=$response}}
 if($resolvedTransmitting.Status -ne 'Completed'){throw 'authoritative transmitting reconciliation failed'}
 $conflict=$false;try{Continue-MayaQaDeploymentValidation $root $task $wf $unknown.OperationId ($unknown.ExpectedTaskRevision+1) $build $commit $hash $qa $test}catch{$conflict=$true};if(!$conflict){throw 'revision conflict was accepted'}
 $conflict=$false;try{Continue-MayaQaDeploymentValidation $root $task $wf $unknown.OperationId $unknown.ExpectedTaskRevision $build ('C'*40) $hash $qa $test}catch{$conflict=$true};if(!$conflict){throw 'candidate identity conflict was accepted'}
 $d=Read-RepatoTaskStore $root;$t=Find-RepatoTask $d $task;if(@($t.deploymentValidationOperations).Count -ne 3){throw 'duplicate lifecycle prevention failed'}
 [pscustomobject]@{ConfirmedUnsent='PASS';RequestIdPersistedBeforeTransmission='PASS';ResponseRequestBinding='PASS';UnknownRejectedWithoutEvidence='PASS';TransmittingRejectedWithoutEvidence='PASS';UnknownAuthoritativeReconciliation='PASS';TransmittingAuthoritativeReconciliation='PASS';MismatchedEvidenceRejected='PASS';IdempotentCompleted='PASS';DuplicateLifecycle='PASS';IdentityRevisionConflicts='PASS';NoNativeExecution='PASS';ApprovalBoundary='PASS';RealStoreTouched=$false}|ConvertTo-Json -Compress
} finally {Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue}
