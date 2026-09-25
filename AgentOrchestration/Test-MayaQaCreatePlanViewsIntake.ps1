$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1'
Import-Module $module -Force

$request = 'Create floor plan views for Levels 0, 1, and 2 at 1:100 using the architectural template, named by level'
$canonical = 'create-plan-views-v1'
$definition = Get-MayaQaWorkflowDefinition $canonical
if ($definition.TestId -ne $canonical -or $definition.NativeTestId -ne $canonical) { throw 'Create Plan Views identity mapping is incorrect.' }
$resolved = Resolve-MayaQaRequestWorkflow $request
if ($resolved -cne $canonical) { throw 'Natural-language Create Plan Views routing failed.' }

$intake = Invoke-MayaQaIntake 'task-plan-views-regression' 'workflow-plan-views-regression' $canonical $request -DryRun
if ($intake.QaWorkflowId -ne $canonical -or $intake.NativeTestId -ne $canonical) { throw 'Canonical intake identity was not preserved.' }
if ((@($intake.RequestIntent.SelectedLevels) -join ',') -ne '0,1,2' -or
    $intake.RequestIntent.ViewType -ne 'floor-plan' -or
    $intake.RequestIntent.Scale -ne '1:100' -or
    [string]::IsNullOrWhiteSpace([string]$intake.RequestIntent.CustomNamingIntent) -or
    [string]::IsNullOrWhiteSpace([string]$intake.RequestIntent.TemplateIntent)) { throw 'Create Plan Views request intent was not preserved.' }
if ($intake.RequiredApprovalStage -ne 'Maya approval after Tara QA passed') { throw 'Approval gate was not preserved.' }

$handoff = New-MayaQaHandoff 'C:\synthetic-plan-views-store' 'task-plan-views' 'workflow-plan-views' $canonical -DryRun
if ($handoff.QaWorkflowId -ne $canonical -or $handoff.NativeTestId -ne $canonical) { throw 'Handoff metadata identity was not preserved.' }

$unsupported = $false
try { Resolve-MayaQaRequestWorkflow 'Create schedules for Levels 0 and 1' | Out-Null } catch { $unsupported = $_.Exception.Message -match 'supported QA workflow' }
if (-not $unsupported) { throw 'Unsupported request was accepted.' }

$source = Get-Content -LiteralPath $module -Raw
$tara = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Raw
if ($tara -notmatch 'create-plan-views-v1' -or $tara -notmatch 'Repato.CreatePlanViews.TestRunner.addin') { throw 'Tara native runner mapping is missing.' }
if ($source -match '(?i)APPDATA|Start-Process.*Revit|Revit\.exe|Invoke-TaraRevit') { throw 'Synthetic intake path performs unsafe side effects.' }

'Maya Create Plan Views intake checks passed: 6'
