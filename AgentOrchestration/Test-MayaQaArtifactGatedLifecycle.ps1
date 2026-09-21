$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
$store=Join-Path ([IO.Path]::GetTempPath()) ('maya-artifact-gate-'+[guid]::NewGuid().ToString('N'))
$boot=New-MayaQaBootstrap create-levels run-artifact-gate $store task-artifact-gate
$req=New-MayaQaBuildRequest $store $boot.TaskId $boot.WorkflowId create-levels create-levels
$wf=Get-DeployWorkflow $store $boot.TaskId $boot.WorkflowId
$build=Invoke-MayaQaBuildExecute $store $boot.TaskId $boot.WorkflowId create-levels
if($build.BuildStatus -ne 'succeeded' -or !$build.ArtifactSha256){throw 'Build evidence was not persisted.'}
$run=New-MayaQaRun $store $boot.TaskId $boot.WorkflowId create-levels run-artifact-gate
if($run.QaWorkflowId -ne 'create-levels'){throw 'QA run did not use artifact-gated workflow.'}
'Maya QA artifact-gated lifecycle checks passed: 6'
