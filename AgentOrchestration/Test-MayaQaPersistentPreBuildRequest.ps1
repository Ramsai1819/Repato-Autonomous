$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force
$store=Join-Path ([IO.Path]::GetTempPath()) ('maya-prebuild-'+[guid]::NewGuid().ToString('N'))
$worktree=Join-Path 'C:\Repato-Autonomous\Worktrees' ('test-'+[guid]::NewGuid().ToString('N'))
$passed=0
function Check([bool]$ok,[string]$name){if(!$ok){throw "FAILED: $name"};$script:passed++}
function Reject([scriptblock]$x,[string]$name){$ok=$false;try{&$x|Out-Null}catch{$ok=$true};Check $ok $name}
try {
    $commit=(& git -C $root rev-parse HEAD).Trim()
    $dryStore=Join-Path ([IO.Path]::GetTempPath()) ('maya-dryrun-'+[guid]::NewGuid().ToString('N'))
    $dry=Invoke-MayaQaRequest -StoreRoot $dryStore -UserRequest 'Create Plan Views' -DryRun
    Check ($dry.TaskId -match '^task-') 'DryRun TaskId'
    Check ($dry.WorkflowId -match '^workflow-') 'DryRun WorkflowId'
    Check ($dry.SideEffectsPerformed -eq $false) 'DryRun side effects'
    Check (!(Test-Path $dryStore)) 'DryRun persistent store untouched'
    & git -C $root worktree add --detach $worktree $commit|Out-Null
    $source=[pscustomobject]@{RepositoryRoot=$worktree;ExpectedSourceCommit=$commit;ProjectRelativePath='Forma.RevitConnector.csproj'}
    $result=New-MayaQaPersistentPreBuildRequest -StoreRoot $store -UserRequest 'Create Plan Views' -SourceBranch 'current' -ProjectPath 'Forma.RevitConnector.csproj' -AuthenticatedBuildSource $source
    $task=Find-RepatoTask (Read-RepatoTaskStore $store) $result.TaskId
    $workflow=@($task.deploymentWorkflows|Where-Object workflowId -ceq $result.WorkflowId)[0]
    Check ($result.TaskId -match '^task-') 'fresh TaskId'
    Check (![string]::IsNullOrWhiteSpace([string]$result.WorkflowId)) 'fresh WorkflowId'
    Check ($result.BuildRequest.BuildRequestId -match '^build-') 'single BuildRequestId'
    Check ($result.QaWorkflowId -eq 'create-plan-views-v1') 'QaWorkflowId'
    Check ($workflow.qaBuildRequest.AuthenticatedBuildSource.RepositoryRoot -eq $worktree) 'authenticated repository persisted'
    Check ($workflow.qaBuildRequest.AuthenticatedBuildSource.ExpectedSourceCommit -eq $commit) 'authenticated commit persisted'
    Check ($workflow.qaBuildRequest.AuthenticatedBuildSource.ProjectRelativePath -eq 'Forma.RevitConnector.csproj') 'project relative path persisted'
    Check ($workflow.qaBuildRequest.BuildStatus -eq 'requested') 'requested build status'
    Check ($workflow.PSObject.Properties.Name -notcontains 'qaBuildEvidence') 'no build evidence'
    Check ($result.QaApprovalStatus -eq 'pending') 'pending approval'
    Check (@($task.approvalRequests|Where-Object {$_.action -eq 'qa-run' -and $_.status -eq 'approved'}).Count -eq 0) 'not approved'
    Check ($task.PSObject.Properties.Name -notcontains 'mayaTaraAttempt') 'no Tara attempt'
    Check ($task.PSObject.Properties.Name -notcontains 'mayaTaraExecution') 'no Tara execution'
    Check ($workflow.PSObject.Properties.Name -notcontains 'qaStaging') 'no candidate staging'
    Check ($workflow.PSObject.Properties.Name -notcontains 'qaLaunchAgentRequest') 'no Launch Agent request'
    Check ($task.PSObject.Properties.Name -notcontains 'mayaTaraQaPacket') 'no Tara handoff packet'
    Check ($task.PSObject.Properties.Name -notcontains 'mayaTaraExecutionEvidence') 'no Tara execution evidence'
    Check (!(Test-Path (Join-Path $worktree 'bin\Release\net8.0-windows\Repato.Revit.dll'))) 'no build output'
    Check (@(Get-Process -Name Revit -ErrorAction SilentlyContinue).Count -eq 0) 'Revit not launched'
    Reject {New-MayaQaPersistentPreBuildRequest -StoreRoot (Join-Path $store 'bad-root') -UserRequest 'Create Plan Views' -AuthenticatedBuildSource ([pscustomobject]@{RepositoryRoot='C:\outside';ExpectedSourceCommit=$commit;ProjectRelativePath='Forma.RevitConnector.csproj'})} 'arbitrary source root rejected'
    Reject {New-MayaQaPersistentPreBuildRequest -StoreRoot (Join-Path $store 'bad-commit') -UserRequest 'Create Plan Views' -AuthenticatedBuildSource ([pscustomobject]@{RepositoryRoot=$worktree;ExpectedSourceCommit=('0'*40);ProjectRelativePath='Forma.RevitConnector.csproj'})} 'source commit mismatch rejected'
    Reject {New-MayaQaPersistentPreBuildRequest -StoreRoot (Join-Path $store 'bad-project') -UserRequest 'Create Plan Views' -AuthenticatedBuildSource ([pscustomobject]@{RepositoryRoot=$worktree;ExpectedSourceCommit=$commit;ProjectRelativePath='..\Forma.RevitConnector.csproj'})} 'project escape rejected'
    [pscustomobject]@{Status='PASS';AssertionsPassed=$passed;AssertionsFailed=0;BuildInvoked=$false;LaunchAgentInvoked=$false;RevitLaunched=$false}|ConvertTo-Json -Compress
} finally {
    if(Test-Path $worktree){& git -C $root worktree remove --force $worktree 2>$null|Out-Null}
    if($dryStore -and (Test-Path $dryStore)){Remove-Item $dryStore -Recurse -Force -ErrorAction SilentlyContinue}
    Remove-Item $store -Recurse -Force -ErrorAction SilentlyContinue
}
