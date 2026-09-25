$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1'
Import-Module $module -Force

$canonical = 'grid-resequence-v1'
$definition = Get-MayaQaWorkflowDefinition $canonical
if ($definition.TestId -ne $canonical -or $definition.NativeTestId -ne 'grid-resequence-all-directions-v1') {
    throw 'Grid Resequence canonical/native test ID mapping is incorrect.'
}
$requests = @{
    'bottom to top' = 'Resequence the grids from bottom to top'
    'top to bottom' = 'Resequence the grids from top to bottom'
    'left to right' = 'Resequence the grids from left to right'
    'right to left' = 'Resequence the grids from right to left'
}
foreach ($pair in $requests.GetEnumerator()) {
    $intake = Invoke-MayaQaIntake ('task-resequence-' + $pair.Key.Replace(' ', '-')) `
        ('workflow-resequence-' + $pair.Key.Replace(' ', '-')) 'grid-resequence-v1' $pair.Value -DryRun
    if ((Resolve-MayaQaRequestWorkflow $pair.Value) -cne $canonical -or $intake.QaWorkflowId -cne $canonical) {
        throw "Grid Resequence routing failed: $($pair.Value)"
    }
    $expectedDirection = switch ($pair.Key) {
        'bottom to top' { 'BottomToTop' }
        'top to bottom' { 'TopToBottom' }
        'left to right' { 'LeftToRight' }
        'right to left' { 'RightToLeft' }
    }
    if ($intake.RequestIntent.ResequenceDirection -cne $expectedDirection) {
        throw "Direction intent was not preserved: $($pair.Value)"
    }
}

$namedRequest = 'Resequence the grids from bottom to top, using custom naming starting at G1'
$named = Invoke-MayaQaIntake 'task-resequence-naming' 'workflow-resequence-naming' $canonical $namedRequest -DryRun
if ([string]::IsNullOrWhiteSpace([string]$named.RequestIntent.CustomNamingIntent) -or
    $named.RequestIntent.CustomNamingIntent -ne $namedRequest) {
    throw 'Custom naming intent was not preserved.'
}
if ($named.RequiredApprovalStage -ne 'Maya approval after Tara QA passed') {
    throw 'Approval-required state was not preserved.'
}
$handoff = New-MayaQaHandoff 'C:\synthetic-grid-resequence-store' 'task-grid-resequence' 'workflow-grid-resequence' $canonical -DryRun
if ($handoff.QaWorkflowId -ne $canonical -or $handoff.NativeTestId -ne 'grid-resequence-all-directions-v1') {
    throw 'Handoff did not preserve the expected canonical/native IDs.'
}

$unsupported = $false
try { Resolve-MayaQaRequestWorkflow 'Resequence the views from bottom to top' | Out-Null } catch {
    $unsupported = $_.Exception.Message -match 'supported QA workflow'
}
if (-not $unsupported) { throw 'Unsupported request was accepted.' }

$source = Get-Content -LiteralPath $module -Raw
if ($source -notmatch "Approved qa-run approval is required before Tara handoff") {
    throw 'Tara handoff approval gate is missing.'
}
if ($source -notmatch 'Get-MayaQaNativeTestId') { throw 'Tara native test ID mapping is not used.' }
if ($source -match '(?i)Start-Process.*Revit|Revit\.exe|Invoke-TaraRevit|APPDATA') {
    throw 'Synthetic path contains Revit launch or production APPDATA access.'
}

if ((Resolve-MayaQaRequestWorkflow 'Create Grids') -cne 'create-grids-world-axis-v1' -or
    (Resolve-MayaQaRequestWorkflow 'Show the left and right bubbles for the selected grids') -cne 'grid-bubble-visibility-v1' -or
    (Resolve-MayaQaRequestWorkflow 'Offset the selected grid bubbles by 3000 mm') -cne 'grid-bubble-offset-v1' -or
    (Resolve-MayaQaRequestWorkflow 'Create three levels at 0, 3000, and 6000 mm') -cne 'create-levels-elevations-v1') {
    throw 'Existing Maya routing changed.'
}

'Maya Grid Resequence intake checks passed: 6'
