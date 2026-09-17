$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$taskCli=Join-Path $PSScriptRoot 'Invoke-RepatoAgentTask.ps1';$executorCli=Join-Path $PSScriptRoot 'Invoke-RepatoAgentExecutor.ps1'
$root=Join-Path ([IO.Path]::GetTempPath()) ('Repato-ExecutorCli-'+[guid]::NewGuid().ToString('N'));$checks=0
function Run([string]$Cli,[string[]]$Arguments){$json=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Cli @Arguments 2>$null;if($LASTEXITCODE-ne0){throw "CLI failed: $($Arguments-join' ')"};if($json){$json|ConvertFrom-Json}}
function Check([string]$name,[bool]$condition){if(!$condition){throw "FAILED: $name"};$script:checks++;Write-Host "PASS $name"}
$null=Run $taskCli @('create','-TaskId','EXEC-CLI','-Title','Executor CLI','-Description','End-to-end dry executor','-BranchName','feat/executor-cli','-StoreRoot',$root)
$queued=Run $executorCli @('executor-list-queued','-StoreRoot',$root)
Check 'executor CLI reads queued tasks' ($queued.taskId-eq'EXEC-CLI')
$plan=Run $executorCli @('executor-plan','-TaskId','EXEC-CLI','-Agent','Neil','-Actions','validate-branch','-StoreRoot',$root)
$null=Run $executorCli @('executor-claim','-TaskId','EXEC-CLI','-ExecutionId',$plan.executionId,'-Agent','Neil','-StoreRoot',$root)
$null=Run $executorCli @('executor-validate','-TaskId','EXEC-CLI','-ExecutionId',$plan.executionId,'-StoreRoot',$root)
$preview=Run $executorCli @('executor-preview','-TaskId','EXEC-CLI','-ExecutionId',$plan.executionId,'-StoreRoot',$root)
Check 'executor CLI exact dry-run preview' ($preview.Mode-eq'DryRun'-and!$preview.SideEffectsPerformed-and$preview.WouldExecute[0].command-eq'git branch --show-current # expect feat/executor-cli')
$done=Run $executorCli @('executor-complete','-TaskId','EXEC-CLI','-ExecutionId',$plan.executionId,'-LogPaths','executor-cli.log','-ReportPaths','executor-cli.json','-StoreRoot',$root)
Check 'executor CLI records completion' ($done.status-eq'completed'-and$done.finishedUtc-and$done.logs[0]-eq'executor-cli.log')
Write-Host "$checks executor CLI checks passed; synthetic store: $root"
