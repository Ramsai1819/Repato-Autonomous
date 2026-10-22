$ErrorActionPreference='Stop'
$runner=Get-Content (Join-Path $PSScriptRoot '..\TestRunner\CreatePlanViewsQaApplication.cs') -Raw
foreach($name in @('"Level 0"','"Level 1"','LevelInventoryEnvironmentVariable')){if($runner -notmatch [regex]::Escape($name)){throw "Required level marker missing: $name"}}
if($runner -notmatch 'Millimeters'){throw 'Level preparation is not expressed in millimeters.'}
if($runner.IndexOf('"Level 0"') -ge $runner.IndexOf('RuntimeModelSha256')){throw 'Level preparation does not precede native runtime hashing.'}
Write-Host 'Create Plan Views prepared-level regression passed: 4'
