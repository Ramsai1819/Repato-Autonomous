$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1'
$m=Import-Module $path -Force -PassThru
$names='Invoke-RepatoWorkflowMutation','Get-DeployWorkflow','Get-DeployWorkflowPlan','New-DeployPlan','New-DeployWorkflow'
foreach($n in $names){if((Get-Command $n -ErrorAction SilentlyContinue).Module.Path -ne $path){throw "Import failed: $n"};if(([regex]::Matches((Get-Content $path -Raw),"function\s+$n\b")).Count -ne 1){throw "Definition count failed: $n"}}
if(([regex]::Matches((Get-Content $path -Raw),'Export-ModuleMember')).Count -ne 1){throw 'Export count failed'}
$ok=$false;try{Invoke-RepatoWorkflowMutation '' '' '' 0 0 $null}catch{if($_.Exception.Message -match 'transform'){$ok=$true}};if(!$ok){throw 'Null transform was not rejected'}
'Deployment v4 import checks passed: 4'
