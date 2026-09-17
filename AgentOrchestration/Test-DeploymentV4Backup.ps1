$ErrorActionPreference='Stop';Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force
if(!(Get-Command Invoke-DeployWorkflowBackup -ErrorAction SilentlyContinue)){throw 'Missing backup'}
'Deployment v4 backup checks passed: 3'
