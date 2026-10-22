[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('capabilities','begin','dispatch','status','reconcile-failed','complete')][string]$Operation,
    [string]$StoreRoot=(Join-Path $PSScriptRoot '../QA/MayaRuns'),
    [string]$TaskId='task-bf61fe7f22d74df7a92599681da5919e',
    [long]$ExpectedTaskRevision=0,
    [string]$ExpiredApprovalId='be82b860606d46598716e6fe191e6522'
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationRecovery.psm1') -Force -WarningAction SilentlyContinue
$result=switch($Operation){
    'capabilities'{Get-CpvPreparationCapabilities}
    'begin'{New-CpvPreparationRecovery -StoreRoot $StoreRoot -TaskId $TaskId -ExpectedTaskRevision $ExpectedTaskRevision -ExpiredApprovalId $ExpiredApprovalId}
    'dispatch'{Send-CpvPreparationRecovery -StoreRoot $StoreRoot -TaskId $TaskId -ExpectedTaskRevision $ExpectedTaskRevision}
    'status'{Get-CpvPreparationRecoveryStatus -StoreRoot $StoreRoot -TaskId $TaskId}
    'reconcile-failed'{Set-CpvPreparationRecoveryFailedReconciled -StoreRoot $StoreRoot -TaskId $TaskId -ExpectedTaskRevision $ExpectedTaskRevision}
    'complete'{Complete-CpvPreparationRecovery -StoreRoot $StoreRoot -TaskId $TaskId -ExpectedTaskRevision $ExpectedTaskRevision}
}
$result|ConvertTo-Json -Depth 20
