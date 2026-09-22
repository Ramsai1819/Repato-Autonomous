$ErrorActionPreference='Stop'
$module=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\AgentOrchestration\Repato.TaraRevitQa.psm1') -Raw
if($module -notmatch "create-grids-world-axis-v1.*Repato\.CreateGrids\.TestRunner\.addin.*REPATO_QA_CREATE_GRIDS_REQUEST.*Invoke-CreateGridsQA\.ps1.*Repato\.Revit\.TestRunner\.CreateGridsQaApplication"){throw 'Create Grids Tara mapping is missing.'}
$xml=[xml](Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Repato.CreateGrids.TestRunner.addin') -Raw)
$classes=@($xml.RevitAddIns.AddIn|ForEach-Object {$_.FullClassName})
if($classes -notcontains 'Repato.Revit.TestRunner.CreateGridsQaApplication' -or $classes -notcontains 'Repato.Revit.TestRunner.CreateGridsTestCommand'){throw 'Create Grids manifest classes are incorrect.'}
Write-Host 'Create Grids runner mapping and manifest passed.'
