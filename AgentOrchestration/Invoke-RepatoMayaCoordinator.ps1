[CmdletBinding()]
param(
 [Parameter(Mandatory)][ValidateSet('maya-cycle-preview','maya-assign','maya-status','maya-reconcile','maya-request-approval','maya-fail')][string]$Operation,
 [string]$TaskId,[ValidateSet('Neil','Tara')][string]$Agent,[string]$Action,[ValidateSet('maya','user')][string]$ApprovalLevel='maya',[ValidateRange(1,1440)][int]$ExpiryMinutes=30,[string]$ErrorDetails,[string]$StoreRoot=(Join-Path $PSScriptRoot 'Store'),[switch]$DryRun
)
$ErrorActionPreference='Stop';Import-Module (Join-Path $PSScriptRoot 'Repato.MayaCoordinator.psm1') -Force -WarningAction SilentlyContinue
$result=switch($Operation){'maya-cycle-preview'{Get-MayaCyclePreview $StoreRoot};'maya-assign'{Invoke-MayaAssign $StoreRoot $TaskId $Agent -DryRun:$DryRun};'maya-status'{Get-MayaStatus $StoreRoot $TaskId};'maya-reconcile'{Invoke-MayaReconcile $StoreRoot $TaskId -DryRun:$DryRun};'maya-request-approval'{Request-MayaApproval $StoreRoot $TaskId $Action $ApprovalLevel $ExpiryMinutes -DryRun:$DryRun};'maya-fail'{Fail-MayaTask $StoreRoot $TaskId $ErrorDetails -DryRun:$DryRun}}
$result|ConvertTo-Json -Depth 20
