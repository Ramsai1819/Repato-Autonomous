$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'
$here = $PSScriptRoot
Import-Module (Join-Path $here 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $here 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue

$root = Join-Path ([IO.Path]::GetTempPath()) ('repato-v4-apply-' + [guid]::NewGuid().ToString('N'))
$target = Join-Path $root 'target'
$store = Join-Path $root 'store'
$env:REPATO_AGENT_STORE_PATH = [IO.Path]::GetFullPath($store)
Write-Output ("EffectiveStorePath: {0}" -f $env:REPATO_AGENT_STORE_PATH)
Write-Output ("StoreFilePath: {0}" -f (Join-Path $env:REPATO_AGENT_STORE_PATH 'tasks.json'))
Write-Output ("User: {0}" -f [Environment]::UserName)
New-Item -ItemType Directory -Path $target -Force | Out-Null
$fixture = Join-Path $here 'DeploymentFixtures'
foreach($name in @('artifact.source','manifest.source','artifact.target','manifest.target')) { Copy-Item (Join-Path $fixture $name) (Join-Path $target $name) }

try {
  $id = 'V4-APPLY-' + [guid]::NewGuid().ToString('N')
  New-RepatoTask $store $id $id 'deployment' 'feat/maya-deployment-orchestration' 'maya' | Out-Null
  Claim-RepatoTask $store $id 'Neil' | Out-Null
  Update-RepatoTask $store $id 'in-progress' 'implementation' 'Neil' $null $null | Out-Null
  Update-RepatoTask $store $id 'in-progress' 'build-checks' 'Neil' $null $null | Out-Null
  Update-RepatoTask $store $id 'passed' 'qa' 'Tara' $null $null | Out-Null
  $plan = New-DeployPlan $store $id (Join-Path $target 'artifact.source') (Join-Path $target 'manifest.source') -TargetRoot $target
  $workflow = New-DeployWorkflow $store $plan
  $null = Request-DeployWorkflowApproval $store $id $workflow.workflowId
  $taskBeforeApproval = Find-RepatoTask (Read-RepatoTaskStore $store) $id
  $pending = @($taskBeforeApproval.approvalRequests | Where-Object { $_.status -eq 'pending' })
  if($pending.Count -ne 1) {
    $ids = ($taskBeforeApproval.approvalRequests | ForEach-Object { $_.requestId }) -join ', '
    throw "Expected exactly one pending approval for task $id; found $($pending.Count). ApprovalIds: $ids"
  }
  $workflow = Approve-DeployWorkflow $store $id $workflow.workflowId
  $validation = Validate-DeployWorkflowApproval $store $id $workflow.workflowId $workflow.approvalId
  $workflow = Invoke-DeployWorkflowBackup $store $id $workflow.workflowId $workflow.approvalId
  Write-Output ("BackupReturned: WorkflowId={0};Stage={1};WorkflowRevision={2};TaskRevision={3}" -f $workflow.workflowId,$workflow.stage,$workflow.workflowRevision,$workflow.taskRevision)
  $reloadedBackup = Get-DeployWorkflow $store $id $workflow.workflowId
  Write-Output ("BackupReloaded: WorkflowId={0};Stage={1};WorkflowRevision={2};TaskRevision={3}" -f $reloadedBackup.workflowId,$reloadedBackup.stage,$reloadedBackup.workflowRevision,$reloadedBackup.taskRevision)
  $rawStore = Get-Content (Join-Path $store 'tasks.json') -Raw
  $rawData = $rawStore | ConvertFrom-Json
  $rawMatches = @($rawData.tasks | ForEach-Object { @($_.deploymentWorkflows) } | Where-Object workflowId -eq $workflow.workflowId)
  Write-Output ("RawMatchingCount: {0}" -f $rawMatches.Count)
  foreach($rawWorkflow in $rawMatches){ Write-Output ("RawWorkflow: {0}" -f ($rawWorkflow | ConvertTo-Json -Compress -Depth 20)) }
  $dry = Invoke-DeployWorkflowApply $store $id $workflow.workflowId $workflow.approvalId -DryRun
  if($dry.sideEffectsPerformed){throw 'Dry-run reported side effects.'}
  $beforeNonce = $workflow.consumedNonce
  $workflow = Invoke-DeployWorkflowApply $store $id $workflow.workflowId $workflow.approvalId
  if($workflow.stage -ne 'applied'){throw 'Expected applied stage.'}
  $ah = (Get-FileHash (Join-Path $target 'artifact.target') -Algorithm SHA256).Hash
  $mh = (Get-FileHash (Join-Path $target 'manifest.target') -Algorithm SHA256).Hash
  if($ah -ne $plan.artifactSha256 -or $mh -ne $plan.manifestSha256){throw 'Applied hashes do not match sources.'}
  if($workflow.consumedNonce -ne $beforeNonce -or !$workflow.nonceConsumed){throw 'Nonce changed or was not consumed exactly once.'}
  if($workflow.appliedHashes.Count -ne 2){throw 'Applied evidence missing.'}
  'Deployment v4 apply checks passed: 8'
} finally {
  if(Test-Path -LiteralPath $root){ Remove-Item -LiteralPath $root -Recurse -Force }
}
