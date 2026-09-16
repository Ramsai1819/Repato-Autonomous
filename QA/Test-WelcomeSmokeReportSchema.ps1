$ErrorActionPreference = 'Stop'
$command = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\TestRunner\WelcomeSmokeTestCommand.cs') -Raw
$controller = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Invoke-WelcomeSmokeQA.ps1') -Raw
$reportType = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\TestRunner\TestRunReport.cs') -Raw
$required = @('addin-isolation','fixture-content-policy','safety-gate','command-result','dialog-observed','dialog-window-title','dialog-title','dialog-message','screenshot-dialog','model-file-unchanged','model-elements-unchanged','rollback-status','baseline-restored')
foreach ($id in $required) {
    if ($controller -notmatch [regex]::Escape("'$id'")) { throw "Verifier is missing assertion $id" }
}
foreach ($field in @('ExpectedTitle','ExpectedVisibleWindowTitle','ExpectedMessage','AssemblyIdentity','FixtureSha256','Screenshots','RollbackStatus')) {
    if (($command + $controller + $reportType) -notmatch [regex]::Escape($field)) { throw "Report contract is missing $field" }
}
Write-Host 'Welcome smoke report-schema checks: 2 passed.'
