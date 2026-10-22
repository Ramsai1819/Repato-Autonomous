$ErrorActionPreference='Stop'
$here=$PSScriptRoot
Import-Module (Join-Path $here 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $here 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $here 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue

$taskId='task-bf61fe7f22d74df7a92599681da5919e';$workflowId='fa2c2f578cbc40cbacac45c96313ca4c';$buildId='build-4b47d1c11c6b48e094b2d75f0097af04'
$repoRoot=Split-Path $here -Parent;$commit=(& git -C $repoRoot rev-parse HEAD).Trim();$primaryRepo=Split-Path -Parent ((& git -C $repoRoot rev-parse --path-format=absolute --git-common-dir).Trim());$qaId='create-plan-views-v1'
$candidate=Join-Path $primaryRepo ('DeploymentCandidates\AgentBuilds\ReleaseCandidate-'+$commit.Substring(0,12));$candidateHash=(Get-FileHash (Join-Path $candidate 'Repato.Revit.dll') -Algorithm SHA256).Hash
$sourceRunner=Join-Path (Split-Path $here -Parent) 'QA\Repato.CreatePlanViews.TestRunner.addin';$runnerHash=(Get-FileHash $sourceRunner -Algorithm SHA256).Hash
$installedRunner='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin';$addinRoot='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA'
$fixture=Join-Path (Split-Path $here -Parent) 'QA\Fixtures\CreatePlanViewsEmpty.rvt';$madeFixture=$false
if(!(Test-Path -LiteralPath $fixture)){New-Item -ItemType Directory -Path (Split-Path $fixture -Parent) -Force|Out-Null;[IO.File]::WriteAllBytes($fixture,[byte[]](1..128));$madeFixture=$true}
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('maya-independent-approval-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $tmp|Out-Null
$prepRoots=[Collections.Generic.List[string]]::new()
$passed=0;$total=0
function Case([string]$name,[scriptblock]$body){$script:total++;try{&$body;$script:passed++}catch{throw "$name : $($_.Exception.Message) [$($_.ScriptStackTrace)]"}}
function New-ApprovalFixture([string]$mode){
    $store=Join-Path $tmp ([guid]::NewGuid().ToString('N'));Initialize-RepatoTaskStore $store|Out-Null
    New-RepatoTask $store $taskId 'Synthetic Create Plan Views' 'approval binding regression' 'qa/maya-approval-binding' 'maya'|Out-Null
    $dll=Join-Path $candidate 'Repato.Revit.dll';$addin=Join-Path $candidate 'Repato.addin';$prov=Join-Path $candidate 'release-manifest.json';$provHash=(Get-FileHash $prov -Algorithm SHA256).Hash;$addinHash=(Get-FileHash $addin -Algorithm SHA256).Hash
    $original='C:\Repato-Autonomous\Worktrees\create-plan-views-buildfix-4f2cbba22ba9\QA\Repato.CreatePlanViews.TestRunner.addin'
    $e=[pscustomobject][ordered]@{BuildRequestId=$buildId;BuildStatus='succeeded';SourceCommit=$commit;CandidateSourceCommit=$commit;EvidenceSource='FrozenCandidate';CandidateDirectory=$candidate;CandidateProvenancePath=$prov;CandidateProvenanceSha256=$provHash;ArtifactPath=$dll;ArtifactSha256=$candidateHash;ManifestPath=$addin;ManifestSha256=$addinHash;RunnerManifestPath=$sourceRunner;RunnerManifestSha256=$runnerHash;RunnerManifestQaWorkflowId=$qaId;RunnerManifestTestId=$qaId;OriginalRunnerManifestPath=$original;DeploymentValidation=$true;ManifestIntegrityValidation=$true;QaIsolation=$true;DeployedRunnerManifestPath=$installedRunner;DeployedRunnerManifestSha256=$runnerHash;QaAddinRoot=$addinRoot;Isolation=[pscustomobject]@{Allowed=$true;PolicyPath=(Join-Path (Split-Path $here -Parent) 'QA\MachineWideAddins.allowlist.json');PolicySha256=(Get-FileHash (Join-Path (Split-Path $here -Parent) 'QA\MachineWideAddins.allowlist.json') -Algorithm SHA256).Hash}}
    $opId=[guid]::NewGuid().ToString('N');$requestId=[guid]::NewGuid().ToString('N')
    $ce=[pscustomobject][ordered]@{SchemaVersion=1;TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId=$qaId;TestId=$qaId;CandidateSourceCommit=$commit;CandidateDirectory=$candidate;CandidateDllPath=$dll;CandidateDllSha256=$candidateHash;NeilBuildArtifactSha256=$candidateHash;RunnerManifestPath=$sourceRunner;RunnerManifestSha256=$runnerHash;CandidateProvenancePath=$prov;OriginalRunnerManifestPath=$original}
    $req=[pscustomobject][ordered]@{schemaVersion=1;operation='validate-qa-deployment';requestId=$requestId;candidateCommit=$commit;expectedCandidateSha256=$candidateHash;taskId=$taskId;workflowId=$workflowId;qaWorkflowId=$qaId;testId=$qaId;candidateEvidence=$ce}
    $reqJson=ConvertTo-Json -InputObject $req -Compress -Depth 32;$sha=[Security.Cryptography.SHA256]::Create();try{$reqHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($reqJson)))).Replace('-','')}finally{$sha.Dispose()}
    $resp=[pscustomobject][ordered]@{schemaVersion=1;operation='validate-qa-deployment';requestId=$requestId;succeeded=$true;candidateCommit=$commit;candidateSha256=$candidateHash;qaWorkflowId=$qaId;testId=$qaId;validationIdentity='RAMSAI\RepatoQA';qaAddinRoot=$addinRoot;isolationPassed=$true;runnerManifestPath=$installedRunner;runnerManifestSha256=$runnerHash;validatedRunnerManifestPath=$installedRunner;manifestIntegrityEvidenceAvailable=$true;manifestIntegrityPassed=$true}
    $op=[pscustomobject][ordered]@{SchemaVersion=1;OperationId=$opId;RequestId=$requestId;TaskId=$taskId;WorkflowId=$workflowId;ExpectedTaskRevision=1;BuildRequestId=$buildId;CandidateSourceCommit=$commit;CandidateSha256=$candidateHash;QaWorkflowId=$qaId;TestId=$qaId;ValidationPurpose='IndependentAfterAmbiguousStaging';ValidationRequest=$req;ValidationRequestSha256=$reqHash;RequestDisposition='completed';TransmittingTaskRevision=1;Response=$resp}
    $ind=[pscustomobject][ordered]@{Purpose='independent-current-deployment-validation';OperationId=$opId;RequestId=$requestId;ValidationRequest=$req;ValidationRequestSha256=$reqHash;TaskId=$taskId;WorkflowId=$workflowId;BuildRequestId=$buildId;CandidateSourceCommit=$commit;CandidateDllSha256=$candidateHash;RunnerManifestPath=$installedRunner;RunnerManifestSha256=$runnerHash;Response=$resp;StagingDisposition='ambiguous-unresolved';StagingSuccessClaimed=$false}
    $e|Add-Member NoteProperty IndependentDeploymentValidation $ind -Force
    $wf=[pscustomobject][ordered]@{workflowId=$workflowId;taskId=$taskId;workflowRevision=1;taskRevision=1;stage='validated';status='validated';qaWorkflowId=$qaId;qaTestId=$qaId;qaBuildRequest=[pscustomobject]@{BuildRequestId=$buildId;AuthenticatedBuildSource=[pscustomobject]@{RepositoryRoot=$repoRoot;ExpectedSourceCommit=$commit;ProjectRelativePath='Forma.RevitConnector.csproj'}};qaBuildStatus='succeeded';qaBuildEvidence=$e}
    $null=Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.status='in-progress';$t.workflowStage='build-checks';$t|Add-Member NoteProperty deploymentWorkflows ([object[]]@($wf)) -Force;$t|Add-Member NoteProperty deploymentValidationOperations ([object[]]@($op)) -Force;Add-RepatoHistory $t 'deployment-validation-completed' 'Maya' "operation=$opId";$d}
    switch($mode){
        'operation-id' {Invoke-RepatoStoreMutation $store {param($d,$p)(Find-RepatoTask $d $taskId).deploymentWorkflows[0].qaBuildEvidence.IndependentDeploymentValidation.OperationId='bad';$d}|Out-Null}
        'request-id' {Invoke-RepatoStoreMutation $store {param($d,$p)(Find-RepatoTask $d $taskId).deploymentWorkflows[0].qaBuildEvidence.IndependentDeploymentValidation.RequestId='bad';$d}|Out-Null}
        'response-id' {Invoke-RepatoStoreMutation $store {param($d,$p)(Find-RepatoTask $d $taskId).deploymentValidationOperations[0].Response.requestId='bad';$d}|Out-Null}
        'candidate' {Invoke-RepatoStoreMutation $store {param($d,$p)(Find-RepatoTask $d $taskId).deploymentValidationOperations[0].CandidateSha256='0'*64;$d}|Out-Null}
        'manifest' {Invoke-RepatoStoreMutation $store {param($d,$p)(Find-RepatoTask $d $taskId).deploymentValidationOperations[0].Response.runnerManifestSha256='0'*64;$d}|Out-Null}
        'identity' {Invoke-RepatoStoreMutation $store {param($d,$p)(Find-RepatoTask $d $taskId).deploymentValidationOperations[0].Response.validationIdentity='RAMSAI\Other';$d}|Out-Null}
        'isolation' {Invoke-RepatoStoreMutation $store {param($d,$p)(Find-RepatoTask $d $taskId).deploymentValidationOperations[0].Response.isolationPassed=$false;$d}|Out-Null}
        'staging-claim' {Invoke-RepatoStoreMutation $store {param($d,$p)(Find-RepatoTask $d $taskId).deploymentWorkflows[0].qaBuildEvidence.IndependentDeploymentValidation.StagingSuccessClaimed=$true;$d}|Out-Null}
        'wrong-build' {Invoke-RepatoStoreMutation $store {param($d,$p)(Find-RepatoTask $d $taskId).deploymentValidationOperations[0].BuildRequestId='other';$d}|Out-Null}
        'duplicate' {Invoke-RepatoStoreMutation $store {param($d,$p)$t=Find-RepatoTask $d $taskId;$t.approvalRequests=@([pscustomobject]@{action='qa-run';status='pending'});$d}|Out-Null}
        'wrong-stage' {Invoke-RepatoStoreMutation $store {param($d,$p)(Find-RepatoTask $d $taskId).workflowStage='build-checks';$d}|Out-Null}
    }
    [pscustomobject]@{Store=$store;Mode=$mode;OperationId=$opId;RequestId=$requestId;Revision=[long](Find-RepatoTask (Read-RepatoTaskStore $store) $taskId).revision}
}
function Prepare-And-Request($f,[switch]$Stale){
    $prepRoot=Join-Path (Split-Path $fixture -Parent) ('..\TestRuns\independent-prep-'+[guid]::NewGuid().ToString('N'));$prepRoot=[IO.Path]::GetFullPath($prepRoot);New-Item $prepRoot -ItemType Directory|Out-Null;$script:prepRoots.Add($prepRoot);$pa=[guid]::NewGuid().ToString('N');$pr=[guid]::NewGuid().ToString('N');$pm=Join-Path $prepRoot 'model.rvt';Copy-Item $fixture $pm;$ph=(Get-FileHash $fixture).Hash;$rq=Join-Path $prepRoot ($pa+'.request.json');$rs=$rq+'.preparation.json';[ordered]@{operation='prepare-disposable-create-plan-views-fixture';taskId=$taskId;workflowId=$workflowId;attemptId=$pa;runId=$pr;requestPath=$rq;modelPath=$pm;modelSha256=$ph;outputPath=$rs}|ConvertTo-Json|Set-Content $rq;[ordered]@{Status='Passed';Operation='prepare-disposable-create-plan-views-fixture';TaskId=$taskId;WorkflowId=$workflowId;AttemptId=$pa;RunId=$pr;ModelPath=$pm;SourceModelSha256=$ph;PreparedModelSha256=$ph}|ConvertTo-Json|Set-Content $rs
    $syntheticRequest=Get-Content $rq -Raw|ConvertFrom-Json
    $syntheticRequest|Add-Member NoteProperty expiresUtc ([DateTimeOffset]::UtcNow.AddHours(1).ToString('O'))
    $syntheticRequest|ConvertTo-Json|Set-Content $rq
    $run=New-MayaQaRun -StoreRoot $f.Store -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -RunId $pr -RuntimeRoot (Join-Path $f.Store 'runtime') -FixturePreparationResultPath $rs
    $t=if($f.Mode -eq 'wrong-stage'){Find-RepatoTask (Read-RepatoTaskStore $f.Store) $taskId}else{Update-RepatoTask $f.Store $taskId 'in-progress' 'qa' 'Maya' $null $null -ExpectedTaskRevision ([long]$run.TaskRevision) -ExpectedWorkflowId $workflowId -ExpectedWorkflowRevision ([long]$run.WorkflowRevision) -ExpectedQaWorkflowId $qaId}
    $revision=[long]$t.revision;if($Stale){$revision--}
    Request-MayaQaCanonicalExecutionApproval -StoreRoot $f.Store -TaskId $taskId -WorkflowId $workflowId -BuildRequestId $buildId -ExpectedTaskRevision $revision -CandidateSourceCommit $commit -CandidateSha256 $candidateHash
}
try {
    Case 'independent validation bound to fresh user approval and QA plan' {
        $f=New-ApprovalFixture 'valid';$q=Prepare-And-Request $f;$t=Find-RepatoTask (Read-RepatoTaskStore $f.Store) $taskId;$w=$t.deploymentWorkflows[0];$plan=$q.executionBinding.ExecutionPlan
        if($q.status -cne 'pending' -or $q.requiredLevel -cne 'user' -or $q.executionBinding.DeploymentValidationEvidence.OperationId -cne $f.OperationId -or $q.executionBinding.DeploymentValidationEvidence.RequestId -cne $f.RequestId -or $q.executionBinding.DeploymentValidationEvidence.StagingSuccessClaimed -ne $false -or !$w.qaRunId -or !$w.qaModelPath -or !$w.qaSidecarPath -or !$w.qaFixtureSha256 -or $t.workflowStage -cne 'approval' -or $plan.NextAgent -cne 'Tara'){throw 'Independent evidence or canonical QA plan was not bound.'}
        Resolve-RepatoTaskApproval $f.Store $taskId approve user 'synthetic binding verification'|Out-Null
    }
    Case 'active repository candidate approval resolves without legacy manifest provenance' {
        $f=New-ApprovalFixture 'valid';Invoke-RepatoStoreMutation $f.Store {param($d,$p)$w=@((Find-RepatoTask $d $taskId).deploymentWorkflows|Where-Object workflowId -ceq $workflowId)[0];$w.qaBuildEvidence.PSObject.Properties.Remove('OriginalRunnerManifestPath');$d}|Out-Null
        $q=Prepare-And-Request $f;Resolve-RepatoTaskApproval $f.Store $taskId approve user 'synthetic active-root approval verification'|Out-Null
        $t=Find-RepatoTask (Read-RepatoTaskStore $f.Store) $taskId;if($t.status -cne 'in-progress' -or @($t.approvalRequests|Where-Object {$_.requestId -ceq $q.requestId -and $_.status -ceq 'approved'}).Count -ne 1){throw 'Active repository candidate did not resolve after optional legacy provenance was omitted.'}
    }
    foreach($mode in @('operation-id','request-id','response-id','candidate','manifest','identity','isolation','staging-claim','wrong-build')){Case "$mode rejected" {$f=New-ApprovalFixture $mode;$failed=$false;try{Prepare-And-Request $f|Out-Null}catch{$failed=$true};$t=Find-RepatoTask (Read-RepatoTaskStore $f.Store) $taskId;if(!$failed -or @($t.approvalRequests|Where-Object status -ceq 'pending').Count){throw "$mode crossed approval boundary"}}}
    Case 'stale revision rejected' {$f=New-ApprovalFixture 'valid';$failed=$false;try{Prepare-And-Request $f -Stale|Out-Null}catch{$failed=$true};if(!$failed){throw 'stale revision was accepted'}}
    Case 'duplicate approval rejected' {$f=New-ApprovalFixture 'duplicate';$failed=$false;try{Prepare-And-Request $f|Out-Null}catch{$failed=$true};if(!$failed){throw 'duplicate approval was accepted'}}
    Case 'inconsistent workflow state rejected' {$f=New-ApprovalFixture 'wrong-stage';$failed=$false;try{Prepare-And-Request $f|Out-Null}catch{$failed=$true};if(!$failed){throw 'wrong workflow stage was accepted'}}
    Case 'approval cannot be reused after validation response changes' {
        $f=New-ApprovalFixture 'valid';$q=Prepare-And-Request $f;Invoke-RepatoStoreMutation $f.Store {param($d,$p)$t=Find-RepatoTask $d $taskId;$op=$t.deploymentValidationOperations[0];$op.Response|Add-Member NoteProperty errorMessage 'changed-after-approval' -Force;$t.deploymentWorkflows[0].qaBuildEvidence.IndependentDeploymentValidation.Response|Add-Member NoteProperty errorMessage 'changed-after-approval' -Force;$d}|Out-Null
        $failed=$false;try{Resolve-RepatoTaskApproval $f.Store $taskId approve user 'tampered evidence attempt'|Out-Null}catch{$failed=$true};if(!$failed){throw 'approval accepted changed independent validation response'}
    }
    [pscustomobject]@{Passed=$passed;Total=$total;SyntheticStoresOnly=$true;SyntheticFixtureOnly=$true;ApprovalCreatedOnlyInSyntheticStore=$true;TaraLaunched=$false;RevitLaunched=$false}|ConvertTo-Json -Compress
} finally {Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue;foreach($p in $prepRoots){Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue};if($madeFixture){Remove-Item -LiteralPath $fixture -Force -ErrorAction SilentlyContinue}}
