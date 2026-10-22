[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$SourceCommit,
    [Parameter(Mandatory)][string]$RuntimeReleaseRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$RuntimeManifestSha256,
    [Parameter(Mandatory)][string]$RollbackReleaseRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$RollbackManifestSha256,
    [Parameter(Mandatory)][string]$FixedFixturePath,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$ToolCommit,
    [Parameter(Mandatory)][string]$BundleParent
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvInstallerBundle.psm1') -Force
New-RepatoCpvInstallerBundle @PSBoundParameters | ConvertTo-Json -Depth 8
