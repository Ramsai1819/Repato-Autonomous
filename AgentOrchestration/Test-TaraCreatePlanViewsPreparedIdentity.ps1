$ErrorActionPreference='Stop'
$m=Get-Content (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Raw
$r=Get-Content (Join-Path $PSScriptRoot '..\TestRunner\TestRunReport.cs') -Raw
foreach($x in @('RuntimeModelSha256','Prepared runtime model hash mismatch','SourceFixturePath')){if($m -notmatch [regex]::Escape($x)){throw "Prepared identity validation missing: $x"}}
if($r -notmatch 'RuntimeModelSha256'){throw 'Report runtime model identity field missing.'}
Write-Host 'Create Plan Views prepared-model identity regression passed: 4'
