$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Repato.ProcessSupervisor.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.TaraAdapter.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -WarningAction SilentlyContinue
$root=Join-Path ([IO.Path]::GetTempPath()) ('Repato-Supervisor-'+[guid]::NewGuid().ToString('N'));$checks=0;$branch=(Get-Content 'C:\Repato-Autonomous\Source\.git\HEAD' -Raw).Trim().Replace('ref: refs/heads/','')
function Check($n,$c){if(!$c){throw "FAILED: $n"};$script:checks++;Write-Host "PASS $n"};function Reject($n,[scriptblock]$a){try{&$a;throw "FAILED: $n accepted"}catch{if($_.Exception.Message-like'FAILED:*'){throw};$script:checks++;Write-Host "PASS $n"}}
function NewReady($id){New-RepatoTask $root $id $id 'Tara build validation' $branch maya|Out-Null;Claim-RepatoTask $root $id Tara|Out-Null;Update-RepatoTask $root $id in-progress implementation Tara $null $null|Out-Null;Update-RepatoTask $root $id in-progress build-checks Tara $null $null|Out-Null;$tr=New-TaraPlan $root $id git.status;Test-TaraPlan $root $id $tr.runId|Out-Null;Request-TaraApproval $root $id $tr.runId|Out-Null;Resolve-RepatoTaskApproval $root $id approve Maya 'Tara adapter approved'|Out-Null;$tr}
Initialize-RepatoTaskStore $root|Out-Null
$valid=NewReady SUP-VALID;$sp=New-SupervisorPlan $root SUP-VALID tara.run;Check 'registered adapter plan' ($sp.adapterId-eq'tara.run'-and$sp.adapterRunId-eq$valid.runId)
Check 'bounded timeout' ($sp.timeoutSeconds-eq1800)
$null=Test-SupervisorPlan $root SUP-VALID $sp.runId; $null=Request-SupervisorApproval $root SUP-VALID $sp.runId;Resolve-RepatoTaskApproval $root SUP-VALID approve Maya 'Supervisor launch approved'|Out-Null
$preview=Get-SupervisorPreview $root SUP-VALID $sp.runId;Check 'preview has no side effects' (!$preview.SideEffectsPerformed-and$preview.WouldStart-match'tara.run')
$before=(Get-FileHash (Join-Path $root 'tasks.json') -Algorithm SHA256).Hash;$dry=Invoke-SupervisorStart $root SUP-VALID $sp.runId -DryRun;$after=(Get-FileHash (Join-Path $root 'tasks.json') -Algorithm SHA256).Hash;Check 'dry-run launch prevention' (!$dry.SideEffectsPerformed-and$before-eq$after)
$result=Invoke-SupervisorStart $root SUP-VALID $sp.runId;Check 'registered adapter launch and capture' ($result.status-eq'failed'-and$result.exitCode-ne0-and$result.processId-and(Test-Path $result.logPath)-and$result.startedUtc-and$result.finishedUtc-and$result.stderr-match'approval')
Reject 'duplicate launch prevention' {Invoke-SupervisorStart $root SUP-VALID $sp.runId|Out-Null}
Reject 'unknown adapter rejection' {New-SupervisorPlan $root SUP-VALID arbitrary.adapter|Out-Null}
$wrong=New-RepatoTask $root SUP-WRONG SUP-WRONG 'Neil implementation' $branch maya;Claim-RepatoTask $root SUP-WRONG Neil|Out-Null;Update-RepatoTask $root SUP-WRONG in-progress implementation Neil $null $null|Out-Null;Reject 'wrong agent rejection' {New-SupervisorPlan $root SUP-WRONG tara.run|Out-Null}
New-RepatoTask $root SUP-STAGE SUP-STAGE 'queued' $branch maya|Out-Null;Reject 'invalid stage rejection' {New-SupervisorPlan $root SUP-STAGE tara.run|Out-Null}
NewReady SUP-FAIL|Out-Null
$failPlan=New-SupervisorPlan $root SUP-FAIL tara.run;Test-SupervisorPlan $root SUP-FAIL $failPlan.runId|Out-Null;Reject 'missing supervisor approval rejection' {Invoke-SupervisorStart $root SUP-FAIL $failPlan.runId|Out-Null}
$bad=Join-Path $root malformed;Initialize-RepatoTaskStore $bad|Out-Null;[IO.File]::WriteAllText((Join-Path $bad 'tasks.json'),'{bad');Reject 'malformed task rejection' {New-SupervisorPlan $bad BAD-001 tara.run|Out-Null}
$lock=[IO.File]::Open((Join-Path $root 'store.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);try{Reject 'concurrent launch protection' {Invoke-SupervisorStart $root SUP-FAIL $failPlan.runId|Out-Null}}finally{$lock.Dispose()}
$stop=Stop-SupervisorMonitor $root SUP-VALID $sp.runId;Check 'stop monitor never kills process' (!$stop.Stopped-and$stop.Reason-match'termination')
$status=Get-SupervisorStatus $root SUP-VALID;Check 'status retains log and result' (@($status.Runs|Where-Object status -eq 'failed').Count-eq1-and$status.Logs.Count-ge1)
Write-Host "$checks supervisor checks passed; synthetic store: $root"
