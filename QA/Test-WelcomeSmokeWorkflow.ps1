$ErrorActionPreference = 'Stop'
$controller = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Invoke-WelcomeSmokeQA.ps1') -Raw
$fixture = Join-Path $PSScriptRoot 'Fixtures\CreateLevelsEmpty.rvt'
$provenance = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Fixtures\CreateLevelsEmpty.provenance.json') -Raw | ConvertFrom-Json
$hash = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash
if ($provenance.fixtureId -cne 'CreateLevelsEmpty' -or $provenance.sourceSha256 -ine $hash) { throw 'Existing empty fixture provenance is invalid.' }
foreach ($shared in @('Read-RepatoQaFixtureProvenance','New-RepatoQaRun','Start-RepatoQaRevit','Wait-RepatoQaResult','Write-RepatoQaDiagnostic')) {
    if ($controller -notmatch [regex]::Escape($shared)) { throw "Controller does not use shared foundation function $shared" }
}
foreach ($contract in @('welcome.request.json','REPATO_QA_WELCOME_REQUEST','welcome-supervised-dialog-v1','model-file-unchanged','model-elements-unchanged','screenshot-dialog')) {
    if ($controller -notmatch [regex]::Escape($contract)) { throw "Controller is missing workflow contract $contract" }
}
Write-Host 'Welcome smoke workflow checks: 3 passed.'
