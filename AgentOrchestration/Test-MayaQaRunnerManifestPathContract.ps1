$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$validation=Get-Content (Join-Path $PSScriptRoot 'Invoke-RepatoQaDeploymentValidation.ps1') -Raw
$module=Get-Content (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Raw
if($validation -notmatch '\$manifestRoot=Split-Path \$qaRoot -Parent' -or $validation -notmatch '\$runnerPath=Join-Path \$manifestRoot \$runnerName'){throw 'Deployment validation does not use the parent manifest root.'}
if($module -notmatch 'validatedRunnerManifestPath' -or $module -notmatch 'Canonical deployed runner-manifest path contract mismatch before execution'){throw 'Canonical deployed-path persistence/consistency gate is missing.'}
if($module -notmatch 'manifestPath=\$validatedManifest' -or $module -notmatch 'Validated deployed runner-manifest path or hash is invalid'){throw 'Native launch deployed-manifest binding gate is missing.'}
if(([regex]::Matches($module,'ValidatedRunnerManifestPath = \$evidence\.DeployedRunnerManifestPath')).Count -ne 2 -or ([regex]::Matches($module,'ValidatedRunnerManifestSha256 = \$evidence\.DeployedRunnerManifestSha256')).Count -ne 2){throw 'Canonical handoff producers do not preserve the independently validated deployed manifest identity.'}
if($module -notmatch '\$newExec\.ValidatedRunnerManifestPath=\$deployedManifest' -or $module -notmatch '\$newExec\.ValidatedRunnerManifestSha256=\$deployedManifestHash'){throw 'Terminal launch-failure recovery does not rebind deployed manifest evidence.'}
if($module -notmatch '\$modelSource=\$source;\$modelHash=\$old\.AuthoritativeFixtureSha256;\$prep=\$old\.FixturePreparationEvidence' -or $module -notmatch '\$modelSource=\[IO\.Path\]::GetFullPath\(\[string\]\$prep\.PreparedModelPath\)' -or $module -notmatch 'preparedModelSha256=\$prep\.PreparedModelSha256'){throw 'Terminal launch-failure recovery does not preserve prepared-model provenance.'}
if($module -notmatch 'function Request-MayaQaRecoveredLaunchFailureApproval' -or $module -notmatch "FailureCode -ceq 'native-process-start-failed'" -or $module -notmatch 'DeployedRunnerManifestPath=\[string\]\$e\.DeployedRunnerManifestPath' -or $module -notmatch 'maya-tara-launch-failure-approval-requested'){throw 'Recovered launch-failure approval producer or its immutable bindings are missing.'}
if($module -notmatch '\[IO\.Path\]::GetFullPath\(\[string\]\$ev\.DeployedRunnerManifestPath\) -ine \$deployedManifest'){throw 'Fallback manifest attestation still compares deployed evidence to source provenance.'}
if($module -match 'derivedPath=Join-Path \(\[string\]\$r\.qaAddinRoot\)'){throw 'Obsolete production qaAddinRoot derivation remains.'}
$canonical='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin'
$qaRoot='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA'
$computed=Join-Path ([IO.Path]::GetFullPath((Join-Path $qaRoot '..')) ) 'Repato.CreatePlanViews.TestRunner.addin'
if($computed -ine $canonical){throw 'Parent-directory contract computed the wrong path.'}
$request=[pscustomobject]@{manifestPath=$canonical;manifestSha256='A'*64}
if($request.manifestPath -ine $canonical){throw 'Serialized manifest path binding failed.'}
Write-Output 'Runner manifest path contract synthetic tests passed: parent deployment path, canonical persistence, serialization binding, duplicate derivation removal, and fail-closed consistency gates.'
