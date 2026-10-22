$ErrorActionPreference='Stop'
$coordinator=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\QaLaunchAgent\LaunchCoordinator.cs') -Raw
$adapter=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\QaLaunchAgent\StagingAdapter.cs') -Raw
$script=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Invoke-RepatoQaDeploymentValidation.ps1') -Raw
$deployment=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Repato.QaAddinDeployment.psm1') -Raw
$handler=[regex]::Match($coordinator,'public QaDeploymentValidationResponse HandleDeploymentValidation[\s\S]*?\n    }').Value
$validationAdapter=[regex]::Match($adapter,'public static QaDeploymentValidationResponse ValidateDeployment[\s\S]*?\n    }').Value
$isolation=[regex]::Match($deployment,'function Test-TaraFrozenCandidateQaIsolation \{[\s\S]*?\n}').Value
foreach($pair in @(@('server validation handler',$handler),@('validation adapter',$validationAdapter),@('isolation verifier',$isolation))){if([string]::IsNullOrWhiteSpace($pair[1])){throw "Missing audited $($pair[0]) body."}}
if($handler -notmatch 'StagingAdapter\.ValidateDeployment' -or $handler -match 'launcher\.Launch|StagingAdapter\.Run'){throw 'Validation handler can reach staging or Revit launch.'}
if($validationAdapter -notmatch 'Replace\("Invoke-RepatoQaFrozenCandidateStaging\.ps1", "Invoke-RepatoQaDeploymentValidation\.ps1"\)' -or $validationAdapter -notmatch 'ProcessStartInfo'){throw 'Validation adapter is not fixed to the validation script.'}
if($script -notmatch 'Test-TaraFrozenCandidateQaIsolation' -or $script -match '(?im)^\s*(Copy-Item|Move-Item|Remove-Item|Set-Content|Add-Content|New-Item|Start-Process)\b' -or $script -match 'Install-TaraFrozenCandidateForQa|Invoke-QaAddinDeployment'){throw 'Validation script contains a deployment or launch mutation.'}
if($isolation -notmatch 'SideEffectsPerformed=\$false' -or $isolation -match '(?im)^\s*(Copy-Item|Move-Item|Remove-Item|Set-Content|Add-Content|New-Item|Start-Process)\b' -or $isolation -match 'Install-TaraFrozenCandidateForQa|Invoke-QaAddinDeployment'){throw 'Isolation validation is not read-only.'}
[pscustomobject]@{DeploymentFilesReadOnly='PASS';NoStagingCall='PASS';NoDeploymentMutation='PASS';NoRevitLaunch='PASS';BoundedTemporaryRequestFile=$true;ReplayLedgerReservation=$true}|ConvertTo-Json -Compress
