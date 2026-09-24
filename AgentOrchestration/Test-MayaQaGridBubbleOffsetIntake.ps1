$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1'
Import-Module $module -Force

$canonical = 'grid-bubble-offset-v1'
$request = 'Offset the selected grid bubbles by 3000 mm on the left and right'
$intake = Invoke-MayaQaIntake 'task-grid-offset-regression' 'workflow-grid-offset-regression' $canonical $request -DryRun
if ((Resolve-MayaQaRequestWorkflow $request) -cne $canonical -or $intake.QaWorkflowId -cne $canonical) {
    throw 'Grid Bubble Offset routing did not preserve the canonical workflow.'
}
if ($intake.RequestIntent.GridSelection -cne 'selected-grids' -or $intake.RequestIntent.OffsetMillimetres -ne 3000) {
    throw 'Selected-grid or offset value intent was not preserved.'
}
if ((@($intake.RequestIntent.BubbleSides) -join ',') -ne 'left,right') {
    throw 'Left/right bubble-side intent was not preserved.'
}

$topBottom = Invoke-MayaQaIntake 'task-grid-offset-top-bottom' 'workflow-grid-offset-top-bottom' $canonical `
    'Offset the selected grid bubbles by 1250.5 mm on the top and bottom' -DryRun
if ($topBottom.RequestIntent.OffsetMillimetres -ne 1250.5 -or (@($topBottom.RequestIntent.BubbleSides) -join ',') -ne 'top,bottom') {
    throw 'Top/bottom or decimal offset intent was not preserved.'
}
if ($intake.RequiredApprovalStage -ne 'Maya approval after Tara QA passed') {
    throw 'Approval-required state was not preserved.'
}

$unsupported = $false
try { Resolve-MayaQaRequestWorkflow 'Offset the selected views by 3000 mm' | Out-Null } catch {
    $unsupported = $_.Exception.Message -match 'supported QA workflow'
}
if (-not $unsupported) { throw 'Unsupported request was accepted.' }

$handoff = New-MayaQaHandoff 'C:\synthetic-grid-offset-store' 'task-grid-offset' 'workflow-grid-offset' $canonical -DryRun
if ($handoff.HandoffStatus -ne 'planned' -or $handoff.SideEffectsPerformed) { throw 'Synthetic handoff was not side-effect free.' }

$source = Get-Content -LiteralPath $module -Raw
if ($source -notmatch "Approved qa-run approval is required before Tara handoff" -or $source -notmatch "QaApprovalStatus = 'approved'") {
    throw 'Approval or approved handoff gate is missing.'
}
if ($source -match '(?i)Start-Process.*Revit|Revit\.exe|Invoke-TaraRevit|APPDATA') {
    throw 'Synthetic path contains Revit launch or production APPDATA access.'
}
if ((Resolve-MayaQaRequestWorkflow 'Create Grids') -cne 'create-grids-world-axis-v1' -or
    (Resolve-MayaQaRequestWorkflow 'Show the left and right bubbles for the selected grids') -cne 'grid-bubble-visibility-v1' -or
    (Resolve-MayaQaRequestWorkflow 'Create three levels at 0, 3000, and 6000 mm') -cne 'create-levels-elevations-v1') {
    throw 'Existing Maya routing changed.'
}

'Maya Grid Bubble Offset intake checks passed: 7'
