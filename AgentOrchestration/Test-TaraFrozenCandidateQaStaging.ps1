$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.QaAddinDeployment.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue

$candidate='C:\Repato-Autonomous\Source\DeploymentCandidates\AgentBuilds\ReleaseCandidate-1c2da6abf08c'
$expected='717908D7470FA8FC74292E8B7C4689B3F95B6D69C4AB88576F08AFC48A625754'
$commit='1c2da6abf08c281679fbd8ae88c7dc8d0b88f726'
$realStore='C:\Repato-Autonomous\AgentWork\AgentOrchestration\Store'
$realTasks=(Get-FileHash (Join-Path $realStore 'tasks.json')).Hash;$realStatus=(Get-FileHash (Join-Path $realStore 'status.json')).Hash
$realQaDll='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA\Repato.Revit.dll'
$realQaBefore=if(Test-Path $realQaDll){(Get-FileHash $realQaDll).Hash}else{$null};$revitBefore=@(Get-Process Revit -ErrorAction SilentlyContinue).Count
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('tara-stage-'+[guid]::NewGuid().ToString('N'));$user=Join-Path $scratch 'user';$target=Join-Path $user 'RepatoQA';$machine=Join-Path $scratch 'machine';$qa=Join-Path $scratch 'QA'
$passed=0
function Check([bool]$ok,[string]$name){if(!$ok){throw "FAILED: $name"};$script:passed++}
function Reject([scriptblock]$action,[string]$name){$rejected=$false;try{&$action|Out-Null}catch{$rejected=$true};Check $rejected $name}
function Stage([string]$failure='None'){Install-TaraFrozenCandidateForQa -CandidateDirectory $candidate -ExpectedArtifactSha256 $expected -ExpectedSourceCommit $commit -QaWorkflowId 'create-plan-views-v1' -TestId 'create-plan-views-v1' -TestTargetRoot $target -TestManifestRoot $user -TestMachineRoot $machine -QaSourceRoot $qa -FailureMode $failure}
try{
 New-Item $target,$machine,$qa -ItemType Directory -Force|Out-Null
 Copy-Item (Join-Path $PSScriptRoot '..\QA\Repato.CreatePlanViews.TestRunner.addin') (Join-Path $qa 'Repato.CreatePlanViews.TestRunner.addin')
 @{schemaVersion=1;machineWideRoot=$machine;approvedMachineWideManifests=@()}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $qa 'MachineWideAddins.allowlist.json') -Encoding UTF8
 [IO.File]::WriteAllBytes((Join-Path $target 'Repato.Revit.dll'),[Text.Encoding]::UTF8.GetBytes('stale QA DLL'))
 [IO.File]::WriteAllText((Join-Path $user 'Repato.CreatePlanViews.TestRunner.addin'),'<stale/>')
 $staleHash=(Get-FileHash (Join-Path $target 'Repato.Revit.dll')).Hash
 $r=Stage
 Check $r.Success 'valid candidate staging succeeds'
 Check ($r.InstalledDllSha256 -ceq $expected) 'installed hash equals candidate hash'
 Check ($staleHash -cne $r.InstalledDllSha256) 'stale QA DLL safely replaced'
 Check ($r.CandidateSourceCommit -ceq $commit) 'candidate provenance retained'
 Check ((Test-Path $r.StagingEvidencePath) -and (Get-FileHash $r.StagingEvidencePath).Hash -ceq $r.StagingEvidenceSha256) 'staging evidence persisted and hashed'
 Check ($r.Isolation.Allowed -and @($r.Isolation.Errors).Count -eq 0) 'isolation validates staged candidate'
 Check (!$r.BuildInvoked) 'Release build not invoked'
 Reject {Install-TaraFrozenCandidateForQa $candidate ('0'*64) $commit 'create-plan-views-v1' 'create-plan-views-v1' -TestTargetRoot $target -TestManifestRoot $user -TestMachineRoot $machine -QaSourceRoot $qa} 'candidate hash mismatch rejected'
 Reject {Install-TaraFrozenCandidateForQa $candidate $expected ('f'*40) 'create-plan-views-v1' 'create-plan-views-v1' -TestTargetRoot $target -TestManifestRoot $user -TestMachineRoot $machine -QaSourceRoot $qa} 'candidate provenance mismatch rejected'
 Reject {Install-TaraFrozenCandidateForQa $candidate $expected $commit 'unsupported-workflow' 'unsupported-workflow' -TestTargetRoot $target -TestManifestRoot $user -TestMachineRoot $machine -QaSourceRoot $qa} 'incompatible workflow rejected'
 $missingQa=Join-Path $scratch 'missing-contract';New-Item $missingQa -ItemType Directory|Out-Null
 Reject {Install-TaraFrozenCandidateForQa $candidate $expected $commit 'create-plan-views-v1' 'create-plan-views-v1' -TestTargetRoot $target -TestManifestRoot $user -TestMachineRoot $machine -QaSourceRoot $missingQa} 'missing manifest contract rejected'
 Reject {Install-TaraFrozenCandidateForQa $candidate $expected $commit 'create-plan-views-v1' 'create-plan-views-v1' -TargetRoot 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato' -ManifestRoot 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025'} 'normal user target rejected'
 Reject {Install-TaraFrozenCandidateForQa $candidate $expected $commit 'create-plan-views-v1' 'create-plan-views-v1' -TargetRoot 'C:\ProgramData\Autodesk\Revit\Addins\2025' -ManifestRoot 'C:\ProgramData\Autodesk\Revit\Addins\2025'} 'machine-wide target rejected'
 [IO.File]::WriteAllBytes((Join-Path $target 'Repato.Revit.dll'),[Text.Encoding]::UTF8.GetBytes('rollback-old-dll'));[IO.File]::WriteAllText((Join-Path $user 'Repato.CreatePlanViews.TestRunner.addin'),'<rollback-old-manifest/>')
 $oldDll=(Get-FileHash (Join-Path $target 'Repato.Revit.dll')).Hash;$oldManifest=(Get-FileHash (Join-Path $user 'Repato.CreatePlanViews.TestRunner.addin')).Hash
 Reject {Stage 'AfterDllCommit'} 'partial staging failure rejected'
 Check ((Get-FileHash (Join-Path $target 'Repato.Revit.dll')).Hash -ceq $oldDll -and (Get-FileHash (Join-Path $user 'Repato.CreatePlanViews.TestRunner.addin')).Hash -ceq $oldManifest) 'partial failure restored prior installation'
 $store=Join-Path $scratch 'must-not-exist';Reject {Invoke-MayaQaRequest -StoreRoot $store -UserRequest 'create-plan-views-v1' -ArtifactMode FrozenCandidate -CandidateDirectory $candidate -ExpectedCandidateSha256 $expected -ExpectedCandidateSourceCommit $commit -StageFrozenCandidateForQa -QaStagingInvoker {throw 'synthetic staging failure'}} 'controller stops on staging failure'
 Check (!(Test-Path $store)) 'staging occurs before canonical task creation'
 Check ((Get-FileHash (Join-Path $realStore 'tasks.json')).Hash -ceq $realTasks -and (Get-FileHash (Join-Path $realStore 'status.json')).Hash -ceq $realStatus) 'real canonical store untouched'
 $realQaUnchanged=$(if($realQaBefore){(Get-FileHash $realQaDll).Hash -ceq $realQaBefore}else{!(Test-Path $realQaDll)})
 Check $realQaUnchanged 'real QA installation untouched'
 Check (@(Get-Process Revit -ErrorAction SilentlyContinue).Count -eq $revitBefore) 'Revit not launched'
 [pscustomobject]@{Status='PASS';AssertionsPassed=$passed;AssertionsFailed=0;ObservedBlockedInstalledSha256=$realQaBefore;CandidateSha256=$expected;GenericPrimitive='Install-TaraFrozenCandidateForQa';RealStoreTouched=$false;RealQaInstallationTouched=$false;RevitLaunched=$false;LivePipeRequestSent=$false}|ConvertTo-Json -Compress
}finally{Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue}
