[CmdletBinding(SupportsShouldProcess)]param([ValidateSet('DryRun','Install','Uninstall')][string]$Action='DryRun',[string]$RepoRoot)
$ErrorActionPreference='Stop';$repo=[IO.Path]::GetFullPath($RepoRoot);$release=Join-Path $repo 'bin\Release\net8.0-windows';$dll=Join-Path $release 'Repato.Revit.dll';$manifest=Join-Path $repo 'Repato.addin';$addins=Join-Path $env:APPDATA 'Autodesk\Revit\Addins\2025';$target=Join-Path $addins 'Repato';$targetDll=Join-Path $target 'Repato.Revit.dll';$targetManifest=Join-Path $addins 'Repato.addin'
if(!(Test-Path $dll -PathType Leaf)){throw "Release artifact missing: $dll"};if(!(Test-Path $manifest -PathType Leaf)){throw "Production manifest missing: $manifest"}
$payload=[pscustomobject]@{Action=$Action;Artifact=$dll;Manifest=$manifest;TargetDll=$targetDll;TargetManifest=$targetManifest;Excludes=@('QA','TestRunner','*.rvt','*.result.json','Reports','Quarantine','RepatoQA')}
if($Action -eq 'DryRun'){ $payload|ConvertTo-Json -Depth 5;return }
if($Action -eq 'Uninstall'){if($PSCmdlet.ShouldProcess($target,'Remove Repato v1')){if(Test-Path $targetManifest){Remove-Item $targetManifest -Force};if(Test-Path $target){Remove-Item $target -Recurse -Force}};return}
$backup=Join-Path $addins ('Repato.backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
if(Test-Path $target -or Test-Path $targetManifest){New-Item $backup -ItemType Directory -Force|Out-Null;if(Test-Path $target){Copy-Item $target (Join-Path $backup 'Repato') -Recurse};if(Test-Path $targetManifest){Copy-Item $targetManifest (Join-Path $backup 'Repato.addin')}}
if($PSCmdlet.ShouldProcess($target,'Install Repato v1')){New-Item $target -ItemType Directory -Force|Out-Null;Copy-Item $dll $targetDll -Force;Copy-Item $manifest $targetManifest -Force}
[pscustomobject]@{Action='Install';TargetDll=$targetDll;TargetManifest=$targetManifest;Backup=$backup;SideEffectsPerformed=$true}
