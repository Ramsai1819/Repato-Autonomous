$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.QaLaunchAgent.Bootstrap.psm1') -Force

function Assert([bool]$Condition,[string]$Message){if(!$Condition){throw $Message}}
$contract=Get-RepatoQaLaunchAgentBootstrapContract
$actual=[pscustomobject]@{TaskPath=$contract.TaskPath;TaskName=$contract.TaskName;Principal=$contract.Account;PrincipalResolvedSid=$contract.Sid;Sid=$contract.Sid;LogonType='Interactive';RunLevel='Limited';TriggerType='Logon';TriggerUser=$contract.Account;TriggerResolvedSid=$contract.Sid;Execute=$contract.Executable;Arguments='';WorkingDirectory=$contract.InstallRoot;MultipleInstances='IgnoreNew';RestartCount=3;RestartInterval='PT1M'}
$matches=@(Get-TaskSpecComparison $actual)
Assert (($matches | Where-Object {!$_.Match}).Count -eq 0) 'Exact contract did not pass.'

foreach($display in @('RAMSAI\RepatoQA','Ramsai\RepatoQA','RepatoQA')) {
    $identity=$actual | Select-Object *; $identity.Principal=$display; $identity.TriggerUser=$display
    Assert ((Get-TaskSpecComparison $identity | Where-Object {!$_.Match}).Count -eq 0) "SID identity failed for $display."
}
$wrong=$actual | Select-Object *; $wrong.PrincipalResolvedSid='S-1-5-21-wrong'; $debug=@(Get-TaskSpecComparison $wrong | Where-Object {$_.Property -eq 'Principal'}); Assert ($debug.Count -eq 1 -and $debug[0].Match -eq $false) 'Wrong principal SID accepted.'
$wrong=$actual | Select-Object *; $wrong.TriggerResolvedSid='S-1-5-21-wrong'; $debug=@(Get-TaskSpecComparison $wrong | Where-Object {$_.Property -eq 'TriggerUser'}); Assert ($debug.Count -eq 1 -and $debug[0].Match -eq $false) 'Wrong trigger SID accepted.'
$unresolved=$actual | Select-Object *; $unresolved.PrincipalResolvedSid=$null; $debug=@(Get-TaskSpecComparison $unresolved | Where-Object {$_.Property -eq 'Principal'}); Assert ($debug.Count -eq 1 -and $debug[0].Match -eq $false) 'Unresolved principal accepted.'
$unresolved=$actual | Select-Object *; $unresolved.TriggerResolvedSid=$null; $debug=@(Get-TaskSpecComparison $unresolved | Where-Object {$_.Property -eq 'TriggerUser'}); Assert ($debug.Count -eq 1 -and $debug[0].Match -eq $false) 'Unresolved trigger accepted.'

$fields=@('Principal','LogonType','RunLevel','TriggerUser','Execute','Arguments','WorkingDirectory','MultipleInstances','RestartCount','RestartInterval')
foreach($field in $fields){
    $bad=$actual | Select-Object *; $bad.$field='mismatch'
    if($field -eq 'Principal'){$bad.PrincipalResolvedSid='mismatch'}
    if($field -eq 'TriggerUser'){$bad.TriggerResolvedSid='mismatch'}
    $m=@(Get-TaskSpecComparison $bad | Where-Object {!$_.Match})
    Assert ($m.Count -eq 1 -and $m[0].Property -eq $field) "Mismatch was not isolated for $field."
}
$all=$actual | Select-Object *; foreach($field in $fields){$all.$field='mismatch'}; $all.PrincipalResolvedSid='mismatch'; $all.TriggerResolvedSid='mismatch'
$m=@(Get-TaskSpecComparison $all | Where-Object {!$_.Match})
Assert ($m.Count -eq $fields.Count) 'Multiple mismatches were not all reported.'

$moduleText=Get-Content (Join-Path $PSScriptRoot 'Repato.QaLaunchAgent.Bootstrap.psm1') -Raw
Assert ($moduleText -match 'Write-RepatoQaLaunchAgentDiagnostics') 'Diagnostic persistence is missing.'
Assert ($moduleText -match 'RestoreTask') 'Rollback path is missing.'
Assert ($moduleText -match 'Get-RepatoQaLaunchAgentRuntimeIntegrity') 'Runtime integrity check is missing.'
Write-Output 'QA launch-agent bootstrap diagnostic tests passed: exact match, 10 individual mismatches, all mismatches, persistence, rollback, and integrity coverage.'
