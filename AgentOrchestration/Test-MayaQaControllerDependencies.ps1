$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1'
$mayaModulePath = Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1'
$deploymentModulePath = Join-Path $PSScriptRoot 'Repato.QaAddinDeployment.psm1'
$passed = 0

function Check([bool]$Condition, [string]$Name) {
    if (!$Condition) { throw "FAILED: $Name" }
    $script:passed++
}

foreach ($path in @($modulePath, $mayaModulePath, $deploymentModulePath)) {
    Check (Test-Path -LiteralPath $path -PathType Leaf) ("required dependency exists: " + [IO.Path]::GetFileName($path))
    $tokens = $null
    $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    Check ($errors.Count -eq 0) ("dependency parses: " + [IO.Path]::GetFileName($path))
}

Import-Module $modulePath -Force -ErrorAction Stop
Import-Module $mayaModulePath -Force -ErrorAction Stop -WarningAction SilentlyContinue
Import-Module $deploymentModulePath -Force -ErrorAction Stop

Check ($null -ne (Get-Command New-TaraRevitQaPlan -ErrorAction SilentlyContinue)) 'New-TaraRevitQaPlan resolves'
Check ($null -ne (Get-Command Invoke-TaraRevitQa -ErrorAction SilentlyContinue)) 'Invoke-TaraRevitQa resolves'
$isolation = Get-Command Test-TaraFrozenCandidateQaIsolation -ErrorAction Stop
Check ($isolation.Parameters.ContainsKey('QaWorkflowId')) 'supported post-stage isolation API resolves'
Check ($null -eq (Get-Command Assert-ChildPath -ErrorAction SilentlyContinue)) 'isolation path helper remains module-private'

[pscustomobject]@{
    Status = 'PASS'
    AssertionsPassed = $passed
    AssertionsFailed = 0
    RevitLaunched = $false
    LivePipeRequestSent = $false
} | ConvertTo-Json -Compress
