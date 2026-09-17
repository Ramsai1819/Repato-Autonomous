$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue
if(!(Get-Command Invoke-DeployWorkflowVerify -ErrorAction SilentlyContinue)){throw 'Verify API unavailable.'}
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1'),[ref]$null,[ref]$null)
$count=@($ast.FindAll({param($n)$n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-DeployWorkflowVerify'},$true)).Count
if($count -ne 1){throw "Expected one verify definition; found $count"}
'Deployment v4 verify checks passed: 2'
