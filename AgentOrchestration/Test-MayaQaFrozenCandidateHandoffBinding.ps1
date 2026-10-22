$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
$root=Join-Path ([IO.Path]::GetTempPath()) ('maya-frozen-handoff-'+[guid]::NewGuid().ToString('N'));$store=Join-Path $root 'store';$candidate='C:\Repato-Autonomous\Source\DeploymentCandidates\AgentBuilds\ReleaseCandidate-fcf624ee3ed1';$hash='7EC1C819C771DCE4EC4ADCADB93B0245D243F6675EC0F0B070B03303B1F412C2';$commit='fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3';$passed=0
function Check([bool]$ok,[string]$name){if(!$ok){throw "FAILED: $name"};$script:passed++}
try{
  $r=Invoke-MayaQaRequest -StoreRoot $store -UserRequest 'create-plan-views-v1' -ArtifactMode FrozenCandidate -CandidateDirectory $candidate -ExpectedCandidateSha256 $hash -ExpectedCandidateSourceCommit $commit -QaStagingInvoker {param($c,$h,$s,$q,$t,$d)[pscustomobject]@{Success=$true;CandidateSha256=$h;CandidateSourceCommit=$s;BuildInvoked=$false;Isolation=[pscustomobject]@{Allowed=$true;Errors=@()}}}
  Resolve-RepatoTaskApproval $store $r.TaskId approve Maya 'synthetic frozen handoff binding'|Out-Null
  $d=Read-RepatoTaskStore $store;$t=Find-RepatoTask $d $r.TaskId;$w=Get-DeployWorkflow $store $r.TaskId $r.WorkflowId;$fake=Join-Path $root 'AgentWork-Repato.Revit.dll';Set-Content $fake 'conflicting mutable artifact';$fakeHash=(Get-FileHash $fake).Hash;$runner='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA\Repato.CreatePlanViews.TestRunner.addin';$runnerHash=('B'*64)
  $m=@(Invoke-RepatoWorkflowMutation $store $r.TaskId $r.WorkflowId $w.workflowRevision $t.revision {param($x)$x.qaBuildEvidence.ArtifactPath=$fake;$x.qaBuildEvidence.ArtifactSha256=$fakeHash;$x.qaBuildEvidence.RunnerManifestPath=$runner;$x.qaBuildEvidence.RunnerManifestSha256=$runnerHash;$x.qaBuildEvidence.DeploymentValidation=$true;$x.qaBuildEvidence.ManifestIntegrityValidation=$true;$x.qaBuildEvidence.QaIsolation=$true;$x})[-1]
  $h=New-MayaQaHandoff -StoreRoot $store -TaskId $r.TaskId -WorkflowId $r.WorkflowId -QaWorkflowId 'create-plan-views-v1'
  Check ($h.ArtifactPath -ieq (Join-Path $candidate 'Repato.Revit.dll')) 'handoff binds candidate path'
  Check ($h.ArtifactSha256 -ieq $hash) 'handoff binds candidate hash'
  Check ($h.ArtifactPath -notmatch 'AgentWork') 'AgentWork is not authoritative'
  Check ($h.ArtifactSha256 -ine $fakeHash) 'conflicting AgentWork hash rejected'
  Check ($h.QaWorkflowId -ceq 'create-plan-views-v1') 'handoff workflow identity'
  [pscustomobject]@{Status='PASS';AssertionsPassed=$passed;AssertionsFailed=0;RealLaunchPerformed=$false;RealStoreTouched=$false}|ConvertTo-Json -Compress
}finally{Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue}
