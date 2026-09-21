$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
# Coordinator contract tests use an in-memory store and inert bridge. No Revit or deployment.
$root=Join-Path ([IO.Path]::GetTempPath()) ('maya-tara-regression-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$artifact=Join-Path $root 'synthetic.dll';$manifest=Join-Path $root 'synthetic.addin'
Set-Content -LiteralPath $artifact 'synthetic artifact';Set-Content -LiteralPath $manifest 'synthetic manifest'
$model=Join-Path $root 'model.rvt';$sidecar=$model+'.fixture.json'
$build=[pscustomobject]@{BuildStatus='succeeded';BuildRequestId='build-test';ArtifactPath=$artifact;ArtifactSha256=(Get-FileHash $artifact).Hash;ManifestPath=$manifest;ManifestSha256=(Get-FileHash $manifest).Hash}
$handoff=[pscustomobject]@{HandoffId='handoff-test';HandoffStatus='ready';TaskId='task-test';QaWorkflowId='create-levels';BuildRequestId='build-test';FixtureId='CreateLevelsEmpty';NativeTestId='create-levels-elevations-v1';ModelPath=$model;SidecarPath=$sidecar;ArtifactPath=$artifact;ArtifactSha256=$build.ArtifactSha256;ManifestPath=$manifest;ManifestSha256=$build.ManifestSha256}
$workflow=[pscustomobject]@{taskId='task-test';workflowRevision=1;qaBuildRequest=[pscustomobject]@{BuildRequestId='build-test';BuildStatus='requested'};qaBuildEvidence=$build;qaBuildStatus='succeeded';qaHandoff=$handoff;qaHandoffId='handoff-test';qaRunId='run-test';qaWorkflowId='create-levels';qaModelPath=$model;qaSidecarPath=$sidecar;qaFixtureId='CreateLevelsEmpty';qaFixtureSha256=('A'*64);qaTestId='create-levels-elevations-v1';qaApprovalId='approval-test';qaApprovalStatus='approved'}
$task=[pscustomobject]@{revision=1;approvalRequests=@([pscustomobject]@{requestId='approval-test';action='qa-run';status='approved'})}
$testModule=New-Module -ArgumentList (Join-Path $PSScriptRoot 'MayaQa.TaraExecution.ps1'),$workflow,$task -ScriptBlock {
    param($path,$workflow,$task)
    . $path
    $script:testWorkflow=$workflow;$script:testTask=$task;$script:mutations=0;$script:launches=0;$script:failBridge=$false
    function Get-MayaQaWorkflowDefinition {param($id) [pscustomobject]@{FixtureId='CreateLevelsEmpty';TestId='create-levels-elevations-v1';Source='CreateLevelsEmpty.rvt'}}
    function Get-DeployWorkflow {param($store,$taskId,$workflowId) $script:testWorkflow}
    function Read-RepatoTaskStore {param($store) [pscustomobject]@{}}
    function Find-RepatoTask {param($data,$taskId) $script:testTask}
    function Get-MayaQaRoot { 'C:\Repato-Autonomous\Source\QA' }
    function Import-Module {param($Name,$WarningAction)}
    function New-TaraRevitQaPlan {param($Context) if($script:inaccessible){throw 'Path inaccessible: C:\synthetic\RepatoQA. Access was denied while validating the QA path.'}; [pscustomobject]@{Context=$Context}}
    function Invoke-TaraRevitQa {param($Plan,[switch]$DryRun)
        if($DryRun){return [pscustomobject]@{Success=$true;Mode='DryRun';Status='DryRun';Error=$null;ExitCode=$null;ProcessStarted=$false;SideEffectsPerformed=$false;RequestPath='C:\synthetic\request.json';ExecutablePath='C:\synthetic\Revit.exe';ModelPath=$model;QaAddinRoot=$root;ValidationResults=[pscustomobject]@{Validated=$true}}}
        $script:launches++
        if($script:testWorkflow.qaTaraExecutionStatus -cne 'Running'){throw 'Execution claim missing before process boundary.'}
        if($script:failBridge){throw 'synthetic bridge failure'}
        [pscustomobject]@{Status='Passed';SideEffectsPerformed=$true;RequestId='request-test'}
    }
    function Invoke-RepatoWorkflowMutation {
        param($store,$taskId,$workflowId,$workflowRevision,$taskRevision,[scriptblock]$Mutation)
        if($workflowRevision -ne $script:testWorkflow.workflowRevision -or $taskRevision -ne $script:testTask.revision){throw 'Revision conflict'}
        $script:mutations++;$null=& $Mutation $script:testWorkflow
        $script:testWorkflow.workflowRevision++;$script:testTask.revision++
    }
    Export-ModuleMember -Function Invoke-MayaQaTaraExecute
}
Import-Module $testModule
$parameters=@{StoreRoot=$root;TaskId='task-test';WorkflowId='workflow-test';QaWorkflowId='create-levels';RunId='run-test';ModelPath=$model;SidecarPath=$sidecar;ReportDirectory=$root;QaAddinRoot=$root}
$script:checks=0
function Assert-Test($condition,$message){if(!$condition){throw $message};$script:checks++}
function Assert-Rejected([scriptblock]$action,[string]$pattern){$message=$null;try{& $action|Out-Null}catch{$message=$_.Exception.Message};Assert-Test ($message -and $message -match $pattern) "Expected $pattern; observed $message"}
try {
    Assert-Rejected {Invoke-MayaQaTaraExecute @parameters} 'IntegrationTest'
    $dry=Invoke-MayaQaTaraExecute @parameters -DryRun
    Assert-Test ($dry.Success -and $dry.Mode -ceq 'DryRun' -and $dry.Status -ceq 'DryRun' -and $null -eq $dry.ExitCode -and !$dry.ProcessStarted -and !$dry.SideEffectsPerformed -and $null -eq $dry.Error -and $dry.ValidationResults.Validated) 'Dry-run contract failed'
    $counts=& $testModule {@($script:mutations,$script:launches)}
    Assert-Test ($counts[0] -eq 0 -and $counts[1] -eq 0) 'Dry-run crossed mutation/process boundary'
    & $testModule {$script:inaccessible=$true}
    $denied=Invoke-MayaQaTaraExecute @parameters -DryRun
    Assert-Test (!$denied.Success -and $denied.Mode -ceq 'DryRun' -and !$denied.ProcessStarted -and !$denied.SideEffectsPerformed -and $null -eq $denied.ExitCode -and $denied.ValidationResults.PathInaccessible -and $denied.Error -match 'Access was denied') 'Inaccessible QA path was not reported structurally'
    & $testModule {$script:inaccessible=$false}
    foreach($property in @('qaBuildRequest','qaBuildEvidence','qaHandoff','qaRunId','qaApprovalId')){
        $saved=$workflow.$property;$workflow.$property=$null
        Assert-Rejected {Invoke-MayaQaTaraExecute @parameters -DryRun} 'prerequisite is missing'
        $workflow.$property=$saved
    }
    $task.approvalRequests[0].status='pending'
    Assert-Rejected {Invoke-MayaQaTaraExecute @parameters -DryRun} 'approval is required'
    $task.approvalRequests[0].status='approved'
    $handoff.TaskId='wrong'
    Assert-Rejected {Invoke-MayaQaTaraExecute @parameters -DryRun} 'handoff identity mismatch'
    $handoff.TaskId='task-test'
    $bad=$parameters.Clone();$bad.RunId='stale'
    Assert-Rejected {Invoke-MayaQaTaraExecute @bad -DryRun} 'run plan identity mismatch'
    Add-Content -LiteralPath $artifact 'changed'
    Assert-Rejected {Invoke-MayaQaTaraExecute @parameters -DryRun} 'hash mismatch'
    Set-Content -LiteralPath $artifact 'synthetic artifact'
    $result=Invoke-MayaQaTaraExecute @parameters -IntegrationTest
    Assert-Test ($result.Status -ceq 'Passed' -and $workflow.qaTaraExecutionStatus -ceq 'Passed' -and $workflow.qaTaraExecutionEvidence.RequestId -ceq 'request-test') 'Successful execution evidence not persisted'
    Assert-Rejected {Invoke-MayaQaTaraExecute @parameters -IntegrationTest} 'Duplicate Tara execution'
    Assert-Rejected {Invoke-MayaQaTaraExecute @parameters -DryRun} 'Duplicate Tara execution'
    $counts=& $testModule {@($script:mutations,$script:launches)}
    Assert-Test ($counts[0] -eq 2 -and $counts[1] -eq 1) 'Duplicate execution reached process boundary'
    foreach($property in @('qaTaraExecutionStatus','qaTaraExecutionId','qaTaraExecutionStartedUtc','qaTaraExecutionEvidence')){$workflow.PSObject.Properties.Remove($property)}
    & $testModule {$script:failBridge=$true}
    $failure=Invoke-MayaQaTaraExecute @parameters -IntegrationTest
    Assert-Test ($failure.Status -ceq 'Failed' -and $workflow.qaTaraExecutionStatus -ceq 'Failed' -and $workflow.qaTaraExecutionEvidence.Error -match 'synthetic bridge failure') 'Bridge failure was not persisted'
    Assert-Rejected {Invoke-MayaQaTaraExecute @parameters -IntegrationTest} 'Duplicate Tara execution'
    "Maya Tara coordinator checks passed: $script:checks. No Revit launched. Test evidence: $root"
} finally { Remove-Module $testModule -ErrorAction SilentlyContinue }
