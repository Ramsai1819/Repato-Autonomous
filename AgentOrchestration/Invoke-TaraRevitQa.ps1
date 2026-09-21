[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StoreRoot,
    [Parameter(Mandatory)][string]$TaskId,
    [Parameter(Mandatory)][string]$WorkflowId,
    [Parameter(Mandatory)][string]$QaWorkflowId,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$ModelPath,
    [Parameter(Mandatory)][string]$SidecarPath,
    [Parameter(Mandatory)][string]$ReportDirectory,
    [string]$RevitInstallDir='E:\revit\Revit 2025',
    [Parameter(Mandatory)][string]$QaAddinRoot,
    [ValidateRange(1,3600)][int]$TimeoutSeconds=900,
    [switch]$LocalRun,
    [switch]$DryRun,
    [switch]$IntegrationTest
)
$ErrorActionPreference='Stop'
# Store gates and duplicate protection cannot be bypassed by the standalone entry point.
& (Join-Path $PSScriptRoot 'Invoke-MayaQaWorkflow.ps1') -Operation qa-tara-execute @PSBoundParameters
