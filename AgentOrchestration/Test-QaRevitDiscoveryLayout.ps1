$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.QaAddinDeployment.psm1') -Force
$target = Get-QaAddinDeploymentTarget
$expectedRoot = 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025'
if ($target.ManifestRoot -cne $expectedRoot) { throw "Unexpected manifest root: $($target.ManifestRoot)" }
if ([IO.Path]::GetFileName($target.AssemblyPath) -cne 'Repato.Revit.dll') { throw 'Unexpected assembly name.' }
if ([IO.Path]::GetDirectoryName($target.AssemblyPath) -cne $target.TargetRoot) { throw 'Assembly is not isolated below RepatoQA.' }
if ([IO.Path]::GetDirectoryName($target.ManifestPath) -cne $target.ManifestRoot) { throw 'Manifest is not in Revit user discovery root.' }
$source = Join-Path $PSScriptRoot 'DeploymentFixtures\artifact.source'
$manifest = Join-Path $PSScriptRoot 'DeploymentFixtures\manifest.source'
$dry = Invoke-QaAddinDeployment $source $manifest -DryRun
if ($dry.ManifestDestinationPath -notlike "$expectedRoot\*") { throw 'Dry-run manifest destination is outside discovery root.' }
if ($dry.SideEffectsPerformed) { throw 'Dry-run performed side effects.' }
'QA Revit discovery layout checks passed: 5'
