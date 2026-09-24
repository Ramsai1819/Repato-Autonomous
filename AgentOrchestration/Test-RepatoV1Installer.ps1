$ErrorActionPreference='Stop';$s=Get-Content (Join-Path $PSScriptRoot 'Install-RepatoV1.ps1') -Raw
foreach($t in @('Release','Repato.addin','APPDATA','Repato.backup-','Uninstall','QA','RepatoQA','TestRunner')){if($s -notmatch [regex]::Escape($t)){throw "Installer contract missing $t"}}
$r=& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Install-RepatoV1.ps1') -Action DryRun -RepoRoot (Split-Path $PSScriptRoot -Parent)|ConvertFrom-Json
if($r.TargetDll -notmatch 'Autodesk\\Revit\\Addins\\2025\\Repato\\Repato.Revit.dll' -or $r.TargetManifest -notmatch 'Autodesk\\Revit\\Addins\\2025\\Repato.addin'){throw 'Production installation targets are incorrect.'};Write-Host 'Repato v1 installer regression passed.'
