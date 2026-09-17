$ErrorActionPreference='Stop';Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force
foreach($n in 'Request-DeployWorkflowApproval','Approve-DeployWorkflow','Validate-DeployWorkflowApproval','Validate-DeployWorkflowConsumedApproval','Consume-DeployWorkflowApproval'){if(!(Get-Command $n -ErrorAction SilentlyContinue)){throw "Missing $n"}}
'Deployment v4 approval checks passed: 5'
