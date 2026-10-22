$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '../QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1') -Force -WarningAction SilentlyContinue
. (Join-Path $PSScriptRoot 'Repato.QaLaunchAgentInstall.ps1')
$starts=0;$stops=0
$process=[pscustomobject]@{ProcessId=42;ProcessName='Repato.QaLaunchAgent';Path='C:\Program Files\Repato\QaLaunchAgent\Repato.QaLaunchAgent.exe';StartTime='2026-10-12T09:12:55.3364712+05:30';SessionId=4;OwnerSid='S-1-5-21-1031246752-3872016183-2454652381-1015'}
$task=[pscustomobject]@{Valid=$true;TaskPath='\Repato\';TaskName='Repato QA Launch Agent';PrincipalSid='S-1-5-21-1031246752-3872016183-2454652381-1015';TriggerSid='S-1-5-21-1031246752-3872016183-2454652381-1015';State='Running';XmlSha256=('A'*64)}
$getProcess={param($id)$process}
$getTask={$task}
$stopTask={param($path,$name)$script:stops++;$task.State='Ready'}
$startTask={param($path,$name)$script:starts++;$task.State='Running'}
$stopProcess={param($p)throw [NullReferenceException]::new('synthetic Stop-Process race')}
$failed=$false;$failureMessage=$null
try {
    Stop-RepatoQaLaunchAgentForUpdate -ExpectedAgentPid 42 -ExpectedAgentStartTime $process.StartTime -ExpectedSessionId 4 -AgentExe $process.Path -TaskPath '\Repato\' -TaskName 'Repato QA Launch Agent' -GetProcessIdentity $getProcess -GetTaskEvidence $getTask -StopTask $stopTask -StopProcess $stopProcess -StartTask $startTask -Wait {}
} catch {$failureMessage=$_.Exception.Message;$failed=$failureMessage -like '*remains active after failed stop*'}
if(!$failed -or $stops -ne 1 -or $starts -ne 0){throw "Stop-Process failure did not fail closed with the ambiguous still-running task left stopped. failure=$failureMessage taskStops=$stops taskStarts=$starts"}
'Launch Agent stop failure recovery test passed.'
