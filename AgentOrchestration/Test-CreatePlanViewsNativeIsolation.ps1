$ErrorActionPreference='Stop'
$policy=Get-Content (Join-Path $PSScriptRoot '..\TestRunner\AddinIsolationPolicy.cs') -Raw
$runner=Get-Content (Join-Path $PSScriptRoot '..\TestRunner\CreatePlanViewsQaApplication.cs') -Raw
$tara=Get-Content (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Raw
foreach($m in @('selectedManifestPath','selectedManifestSha256')){if($policy -notmatch [regex]::Escape($m) -or $runner -notmatch [regex]::Escape($m) -or $tara -notmatch [regex]::Escape($m)){throw "Selected runner field missing: $m"}}
if($policy -notmatch 'Unselected or hash-mismatched QA runner manifest'){throw 'Native rejection path missing.'}
Write-Host 'Create Plan Views native selected-runner isolation checks passed: 4'
