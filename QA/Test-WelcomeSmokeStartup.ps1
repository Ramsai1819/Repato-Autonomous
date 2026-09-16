$ErrorActionPreference = 'Stop'
$application = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\TestRunner\WelcomeSmokeQaApplication.cs') -Raw
$controller = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Invoke-WelcomeSmokeQA.ps1') -Raw
$manifest = [xml](Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Repato.WelcomeSmoke.TestRunner.addin') -Raw)
foreach ($token in @('REPATO_QA_WELCOME_REQUEST','application.Idling += RunOnce','add-in startup reached','request path detected','command execution starting','result path written','QaRunnerFoundation.WriteReceiptAtomic')) {
    if ($application -notmatch [regex]::Escape($token)) { throw "Startup contract is missing $token" }
}
if ($controller -notmatch 'Start-RepatoQaRevit' -or $controller -notmatch '\-Visible' -or $controller -notmatch 'No automatic retry or process kill|remains open') { throw 'Controller does not preserve visible, bounded, no-kill startup behavior.' }
$classes = @($manifest.RevitAddIns.AddIn.FullClassName)
if ($classes -notcontains 'Repato.Revit.TestRunner.WelcomeSmokeQaApplication' -or $classes -notcontains 'Repato.Revit.TestRunner.WelcomeSmokeTestCommand') { throw 'QA manifest startup/command registration is invalid.' }
Write-Host 'Welcome smoke startup checks: 3 passed.'
