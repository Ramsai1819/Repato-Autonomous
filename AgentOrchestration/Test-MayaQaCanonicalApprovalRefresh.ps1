$ErrorActionPreference='Stop'
$here=$PSScriptRoot
Import-Module (Join-Path $here 'Repato.AgentOrchestration.psm1') -Force
Import-Module (Join-Path $here 'Repato.Deployment.psm1') -Force
Import-Module (Join-Path $here 'Repato.MayaQaWorkflow.psm1') -Force

$passed=0;$total=0
function Check($name,[scriptblock]$body){$script:total++;try{&$body; $script:passed++}catch{throw "${name}: $($_.Exception.Message)"}}
function New-RefreshStore {
    $root=Join-Path ([IO.Path]::GetTempPath()) ('maya-approval-refresh-'+[guid]::NewGuid().ToString('N'));$store=Join-Path $root 'store';$taskId='REFRESH-001';$workflowId='workflow-001';$build='build-001'
    New-RepatoTask $store $taskId 'Synthetic QA' 'canonical approval refresh' 'qa/approval-refresh'|Out-Null
    $plan=[pscustomobject]@{taskId=$taskId;planId='plan-001';artifactPath=(Join-Path $root 'artifact.dll');artifactSha256=('A'*64);manifestPath=(Join-Path $root 'runner.addin');manifestSha256=('B'*64);targetId='qa-local-fixture';targetPath='qa-local-fixture';targetRoot=$root;failureMode='None'}
    New-Item -ItemType Directory -Path $root -Force|Out-Null;Set-Content $plan.artifactPath x;Set-Content $plan.manifestPath y
    $null=Invoke-RepatoStoreMutation $store {param($d,$p)$t=Find-RepatoTask $d $taskId;$t.status='awaiting-approval';$t.workflowStage='approval';$t.revision=14;$t.approvalRequests=[object[]]@([pscustomobject]@{requestId='old';action='qa-run';requiredLevel='maya';status='pending';requestedRevision=9;approvedRevision=$null;requestedUtc='2026-01-01T00:00:00Z';expiresUtc='2026-01-01T00:01:00Z';previousStatus='passed';bindingHash='';decidedUtc=$null;decidedBy=$null;reason=$null;consumedUtc=$null});$w=[pscustomobject]@{workflowId=$workflowId;taskId=$taskId;planId='plan-001';planSha256='x';taskRevision=14;workflowRevision=14;stage='validated';status='validated';qaWorkflowId='create-plan-views-v1';qaBuildRequest=[pscustomobject]@{BuildRequestId=$build};qaBuildStatus='succeeded';qaBuildEvidence=[pscustomobject]@{BuildRequestId=$build;BuildStatus='succeeded';EvidenceSource='FrozenCandidate';SourceCommit=('C'*40);CandidateSourceCommit=('C'*40);ArtifactSha256=('D'*64);CandidateProvenancePath='prov';RunnerManifestPath='source-runner';RunnerManifestSha256=('E'*64);DeploymentValidation=$true;ManifestIntegrityValidation=$true;QaIsolation=$true}};$t|Add-Member NoteProperty deploymentWorkflows ([object[]]@($w)) -Force;$t}
    [pscustomobject]@{Root=$root;StoreRoot=$store;TaskId=$taskId;WorkflowId=$workflowId;Build=$build}
}
function Refresh($c){Request-MayaQaCanonicalApprovalRefresh -StoreRoot ([string]$c.StoreRoot) -TaskId ([string]$c.TaskId) -WorkflowId ([string]$c.WorkflowId) -QaWorkflowId 'create-plan-views-v1' -BuildRequestId ([string]$c.Build)}

$c=New-RefreshStore
Check 'valid refresh' { $r=Refresh $c;$q=@($r.approvalRequests|Where-Object status -ceq 'pending');if($q.Count -ne 1){throw 'pending missing'} }
$t=Find-RepatoTask (Read-RepatoTaskStore $c.StoreRoot) $c.TaskId;$q=@($t.approvalRequests|Where-Object status -ceq 'pending')[0]
Check 'revision binding' {[long]$q.requestedRevision -eq [long]$t.revision}
Check 'old preserved' {@($t.approvalRequests|Where-Object requestId -ceq 'old').status -eq 'superseded'}
Check 'resolve refreshed request' {Resolve-RepatoTaskApproval ([string]$c.StoreRoot) $c.TaskId approve Maya refreshed|Out-Null}

