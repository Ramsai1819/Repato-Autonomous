$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1'
Import-Module $module -Force

$request = 'Create three levels at 0, 3000, and 6000 mm'
$resolved = Resolve-MayaQaRequestWorkflow $request
if ($resolved -cne 'create-levels-elevations-v1') { throw 'Create Levels request did not resolve to the canonical workflow.' }

$intake = Invoke-MayaQaIntake 'task-create-levels-regression' 'workflow-create-levels-regression' `
    'create-levels' $request -DryRun
if ($intake.QaWorkflowId -cne 'create-levels-elevations-v1' -or $intake.SideEffectsPerformed) {
    throw 'Valid Create Levels intake did not produce canonical, side-effect-free state.'
}
if ($intake.RequiredApprovalStage -ne 'Maya approval after Tara QA passed') {
    throw 'Approval-required state is missing.'
}

$rejected = $false
try { Resolve-MayaQaRequestWorkflow 'Create three doors' | Out-Null } catch { $rejected = $_.Exception.Message -match 'supported QA workflow' }
if (-not $rejected) { throw 'Unsupported request was accepted.' }

$bootstrap = New-MayaQaBootstrap 'create-levels' 'run-create-levels-regression' -DryRun
if ($bootstrap.QaWorkflowId -cne 'create-levels-elevations-v1' -or $bootstrap.SideEffectsPerformed) {
    throw 'Approved synthetic bootstrap did not preserve canonical workflow state.'
}

$handoffText = Get-Content $module -Raw
if ($handoffText -notmatch "Approved qa-run approval is required before Tara handoff") {
    throw 'Handoff approval gate is missing.'
}
if ($handoffText -match '(?i)Start-Process.*Revit|Revit\.exe|Invoke-TaraRevit') {
    throw 'Synthetic intake path contains a Revit launch.'
}

'Maya Create Levels intake checks passed: 5'
