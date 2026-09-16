$ErrorActionPreference='Stop'
foreach($path in @('Fixtures\CreateGridsEmptyPlan.rvt','Repato.TestRunner.addin','..\TestRunner\RepatoTestCommand.cs')){if(!(Test-Path (Join-Path $PSScriptRoot $path))){throw "Missing $path"}}
$source=Get-Content (Join-Path $PSScriptRoot '..\TestRunner\RepatoTestCommand.cs') -Raw
foreach($token in @('create-grids-world-axis-v1','GridCreator.Create','rollback-status','world-axis-position-','spacing-')){if($source-notmatch[regex]::Escape($token)){throw "Create Grids contract missing $token"}}
Write-Host '8 Create Grids compatibility checks passed'
