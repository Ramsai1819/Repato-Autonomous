$ErrorActionPreference='Stop'
$maya=Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -PassThru -WarningAction SilentlyContinue
$agentModule=Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -PassThru -WarningAction SilentlyContinue
$repo=Split-Path $PSScriptRoot -Parent;$id='task-bf61fe7f22d74df7a92599681da5919e'
$productionStore=Join-Path $repo 'QA\MayaRuns';$source=Find-RepatoTask (Read-RepatoTaskStore $productionStore) $id
if($source.revision -ne 130){throw 'Integration fixture requires verified revision130; production state is read-only.'}
$workflowId=$source.cpvPreparationRecovery.Request.workflowId;$w=@($source.deploymentWorkflows|Where-Object workflowId -ceq $workflowId)[0];$e=$w.qaBuildEvidence
$build=$e.BuildRequestId;$commit=$e.CandidateSourceCommit;$hash=$e.ArtifactSha256
$manifest='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin';$manifestHash=$e.RunnerManifestSha256
$sourceJson=$source|ConvertTo-Json -Depth 100
$protectedPaths=@((Join-Path $productionStore 'tasks.json'),(Join-Path $productionStore 'status.json'),$e.ArtifactPath,$e.ManifestPath,$e.CandidateProvenancePath,$e.RunnerManifestPath,$w.qaSidecarPath,$w.qaModelPath,$w.qaFixturePreparationEvidence.RequestPath,$w.qaFixturePreparationEvidence.ResultPath,$w.qaFixturePreparationEvidence.RecoveredProvenancePath)
$before=@($protectedPaths|Sort-Object -Unique|ForEach-Object{[pscustomobject]@{Path=$_;Hash=(Get-FileHash -LiteralPath $_).Hash}})
$root=Join-Path ([IO.Path]::GetTempPath()) ('cpv-recovered-binding-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
$script:passed=0
function Check($condition,$name){if(!$condition){throw "FAILED: $name"};$script:passed++}
function New-Case([string]$mode){
    $store=Join-Path $root ([guid]::NewGuid().ToString('N'));Initialize-RepatoTaskStore $store|Out-Null
    $data=Read-RepatoTaskStore $store;$task=$sourceJson|ConvertFrom-Json;$data.tasks=@($task)
    switch($mode){
        'ordinary-qa' {$task.PSObject.Properties.Remove('cpvPreparationRecovery')}
        'unverified-recovery' {$task.cpvPreparationRecovery.Status='Dispatching'}
        'candidate-hash' {$task.deploymentWorkflows|Where-Object workflowId -ceq $workflowId|ForEach-Object{$_.qaBuildEvidence.ArtifactSha256='0'*64}}
        'build-id' {$task.deploymentWorkflows|Where-Object workflowId -ceq $workflowId|ForEach-Object{$_.qaBuildEvidence.BuildRequestId='build-other'}}
        'manifest' {$task.deploymentWorkflows|Where-Object workflowId -ceq $workflowId|ForEach-Object{$_.qaBuildEvidence.RunnerManifestSha256='0'*64}}
        'active-approval' {$task.approvalRequests+=([pscustomobject]@{requestId='synthetic';action='qa-run';status='pending';consumedUtc=$null})}
        'tara' {$task|Add-Member NoteProperty mayaTaraExecution ([pscustomobject]@{ClaimId='synthetic';ExecutionStatus='Claimed'}) -Force}
    }
    [IO.File]::WriteAllText((Join-Path $store 'tasks.json'),($data|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
    $counter=[pscustomobject]@{Calls=0;Mode=$mode;Preflight=0}
    $health={ [pscustomobject]@{Ready=$true;User='RAMSAI\RepatoQA';SID='S-1-5-21-1031246752-3872016183-2454652381-1015';SessionId=1;UserInteractive=$true} }
    $preflight={param($candidate)$counter.Preflight++;[pscustomobject]@{Succeeded=$true;ExecutionIdentity='RAMSAI\RepatoQA';RunnerManifestPath=$manifest;ExpectedRunnerManifestSha256=$manifestHash}}.GetNewClosure()
    $invoke={param($candidate,$op)$counter.Calls++;$r=[pscustomobject]@{schemaVersion=1;operation='validate-qa-deployment';requestId=$op.RequestId;validationIdentity='RAMSAI\RepatoQA';succeeded=$true;candidateCommit=$op.CandidateSourceCommit;candidateSha256=$op.CandidateSha256;qaWorkflowId='create-plan-views-v1';testId='create-plan-views-v1';isolationPassed=$true;qaAddinRoot='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA';runnerManifestPath=$manifest;runnerManifestSha256=$manifestHash;manifestIntegrityPassed=$true};if($counter.Mode -ceq 'response-tamper'){$r.candidateSha256='0'*64};if($counter.Mode -ceq 'timeout'){throw 'Synthetic ambiguous response'};$r}.GetNewClosure()
    [pscustomobject]@{Store=$store;Counter=$counter;Health=$health;Preflight=$preflight;Invoke=$invoke}
}
function Invoke-Case($case,[long]$revision=130){Invoke-MayaQaIndependentDeploymentValidationRecovery -StoreRoot $case.Store -TaskId $id -WorkflowId $workflowId -ExpectedTaskRevision $revision -ExpectedBuildRequestId $build -ExpectedCandidateSourceCommit $commit -ExpectedCandidateSha256 $hash -ExpectedRunnerManifestPath $manifest -ExpectedRunnerManifestSha256 $manifestHash -HealthInvoker $case.Health -PreflightInvoker $case.Preflight -DeploymentValidationInvoker $case.Invoke -RevitProcessProvider {@()}}
function Read-Case($case){Find-RepatoTask (Read-RepatoTaskStore $case.Store) $id}
function Get-Proof($task){$wf=@($task.deploymentWorkflows|Where-Object workflowId -ceq $workflowId)[0];& $agentModule {param($t,$w,$b,$c,$h,$m,$mh)Get-RepatoCanonicalQaDeploymentApprovalEvidence -Task $t -Workflow $w -BuildRequestId $b -CandidateSourceCommit $c -CandidateSha256 $h -RunnerManifestPath $m -RunnerManifestSha256 $mh} $task $wf $build $commit $hash $e.RunnerManifestPath $manifestHash}
function Reject($action,$name){$rejected=$false;try{$null=&$action}catch{$rejected=$true};Check $rejected $name}
try {
    $case=New-Case 'success';$old=Read-Case $case;$result=Invoke-Case $case;$task=Read-Case $case;$wf=@($task.deploymentWorkflows|Where-Object workflowId -ceq $workflowId)[0]
    Check ($task.revision -eq 134 -and $task.workflowStage -ceq 'qa' -and $task.status -ceq 'in-progress') 'four mutations preserve QA stage'
    Check ($result.Status -ceq 'IndependentDeploymentValidated' -and !$result.StagingSuccessClaimed -and !$result.StageRequestResent -and !$result.RevitLaunched -and !$result.ApprovalRequested -and $case.Counter.Calls -eq 1) 'single synthetic validation lifecycle'
    Check ($wf.qaBuildEvidence.IndependentDeploymentValidation.StagingDisposition -ceq 'existing-verified-deployment' -and $task.deploymentValidationOperations[-1].ValidationPurpose -ceq 'RecoveredQaCurrentDeployment') 'distinct recovered deployment purpose'
    foreach($name in @($e.PSObject.Properties.Name|Where-Object {$_ -notin @('DeploymentValidation','ManifestIntegrityValidation','QaIsolation','QaAddinRoot','Isolation','IndependentDeploymentValidation','DeployedRunnerManifestPath','DeployedRunnerManifestSha256')})){
        Check (($e.$name|ConvertTo-Json -Depth 100 -Compress) -ceq ($wf.qaBuildEvidence.$name|ConvertTo-Json -Depth 100 -Compress)) "adopted build field preserved: $name"
    }
    Check (($old.approvalRequests|ConvertTo-Json -Depth 100 -Compress) -ceq ($task.approvalRequests|ConvertTo-Json -Depth 100 -Compress)) 'approvals preserved'
    Check (($old.cpvPreparationRecovery|ConvertTo-Json -Depth 100 -Compress) -ceq ($task.cpvPreparationRecovery|ConvertTo-Json -Depth 100 -Compress)) 'recovery preserved'
    $proof=Get-Proof $task;Check ($proof.StagingDisposition -ceq 'existing-verified-deployment' -and !$proof.StagingSuccessClaimed) 'canonical downstream approval evidence accepted'
    Reject {Invoke-Case $case 134} 'completed lifecycle replay rejected';Check ($case.Counter.Calls -eq 1) 'replay never transmits'
    foreach($mode in 'ordinary-qa','unverified-recovery','candidate-hash','build-id','manifest','active-approval','tara'){$bad=New-Case $mode;Reject {Invoke-Case $bad} "$mode rejected";Check ($bad.Counter.Calls -eq 0) "$mode never transmits"}
    $bad=New-Case 'success';Reject {Invoke-Case $bad 129} 'stale revision rejected';Check ($bad.Counter.Calls -eq 0) 'stale revision never transmits'
    $bad=New-Case 'response-tamper';Reject {Invoke-Case $bad} 'tampered response rejected';Check (!(Read-Case $bad).deploymentWorkflows[0].qaBuildEvidence.DeploymentValidation) 'tampered response never promoted'
    $bad=New-Case 'timeout';Reject {Invoke-Case $bad} 'ambiguous timeout rejected';$unknown=Read-Case $bad;Reject {Invoke-Case $bad $unknown.revision} 'ambiguous lifecycle replay rejected';Check ($bad.Counter.Calls -eq 1) 'ambiguous lifecycle sends once'
    $task.deploymentValidationOperations[-1].ValidationRequest.expectedCandidateSha256='0'*64;Reject {Get-Proof $task} 'persisted proof tamper rejected'
    foreach($file in $before){Check ((Get-FileHash -LiteralPath $file.Path).Hash -ceq $file.Hash) 'protected production bytes unchanged'}
    "PASS: $script:passed recovered QA deployment integration assertions; isolated stores only; zero production endpoint calls."
}finally{if([IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $root -Recurse -Force}}
