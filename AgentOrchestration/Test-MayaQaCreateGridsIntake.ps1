$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1'
Import-Module $module -Force

$canonical = 'create-grids-world-axis-v1'
$gridRequests = @(
    'Create eight grids on the world axis',
    'Create Grids',
    'Create Grids World Axis'
)
foreach ($request in $gridRequests) {
    if ((Resolve-MayaQaRequestWorkflow $request) -cne $canonical) {
        throw "Create Grids request did not resolve canonically: $request"
    }
}

$orchestration = Invoke-MayaQaRequest -StoreRoot ([IO.Path]::GetTempPath()) `
    -UserRequest 'Create eight grids on the world axis' -DryRun
if (!$orchestration.Success -or $orchestration.QaWorkflowId -cne $canonical -or $orchestration.SideEffectsPerformed) {
    throw 'Create Grids request orchestration did not preserve the canonical ID.'
}

$intake = Invoke-MayaQaIntake 'task-create-grids-regression' 'workflow-create-grids-regression' `
    $canonical 'Create Grids' -DryRun
if ($intake.QaWorkflowId -cne $canonical -or $intake.RequiredApprovalStage -ne 'Maya approval after Tara QA passed') {
    throw 'Create Grids approval-required intake state was not preserved.'
}

$unsupported = $false
try { Resolve-MayaQaRequestWorkflow 'Create three doors' | Out-Null } catch {
    $unsupported = $_.Exception.Message -match 'supported QA workflow'
}
if (-not $unsupported) { throw 'Unsupported request was accepted.' }

if ((Resolve-MayaQaRequestWorkflow 'Create three levels at 0, 3000, and 6000 mm') -cne 'create-levels-elevations-v1') {
    throw 'Existing Create Levels routing changed.'
}
$levels = Invoke-MayaQaIntake 'task-create-levels-regression' 'workflow-create-levels-regression' `
    'create-levels-elevations-v1' 'Create three levels at 0, 3000, and 6000 mm' -DryRun
if ($levels.QaWorkflowId -cne 'create-levels-elevations-v1' -or $levels.SideEffectsPerformed) {
    throw 'Existing Create Levels intake behavior changed.'
}

$source = Get-Content -LiteralPath $module -Raw
if ($source -match '(?i)Start-Process.*Revit|Revit\.exe|Invoke-TaraRevit') {
    throw 'Synthetic intake path contains a Revit launch.'
}
if ($source -match '(?i)APPDATA') { throw 'Synthetic intake path references production APPDATA.' }

'Maya Create Grids intake checks passed: 7'
