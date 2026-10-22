$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Force
$module=Get-Module Repato.TaraRevitQa
$process=[pscustomobject]@{HasExited=$false;ExitCode=$null;Killed=$false;CloseRequested=$false}
$process|Add-Member ScriptMethod Refresh {}
$process|Add-Member ScriptMethod CloseMainWindow {$this.CloseRequested=$true;return $true}
$process|Add-Member ScriptMethod Kill {$this.Killed=$true;throw 'Force termination was attempted.'}
$close=& $module {param($p)Close-TaraOwnedProcess $p 0 -NoForceRevitClose} $process
if($close.State -cne 'GracefulCloseTimedOut' -or $close.Forced -or !$process.CloseRequested -or $process.Killed){throw 'No-force cleanup did not stop after requesting graceful closure.'}
$plan=[pscustomobject]@{ResultPath=(Join-Path ([IO.Path]::GetTempPath()) ('tara-no-force-'+[guid]::NewGuid().ToString('N')+'.json'));TimeoutSeconds=0;NoForceRevitClose=$true;TrustConfiguration=[pscustomobject]@{PromptRecords=@()}}
$timeoutObserved=$false
try{& $module {param($p,$child)Wait-TaraResult $p $child} $plan $process}catch [TimeoutException]{$timeoutObserved=$true}
if(!$timeoutObserved -or $process.Killed){throw 'No-force result timeout attempted forced termination or did not report timeout.'}
$fixtureScript=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Invoke-TaraCreatePlanViewsFixturePreparation.ps1') -Raw
if($fixtureScript -notmatch '-TimeoutSeconds 7200' -or $fixtureScript -notmatch '-NoForceRevitClose' -or $fixtureScript -notmatch 'Repato\.Deployment\.v4\.psm1' -or $fixtureScript -notmatch 'Resolve-MayaQaAuthenticatedBuildSource \$null'){throw 'CPV fixture preparation does not use the bounded no-force path and approved primary repository roots.'}
[pscustomobject]@{Status='PASS';Assertions=3;GracefulCloseRequested=$process.CloseRequested;ForceTerminationAttempted=$process.Killed;TimeoutObserved=$timeoutObserved;FixturePreparationNoForce=$true}|ConvertTo-Json -Compress
