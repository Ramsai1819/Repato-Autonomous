$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
$module=Get-Module Repato.MayaQaWorkflow
$checks=0
function Check([string]$name,[bool]$condition){if(!$condition){throw "FAILED: $name"};$script:checks++}
function Reject([string]$name,[scriptblock]$body){$failed=$false;try{&$body|Out-Null}catch{$failed=$true};Check $name $failed}
function Copy-Object($value){$value|ConvertTo-Json -Depth 25|ConvertFrom-Json}
function Get-Hash($value){$json=ConvertTo-Json -InputObject $value -Depth 25 -Compress;$sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}finally{$sha.Dispose()}}
$workflow=[pscustomobject]@{taskId='task';workflowId='workflow';qaWorkflowId='create-plan-views-v1';qaRunId='run';qaBuildEvidence=[pscustomobject]@{BuildRequestId='build';CandidateSourceCommit=('a'*40);ArtifactSha256=('b'*64);RunnerManifestPath='C:\Source\QA\runner.addin';RunnerManifestSha256=('c'*64)};qaModelPath='C:\Source\QA\TestRuns\run\model.rvt';qaDisposableModelSha256=('d'*64);qaSidecarPath='C:\Source\QA\TestRuns\run\model.rvt.fixture.json'}
$binding=[ordered]@{TaskId='task';WorkflowId='workflow';QaWorkflowId='create-plan-views-v1';BuildRequestId='build';CandidateSourceCommit=('a'*40);CandidateSha256=('b'*64);RunId='run';ModelPath=$workflow.qaModelPath;ModelSha256=('d'*64);SidecarPath=$workflow.qaSidecarPath;RunnerManifestPath='C:\Source\QA\runner.addin';RunnerManifestSha256=('c'*64)}
$request=[pscustomobject]@{requestId='old';action='qa-run';status='approved';requiredLevel='user';decidedBy='user';consumedUtc=$null;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(-5).ToString('O');requestedRevision=[long]177;approvedRevision=[long]178;bindingHash=(Get-Hash $binding);executionBinding=[pscustomobject]$binding}
$task=[pscustomobject]@{taskId='task';revision=[long]178;status='in-progress';workflowStage='approval';approvalRequests=@($request)}
$found=&$module {param($t,$w) Get-MayaQaExpiredApprovedCanonicalRequestForRefresh -Task $t -Workflow $w} $task $workflow
Check 'valid expired approval selected' ($found.requestId -ceq 'old')
$legacy=Copy-Object $task;$legacy.approvalRequests=@([pscustomobject]@{requestId='legacy';action='qa-run';status='approved'})+$legacy.approvalRequests
$found=&$module {param($t,$w) Get-MayaQaExpiredApprovedCanonicalRequestForRefresh -Task $t -Workflow $w} $legacy $workflow
Check 'legacy approval without binding safely ignored' ($found.requestId -ceq 'old')
$bad=Copy-Object $task;$bad.approvalRequests[0].expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(5).ToString('O')
Reject 'unexpired approval rejected' {&$module {param($t,$w) Get-MayaQaExpiredApprovedCanonicalRequestForRefresh -Task $t -Workflow $w} $bad $workflow}
$bad=Copy-Object $task;$bad.approvalRequests[0].consumedUtc=[DateTimeOffset]::UtcNow.ToString('O')
Reject 'consumed approval rejected' {&$module {param($t,$w) Get-MayaQaExpiredApprovedCanonicalRequestForRefresh -Task $t -Workflow $w} $bad $workflow}
$bad=Copy-Object $task;$bad.approvalRequests[0].decidedBy='Maya'
Reject 'non-user decision rejected' {&$module {param($t,$w) Get-MayaQaExpiredApprovedCanonicalRequestForRefresh -Task $t -Workflow $w} $bad $workflow}
$bad=Copy-Object $task;$bad.revision=[long]179
Reject 'stale task revision rejected' {&$module {param($t,$w) Get-MayaQaExpiredApprovedCanonicalRequestForRefresh -Task $t -Workflow $w} $bad $workflow}
$bad=Copy-Object $task;$bad.approvalRequests[0].executionBinding.CandidateSha256='e'*64
Reject 'candidate mismatch rejected' {&$module {param($t,$w) Get-MayaQaExpiredApprovedCanonicalRequestForRefresh -Task $t -Workflow $w} $bad $workflow}
$bad=Copy-Object $task;$bad.approvalRequests+=Copy-Object $bad.approvalRequests[0]
Reject 'duplicate expired approvals rejected' {&$module {param($t,$w) Get-MayaQaExpiredApprovedCanonicalRequestForRefresh -Task $t -Workflow $w} $bad $workflow}
$bad=Copy-Object $task;$bad.status='awaiting-approval'
$none=&$module {param($t,$w) Get-MayaQaExpiredApprovedCanonicalRequestForRefresh -Task $t -Workflow $w} $bad $workflow
Check 'unexpected task state has no refresh' ($null -eq $none)
[pscustomobject]@{Status='PASS';Assertions=$checks;ExpiredApprovalAccepted=$true;UnexpiredConsumedStaleMismatchedAndDuplicateRejected=$true}|ConvertTo-Json -Compress
