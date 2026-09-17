$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
$root=Join-Path ([IO.Path]::GetTempPath()) ('Repato-Executor-'+[guid]::NewGuid().ToString('N'));$checks=0
function Check([string]$name,[bool]$condition){if(!$condition){throw "FAILED: $name"};$script:checks++;Write-Host "PASS $name"}
function Reject([string]$name,[scriptblock]$action){try{&$action;throw "FAILED: $name accepted"}catch{if($_.Exception.Message-like'FAILED:*'){throw};$script:checks++;Write-Host "PASS $name"}}
function NewTask([string]$id,[string]$level='maya'){New-RepatoTask $root $id $id 'Executor test task' ("feat/"+$id.ToLowerInvariant()) $level}
Initialize-RepatoTaskStore $root|Out-Null

$null=NewTask EXEC-001
$run=New-RepatoExecutorPlan $root EXEC-001 Neil @('validate-branch','create-worktree','validate-worktree')
$run=Claim-RepatoExecutorRun $root EXEC-001 $run.executionId Neil
Check 'queued task claiming records executor start' ($run.status-eq'claimed'-and$run.startedUtc)
Reject 'duplicate execution claim' {Claim-RepatoExecutorRun $root EXEC-001 $run.executionId Neil|Out-Null}
$validation=Test-RepatoExecutorRun $root EXEC-001 $run.executionId
$before=(Get-FileHash (Join-Path $root 'tasks.json') -Algorithm SHA256).Hash
$preview=Get-RepatoExecutorPreview $root EXEC-001 $run.executionId
$after=(Get-FileHash (Join-Path $root 'tasks.json') -Algorithm SHA256).Hash
Check 'preview shows exact actions without side effects' ($preview.Mode-eq'DryRun'-and!$preview.SideEffectsPerformed-and$preview.WouldExecute.Count-eq3-and$before-eq$after)
$run=Complete-RepatoExecutorRun $root EXEC-001 $run.executionId @('executor.log') @('report.json') @('evidence.png')
Check 'executor completion timestamps and evidence' ($run.status-eq'completed'-and$run.finishedUtc-and$run.logs.Count-eq1-and$run.evidence.Count-eq1)
$task=(Get-RepatoTasks $root EXEC-001)[0]
Check 'task history and paths updated' ($task.workflowStage-eq'assigned'-and$task.history[-1].event-eq'executor-completed'-and$task.reportPaths.Count-eq2)

$null=NewTask EXEC-AGENT
Reject 'unknown agent rejection' {New-RepatoExecutorPlan $root EXEC-AGENT Intruder @('validate-branch')|Out-Null}
Reject 'unknown action rejection' {New-RepatoExecutorPlan $root EXEC-AGENT Neil @('shell-anything')|Out-Null}
Reject 'unsafe branch rejection' {New-RepatoTask $root EXEC-BRANCH bad bad 'feat/good;git commit' maya|Out-Null}
$null=Claim-RepatoTask $root EXEC-AGENT Neil
$null=Update-RepatoTask $root EXEC-AGENT in-progress implementation Neil $null $null
Reject 'invalid stage rejection' {New-RepatoExecutorPlan $root EXEC-AGENT Tara @('revit-launch')|Out-Null}

$null=NewTask EXEC-COMMIT user
$null=Claim-RepatoTask $root EXEC-COMMIT Neil
$null=Update-RepatoTask $root EXEC-COMMIT in-progress implementation Neil $null $null
$null=Update-RepatoTask $root EXEC-COMMIT in-progress build-checks Tara $null $null
$null=Update-RepatoTask $root EXEC-COMMIT passed qa Tara $null $null
$commit=New-RepatoExecutorPlan $root EXEC-COMMIT Neil @('production-commit')
$null=Claim-RepatoExecutorRun $root EXEC-COMMIT $commit.executionId Neil
$null=Test-RepatoExecutorRun $root EXEC-COMMIT $commit.executionId
Reject 'production commit missing approval' {Get-RepatoExecutorPreview $root EXEC-COMMIT $commit.executionId|Out-Null}
$null=Request-RepatoExecutorApproval $root EXEC-COMMIT $commit.executionId production-commit 30
Reject 'production commit requires user approver' {Resolve-RepatoTaskApproval $root EXEC-COMMIT approve Maya no|Out-Null}
$null=Resolve-RepatoTaskApproval $root EXEC-COMMIT approve user approved
$commitPreview=Get-RepatoExecutorPreview $root EXEC-COMMIT $commit.executionId
Check 'production commit approval gate' ($commitPreview.WouldExecute[0].name-eq'production-commit')
$null=Complete-RepatoExecutorRun $root EXEC-COMMIT $commit.executionId @() @() @()
$commitTask=(Get-RepatoTasks $root EXEC-COMMIT)[0]
Check 'approval consumed once' (@($commitTask.approvalRequests|Where-Object consumedUtc).Count-eq1)

$null=NewTask EXEC-REVIT user
$null=Claim-RepatoTask $root EXEC-REVIT Tara
$null=Update-RepatoTask $root EXEC-REVIT in-progress implementation Tara $null $null
$null=Update-RepatoTask $root EXEC-REVIT in-progress build-checks Tara $null $null
$revit=New-RepatoExecutorPlan $root EXEC-REVIT Tara @('revit-launch')
$null=Claim-RepatoExecutorRun $root EXEC-REVIT $revit.executionId Tara
$null=Test-RepatoExecutorRun $root EXEC-REVIT $revit.executionId
Reject 'Revit launch missing approval' {Get-RepatoExecutorPreview $root EXEC-REVIT $revit.executionId|Out-Null}

