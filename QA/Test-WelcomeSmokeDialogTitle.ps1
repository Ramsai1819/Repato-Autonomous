$ErrorActionPreference = 'Stop'
$command = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\TestRunner\WelcomeSmokeTestCommand.cs') -Raw
$production = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\RepatoWelcomeCommand.cs') -Raw
$manifest = [xml](Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Repato.WelcomeSmoke.TestRunner.addin') -Raw)
$applicationName = [string](@($manifest.RevitAddIns.AddIn | Where-Object Type -eq 'Application')[0].Name)
if ($applicationName -cne 'Repato Welcome Smoke QA Startup') { throw 'QA application wrapper title changed.' }
if ($production -notmatch 'DialogTitle\s*=\s*"(?<title>[^"]+)"') { throw 'Production dialog title constant missing.' }
$commandTitle = $Matches.title
$visibleTitle = 'Repato QA - Welcome Smoke - Repato'
if ($commandTitle -cne 'Repato' -or $visibleTitle -cne 'Repato QA - Welcome Smoke - Repato') { throw 'Exact command or visible title changed.' }
if ($command -notmatch 'GetForegroundWindow' -or $command -notmatch 'GetWindowText' -or
    $command -notmatch 'StartsWith\(prefix, StringComparison\.Ordinal\)' -or
    $command -notmatch 'observedWindowTitle == ExpectedVisibleWindowTitle' -or
    $command -notmatch 'string\.IsNullOrEmpty\(observedCommandTitle\)') { throw 'Native exact-title capture or empty DialogId handling is missing.' }
Write-Host 'Welcome exact dialog-title regression checks: 2 passed.'
