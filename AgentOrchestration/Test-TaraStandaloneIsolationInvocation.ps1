$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$modulePath=Join-Path $PSScriptRoot 'Repato.QaAddinDeployment.psm1'
$mayaPath=Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1'
$sourceCandidate='C:\Repato-Autonomous\Worktrees\create-plan-views-buildfix-4f2cbba22ba9\DeploymentCandidates\AgentBuilds\ReleaseCandidate-4f2cbba22ba9'
$expected='8C3F6EF16790247B9949EADED8FF098B4D95598791011C418D003DAAC0680AB5'
$commit='4f2cbba22ba9f4d6d3176e2d36daf2890bd1849c'
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('tara-isolation-api-'+[guid]::NewGuid().ToString('N'))
$revitBefore=@(Get-Process Revit -ErrorAction SilentlyContinue).Count
$passed=0
function Check([bool]$Condition,[string]$Name){if(!$Condition){throw "FAILED: $Name"};$script:passed++}
function Reject([scriptblock]$Action,[string]$Name){$rejected=$false;try{&$Action|Out-Null}catch{$rejected=$true};Check $rejected $Name}
function New-Layout([string]$Name){
    $root=Join-Path $scratch $Name;$candidate=Join-Path $root 'candidate';$qa=Join-Path $root 'QA';$user=Join-Path $root 'user';$target=Join-Path $user 'RepatoQA';$machine=Join-Path $root 'machine'
    New-Item $candidate,$qa,$target,$machine -ItemType Directory -Force|Out-Null
    Copy-Item (Join-Path $sourceCandidate 'Repato.Revit.dll') $candidate
    Copy-Item (Join-Path $sourceCandidate 'release-manifest.json') $candidate
    Copy-Item (Join-Path $PSScriptRoot '..\QA\Repato.CreatePlanViews.TestRunner.addin') $qa
    @{schemaVersion=1;machineWideRoot=$machine;approvedMachineWideManifests=@()}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $qa 'MachineWideAddins.allowlist.json') -Encoding UTF8
    [pscustomobject]@{Root=$root;Candidate=$candidate;Qa=$qa;User=$user;Target=$target;Machine=$machine}
}
function Stage($Layout){
    Install-TaraFrozenCandidateForQa -CandidateDirectory $Layout.Candidate -ExpectedArtifactSha256 $expected -ExpectedSourceCommit $commit -QaWorkflowId 'create-plan-views-v1' -TestId 'create-plan-views-v1' -TestTargetRoot $Layout.Target -TestManifestRoot $Layout.User -TestMachineRoot $Layout.Machine -QaSourceRoot $Layout.Qa
}
function Validate($Layout){
    Test-TaraFrozenCandidateQaIsolation -CandidateDirectory $Layout.Candidate -ExpectedArtifactSha256 $expected -ExpectedSourceCommit $commit -QaWorkflowId 'create-plan-views-v1' -TestId 'create-plan-views-v1' -TargetRoot $Layout.Target -ManifestRoot $Layout.User -MachineRoot $Layout.Machine -QaSourceRoot $Layout.Qa -TestLayout
}
try{
    Check ($null -eq (Get-Command Assert-ChildPath -ErrorAction SilentlyContinue)) 'AssertChildPathPreExisting = False'
    Import-Module $modulePath -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
    Check ($null -eq (Get-Command Assert-ChildPath -ErrorAction SilentlyContinue)) 'module import does not introduce global helper'

    $valid=New-Layout valid;$staged=Stage $valid;$result=Validate $valid
    Check ($staged.Success -and $result.Success) 'standalone isolation invocation passes after staging'
    Check ($result.Isolation.Allowed -and @($result.Isolation.Errors).Count -eq 0) 'isolation validation result passes'
    Check ($result.InstalledDllSha256 -ceq $expected) 'installed candidate binding retained'

    $escape=New-Layout escape;$null=Stage $escape;$outside=Join-Path $escape.Root 'outside.addin';Set-Content $outside '<x/>'
    @{schemaVersion=1;machineWideRoot=$escape.Machine;approvedMachineWideManifests=@(@{path=$outside;sha256=(Get-FileHash $outside).Hash;reviewReason='synthetic escape'})}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $escape.Qa 'MachineWideAddins.allowlist.json')
    Reject {Validate $escape} 'path escaping machine root rejected'

    $wrongHash=New-Layout wrongHash;$null=Stage $wrongHash;Set-Content (Join-Path $wrongHash.Target 'Repato.Revit.dll') 'wrong'
    Reject {Validate $wrongHash} 'wrong installed candidate hash rejected'

    $manifest=New-Layout manifest;$null=Stage $manifest;(Get-Content (Join-Path $manifest.User 'Repato.CreatePlanViews.TestRunner.addin') -Raw).Replace('CreatePlanViewsQaApplication','WrongApplication')|Set-Content (Join-Path $manifest.User 'Repato.CreatePlanViews.TestRunner.addin')
    Reject {Validate $manifest} 'incompatible manifest rejected'

    $rogueUser=New-Layout rogueUser;$null=Stage $rogueUser;Set-Content (Join-Path $rogueUser.User 'Unauthorized.addin') '<RevitAddIns/>'
    Reject {Validate $rogueUser} 'unauthorized user add-in rejected'

    $rogueMachine=New-Layout rogueMachine;$null=Stage $rogueMachine;Set-Content (Join-Path $rogueMachine.Machine 'Unauthorized.addin') '<RevitAddIns/>'
    Reject {Validate $rogueMachine} 'unapproved machine-wide add-in rejected'

    $orphan=Join-Path $scratch 'orphan\AgentOrchestration';New-Item $orphan -ItemType Directory -Force|Out-Null;Copy-Item $modulePath $orphan
    Reject {Import-Module (Join-Path $orphan 'Repato.QaAddinDeployment.psm1') -Force} 'missing isolation dependency fails closed'
    Check ($null -eq (Get-Command Assert-ChildPath -ErrorAction SilentlyContinue)) 'no reliance on caller or global scope'

    Import-Module $mayaPath -Force -WarningAction SilentlyContinue
    $store=Join-Path $scratch 'must-not-exist'
    Reject {Invoke-MayaQaRequest -StoreRoot $store -UserRequest 'create-plan-views-v1' -ArtifactMode FrozenCandidate -CandidateDirectory $sourceCandidate -ExpectedCandidateSha256 $expected -ExpectedCandidateSourceCommit $commit -StageFrozenCandidateForQa -QaStagingInvoker {param($c,$h,$s,$q,$t,$d)[pscustomobject]@{Success=$true;CandidateSha256=$h;BuildInvoked=$false;Isolation=[pscustomobject]@{Allowed=$false;Errors=@('blocked')}}}} 'controller rejects failed supported isolation result'
    $failedStore=if(Test-Path $store){Read-RepatoTaskStore $store}else{$null};$failedTasks=if($failedStore){@($failedStore.tasks)}else{@()}
    Check (@($failedTasks|Where-Object {($_.PSObject.Properties.Name -contains 'mayaTaraAttempt' -and $_.mayaTaraAttempt) -or ($_.PSObject.Properties.Name -contains 'mayaTaraExecution' -and $_.mayaTaraExecution) -or @($_.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -in @('pending','approved')}).Count}).Count -eq 0) 'no attempt, execution, or active QA approval created on isolation failure'
    Check (@(Get-Process Revit -ErrorAction SilentlyContinue).Count -eq $revitBefore) 'no Revit launched'

    [pscustomobject]@{Status='PASS';AssertChildPathPreExisting=$false;StandaloneIsolationInvocation='PASS';IsolationValidationResult='PASS';AssertionsPassed=$passed;AssertionsFailed=0;CanonicalAttemptCreated=$false;RevitLaunched=$false;LivePipeRequestSent=$false}|ConvertTo-Json -Compress
}finally{Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue}
