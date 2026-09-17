[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('executor-list-queued','executor-plan','executor-claim','executor-validate','executor-preview','executor-request-approval','executor-complete','executor-fail')][string]$Operation,
    [string]$TaskId,
    [string]$ExecutionId,[string]$Agent,[string[]]$Actions,[string]$ApprovalAction,[ValidateRange(1,1440)][int]$ExpiryMinutes=30,
    [string[]]$LogPaths=@(),[string[]]$ReportPaths=@(),[string[]]$EvidencePaths=@(),[string]$ErrorDetails,
    [string]$StoreRoot=(Join-Path $PSScriptRoot 'Store'),[switch]$DryRun
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
if($Operation-cne'executor-list-queued'-and[string]::IsNullOrWhiteSpace($TaskId)){throw '-TaskId is required.'}
$result=switch($Operation){
 'executor-list-queued'{@(Get-RepatoTasks $StoreRoot $null|Where-Object status -ceq queued)}
 'executor-plan'{New-RepatoExecutorPlan $StoreRoot $TaskId $Agent $Actions -DryRun:$DryRun}
 'executor-claim'{Claim-RepatoExecutorRun $StoreRoot $TaskId $ExecutionId $Agent -DryRun:$DryRun}
 'executor-validate'{Test-RepatoExecutorRun $StoreRoot $TaskId $ExecutionId -DryRun:$DryRun}
 'executor-preview'{Get-RepatoExecutorPreview $StoreRoot $TaskId $ExecutionId}
 'executor-request-approval'{Request-RepatoExecutorApproval $StoreRoot $TaskId $ExecutionId $ApprovalAction $ExpiryMinutes -DryRun:$DryRun}
 'executor-complete'{Complete-RepatoExecutorRun $StoreRoot $TaskId $ExecutionId $LogPaths $ReportPaths $EvidencePaths -DryRun:$DryRun}
 'executor-fail'{Fail-RepatoExecutorRun $StoreRoot $TaskId $ExecutionId $ErrorDetails $LogPaths $ReportPaths -DryRun:$DryRun}
}
$result|ConvertTo-Json -Depth 20
