$ErrorActionPreference='Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('DepApproval-'+[guid]::NewGuid().ToString('N'))
$dir = Join-Path $PSScriptRoot 'DeploymentFixtures'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.psm1') -Force
Initialize-RepatoTaskStore $root|Out-Null
New-RepatoTask $root DEP DEP deployment 'feat/local-deployment-executor' maya|Out-Null
Claim-RepatoTask $root DEP Neil|Out-Null
Update-RepatoTask $root DEP in-progress implementation Neil $null $null|Out-Null
Update-RepatoTask $root DEP in-progress build-checks Neil $null $null|Out-Null
Update-RepatoTask $root DEP passed qa Tara $null $null|Out-Null
$plan=New-DeployPlan $root DEP (Join-Path $dir 'artifact.source') (Join-Path $dir 'manifest.source') qa-local-fixture
$pending=Request-DeployApproval $root $plan
try{Validate-DeployApproval $root $plan $pending.requestId;throw 'pending accepted'}catch{}
Resolve-RepatoTaskApproval $root DEP approve Maya approved|Out-Null
$ok=Validate-DeployApproval $root $plan $pending.requestId
if(!$ok){throw 'approval failed'}
Consume-DeployApproval $root DEP $pending.requestId|Out-Null
try{Validate-DeployApproval $root $plan $pending.requestId;throw 'replay accepted'}catch{}
'Persisted deployment approval checks passed: 3'


