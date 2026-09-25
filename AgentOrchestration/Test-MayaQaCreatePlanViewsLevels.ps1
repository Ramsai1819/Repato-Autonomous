$ErrorActionPreference='Stop'
$runner=Get-Content (Join-Path $PSScriptRoot '..\TestRunner\CreatePlanViewsQaApplication.cs') -Raw
foreach($name in @('"0"','"1"','"2"')){if($runner -notmatch [regex]::Escape($name)){throw "Required level missing: $name"}}
foreach($mm in @('0.0','3000.0','6000.0')){if($runner -notmatch [regex]::Escape($mm)){throw "Required elevation missing: $mm mm"}}
if($runner -notmatch 'EnsureRequiredLevels\(app\.ActiveUIDocument[^;]*\); Execute\(app, report\)'){throw 'Level preparation does not precede native execution.'}
if($runner -notmatch 'UnitTypeId\.Millimeters'){throw 'Level preparation is not expressed in millimeters.'}
Write-Host 'Create Plan Views prepared-level regression passed: 5'
