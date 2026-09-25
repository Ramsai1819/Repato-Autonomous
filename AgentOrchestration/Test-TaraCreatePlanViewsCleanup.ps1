$ErrorActionPreference='Stop'
$text=Get-Content (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Raw
foreach($marker in @("PSObject.Properties.Name -contains 'Stopped'",'IDisposable','Dispose()')){if($text -notmatch [regex]::Escape($marker)){throw "Safe trust-handler cleanup marker missing: $marker"}}
Write-Host 'Tara trust-handler cleanup regression passed.'
