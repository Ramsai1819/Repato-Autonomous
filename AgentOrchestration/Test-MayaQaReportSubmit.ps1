$ErrorActionPreference = 'Stop'
$store = Join-Path ([IO.Path]::GetTempPath()) ('maya-report-submit-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $store -Force | Out-Null
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
$taskId = 'task-' + [guid]::NewGuid().ToString('N')
$boot = New-MayaQaBootstrap create-levels ('run-' + [guid]::NewGuid().ToString('N')) $store $taskId
$null = New-MayaQaBuildRequest $boot.StoreRoot $boot.TaskId $boot.WorkflowId create-levels 'create-levels'
$data = Read-RepatoTaskStore $store
$task = Find-RepatoTask $data $taskId
$workflow = Get-DeployWorkflow $store $taskId $boot.WorkflowId
@(Invoke-RepatoWorkflowMutation $store $taskId $boot.WorkflowId $workflow.workflowRevision $task.revision { param($current) $current | Add-Member -NotePropertyName qaBuildStatus -NotePropertyValue 'requested' -Force; return $current })[-1] | Out-Null
$null = Invoke-MayaQaBuildExecute $store $taskId $boot.WorkflowId create-levels
$run = New-MayaQaRun $store $taskId $boot.WorkflowId create-levels ('qa-' + [guid]::NewGuid().ToString('N'))
$handoff = New-MayaQaHandoff $store $taskId $boot.WorkflowId create-levels
$reports = Join-Path (Join-Path $PSScriptRoot '..\..\Source\QA') 'Reports'
$reportPath = Join-Path $reports ('submit-' + [guid]::NewGuid().ToString('N') + '.json')
$report = [ordered]@{RunId=([guid]::NewGuid().ToString('N'));TestId='create-levels-elevations-v1';Status='Passed';DocumentPath=$run.ModelPath;FixtureId=$run.FixtureId;FixtureSha256=$run.FixtureSha256;Assertions=@([pscustomobject]@{Id='synthetic';Passed=$true});RollbackStatus='RolledBack';StartedUtc=(Get-Date).ToUniversalTime().AddSeconds(-1).ToString('O');FinishedUtc=(Get-Date).ToUniversalTime().ToString('O')}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$submitted = Submit-MayaQaReport $store $taskId $boot.WorkflowId create-levels $handoff.HandoffId $reportPath
if ($submitted.SubmissionStatus -ne 'submitted' -or !$submitted.Valid -or [string]::IsNullOrWhiteSpace($submitted.ReportSha256)) { throw 'Valid report submission failed.' }
$reloaded = Get-DeployWorkflow $store $taskId $boot.WorkflowId
if ($reloaded.qaReportPath -ne [IO.Path]::GetFullPath($reportPath) -or $reloaded.qaEvidence.NativeRunId -ne $report.RunId -or $reloaded.qaEvidence.CoordinatorRunId -ne $run.RunId) { throw 'Report evidence was not persisted.' }
$duplicate = $false; try { Submit-MayaQaReport $store $taskId $boot.WorkflowId create-levels $handoff.HandoffId $reportPath | Out-Null } catch { $duplicate = $true }; if (!$duplicate) { throw 'Duplicate report accepted.' }
$wrongHandoff = $false; try { Submit-MayaQaReport $store $taskId $boot.WorkflowId create-levels 'handoff-wrong' $reportPath | Out-Null } catch { $wrongHandoff = $true }; if (!$wrongHandoff) { throw 'Wrong handoff accepted.' }
$dry = Submit-MayaQaReport $store $taskId $boot.WorkflowId create-levels $handoff.HandoffId $reportPath -DryRun
if ($dry.SideEffectsPerformed -or $dry.SubmissionStatus -ne 'planned') { throw 'Dry-run changed state.' }
'Maya QA report-submit checks passed: 8'
