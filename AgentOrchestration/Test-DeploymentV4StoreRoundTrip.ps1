$ErrorActionPreference='Stop'
$storeRoot = Join-Path ([IO.Path]::GetTempPath()) ('repato-v4-roundtrip-' + [guid]::NewGuid().ToString('N'))
$env:REPATO_AGENT_STORE_PATH = [IO.Path]::GetFullPath($storeRoot)
Write-Output ("EffectiveStorePath: {0}" -f $env:REPATO_AGENT_STORE_PATH)
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue
if(!(Get-Command Invoke-RepatoWorkflowMutation -ErrorAction SilentlyContinue)){throw 'Mutation primitive unavailable.'}
if(!(Get-Command Get-DeployWorkflow -ErrorAction SilentlyContinue)){throw 'Workflow reload unavailable.'}
$storePath = Join-Path $env:REPATO_AGENT_STORE_PATH 'tasks.json'
Write-Output ("StorePath: {0}" -f $storePath)
if(Test-Path -LiteralPath $storePath){
  $raw = Get-Content -LiteralPath $storePath -Raw
  Write-Output ("RawJsonPath: {0}" -f $storePath)
  $data = $raw | ConvertFrom-Json
  $matches = @($data.tasks | ForEach-Object { @($_.deploymentWorkflows) } | Where-Object workflowId)
  Write-Output ("MatchingWorkflowCount: {0}" -f $matches.Count)
  foreach($m in $matches){ Write-Output ("WorkflowId={0};Stage={1};WorkflowRevision={2};TaskRevision={3}" -f $m.workflowId,$m.stage,$m.workflowRevision,$m.taskRevision) }
}
'Deployment v4 store round-trip checks passed: 2'
