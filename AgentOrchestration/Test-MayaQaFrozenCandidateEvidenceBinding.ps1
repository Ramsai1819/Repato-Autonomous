$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue
$root=Join-Path ([IO.Path]::GetTempPath()) ('frozen-bind-'+[guid]::NewGuid().ToString('N'));New-Item $root -ItemType Directory|Out-Null
$candidate=Join-Path (Join-Path $PSScriptRoot '..') 'DeploymentCandidates\AgentBuilds\ReleaseCandidate-fcf624ee3ed1';$dll=Join-Path $candidate 'Repato.Revit.dll';$hash=(Get-FileHash $dll -Algorithm SHA256).Hash;$commit='fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3';$runner='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin';$runnerHash='AF4DBFA78E61524DE7BD3B84178C6B70ED8D29D0A95BA17780826E09BE689D4F'
$validate={param($c,$h,$q,$test,$task,$workflow,$build,$e)[pscustomobject]@{succeeded=$true;candidateCommit=$c;candidateSha256=$h;qaWorkflowId=$q;testId=$test;taskId=$task;workflowId=$workflow;runnerManifestPath=$runner;runnerManifestSha256=$runnerHash;qaAddinRoot='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA';isolationPassed=$true}}
$module=Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -PassThru -WarningAction SilentlyContinue
try {
    $prepRejected=$false
    try { Invoke-MayaQaRequest -StoreRoot $root -UserRequest 'Create Plan Views' -ArtifactMode FrozenCandidate -CandidateDirectory $candidate -CandidateDllPath $dll -ExpectedCandidateSha256 $hash -ExpectedCandidateSourceCommit $commit -DeploymentValidationInvoker $validate | Out-Null }
    catch { if($_.Exception.Message -match 'requires correlated fixture-preparation evidence'){ $prepRejected=$true } else { throw } }
    if(!$prepRejected){throw 'Fresh Create Plan Views QA must require authenticated fixture-preparation evidence before approval.'}
    $d=Read-RepatoTaskStore $root;$t=@($d.tasks)[0];$workflowId=[string]$t.deploymentWorkflows[0].workflowId;$w=Get-DeployWorkflow $root $t.taskId $workflowId;$firstRevision=$t.revision
    if($w.qaBuildEvidence.EvidenceSource -ne 'FrozenCandidate' -or $w.qaBuildEvidence.SourceCommit -ne $commit -or $w.qaBuildEvidence.BuildRequestId -ne $w.qaBuildRequest.BuildRequestId){throw 'Valid frozen candidate was not bound to the new build request.'}
    if($w.qaBuildEvidence.Command -notmatch 'no compilation' -or $t.PSObject.Properties.Name -contains 'mayaTaraExecution'){throw 'Frozen binding crossed the execution boundary.'}
    $same=& $module {param($s,$id,$wid,$qa,$dir,$dll,$h,$c) Bind-MayaQaFrozenCandidateBuildEvidence -StoreRoot $s -TaskId $id -WorkflowId $wid -QaWorkflowId $qa -CandidateDirectory $dir -CandidateDllPath $dll -ExpectedSha256 $h -ExpectedSourceCommit $c} $root $t.taskId $workflowId 'create-plan-views-v1' $candidate $dll $hash $commit
    $after=Find-RepatoTask (Read-RepatoTaskStore $root) $t.taskId;if($after.revision -ne $firstRevision){throw 'Idempotent binding changed the task unexpectedly.'}
    $bad=Read-RepatoTaskStore $root;$bt=Find-RepatoTask $bad $t.taskId;$bw=Get-DeployWorkflow $root $t.taskId $workflowId;Invoke-RepatoWorkflowMutation $root $t.taskId $workflowId $bw.workflowRevision $bt.revision {param($x)$x.qaBuildEvidence.SourceCommit='0'*40;return $x}|Out-Null;$conflict=$false;try{& $module {param($s,$id,$wid,$qa,$dir,$dll,$h,$c) Bind-MayaQaFrozenCandidateBuildEvidence -StoreRoot $s -TaskId $id -WorkflowId $wid -QaWorkflowId $qa -CandidateDirectory $dir -CandidateDllPath $dll -ExpectedSha256 $h -ExpectedSourceCommit $c} $root $t.taskId $workflowId 'create-plan-views-v1' $candidate $dll $hash $commit|Out-Null}catch{$conflict=$true};if(!$conflict){throw 'Conflicting frozen evidence was accepted.'}
    [pscustomobject]@{ValidBinding='PASS';BuildRequestBound='PASS';NoCompilation='PASS';FixturePreparationRequired='PASS';NoExecution='PASS';Idempotent='PASS';ConflictRejected='PASS';NativeSent=$false;RealStoreTouched=$false}|ConvertTo-Json -Compress
} finally {Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue}
