$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
$store = Join-Path ([IO.Path]::GetTempPath()) ('maya-supervised-' + [guid]::NewGuid().ToString('N'))
$taskId = 'task-' + [guid]::NewGuid().ToString('N')
$workflowId = 'workflow-' + [guid]::NewGuid().ToString('N')
$runId = 'run-' + [guid]::NewGuid().ToString('N')
$intake = Invoke-MayaQaIntake $taskId $workflowId create-levels 'Run create-levels supervised QA'
if ($intake.QaWorkflowId -ne 'create-levels' -or $intake.SideEffectsPerformed) { throw 'QA intake mismatch.' }
$boot = New-MayaQaBootstrap create-levels $runId $store $taskId
if ($boot.TaskId -ne $taskId -or $boot.WorkflowId -eq '') { throw 'Bootstrap identity mismatch.' }
$request = New-MayaQaBuildRequest $store $taskId $boot.WorkflowId create-levels 'Run create-levels supervised QA'
$data = Read-RepatoTaskStore $store; $task = Find-RepatoTask $data $taskId; $workflow = Get-DeployWorkflow $store $taskId $boot.WorkflowId
@(Invoke-RepatoWorkflowMutation $store $taskId $boot.WorkflowId $workflow.workflowRevision $task.revision { param($current) $current | Add-Member -NotePropertyName qaBuildStatus -NotePropertyValue 'requested' -Force; return $current })[-1] | Out-Null
$build = Invoke-MayaQaBuildExecute $store $taskId $boot.WorkflowId create-levels
if ($build.BuildStatus -ne 'succeeded' -or [string]::IsNullOrWhiteSpace($build.ArtifactSha256)) { throw 'Neil build evidence mismatch.' }
$handoff = New-MayaQaHandoff $store $taskId $boot.WorkflowId create-levels
$plan = New-MayaQaRun $store $taskId $boot.WorkflowId create-levels $runId
$reports = Join-Path (Join-Path $PSScriptRoot '..\..\Source\QA') 'Reports'
$reportPath = Join-Path $reports ('supervised-' + [guid]::NewGuid().ToString('N') + '.json')
$report = [ordered]@{RunId=([guid]::NewGuid().ToString('N'));TestId='create-levels-elevations-v1';Status='Passed';DocumentPath=$plan.ModelPath;FixtureId=$plan.FixtureId;FixtureSha256=$plan.FixtureSha256;Assertions=@([pscustomobject]@{Id='supervised';Passed=$true});RollbackStatus='RolledBack';StartedUtc=(Get-Date).ToUniversalTime().AddSeconds(-1).ToString('O');FinishedUtc=(Get-Date).ToUniversalTime().ToString('O')}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$submitted = Submit-MayaQaReport $store $taskId $boot.WorkflowId create-levels $handoff.HandoffId $reportPath
if (!$submitted.Valid -or $submitted.SubmissionStatus -ne 'submitted') { throw 'Report submission failed.' }
$complete = Complete-MayaQaWorkflow $store $taskId $boot.WorkflowId
if ($complete.QaCompletionStatus -ne 'completed' -or $complete.CoordinatorRunId -eq $complete.NativeRunId) { throw 'Completion identity/status mismatch.' }
$receipt = New-MayaQaReceipt $store $taskId $boot.WorkflowId
$status = Get-MayaQaReceiptStatus $store $taskId $boot.WorkflowId create-levels
$dashboard = Get-MayaQaDashboard $store $taskId $boot.WorkflowId create-levels
if ($status.ReceiptStatus -ne 'Valid' -or $dashboard.ReceiptStatus -ne 'Valid') { throw 'Receipt/dashboard validation failed.' }
$duplicateReport = $false; try { Submit-MayaQaReport $store $taskId $boot.WorkflowId create-levels $handoff.HandoffId $reportPath | Out-Null } catch { $duplicateReport = $true }; if (!$duplicateReport) { throw 'Duplicate report accepted.' }
$duplicateComplete = $false; try { Complete-MayaQaWorkflow $store $taskId $boot.WorkflowId | Out-Null } catch { $duplicateComplete = $true }; if (!$duplicateComplete) { throw 'Duplicate completion accepted.' }
$badHandoff = $false; try { Submit-MayaQaReport $store $taskId $boot.WorkflowId create-levels 'handoff-invalid' $reportPath | Out-Null } catch { $badHandoff = $true }; if (!$badHandoff) { throw 'Invalid handoff accepted.' }
$dry = Submit-MayaQaReport $store $taskId $boot.WorkflowId create-levels $handoff.HandoffId $reportPath -DryRun
if ($dry.SideEffectsPerformed) { throw 'Dry-run performed side effects.' }
$missingBuild = $false; try { New-MayaQaRun $store ('missing-' + [guid]::NewGuid().ToString('N')) $boot.WorkflowId create-levels ('missing-' + [guid]::NewGuid().ToString('N')) | Out-Null } catch { $missingBuild = $true }; if (!$missingBuild) { throw 'Missing build evidence accepted.' }
'Maya QA supervised lifecycle checks passed: 12'
