$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Repato.TaraAdapter.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -WarningAction SilentlyContinue

$root = Join-Path ([IO.Path]::GetTempPath()) ('Repato-Tara-' + [guid]::NewGuid().ToString('N'))
$checks = 0
function Check([string]$Name,[bool]$Condition) { if (!$Condition) { throw "FAILED: $Name" }; $script:checks++; Write-Host "PASS $Name" }
function Reject([string]$Name,[scriptblock]$Action) { try { & $Action; throw "FAILED: $Name accepted" } catch { if ($_.Exception.Message -like 'FAILED:*') { throw }; $script:checks++; Write-Host "PASS $Name" } }
function New-TestTask([string]$Id,[string]$Agent='Tara',[string]$Stage='build-checks') {
    $null=New-RepatoTask $root $Id $Id 'Tara adapter regression task' ('feat/'+$Id.ToLowerInvariant()) maya
    $null=Claim-RepatoTask $root $Id $Agent
    if ($Stage -in @('implementation','build-checks','qa')) { $null=Update-RepatoTask $root $Id in-progress implementation $Agent $null $null }
    if ($Stage -in @('build-checks','qa')) { $null=Update-RepatoTask $root $Id in-progress build-checks $Agent $null $null }
    if ($Stage -eq 'qa') { $null=Update-RepatoTask $root $Id in-progress qa $Agent $null $null }
}
function New-ValidatedRun([string]$Id,[string]$CommandId,[string]$Stage='build-checks') {
    New-TestTask $Id Tara $Stage
    $run=New-TaraPlan $root $Id $CommandId
    $null=Test-TaraPlan $root $Id $run.runId
    $run
}
function Approve-Run([string]$Id,[string]$RunId,[int]$ExpiryMinutes=30) {
    $null=Request-TaraApproval $root $Id $RunId $ExpiryMinutes
    $null=Resolve-RepatoTaskApproval $root $Id approve Maya approved
}

Initialize-RepatoTaskStore $root | Out-Null
$catalog=Get-TaraCommandCatalog
Check 'approved release build is exact' ($catalog['build.release'].Arguments -join ' ' -eq 'build .\Forma.RevitConnector.csproj -c Release -p:RevitInstallDir=E:\revit\Revit 2025')
Check 'approved repository validation script is registered' $catalog.Contains('script.QA.Test-QaRunnerFoundation')
$missingGit=@('git.diff-check','git.status','git.log','git.diff')|Where-Object{-not $catalog.Contains($_)}
Check 'read-only Git commands only' (@($missingGit).Count -eq 0)

New-TestTask TARA-UNKNOWN
Reject 'unknown command rejection' { New-TaraPlan $root TARA-UNKNOWN 'shell.arbitrary' | Out-Null }
$cli=Join-Path $PSScriptRoot 'Invoke-RepatoTaraAdapter.ps1'
$oldPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli tara-plan -TaskId TARA-UNKNOWN -CommandId git.status -Arguments commit -StoreRoot $root 2>$null | Out-Null
$unsafeExit=$LASTEXITCODE;$ErrorActionPreference=$oldPreference
Check 'unsafe argument injection rejection' ($unsafeExit -ne 0)
Reject 'path traversal rejection' { New-TaraPlan $root TARA-UNKNOWN 'script.QA...\outside' | Out-Null }
foreach($blocked in @('revit-launch','production-commit','file-delete','addin-change')) { Reject "$blocked action rejection" { New-TaraPlan $root TARA-UNKNOWN $blocked | Out-Null } }

New-TestTask TARA-AGENT Neil
Reject 'wrong agent rejection' { New-TaraPlan $root TARA-AGENT git.status | Out-Null }
New-TestTask TARA-STAGE Tara implementation
Reject 'wrong stage rejection' { New-TaraPlan $root TARA-STAGE build.release | Out-Null }

$scriptRun=New-ValidatedRun TARA-SCRIPT script.QA.Test-QaRunnerFoundation qa
Check 'approved validation script plan' ($scriptRun.commandId-eq'script.QA.Test-QaRunnerFoundation')

New-TestTask TARA-PLAN-CHANGED
$changedPlan=New-TaraPlan $root TARA-PLAN-CHANGED git.status
$queuePath=Join-Path $root 'tasks.json';$queue=Get-Content $queuePath -Raw|ConvertFrom-Json
(($queue.tasks|Where-Object taskId -ceq 'TARA-PLAN-CHANGED').taraRuns|Where-Object runId -ceq $changedPlan.runId).commandSha256='0'*64
$queue|ConvertTo-Json -Depth 30|Set-Content $queuePath -Encoding UTF8
Reject 'changed plan rejection' { Test-TaraPlan $root TARA-PLAN-CHANGED $changedPlan.runId | Out-Null }