$null=NewTask EXEC-CHANGED user
$null=Claim-RepatoTask $root EXEC-CHANGED Neil
$changed=New-RepatoExecutorPlan $root EXEC-CHANGED Neil @('file-delete')
$null=Claim-RepatoExecutorRun $root EXEC-CHANGED $changed.executionId Neil
$null=Test-RepatoExecutorRun $root EXEC-CHANGED $changed.executionId
$null=Request-RepatoExecutorApproval $root EXEC-CHANGED $changed.executionId file-delete 30
$null=Resolve-RepatoTaskApproval $root EXEC-CHANGED approve user approved
$null=Update-RepatoTask $root EXEC-CHANGED in-progress assigned Neil 'changed-after-approval.log' $null
Reject 'approval invalid after task change' {Get-RepatoExecutorPreview $root EXEC-CHANGED $changed.executionId|Out-Null}

$null=NewTask EXEC-MISMATCH user
$null=Claim-RepatoTask $root EXEC-MISMATCH Neil
$mismatch=New-RepatoExecutorPlan $root EXEC-MISMATCH Neil @('file-delete')
$null=Claim-RepatoExecutorRun $root EXEC-MISMATCH $mismatch.executionId Neil
$null=Test-RepatoExecutorRun $root EXEC-MISMATCH $mismatch.executionId
$null=Request-RepatoExecutorApproval $root EXEC-MISMATCH $mismatch.executionId file-delete 30
$null=Resolve-RepatoTaskApproval $root EXEC-MISMATCH approve user approved
$queue=Get-Content (Join-Path $root 'tasks.json') -Raw|ConvertFrom-Json
($queue.tasks|Where-Object taskId -eq 'EXEC-MISMATCH').approvalRequests[0].bindingHash='0'*64
$queue|ConvertTo-Json -Depth 20|Set-Content (Join-Path $root 'tasks.json') -Encoding UTF8
Reject 'mismatched plan approval rejected' {Get-RepatoExecutorPreview $root EXEC-MISMATCH $mismatch.executionId|Out-Null}

$null=NewTask EXEC-EXPIRED user
$null=Claim-RepatoTask $root EXEC-EXPIRED Neil
$expired=New-RepatoExecutorPlan $root EXEC-EXPIRED Neil @('file-delete')
$null=Claim-RepatoExecutorRun $root EXEC-EXPIRED $expired.executionId Neil
$null=Test-RepatoExecutorRun $root EXEC-EXPIRED $expired.executionId
$null=Request-RepatoExecutorApproval $root EXEC-EXPIRED $expired.executionId file-delete -1
Reject 'expired approval rejected' {Resolve-RepatoTaskApproval $root EXEC-EXPIRED approve user late|Out-Null}

$null=NewTask EXEC-DRY
$hashBefore=(Get-FileHash (Join-Path $root 'tasks.json') -Algorithm SHA256).Hash
$dry=New-RepatoExecutorPlan $root EXEC-DRY Neil @('validate-branch') -DryRun
$hashAfter=(Get-FileHash (Join-Path $root 'tasks.json') -Algorithm SHA256).Hash
Check 'dry-run plan has no state side effects' ($dry.mode-eq'DryRun'-and$hashBefore-eq$hashAfter)

$null=NewTask EXEC-FAIL
$failure=New-RepatoExecutorPlan $root EXEC-FAIL Neil @('validate-branch')
$null=Claim-RepatoExecutorRun $root EXEC-FAIL $failure.executionId Neil
$failure=Fail-RepatoExecutorRun $root EXEC-FAIL $failure.executionId 'validation failed' @('failed.log') @('failed.json')
$failedTask=(Get-RepatoTasks $root EXEC-FAIL)[0]
Check 'failed task and evidence preserved' ($failure.status-eq'failed'-and$failedTask.status-eq'failed'-and$failedTask.errorDetails-eq'validation failed'-and$failedTask.reportPaths[0]-eq'failed.json')

$null=NewTask EXEC-CONCURRENT
$concurrent=New-RepatoExecutorPlan $root EXEC-CONCURRENT Neil @('validate-branch')
$module=Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1';$jobs=@()
1..2|ForEach-Object{$jobs+=Start-Job -ScriptBlock {param($m,$s,$t,$e)Import-Module $m -Force -WarningAction SilentlyContinue;Claim-RepatoExecutorRun $s $t $e Neil|Out-Null} -ArgumentList $module,$root,'EXEC-CONCURRENT',$concurrent.executionId}
$jobs|Wait-Job|Out-Null;$states=@($jobs.State);$jobs|Receive-Job -ErrorAction SilentlyContinue|Out-Null;$jobs|Remove-Job -Force
Check 'concurrent claim protection' (@($states|Where-Object{$_-eq'Completed'}).Count-eq1-and@($states|Where-Object{$_-eq'Failed'}).Count-eq1)

$malformed=Join-Path $root 'malformed';Initialize-RepatoTaskStore $malformed|Out-Null;[IO.File]::WriteAllText((Join-Path $malformed 'tasks.json'),'{bad')
Reject 'malformed task data' {Read-RepatoTaskStore $malformed|Out-Null}
$legacy=Join-Path $root 'legacy';Initialize-RepatoTaskStore $legacy|Out-Null
$legacyTask=(Get-RepatoTasks $root EXEC-DRY)[0];$legacyTask.PSObject.Properties.Remove('executorRuns');$legacyTask.PSObject.Properties.Remove('revision')
@{schemaVersion=1;tasks=@($legacyTask)}|ConvertTo-Json -Depth 20|Set-Content (Join-Path $legacy 'tasks.json') -Encoding UTF8
$upgraded=(Read-RepatoTaskStore $legacy).tasks[0]
Check 'orchestration v1 store compatibility' ($upgraded.executorRuns -is [Array]-and$upgraded.revision-ge1)
Write-Host "$checks executor foundation checks passed; synthetic store: $root"
