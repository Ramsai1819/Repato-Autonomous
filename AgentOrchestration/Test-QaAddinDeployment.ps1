$ErrorActionPreference='Stop';Import-Module (Join-Path $PSScriptRoot 'Repato.QaAddinDeployment.psm1') -Force
$t=Get-QaAddinDeploymentTarget;if($t.TargetRoot -ne 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA'){throw 'Target mismatch'}
$bad=$false;try{Test-QaAddinTarget 'C:\ProgramData\Autodesk\Revit\Addins\2025'}catch{$bad=$true};if(!$bad){throw 'Unsafe target accepted'}
$a=Join-Path $PSScriptRoot 'DeploymentFixtures\artifact.source';$m=Join-Path $PSScriptRoot 'DeploymentFixtures\manifest.source';$r=Invoke-QaAddinDeployment $a $m -DryRun;if($r.SideEffectsPerformed){throw 'Dry-run side effects'};'QA add-in deployment checks passed: 3'
