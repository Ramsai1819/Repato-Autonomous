$ErrorActionPreference='Stop'
$m=Get-Content (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Raw
if($m -notmatch 'RunnerManifest=\$runnerPath' -or $m -notmatch 'ValidatedRunnerManifestPath=\$validatedPath' -or $m -notmatch 'manifestPath=\$validatedManifest'){throw 'Canonical preflight does not select validated runner manifest evidence.'}
if($m -notmatch 'RunnerManifestSha256'){throw 'Canonical preflight runner manifest hash binding is missing.'}
$qaRoot='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025';$runner=Join-Path $qaRoot 'Repato.CreatePlanViews.TestRunner.addin';$candidate='C:\Repato-Autonomous\Source\DeploymentCandidates\AgentBuilds\ReleaseCandidate-fcf624ee3ed1\Repato.addin'
$under=$runner.StartsWith($qaRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase);$candidateUnder=$candidate.StartsWith($qaRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)
if(!$under -or $candidateUnder){throw 'Manifest boundary synthetic predicate failed.'}
[pscustomobject]@{Status='PASS';ManifestPath=$runner;ManifestUnderQaProfileRoot=$under;FrozenBuildManifestRejected=(!$candidateUnder);LivePipeRequestSent=$false;RevitLaunched=$false}|ConvertTo-Json -Compress
