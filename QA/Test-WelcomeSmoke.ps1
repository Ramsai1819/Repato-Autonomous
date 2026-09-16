$ErrorActionPreference = 'Stop'
$command = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\TestRunner\WelcomeSmokeTestCommand.cs') -Raw
$production = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\RepatoWelcomeCommand.cs') -Raw
$application = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\FormaApplication.cs') -Raw
foreach ($token in @('welcome-supervised-dialog-v1','RepatoWelcomeCommand.ShowWelcome()','Result.Succeeded','dialog-window-title','dialog-title','dialog-message','model-file-unchanged','model-elements-unchanged','Supervised UI')) {
    if ($command -notmatch [regex]::Escape($token)) { throw "Welcome smoke command is missing $token" }
}
if ($production -notmatch 'DialogTitle\s*=\s*"Repato"' -or $production -notmatch 'Repato is running successfully\.\\n\\nNext: Create Grids\.') { throw 'Production welcome dialog contract changed.' }
if ($command -notmatch 'QaApplicationTitle\s*=\s*"Repato Welcome Smoke QA Startup"' -or
    $command -notmatch 'observedWindowTitle == ExpectedVisibleWindowTitle' -or
    $command -notmatch 'observedCommandTitle == RepatoWelcomeCommand\.DialogTitle') { throw 'Exact wrapper and command title validation is missing.' }
if ($application -match 'RepatoWelcomeCommand') { throw 'Welcome command must not be added to the production ribbon.' }
Write-Host 'Welcome smoke static checks: 3 passed.'
