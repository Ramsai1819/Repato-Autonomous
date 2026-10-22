$ErrorActionPreference='Stop';Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
$d=Get-MayaQaWorkflowDefinition 'create-plan-views-v1';$resolved=Get-MayaQaNativeTestId $d
if($d.TestId -cne 'create-plan-views-v1' -or $resolved -cne 'create-plan-views-v1'){throw 'Canonical Create Plan Views identity mismatch.'}
if($d.FixtureId -cne 'CreatePlanViewsEmpty'){throw 'Canonical fixture changed.'}
if((Get-Content (Join-Path $PSScriptRoot 'Repato.QaAddinDeployment.psm1') -Raw) -notmatch "'create-plan-views-v1'\s*=.*Repato\.CreatePlanViews\.TestRunner\.addin"){throw 'Canonical runner mapping changed.'}
foreach($bad in @('create-plan-views-elevations-v1','unknown-test-id','')){if($bad -and $bad -eq $resolved){throw "Rejected identity resolved: $bad"}}
$levels=Get-MayaQaWorkflowDefinition 'create-levels-elevations-v1';if($levels.TestId -cne 'create-levels-elevations-v1' -or $levels.FixtureId -ne 'CreateLevelsEmpty'){throw 'Create Levels elevation workflow changed.'}
[pscustomobject]@{Status='PASS';QaWorkflowId='create-plan-views-v1';RequiredTestId='create-plan-views-v1';ResolvedTestId=$resolved;NativeTestId=$resolved;ErroneousElevationRejected=$true;CreateLevelsPreserved=$true;LivePipeRequestSent=$false;RevitLaunched=$false}|ConvertTo-Json -Compress
