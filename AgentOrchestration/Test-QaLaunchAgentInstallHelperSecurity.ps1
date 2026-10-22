$ErrorActionPreference='Stop'
$helperPath=Join-Path $PSScriptRoot 'Repato.QaLaunchAgentInstall.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($helperPath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw "Helper parse failed: $($errors[0].Message)"}
Import-Module (Join-Path $PSScriptRoot '../QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1') -Force -WarningAction SilentlyContinue
$script:assertions=0
function Assert([bool]$Value,[string]$Message){$script:assertions++;if(!$Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$script:assertions++;$rejected=$false;try{& $Action|Out-Null}catch{$rejected=$true};if(!$rejected){throw $Message}}
. $helperPath

$expectedStart='2026-10-12T09:12:55.3364712+05:30'
$sid='S-1-5-21-1031246752-3872016183-2454652381-1015'
$exe='C:\Program Files\Repato\QaLaunchAgent\Repato.QaLaunchAgent.exe'
function New-Harness([string]$Mode='valid'){
    $state=@{TaskStops=0;TaskStarts=0;ProcessStops=0;Process=$null;Task=$null;AfterStop=$null;FailTermination=$false}
    $state.Process=[pscustomobject]@{ProcessId=42;ProcessName='Repato.QaLaunchAgent';Path=$exe;StartTime=$expectedStart;SessionId=4;OwnerSid=$sid}
    $state.Task=[pscustomobject]@{Valid=$true;TaskPath='\Repato\';TaskName='Repato QA Launch Agent';PrincipalSid=$sid;TriggerSid=$sid;State='Running';XmlSha256=('A'*64)}
    $getProcess={param($id)if($state.AfterStop){$state.Process=$state.AfterStop;$state.AfterStop=$null};$state.Process}.GetNewClosure()
    $getTask={if($Mode -eq 'duplicate-task'){@($state.Task,$state.Task)}else{$state.Task}}.GetNewClosure()
    $stopTask={param($path,$name)$state.TaskStops++;if($Mode -ne 'task-still-running'){$state.Task.State='Ready'};if($Mode -eq 'pid-reuse'){$state.AfterStop=$state.Process.PSObject.Copy();$state.AfterStop.StartTime='2026-10-12T09:13:55.3364712+05:30'}}.GetNewClosure()
    $startTask={param($path,$name)$state.TaskStarts++;$state.Task.State='Running'}.GetNewClosure()
    $stopProcess={param($identity)$state.ProcessStops++;if($state.FailTermination){throw 'synthetic termination failed'};$state.Process=$null}.GetNewClosure()
    [pscustomobject]@{State=$state;GetProcess=$getProcess;GetTask=$getTask;StopTask=$stopTask;StartTask=$startTask;StopProcess=$stopProcess}
}
function Invoke-Stop($h,[int]$Session=4){Stop-RepatoQaLaunchAgentForUpdate -ExpectedAgentPid 42 -ExpectedAgentStartTime $expectedStart -ExpectedSessionId $Session -AgentExe $exe -TaskPath '\Repato\' -TaskName 'Repato QA Launch Agent' -GetProcessIdentity $h.GetProcess -GetTaskEvidence $h.GetTask -StopTask $h.StopTask -StopProcess $h.StopProcess -StartTask $h.StartTask -Wait {}}

$h=New-Harness;$result=Invoke-Stop $h
Assert ($h.State.TaskStops -eq 1 -and $h.State.ProcessStops -eq 1 -and $h.State.TaskStarts -eq 0 -and !$h.State.Process) 'Legitimate matching process was not stopped exactly once.'

$h=New-Harness 'pid-reuse';Reject {Invoke-Stop $h} 'PID reuse was accepted.'
Assert ($h.State.ProcessStops -eq 0 -and $h.State.TaskStarts -eq 0) 'PID reuse terminated a replacement process or restarted the task while process identity was ambiguous.'

$h=New-Harness;$h.State.Process.Path='C:\Other\Repato.QaLaunchAgent.exe';Reject {Invoke-Stop $h} 'Wrong executable was accepted.'
Assert ($h.State.TaskStops -eq 0 -and $h.State.ProcessStops -eq 0) 'Wrong executable caused a task or process stop.'

$h=New-Harness;Reject {Invoke-Stop $h 9} 'Wrong expected session was accepted.'
Assert ($h.State.TaskStops -eq 0) 'Wrong session reached the task-stop boundary.'
$h=New-Harness;$h.State.Process.SessionId=0;Reject {Invoke-Stop $h} 'Session 0 process was accepted.'

$h=New-Harness;$h.State.Task.PrincipalSid='S-1-5-18';Reject {Invoke-Stop $h} 'Wrong task principal was accepted.'
Assert ($h.State.TaskStops -eq 0 -and $h.State.ProcessStops -eq 0) 'Wrong task principal caused a stop.'

$h=New-Harness 'duplicate-task';Reject {Invoke-Stop $h} 'Ambiguous task state was accepted.'
$h=New-Harness;$h.State.Task.State='Disabled';Reject {Invoke-Stop $h} 'Disabled task state was accepted.'

$h=New-Harness;$h.State.FailTermination=$true;Reject {Invoke-Stop $h} 'Failed termination was treated as successful.'
Assert ($h.State.ProcessStops -eq 1 -and $h.State.TaskStarts -eq 0 -and $h.State.Task.State -eq 'Ready') 'Failed termination restarted the task while the process identity remained active.'

$h=New-Harness 'task-still-running';Reject {Invoke-Stop $h} 'A running scheduled task was accepted after agent exit.'
Assert ($h.State.ProcessStops -eq 1 -and $h.State.TaskStarts -eq 0 -and $h.State.Task.State -eq 'Running') 'Installer proceeded while the scheduled task still reported Running.'

$ready=New-Harness;$ready.State.Task.State='Ready';$ready.State.FailTermination=$true;Reject {Invoke-Stop $ready} 'Ready-task termination failure was accepted.'
Assert ($ready.State.TaskStarts -eq 0) 'Failure incorrectly started a task that was previously Ready.'

$helper=Get-Content -LiteralPath $helperPath -Raw
foreach($forbidden in 'Start-Process','Revit','Invoke-CpvPreparation','active.json','approvalRequests','Set-CpvPreparationRecoveryFailedReconciled'){
    Assert (!$helper.Contains($forbidden)) "Helper contains a forbidden launch/recovery reference: $forbidden"
}
'PASS: '+$script:assertions+' isolated helper-security assertions; process/task boundaries injected; Revit/native QA/live tasks not invoked.'
