[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationUpgrade.psm1') -Force -PassThru
$script:assertions=0
function Assert([bool]$Condition,[string]$Message){$script:assertions++;if(!$Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$script:assertions++;$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};if(!$failed){throw $Message}}
function Resolve-Sid($identity,[string]$processSid){& $module {param($i,$s)Get-CpvInstalledAgentSid -InstalledAgent $i -ProcessSid $s} $identity $processSid}
function Resolve-HealthSid($health){& $module {param($h)Get-CpvHealthSid -Health $h} $health}
$validSid='S-1-5-21-1031246752-3872016183-2454652381-1015'
$missing=[pscustomobject]@{ProcessName='Repato.QaLaunchAgent';Id=4242}
$incorrect=[pscustomobject]@{Sid='S-1-5-21-1-2-3-1000'}
$valid=[pscustomobject]@{Sid=$validSid}
Assert ((Resolve-Sid $missing $validSid) -ceq $validSid) 'Missing object SID did not resolve from trusted process-owner evidence.'
Reject {Resolve-Sid $missing 'S-1-5-21-1-2-3-1000'} 'Missing process SID evidence was accepted.'
Reject {Resolve-Sid $incorrect $validSid} 'Incorrect installed SID evidence was replaced by fallback evidence.'
Assert ((Resolve-Sid $valid $validSid) -ceq $validSid) 'Valid process SID evidence was rejected.'
$healthWithSid=[pscustomobject]@{Ready=$true;User='RAMSAI\RepatoQA';SID=$validSid;SessionId=2}
Assert ((Resolve-HealthSid $healthWithSid) -ceq $validSid) 'Authenticated health SID evidence was not read safely.'
$healthWithoutSid=[pscustomobject]@{Ready=$true;User='RAMSAI\RepatoQA';SessionId=2}
Set-StrictMode -Version Latest
$originalErrorId=$null
try{$null=$healthWithoutSid.Sid}catch{$originalErrorId=$_.FullyQualifiedErrorId}
Assert ($originalErrorId -like 'PropertyNotFoundStrict*') 'The regression fixture did not reproduce the original strict-mode Sid failure.'
Reject {Resolve-HealthSid $healthWithoutSid} 'A missing health SID was accepted.'
$installer=Get-Content (Join-Path $PSScriptRoot 'Install-CpvPreparationAgentCandidate.ps1') -Raw
Assert ($installer.Contains('$healthSid=Get-CpvHealthSid -Health $health') -and $installer.Contains('Installer failure: $($failure.Exception.Message); rollback identity verification failed:')) 'Rollback health validation preserves the initiating install failure.'
Assert (($installer.IndexOf('$healthSid=Get-CpvHealthSid -Health $health') -lt $installer.IndexOf('Stop-RepatoQaLaunchAgentForUpdate -ExpectedAgentPid $process.Id'))) 'Rollback must validate SID evidence before any agent stop.'
[pscustomobject]@{Test='CpvPreparationUpgradeSidEvidence';Assertions=$script:assertions;MissingSidFallback='PASS';MissingEvidenceRejected='PASS';IncorrectSidRejected='PASS';ValidSidAccepted='PASS';PropertyNotFoundStrictReproduced='PASS';MissingHealthSidRejectedBeforeStop='PASS';OriginalFailurePreserved='PASS';LiveStoresTouched=$false;RevitLaunched=$false}|ConvertTo-Json -Compress
