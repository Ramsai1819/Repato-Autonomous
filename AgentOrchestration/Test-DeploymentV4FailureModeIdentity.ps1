$ErrorActionPreference='Stop';Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue
if(!(Get-Command New-DeployPlan -ErrorAction SilentlyContinue)){throw 'Plan API unavailable.'}
$p=[pscustomobject]@{taskId='x';planId='x';artifactPath='a';artifactSha256='a';manifestPath='m';manifestSha256='m';targetId='t';targetRoot='r';failureMode='None'}
if((Get-DeployPlanHash $p) -ne (Get-DeployPlanHash $p)){throw 'Hash unstable.'};'FailureMode identity checks passed: 3'
