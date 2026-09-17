[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('neil-plan','neil-validate','neil-preview','neil-request-approval','neil-apply','neil-fail')][string]$Operation,
    [Parameter(Mandatory)][string]$TaskId,
    [string]$RunId,
    [string]$ActionId,
    [ValidateRange(1,1440)][int]$ExpiryMinutes=30,
    [string]$ErrorDetails,
    [string]$StoreRoot=(Join-Path $PSScriptRoot 'Store'),
    [string]$JointApprovalId,
    [switch]$DryRun
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.NeilAdapter.psm1') -Force -WarningAction SilentlyContinue
$result=switch($Operation){
    'neil-plan'{New-NeilPlan $StoreRoot $TaskId $ActionId -DryRun:$DryRun}
    'neil-validate'{Test-NeilPlan $StoreRoot $TaskId $RunId -DryRun:$DryRun}
    'neil-preview'{Get-NeilPreview $StoreRoot $TaskId $RunId}
    'neil-request-approval'{Request-NeilApproval $StoreRoot $TaskId $RunId $ExpiryMinutes -DryRun:$DryRun}
    'neil-apply'{Invoke-NeilApply $StoreRoot $TaskId $RunId -DryRun:$DryRun}
    'neil-fail'{Fail-NeilRun $StoreRoot $TaskId $RunId $ErrorDetails -DryRun:$DryRun}
}
$result|ConvertTo-Json -Depth 20