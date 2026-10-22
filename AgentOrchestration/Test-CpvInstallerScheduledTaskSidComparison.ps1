[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$bootstrap=Import-Module (Join-Path $PSScriptRoot '../QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1') -Force -PassThru
. (Join-Path $PSScriptRoot 'Repato.QaLaunchAgentInstall.ps1')
$script:assertions=0
function Assert([bool]$Value,[string]$Message){$script:assertions++;if(!$Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$script:assertions++;$accepted=$false;try{$accepted=[bool](& $Action)}catch{throw "Unexpected exception for $Message : $($_.Exception.Message)"};if($accepted){throw "Accepted $Message"}}
$sid='S-1-5-21-1031246752-3872016183-2454652381-1015'
$otherSid='S-1-5-21-1-2-3-1000'
$contract=& $bootstrap { New-TaskSpec }

# Shape returned by ScheduledTasks: identity and action data are nested; there is no top-level Sid.
$rawTask=[pscustomobject]@{
    TaskPath='\Repato\';TaskName='Repato QA Launch Agent';State='Ready'
    Principal=[pscustomobject]@{UserId='RAMSAI\RepatoQA';LogonType='Interactive';RunLevel='Limited'}
    Triggers=@([pscustomobject]@{CimClass=[pscustomobject]@{CimClassName='MSFT_TaskLogonTrigger'};UserId='RAMSAI\RepatoQA'})
    Actions=@([pscustomobject]@{Execute='C:\Program Files\Repato\QaLaunchAgent\Repato.QaLaunchAgent.exe';Arguments='';WorkingDirectory='C:\Program Files\Repato\QaLaunchAgent'})
    Settings=[pscustomobject]@{MultipleInstances='IgnoreNew';RestartCount=3;RestartInterval='PT1M'}
}
Assert ($rawTask.PSObject.Properties.Name -notcontains 'Sid') 'Windows scheduled-task fixture unexpectedly has a top-level Sid.'
$rawComparison=& $bootstrap {param($task) @(Get-TaskSpecComparison $task)} $rawTask
Assert (@($rawComparison|Where-Object Property -ceq 'Sid').Count -eq 1) 'Missing top-level SID was not represented in the comparison.'
Reject {& $bootstrap {param($task) Test-TaskSpec $task} $rawTask} 'raw scheduled-task object without normalized identity evidence'

# The production evidence converter consumes the Windows object shape and independently resolves both identities.
$resolver={param($account)if($account -ceq 'RAMSAI\RepatoQA'){$sid}elseif($account -ceq 'RAMSAI\OtherUser'){$otherSid}else{$null}}.GetNewClosure()
$valid=& $bootstrap {param($task,$sidResolver)ConvertTo-TaskSpecEvidence -Task $task -SidResolver $sidResolver} $rawTask $resolver
Assert ($valid.PSObject.Properties.Name -notcontains 'Sid') 'Normalized task evidence must not invent an aggregate SID property.'
Assert ((& $bootstrap {param($task) Test-TaskSpec $task} $valid)) 'Matching principal and trigger SID evidence was rejected.'
$getValidTask={& $bootstrap {param($task,$sidResolver)ConvertTo-TaskSpecEvidence -Task $task -SidResolver $sidResolver} $rawTask $resolver}.GetNewClosure()
$getRawTask={$rawTask}.GetNewClosure()
$exportTask={param($task)'<Task />'}
$validEvidence=Get-RepatoQaLaunchAgentTaskEvidence -BootstrapModule $bootstrap -GetTask $getValidTask -GetRawTask $getRawTask -ExportTask $exportTask
Assert ($validEvidence.Valid -and $validEvidence.PrincipalSid -ceq $sid -and $validEvidence.TriggerSid -ceq $sid) 'Injected exact preflight evidence producer did not validate both resolved SIDs.'
$missingPrincipalSid=$valid.PSObject.Copy();$missingPrincipalSid.PrincipalResolvedSid=$null
Reject {& $bootstrap {param($task) Test-TaskSpec $task} $missingPrincipalSid} 'missing principal SID evidence'
$missingTriggerSid=$valid.PSObject.Copy();$missingTriggerSid.TriggerResolvedSid=$null
Reject {& $bootstrap {param($task) Test-TaskSpec $task} $missingTriggerSid} 'missing trigger SID evidence'
$wrongPrincipalSid=$valid.PSObject.Copy();$wrongPrincipalSid.PrincipalResolvedSid=$otherSid
Reject {& $bootstrap {param($task) Test-TaskSpec $task} $wrongPrincipalSid} 'mismatched principal SID'
$wrongTriggerSid=$valid.PSObject.Copy();$wrongTriggerSid.TriggerResolvedSid=$otherSid
Reject {& $bootstrap {param($task) Test-TaskSpec $task} $wrongTriggerSid} 'mismatched trigger SID'
$wrongPrincipalRaw=$rawTask.PSObject.Copy();$wrongPrincipalRaw.Principal=[pscustomobject]@{UserId='RAMSAI\OtherUser';LogonType='Interactive';RunLevel='Limited'}
$wrongPrincipal=& $bootstrap {param($task,$sidResolver)ConvertTo-TaskSpecEvidence -Task $task -SidResolver $sidResolver} $wrongPrincipalRaw $resolver
Reject {& $bootstrap {param($task) Test-TaskSpec $task} $wrongPrincipal} 'wrong task principal'
$getWrongTask={& $bootstrap {param($task,$sidResolver)ConvertTo-TaskSpecEvidence -Task $task -SidResolver $sidResolver} $wrongPrincipalRaw $resolver}.GetNewClosure()
$wrongEvidence=Get-RepatoQaLaunchAgentTaskEvidence -BootstrapModule $bootstrap -GetTask $getWrongTask -GetRawTask $getRawTask -ExportTask $exportTask
Assert (!$wrongEvidence.Valid -and $wrongEvidence.PrincipalSid -ceq $otherSid) 'Injected preflight evidence producer accepted a wrong principal.'
$missingField=$rawTask.PSObject.Copy();$missingField.PSObject.Properties.Remove('TaskName')
$missingEvidence=& $bootstrap {param($task,$sidResolver)ConvertTo-TaskSpecEvidence -Task $task -SidResolver $sidResolver} $missingField $resolver
Reject {& $bootstrap {param($task) Test-TaskSpec $task} $missingEvidence} 'missing required task field'

$installer=Get-Content (Join-Path $PSScriptRoot 'Install-CpvPreparationAgentCandidate.ps1') -Raw
Assert ($installer.Contains('$priorTaskEvidence=Get-RepatoQaLaunchAgentTaskEvidence -BootstrapModule $bootstrap')) 'Guarded preflight does not use the scheduled-task evidence producer.'
Assert (!$installer.Contains('$priorTaskValid=& $bootstrap {param($task) Test-TaskSpec $task} $priorTask')) 'Guarded preflight still compares the raw Windows scheduled-task object.'
[pscustomobject]@{Test='CpvInstallerScheduledTaskSidComparison';Assertions=$script:assertions;WindowsTaskShape='PASS';ValidResolvedSids='PASS';MissingSidRejected='PASS';MismatchedSidRejected='PASS';WrongPrincipalRejected='PASS';StrictMode='Latest';LiveTaskStoreTouched=$false;InstallerInvoked=$false;RevitLaunched=$false}|ConvertTo-Json -Compress
