[CmdletBinding()]
param([string]$BundleRoot)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSVersion -lt [version]'5.1' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'This regression must run in a fresh Windows PowerShell 5.1 process.'}
$script:assertions=0
function Assert([bool]$Value,[string]$Message){$script:assertions++;if(!$Value){throw $Message}}
$sid='S-1-5-21-1031246752-3872016183-2454652381-1015'
$global:cpvTask=[pscustomobject]@{
    TaskPath='\Repato\';TaskName='Repato QA Launch Agent';State='Ready'
    Principal=[pscustomobject]@{UserId='RAMSAI\RepatoQA';LogonType='Interactive';RunLevel='Limited'}
    Triggers=@([pscustomobject]@{CimClass=[pscustomobject]@{CimClassName='MSFT_TaskLogonTrigger'};UserId='RAMSAI\RepatoQA'})
    Actions=@([pscustomobject]@{Execute='C:\Program Files\Repato\QaLaunchAgent\Repato.QaLaunchAgent.exe';Arguments='';WorkingDirectory='C:\Program Files\Repato\QaLaunchAgent'})
    Settings=[pscustomobject]@{MultipleInstances='IgnoreNew';RestartCount=3;RestartInterval='PT1M'}
}
function global:Get-ScheduledTask { param($TaskPath,$TaskName,$ErrorAction) $global:cpvTask }
function global:Export-ScheduledTask { param($TaskPath,$TaskName,$ErrorAction) '<Task version="1.2" />' }
$aoRoot=$PSScriptRoot
$bootstrapRoot=Join-Path $PSScriptRoot '../QaLaunchAgent'
if($BundleRoot){
    $bundlePath=[IO.Path]::GetFullPath($BundleRoot)
    $aoRoot=Join-Path $bundlePath 'AgentOrchestration'
    $bootstrapRoot=Join-Path $bundlePath 'QaLaunchAgent'
}
$modulePath=Join-Path $bootstrapRoot 'Repato.QaLaunchAgent.Bootstrap.psm1'
$null=Import-Module $modulePath -Force -PassThru
. (Join-Path $aoRoot 'Repato.QaLaunchAgentInstall.ps1')
$bootstrap=Resolve-RepatoQaLaunchAgentBootstrapModule -ModulePath $modulePath
$valid=Get-RepatoQaLaunchAgentTaskEvidence -BootstrapModule $bootstrap
Assert ($valid.Valid -and $valid.PrincipalSid -ceq $sid -and $valid.TriggerSid -ceq $sid) 'Fresh-process exported entrypoint failed to resolve private SID dependencies for a valid Windows task shape.'
$global:cpvTask.Principal.UserId='NT AUTHORITY\SYSTEM'
$wrong=Get-RepatoQaLaunchAgentTaskEvidence -BootstrapModule $bootstrap
Assert (!$wrong.Valid -and $wrong.PrincipalSid -ceq 'S-1-5-18' -and $wrong.TriggerSid -ceq $sid) 'Wrong principal SID was not rejected while preserving trigger evidence.'
$global:cpvTask.Principal.UserId=''
$missing=Get-RepatoQaLaunchAgentTaskEvidence -BootstrapModule $bootstrap
Assert (!$missing.Valid -and !$missing.PrincipalSid -and $missing.TriggerSid -ceq $sid) 'Missing principal identity was accepted or raised a missing-command/property error.'
$installerPath=Join-Path $aoRoot 'Install-CpvPreparationAgentCandidate.ps1'
$installer=Get-Content -LiteralPath $installerPath -Raw
Assert ($installer.Contains('$priorTaskEvidence=Get-RepatoQaLaunchAgentTaskEvidence -BootstrapModule $bootstrap')) 'Packaged installer does not call the validated task-evidence entrypoint.'
Assert ($installer.IndexOf('$priorTaskEvidence=Get-RepatoQaLaunchAgentTaskEvidence') -ge 0 -and $installer.IndexOf('$priorTaskEvidence=Get-RepatoQaLaunchAgentTaskEvidence') -lt $installer.IndexOf('$journalLease=New-RepatoQaLaunchAgentBootstrapInstallJournal')) 'Packaged task validation does not precede journal creation.'
[pscustomobject]@{Test='CpvInstallerFreshTaskEvidence';PowerShellVersion=$PSVersionTable.PSVersion.ToString();Assertions=$script:assertions;ValidPrincipalAndTriggerSid='PASS';WrongPrincipalRejected='PASS';MissingPrincipalRejected='PASS';LiveTaskStoreTouched=$false;InstallerInvoked=$false;RevitLaunched=$false}|ConvertTo-Json -Compress