$mutations=@(
 @{Name='wrong task';Mutate={param($x)$x.TaskId='bad'}},
 @{Name='wrong workflow';Mutate={param($x)$x.WorkflowId='bad'}},
 @{Name='wrong state';Mutate={param($x)$x.TaskStatus='passed'}},
 @{Name='no request';Mutate={param($x)$x.NoRequest=$true}},
 @{Name='current request';Mutate={param($x)$x.Current=$true}},
 @{Name='approved';Mutate={param($x)$x.Approved=$true}},
 @{Name='rejected';Mutate={param($x)$x.Rejected=$true}},
 @{Name='bad build';Mutate={param($x)$x.BadBuild=$true}},
 @{Name='bad candidate';Mutate={param($x)$x.BadCandidate=$true}},
 @{Name='missing staging';Mutate={param($x)$x.MissingStaging=$true}},
 @{Name='failed staging';Mutate={param($x)$x.FailedStaging=$true}},
 @{Name='bad isolation';Mutate={param($x)$x.BadIsolation=$true}},
 @{Name='missing deployment';Mutate={param($x)$x.MissingDeployment=$true}},
 @{Name='failed deployment';Mutate={param($x)$x.FailedDeployment=$true}},
 @{Name='tara';Mutate={param($x)$x.Tara=$true}},
 @{Name='native';Mutate={param($x)$x.Native=$true}},
 @{Name='completed';Mutate={param($x)$x.Completed=$true}},
 @{Name='terminal';Mutate={param($x)$x.Terminal=$true}},
 @{Name='missing build request';Mutate={param($x)$x.MissingBuildRequest=$true}},
 @{Name='source commit mismatch';Mutate={param($x)$x.SourceCommitMismatch=$true}},
 @{Name='runner hash mismatch';Mutate={param($x)$x.RunnerHashMismatch=$true}},
 @{Name='provenance missing';Mutate={param($x)$x.ProvenanceMissing=$true}},
 @{Name='candidate hash missing';Mutate={param($x)$x.CandidateHashMissing=$true}},
 @{Name='deployment identity missing';Mutate={param($x)$x.DeploymentIdentityMissing=$true}},
 @{Name='tara claim present';Mutate={param($x)$x.TaraClaim=$true}},
 @{Name='native completed';Mutate={param($x)$x.NativeCompleted=$true}}
)
foreach($m in $mutations){
    $x=New-RefreshStore
    if($m.Name -eq 'wrong task'){Check $m.Name {try{Request-MayaQaCanonicalApprovalRefresh -StoreRoot $x.StoreRoot -TaskId 'wrong-task' -WorkflowId $x.WorkflowId -QaWorkflowId 'create-plan-views-v1' -BuildRequestId $x.Build|Out-Null;throw 'unexpected acceptance'}catch{}};continue}
    Invoke-RepatoStoreMutation $x.StoreRoot {param($d,$p)$t=Find-RepatoTask $d $x.TaskId;$w=$t.deploymentWorkflows[0];switch($m.Name){'wrong workflow'{$w.qaWorkflowId='bad'}'wrong state'{$t.status='passed'}'no request'{$t.approvalRequests=@()}'current request'{$t.approvalRequests[0].requestedRevision=$t.revision;$t.approvalRequests[0].expiresUtc=(Get-Date).ToUniversalTime().AddMinutes(5).ToString('O')}'approved'{$t.approvalRequests[0].status='approved'}'rejected'{$t.approvalRequests[0].status='rejected'}'bad build'{$w.qaBuildStatus='failed'}'bad candidate'{$w.qaBuildEvidence.EvidenceSource='Build'}'missing staging'{$w.qaBuildEvidence.DeploymentValidation=$false}'failed staging'{$w.qaBuildEvidence.QaIsolation=$false}'bad isolation'{$w.qaBuildEvidence.ManifestIntegrityValidation=$false}'missing deployment'{$w.qaBuildEvidence.DeploymentValidation=$false}'failed deployment'{$w.qaBuildEvidence.DeploymentValidation=$false}'tara'{$t|Add-Member NoteProperty mayaTaraExecution ([pscustomobject]@{x=1}) -Force}'native'{$t|Add-Member NoteProperty taraRuns ([object[]]@([pscustomobject]@{status='running'})) -Force}'completed'{$t.status='completed'}'terminal'{$t.status='failed'}'missing build request'{$w.qaBuildRequest=$null}'source commit mismatch'{$w.qaBuildEvidence.SourceCommit='bad'}'runner hash mismatch'{$w.qaBuildEvidence.RunnerManifestSha256='bad'}'provenance missing'{$w.qaBuildEvidence.CandidateProvenancePath=$null}'candidate hash missing'{$w.qaBuildEvidence.ArtifactSha256=$null}'deployment identity missing'{$w.qaBuildEvidence.RunnerManifestPath=$null}'tara claim present'{$t|Add-Member NoteProperty mayaTaraAttempt ([pscustomobject]@{x=1}) -Force}'native completed'{$t|Add-Member NoteProperty taraRuns ([object[]]@([pscustomobject]@{status='completed'})) -Force}}}
    Check $m.Name {try{Refresh $x|Out-Null;throw 'unexpected acceptance'}catch{}}
}
Write-Output "Maya canonical approval refresh checks passed: $passed/$total"
