$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
$response=[pscustomobject]@{schemaVersion=1;operation='preflight-readonly';succeeded=$false;executionIdentity='RAMSAI\RepatoQA';qaAddinRoot='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA';runnerManifestPath='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA\Repato.CreatePlanViews.TestRunner.addin';expectedRunnerManifestSha256=('A'*64);checks=@([pscustomobject]@{Name='runner-manifest';Passed=$false;Status='missing-or-inaccessible';Path='x';Detail=$null});failureCode='preflight-failed'}
$script:seen=$null;$result=Invoke-MayaQaLaunchAgentPreflightReadonly -ResponseProvider {param($request)$script:seen=$request;return $response}
if($script:seen.operation -cne 'preflight-readonly' -or $script:seen.schemaVersion -ne 1){throw 'Fixed preflight request contract failed.'}
if($result.ExecutionIdentity -cne 'RAMSAI\RepatoQA' -or $result.Checks.Count -ne 1 -or $result.Response.failureCode -cne 'preflight-failed'){throw 'Complete response parsing failed.'}
$evidence=[pscustomobject]@{TaskId='synthetic-task';WorkflowId='synthetic-workflow';QaWorkflowId='create-plan-views-v1';TestId='create-plan-views-v1';CandidateSourceCommit=('a'*40);CandidateDllSha256=('B'*64);NeilBuildArtifactSha256=('B'*64)}
$candidateArgs=@{CandidateEvidence=$evidence;TaskId=$evidence.TaskId;WorkflowId=$evidence.WorkflowId;QaWorkflowId=$evidence.QaWorkflowId;TestId=$evidence.TestId;CandidateCommit=$evidence.CandidateSourceCommit;ExpectedCandidateSha256=$evidence.CandidateDllSha256;ResponseProvider={param($request)$script:seen=$request;return $response}}
$null=Invoke-MayaQaLaunchAgentPreflightReadonly @candidateArgs
if($script:seen.candidateCommit -cne $evidence.CandidateSourceCommit -or $script:seen.candidateEvidence.TaskId -cne $evidence.TaskId -or $script:seen.PSObject.Properties.Name -contains 'requestId'){throw 'Candidate-aware read-only envelope failed.'}
foreach($name in 'TaskId','WorkflowId','QaWorkflowId','TestId','CandidateCommit','ExpectedCandidateSha256'){
    $bad=@{}+$candidateArgs;$bad[$name]='invalid'
    try{$null=Invoke-MayaQaLaunchAgentPreflightReadonly @bad;throw 'Unexpected acceptance'}catch{if($_.Exception.Message -notmatch 'Candidate-aware preflight'){throw}}
}
$bad=@{}+$candidateArgs;$bad.CandidateEvidence=$null
try{$null=Invoke-MayaQaLaunchAgentPreflightReadonly @bad;throw 'Unexpected acceptance'}catch{if($_.Exception.Message -notmatch 'evidence is required'){throw}}
try { Invoke-MayaQaLaunchAgentPreflightReadonly -ResponseProvider { [pscustomobject]@{schemaVersion=1;operation='launch-revit-qa'} } ; throw 'Invalid operation response was accepted.' } catch { if($_.Exception.Message -notmatch 'missing|Unexpected preflight response') { throw } }
$module=Get-Content (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Raw
$start=$module.IndexOf('function Invoke-MayaQaLaunchAgentPreflightReadonly')
$end=$module.IndexOf('function Read-MayaQaBoundedPipeLine',$start)
if($start -lt 0 -or $end -le $start){throw 'Preflight implementation boundary could not be isolated.'}
$preflight=$module.Substring($start,$end-$start)
if($preflight -notmatch "operation='preflight-readonly'" -or $preflight -match 'param\([^)]*Operation') {throw 'Operation injection surface detected.'}
Write-Output 'Maya preflight client synthetic tests passed: fixed operation, shared pipe transport, complete response, identity gate, and no operation injection.'
