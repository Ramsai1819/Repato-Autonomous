$ErrorActionPreference = 'Stop'
$command = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\TestRunner\WelcomeSmokeTestCommand.cs') -Raw
$controller = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Invoke-WelcomeSmokeQA.ps1') -Raw
foreach ($token in @('string beforeHash = TestRunReport.Hash(document.PathName)','string[] beforeElements = Elements(document)','model-file-unchanged','model-elements-unchanged','VerifyRollback')) {
    if ($command -notmatch [regex]::Escape($token)) { throw "Native integrity check missing: $token" }
}
if ($controller -notmatch 'Get-RepatoQaSha256 \$request\.modelPath' -or $controller -notmatch 'CreateLevelsEmpty\.rvt') { throw 'Verifier does not independently hash the disposable copy and source fixture.' }
Write-Host 'Welcome smoke model-integrity checks: 2 passed.'
