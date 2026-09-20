$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'
$cli = Join-Path $PSScriptRoot 'Invoke-MayaQaWorkflow.ps1'
function Invoke-Overview([string[]] $Arguments) {
    $output = & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $cli @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Overview command failed: $($Arguments -join ' ')" }
    $text = ($output -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'Overview command returned empty stdout.' }
    return ($text | ConvertFrom-Json)
}
$catalog = Invoke-Overview @('-Operation','qa-overview','-Route','qa-catalog-dry-run','-DryRun')
if ($catalog.Operation -ne 'qa-catalog-dry-run' -or $catalog.ResultStatus -ne 'ok' -or $catalog.SideEffectsPerformed -or @($catalog.Result.Workflows).Count -ne 6) { throw 'Catalog overview envelope mismatch.' }
$dashboard = Invoke-Overview @('-Operation','qa-overview','-Route','qa-dashboard','-StoreRoot','unused','-TaskId','unused','-WorkflowId','unused','-QaWorkflowId','create-levels','-DryRun')
if ($dashboard.Operation -ne 'qa-dashboard' -or $dashboard.ResultStatus -ne 'ok' -or $dashboard.SideEffectsPerformed) { throw 'Dashboard overview dry-run mismatch.' }
foreach ($route in @('qa-status','qa-receipt-status')) {
    $failed = $false
    try { Invoke-Overview @('-Operation','qa-overview','-Route',$route,'-StoreRoot','missing','-TaskId','missing','-WorkflowId','missing','-QaWorkflowId','create-levels','-DryRun') | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw "Invalid identity accepted for $route." }
}
$unsupported = $false
try { Invoke-Overview @('-Operation','qa-overview','-Route','qa-catalog-dry-run','-WorkflowId','create-plan-views','-DryRun') | Out-Null } catch { $unsupported = $true }
if (-not $unsupported) { throw 'Unsupported workflow accepted.' }
$invalidOperation = $false
try { & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $cli -Operation qa-overview -Route qa-unknown 2>$null | Out-Null; if ($LASTEXITCODE -ne 0) { $invalidOperation = $true } } catch { $invalidOperation = $true }
if (-not $invalidOperation) { throw 'Unsupported route accepted.' }
$text = Get-Content (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Raw
if ($text -notmatch 'Invoke-MayaQaOverview') { throw 'Overview API missing.' }
'Maya QA overview checks passed: 16'
