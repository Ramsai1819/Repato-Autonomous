& (Join-Path $PSScriptRoot 'Test-MayaQaProductionShapeCanonicalTransaction.ps1');if($LASTEXITCODE -ne 0){exit $LASTEXITCODE};exit 0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force

$task='e2e-task';$workflow='e2e-workflow';$qa='create-plan-views-v1';$attempt='e2e-attempt';$run='e2e-run';$claimId='e2e-claim'
$syntheticStore=Join-Path ([IO.Path]::GetTempPath()) ('maya-e2e-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $syntheticStore -Force|Out-Null;New-RepatoTask $syntheticStore $task 'Maya QA request' 'Create Plan Views' 'qa/maya-qa-workflow' 'maya'|Out-Null;Invoke-RepatoStoreMutation $syntheticStore {param($d,$p)$t=Find-RepatoTask $d $task;$t|Add-Member NoteProperty mayaTaraAttempt ([pscustomobject]@{TaskId=$task;WorkflowId=$workflow;QaWorkflowId=$qa;RunId=$run;AttemptId=$attempt;RequestExpiresUtc=([DateTimeOffset]::UtcNow.AddMinutes(30).ToString('O'))}) -Force;$t}|Out-Null
function Invoke-Case {
    param([scriptblock]$Request,[scriptblock]$Execution,[scriptblock]$Claim,[scriptblock]$Native)
    Invoke-MayaQaCanonicalTransaction -StoreRoot $syntheticStore -UserRequest 'synthetic' -RequestInvoker $Request -ExecutionRecordInvoker $Execution -ClaimInvoker $Claim -NativeCoreInvoker $Native
}
function New-Boundaries {
    param([System.Collections.Generic.List[string]]$Events,[scriptblock]$RequestFailure,[scriptblock]$ExecutionFailure,[scriptblock]$ClaimFailure,[scriptblock]$NativeFailure)
    $request={param($s,$u,$b,$p)$Events.Add('request');if($RequestFailure){&$RequestFailure;return};[pscustomobject]@{Stage='handoff-ready';TaskId=$task;WorkflowId=$workflow;QaWorkflowId=$qa;RunId=$run;Handoff=[pscustomobject]@{HandoffId='e2e-handoff';AttemptId=$attempt;NativeTestId='create-plan-views-v1';ArtifactPath='artifact';ArtifactSha256=('a'*64);ManifestPath='manifest';ManifestSha256=('b'*64);ModelPath='model';ModelSha256=('c'*64);Isolation=[pscustomobject]@{PolicyPath='policy';PolicySha256=('d'*64);Allowed=$true};RunnerManifestPath='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin';ValidatedRunnerManifestPath='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin';RunnerManifestSha256=('e'*64)}}}
    $execution={param($s,$id,$preflight)$Events.Add('execution');if($ExecutionFailure){&$ExecutionFailure;return};[pscustomobject]@{TaskId=$id;WorkflowId=$workflow;QaWorkflowId=$qa;AttemptId=$attempt;RunId=$run;ClaimId=$null}}
    $claimFn={param($s,$id,$owner,$executionRecord)$Events.Add('claim');if($ClaimFailure){&$ClaimFailure;return};$executionRecord|Add-Member NoteProperty ClaimId $claimId -Force;$executionRecord}
    $native={param($s,$id,$idClaim)$Events.Add('native-core');if($NativeFailure){&$NativeFailure;return};[pscustomobject]@{Success=$true;Stage='completed';TaskId=$id;ClaimId=$idClaim;AttemptId=$attempt;RunId=$run}}
    [pscustomobject]@{Request=$request;Execution=$execution;Claim=$claimFn;Native=$native}
}
function Assert-FailureCase {
    param([scriptblock]$RequestFailure,[scriptblock]$ExecutionFailure,[scriptblock]$ClaimFailure,[scriptblock]$NativeFailure,[string]$ExpectedEvents)
    $events=[System.Collections.Generic.List[string]]::new();$b=New-Boundaries $events $RequestFailure $ExecutionFailure $ClaimFailure $NativeFailure;$failed=$false;try{Invoke-Case $b.Request $b.Execution $b.Claim $b.Native|Out-Null}catch{$failed=$true}
    if(!$failed -or ($events -join '|') -cne $ExpectedEvents){throw "Failure contract mismatch: failed=$failed events=$($events -join '|') expected=$ExpectedEvents"}
}
$events=[System.Collections.Generic.List[string]]::new();$b=New-Boundaries $events $null $null $null $null;$success=Invoke-Case $b.Request $b.Execution $b.Claim $b.Native
if(($events -join '|') -cne 'request|execution|claim|native-core'){throw 'Success ordering failed.'}
if($success.TaskId -cne $task -or $success.WorkflowId -cne $workflow -or $success.QaWorkflowId -cne $qa -or $success.Claim.ClaimId -cne $claimId -or $success.Execution.AttemptId -cne $attempt -or $success.Execution.RunId -cne $run){throw "Identity was not preserved: task=$($success.TaskId),workflow=$($success.WorkflowId),qa=$($success.QaWorkflowId),claim=$($success.Claim.ClaimId),attempt=$($success.Execution.AttemptId),run=$($success.Execution.RunId)"}
if(!$success.Result.Success -or $success.Result.Stage -cne 'completed'){throw 'Successful Tara result did not complete the transaction.'}
Assert-FailureCase {throw 'Neil evidence rejected'} $null $null $null 'request'
Assert-FailureCase $null {throw 'Execution preparation failed'} $null $null 'request|execution'
Assert-FailureCase $null $null {throw 'Claim failed'} $null 'request|execution|claim'
Assert-FailureCase $null $null $null {throw 'Tara result failed'} 'request|execution|claim|native-core'
'Canonical synthetic E2E passed: success + 4 failure-stop cases; assertions=14';Remove-Item $syntheticStore -Recurse -Force -ErrorAction SilentlyContinue
