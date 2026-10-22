[CmdletBinding()]
param(
    [string]$StoreRoot=(Join-Path $PSScriptRoot 'Store'),
    [Parameter(Mandatory)][string]$TaskId,
    [Parameter(Mandatory)][string]$AttemptId,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$ClaimId,
    [Parameter(Mandatory)][string]$NativeRequestId,
    [Parameter(Mandatory)][int]$ProcessId,
    [Parameter(Mandatory)][string]$ProcessStartedUtc,
    [Parameter(Mandatory)][string]$RequestPath,
    [Parameter(Mandatory)][string]$RequestSha256,
    [Parameter(Mandatory)][string]$JournalPath,
    [Parameter(Mandatory)][string]$JournalSha256,
    [Parameter(Mandatory)][string]$AgentLedgerPath,
    [Parameter(Mandatory)][string]$AgentPayloadHash,
    [Parameter(Mandatory)][string]$FailureDetails,
    [Parameter(Mandatory)][string]$ManualPromptEvidence,
    [switch]$ManualLoadOnceAcknowledged,
    [switch]$DryRun
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
Complete-MayaQaRunnerStartupFailureReconciliation @PSBoundParameters | ConvertTo-Json -Depth 12