$missing=New-ValidatedRun TARA-MISSING git.status
Reject 'missing approval rejection' { Invoke-TaraRun $root TARA-MISSING $missing.runId | Out-Null }
$expired=New-ValidatedRun TARA-EXPIRED git.status
$null=Request-TaraApproval $root TARA-EXPIRED $expired.runId -1
Reject 'expired approval rejection' { Resolve-RepatoTaskApproval $root TARA-EXPIRED approve Maya late | Out-Null }

$changed=New-ValidatedRun TARA-CHANGED git.status
Approve-Run TARA-CHANGED $changed.runId
$null=Update-RepatoTask $root TARA-CHANGED in-progress build-checks Tara 'changed-after-approval.log' $null
Reject 'changed task revision rejection' { Invoke-TaraRun $root TARA-CHANGED $changed.runId | Out-Null }

$mismatch=New-ValidatedRun TARA-MISMATCH git.status
Approve-Run TARA-MISMATCH $mismatch.runId
$queuePath=Join-Path $root 'tasks.json';$queue=Get-Content $queuePath -Raw|ConvertFrom-Json
(($queue.tasks|Where-Object taskId -ceq 'TARA-MISMATCH').approvalRequests|Where-Object status -ceq 'approved').bindingHash='0'*64
$queue|ConvertTo-Json -Depth 30|Set-Content $queuePath -Encoding UTF8
Reject 'mismatched approval rejection' { Invoke-TaraRun $root TARA-MISMATCH $mismatch.runId | Out-Null }

$dry=New-ValidatedRun TARA-DRY git.status
Approve-Run TARA-DRY $dry.runId
$before=(Get-FileHash $queuePath -Algorithm SHA256).Hash;$logCount=@(Get-ChildItem (Join-Path $PSScriptRoot 'Logs') -File -ErrorAction SilentlyContinue).Count
$preview=Invoke-TaraRun $root TARA-DRY $dry.runId -DryRun
$after=(Get-FileHash $queuePath -Algorithm SHA256).Hash;$afterLogCount=@(Get-ChildItem (Join-Path $PSScriptRoot 'Logs') -File -ErrorAction SilentlyContinue).Count
Check 'dry-run side-effect prevention' ($preview.SideEffectsPerformed-eq$false-and$before-eq$after-and$logCount-eq$afterLogCount)

$success=New-ValidatedRun TARA-SUCCESS git.status
Approve-Run TARA-SUCCESS $success.runId
$successResult=Invoke-TaraRun $root TARA-SUCCESS $success.runId
Check 'approved read-only Git execution' ($successResult.status-eq'passed'-and$successResult.exitCode-eq0-and(Test-Path $successResult.logPath))
Reject 'duplicate execution rejection' { Invoke-TaraRun $root TARA-SUCCESS $success.runId | Out-Null }

$failure=New-ValidatedRun TARA-FAIL script.AgentOrchestration.Fixtures.Validate-TaraFailureFixture
Approve-Run TARA-FAIL $failure.runId
$failureResult=Invoke-TaraRun $root TARA-FAIL $failure.runId
$failureTask=(Get-RepatoTasks $root TARA-FAIL)[0]
Check 'failed command log preservation' ($failureResult.status-eq'failed'-and$failureResult.exitCode-eq7-and(Test-Path $failureResult.logPath)-and$failureTask.status-eq'failed'-and$failureTask.logs.Count-eq1)

$concurrent=New-ValidatedRun TARA-CONCURRENT git.status
Approve-Run TARA-CONCURRENT $concurrent.runId
$lockPath=Join-Path $root 'store.lock';$heldLock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try { Reject 'concurrent execution protection' { Invoke-TaraRun $root TARA-CONCURRENT $concurrent.runId | Out-Null } }
finally { $heldLock.Dispose() }

$malformed=Join-Path $root 'malformed';Initialize-RepatoTaskStore $malformed|Out-Null;[IO.File]::WriteAllText((Join-Path $malformed 'tasks.json'),'{bad')
Reject 'malformed task data rejection' { New-TaraPlan $malformed BAD-001 git.status | Out-Null }

Write-Host "$checks Tara adapter checks passed; synthetic store: $root"
