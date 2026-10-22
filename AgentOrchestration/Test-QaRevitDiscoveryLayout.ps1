$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.QaAddinDeployment.psm1') -Force
$target = Get-QaAddinDeploymentTarget
$expectedRoot = 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025'
$expectedQaRoot = Join-Path $expectedRoot 'RepatoQA'
if ($target.ManifestRoot -cne $expectedRoot) { throw "Unexpected manifest root: $($target.ManifestRoot)" }
if ($target.TargetRoot -cne $expectedQaRoot) { throw "Unexpected dedicated QA root: $($target.TargetRoot)" }
if ([IO.Path]::GetFileName($target.AssemblyPath) -cne 'Repato.Revit.dll') { throw 'Unexpected assembly name.' }
if ([IO.Path]::GetDirectoryName($target.AssemblyPath) -cne $target.TargetRoot) { throw 'Assembly is not isolated below RepatoQA.' }
if ([IO.Path]::GetDirectoryName($target.ManifestPath) -cne $target.ManifestRoot) { throw 'Manifest is not in Revit user discovery root.' }
if ([IO.Path]::GetFileName($target.ManifestPath) -cne 'Repato.WelcomeSmoke.TestRunner.addin') { throw 'Default QA target is not Welcome Smoke compatible.' }
$source = Join-Path $PSScriptRoot 'DeploymentFixtures\artifact.source'
$manifest = Join-Path $PSScriptRoot 'DeploymentFixtures\manifest.source'
$dry = Invoke-QaAddinDeployment $source $manifest -DryRun
if ($dry.ManifestDestinationPath -cne (Join-Path $expectedRoot 'manifest.source')) { throw "Generic deployment did not preserve the supplied manifest name: $($dry.ManifestDestinationPath)" }
if ($dry.ManifestDestinationPath -like 'C:\ProgramData\*') { throw 'QA deployment introduced a machine-wide manifest.' }
if ($dry.SideEffectsPerformed) { throw 'Dry-run performed side effects.' }

$repoRoot = Split-Path $PSScriptRoot -Parent
$normalManifest = [xml](Get-Content -LiteralPath (Join-Path $repoRoot 'Repato.addin') -Raw)
$normalAssembly = [string]$normalManifest.RevitAddIns.AddIn.Assembly
if ($normalAssembly -ine '%APPDATA%\Autodesk\Revit\Addins\2025\Repato\Repato.Revit.dll') { throw 'Normal user deployment destination changed.' }
if ($normalAssembly -like '*\RepatoQA\*') { throw 'Normal user deployment depends on the QA-only root.' }

$planViewsPath = Join-Path $repoRoot 'QA\Repato.CreatePlanViews.TestRunner.addin'
$planViews = [xml](Get-Content -LiteralPath $planViewsPath -Raw)
if ([string]$planViews.RevitAddIns.AddIn.Assembly -cne '.\RepatoQA\Repato.Revit.dll') { throw 'Create Plan Views manifest is not QA-only.' }
if ([string]$planViews.RevitAddIns.AddIn.FullClassName -cne 'Repato.Revit.TestRunner.CreatePlanViewsQaApplication') { throw 'Create Plan Views QA startup contract changed.' }

$welcomePath = Join-Path $repoRoot 'QA\Repato.WelcomeSmoke.TestRunner.addin'
$welcome = [xml](Get-Content -LiteralPath $welcomePath -Raw)
$welcomeApps = @($welcome.RevitAddIns.AddIn | Where-Object Type -eq 'Application')
if ($welcomeApps.Count -ne 1 -or [string]$welcomeApps[0].Assembly -cne '.\RepatoQA\Repato.Revit.dll') { throw 'Welcome Smoke QA discovery contract changed.' }

'QA Revit discovery layout checks passed: 14'
