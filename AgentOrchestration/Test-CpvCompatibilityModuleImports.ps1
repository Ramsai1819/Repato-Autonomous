$ErrorActionPreference='Stop'
$checks=0
# Same import order as guarded installation; command discovery only, no live calls.
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationRecovery.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationUpgrade.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvCompletedOutcomeUpgrade.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
foreach($name in @('Invoke-MayaQaLaunchAgentHealth','Get-CpvPreparationCapabilities')){$null=Get-Command $name -ErrorAction Stop;$checks++}
$recovery=Import-Module (Join-Path $PSScriptRoot 'Repato.CpvCompletedOutcomeRecovery.psm1') -PassThru -WarningAction SilentlyContinue
foreach($name in @('Invoke-MayaQaLaunchAgentHealth','Get-CpvPreparationCapabilities','Get-CpvHealthSid')){$null=Get-Command $name -ErrorAction Stop;$checks++}
for($i=0;$i -lt 2;$i++){
    $null=Import-Module (Join-Path $PSScriptRoot 'Repato.CpvCompletedOutcomeRecovery.psm1') -PassThru -WarningAction SilentlyContinue
    $null=Get-Command Invoke-MayaQaLaunchAgentHealth -ErrorAction Stop;$checks++
    $null=& $recovery {Get-Command Assert-CpvOutcomeRecoveryNonExecutionProof -ErrorAction Stop};$checks++
}
"PASS: $checks guarded-import command assertions; no transport or production mutation."
