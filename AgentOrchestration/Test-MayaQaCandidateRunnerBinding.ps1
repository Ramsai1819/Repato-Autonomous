param([Parameter(Mandatory)][string]$CandidateDllPath,[string]$RevitInstallDir='E:\revit\Revit 2025')
$ErrorActionPreference='Stop'
$module=Join-Path $PSScriptRoot 'Repato.QaAddinDeployment.psm1'
Import-Module $module -Force -WarningAction SilentlyContinue
$manifest=Join-Path $PSScriptRoot '..\QA\Repato.CreatePlanViews.TestRunner.addin'
$old=Join-Path $PSScriptRoot '..\DeploymentCandidates\AgentBuilds\ReleaseCandidate-fcf624ee3ed1\Repato.Revit.dll'
$checks=0
try { Test-TaraCandidateRunnerBinding -CandidateDllPath $old -TrustedManifestPath $manifest -RevitInstallDir $RevitInstallDir | Out-Null; throw 'Frozen candidate unexpectedly contains the Create Plan Views runner.' } catch { if($_.Exception.Message -like 'Frozen candidate unexpectedly*'){throw}; $checks++ }
$binding=Test-TaraCandidateRunnerBinding -CandidateDllPath $CandidateDllPath -TrustedManifestPath $manifest -RevitInstallDir $RevitInstallDir
if(!$binding.Passed -or $binding.Class -cne 'Repato.Revit.TestRunner.CreatePlanViewsQaApplication' -or $binding.Interface -cne 'Autodesk.Revit.UI.IExternalApplication'){throw 'Compiled candidate binding did not match the exact manifest contract.'}
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('repato-binding-'+[guid]::NewGuid().ToString('N')+'.addin')
try {
  $xml=[xml](Get-Content -LiteralPath $manifest -Raw);$xml.RevitAddIns.AddIn.FullClassName='Repato.Revit.TestRunner.MissingApplication';$xml.Save($tmp)
  try { Test-TaraCandidateRunnerBinding -CandidateDllPath $CandidateDllPath -TrustedManifestPath $tmp -RevitInstallDir $RevitInstallDir | Out-Null; throw 'Mismatched manifest class was accepted.' } catch { if($_.Exception.Message -like 'Mismatched manifest*'){throw}; $checks++ }
} finally { if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force} }
[pscustomobject]@{Status='PASS';Assertions=$checks+1;OldFrozenCandidateRejected=$true;CompiledCandidate=$binding.CandidateSha256;Class=$binding.Class;ImplementsIExternalApplication=$true;ManifestHash=$binding.ManifestSha256;RealDeploymentPerformed=$false;RevitLaunched=$false} | ConvertTo-Json -Compress
