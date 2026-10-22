$ErrorActionPreference='Stop'
$installModule=Join-Path $PSScriptRoot 'Repato.QaLaunchAgentInstall.ps1'
. $installModule
$common=@{ReleaseRoot='C:\release';ManifestSha256=('A'*64);RecoverySnapshotRoot='C:\snapshot';RecoveryManifestSha256=('B'*64)}
$stopped=New-RepatoQaLaunchAgentInstallArguments -Agents @() @common
if($stopped.ExpectedAgentPid -ne 0 -or $stopped.ContainsKey('ExpectedAgentStartTime') -or $stopped.ContainsKey('ExpectedAgentSessionId')){throw 'Stopped-agent arguments must bind PID 0 without empty process identity parameters.'}
$start=[datetime]::SpecifyKind([datetime]'2026-01-02T03:04:05.0000000',[DateTimeKind]::Local)
$runningAgent=[pscustomobject]@{ProcessName='Repato.QaLaunchAgent';Path='C:\Program Files\Repato\QaLaunchAgent\Repato.QaLaunchAgent.exe';Id=456;StartTime=$start;SessionId=7}
$running=New-RepatoQaLaunchAgentInstallArguments -Agents @($runningAgent) @common
if($running.ExpectedAgentPid -ne 456 -or $running.ExpectedAgentStartTime -cne $start.ToString('o') -or $running.ExpectedAgentSessionId -ne $runningAgent.SessionId){throw 'Running-agent arguments must preserve the exact PID, start-time, and session identity.'}
$cpvInstaller=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Install-CpvPreparationAgentCandidate.ps1') -Raw
if(!$cpvInstaller.Contains('-ExpectedSessionId $capabilities.sessionId')){throw 'CPV installer must bind the authenticated agent session to the stop helper.'}
[pscustomobject]@{StoppedAgentBinding='PASS';RunningAgentIdentityBinding='PASS';CpvAuthenticatedSessionBinding='PASS'}|ConvertTo-Json -Compress
