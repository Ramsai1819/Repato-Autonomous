$ErrorActionPreference = 'Stop'
$source = Get-Content (Join-Path $PSScriptRoot 'MayaQa.TaraExecution.ps1') -Raw
$wrapper = Get-Content 'C:\Repato-Autonomous\AgentWork\Run-PreparedCreatePlanViewsQa.ps1' -Raw

function Assert-True([bool]$value, [string]$message) { if (!$value) { throw $message } }

$guard = "Canonical Maya Tara attempt exists without an execution record; legacy Tara dispatch is forbidden."
$guardAt = $source.IndexOf($guard, [StringComparison]::Ordinal)
$legacyAt = $source.IndexOf('$definition = Get-MayaQaWorkflowDefinition $QaWorkflowId', [StringComparison]::Ordinal)
$mutationAt = $source.IndexOf('$null = Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId', [StringComparison]::Ordinal)
$planAt = $source.IndexOf('$plan = New-TaraRevitQaPlan', [StringComparison]::Ordinal)
$canonicalAt = $source.IndexOf("if ($canonicalTask.PSObject.Properties.Name -contains 'mayaTaraExecution'", [StringComparison]::Ordinal)

Assert-True ($guardAt -gt $canonicalAt) 'Guard is not after canonical dispatch detection.'
Assert-True ($guardAt -lt $legacyAt -and $guardAt -lt $mutationAt -and $guardAt -lt $planAt) 'Guard is after a legacy side-effect boundary.'
Assert-True ($source.Contains('if ([string]::IsNullOrWhiteSpace([string]$canonical.ClaimId)) { throw ''Canonical Maya execution is not claimed.'' }')) 'Canonical claim gate changed or disappeared.'
Assert-True ($source.Contains('$canonicalTask.PSObject.Properties.Name -contains ''mayaTaraAttempt''')) 'Attempt-presence guard is missing.'
Assert-True ($source.Contains('$properties -contains ''qaTaraExecutionStatus''')) 'Legacy duplicate-execution guard disappeared.'

Assert-True ($wrapper.Contains('$reportingException = $null')) 'Wrapper reporting exception capture is missing.'
Assert-True ($wrapper.Contains('ReportingException=$reportingException')) 'Wrapper does not report post-execution inspection failures.'
Assert-True ($wrapper.Contains('$afterExecution = if ($afterTask.PSObject.Properties.Name -contains ''mayaTaraExecution'')')) 'Wrapper null-safe execution inspection is missing.'
Assert-True (([regex]::Matches($wrapper, 'Invoke-MayaQaTaraExecute')).Count -eq 1) 'Wrapper Tara execution path count changed.'

[pscustomobject]@{
    GuardBeforeLegacyMutation = $true
    CanonicalClaimPathPreserved = $true
    LegacyOnlyPathPreserved = $true
    WrapperExceptionReporting = $true
    TaraExecutionPathCount = 1
    RealQaExecuted = $false
    RealStoreMutated = $false
} | ConvertTo-Json -Compress
