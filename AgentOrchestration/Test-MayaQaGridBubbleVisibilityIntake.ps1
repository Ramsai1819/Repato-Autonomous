$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1'
Import-Module $module -Force

$request = 'Show the left and right bubbles for the selected grids'
$canonical = 'grid-bubble-visibility-v1'
if ((Resolve-MayaQaRequestWorkflow $request) -cne $canonical) {
    throw 'Grid Bubble Visibility request did not resolve to the canonical workflow.'
}

$intake = Invoke-MayaQaIntake 'task-grid-bubbles-regression' 'workflow-grid-bubbles-regression' `
    $canonical $request -DryRun
if ($intake.QaWorkflowId -cne $canonical -or $intake.RequiredApprovalStage -ne 'Maya approval after Tara QA passed') {
    throw 'Canonical workflow or approval-required state was not preserved.'
}
if ($intake.RequestIntent.GridSelection -cne 'selected-grids') {
    throw 'Selected-grid intent was not preserved.'
}
if ((@($intake.RequestIntent.BubbleSides) -join ',') -ne 'left,right') {
    throw 'Left/right bubble-side intent was not preserved.'
}

$topBottom = Invoke-MayaQaIntake 'task-grid-bubbles-top-bottom' 'workflow-grid-bubbles-top-bottom' `
    $canonical 'Show the top and bottom bubbles for the selected grids' -DryRun
if ((@($topBottom.RequestIntent.BubbleSides) -join ',') -ne 'top,bottom') {
    throw 'Top/bottom bubble-side intent was not preserved.'
}

$orchestration = Invoke-MayaQaRequest -StoreRoot ([IO.Path]::GetTempPath()) -UserRequest $request -DryRun
if (!$orchestration.Success -or $orchestration.QaWorkflowId -cne $canonical -or $orchestration.SideEffectsPerformed) {
    throw 'Request orchestration did not preserve the canonical workflow.'
}

$unsupported = $false
try { Resolve-MayaQaRequestWorkflow 'Show the selected views' | Out-Null } catch {
    $unsupported = $_.Exception.Message -match 'supported QA workflow'
}
if (-not $unsupported) { throw 'Unsupported request was accepted.' }

$planned = New-MayaQaHandoff 'C:\synthetic-grid-bubbles-store' 'task-grid-bubbles' 'workflow-grid-bubbles' $canonical -DryRun
if ($planned.HandoffStatus -ne 'planned' -or $planned.SideEffectsPerformed) {
    throw 'Synthetic handoff planning was not side-effect free.'
}
$source = Get-Content -LiteralPath $module -Raw
if ($source -notmatch "Approved qa-run approval is required before Tara handoff" -or $source -notmatch "QaApprovalStatus = 'approved'") {
    throw 'Approved handoff gate/status is missing.'
}
if ($source -match '(?i)Start-Process.*Revit|Revit\.exe|Invoke-TaraRevit|APPDATA') {
    throw 'Synthetic test path contains Revit launch or production APPDATA access.'
}

if ((Resolve-MayaQaRequestWorkflow 'Create Grids') -cne 'create-grids-world-axis-v1') {
    throw 'Create Grids routing changed.'
}
if ((Resolve-MayaQaRequestWorkflow 'Create three levels at 0, 3000, and 6000 mm') -cne 'create-levels-elevations-v1') {
    throw 'Create Levels routing changed.'
}

'Maya Grid Bubble Visibility intake checks passed: 7'
