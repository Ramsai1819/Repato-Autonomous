$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$cli=Join-Path $PSScriptRoot 'Invoke-RepatoAgentTask.ps1';$root=Join-Path ([IO.Path]::GetTempPath()) ('Repato-AgentCli-'+[guid]::NewGuid().ToString('N'));$checks=0
function Run([string[]]$Arguments){$json=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli @Arguments 2>$null;if($LASTEXITCODE-ne0){throw "CLI failed: $($Arguments-join' ')"};if($json){$json|ConvertFrom-Json}}
function Check([string]$name,[bool]$condition){if(!$condition){throw "FAILED: $name"};$script:checks++;Write-Host "PASS $name"}
$dry=Run @('create','-TaskId','CLI-DRY','-Title','Dry','-Description','Preview','-BranchName','feat/dry','-StoreRoot',$root,'-DryRun')
Check 'CLI dry run creates no store' ($dry.taskId-eq'CLI-DRY'-and!(Test-Path $root))
$null=Run @('create','-TaskId','CLI-001','-Title','CLI task','-Description','Exercise operations','-BranchName','feat/cli','-StoreRoot',$root)
$null=Run @('claim','-TaskId','CLI-001','-Agent','Neil','-StoreRoot',$root)
$null=Run @('update','-TaskId','CLI-001','-Stage','implementation','-LogPath','neil.log','-StoreRoot',$root)
$null=Run @('update','-TaskId','CLI-001','-Stage','build-checks','-StoreRoot',$root)
$null=Run @('update','-TaskId','CLI-001','-Stage','qa','-Status','passed','-Agent','Tara','-StoreRoot',$root)
$null=Run @('attach-report','-TaskId','CLI-001','-ReportPath','QA/Reports/cli.json','-Agent','Tara','-StoreRoot',$root)
$null=Run @('request-approval','-TaskId','CLI-001','-ApprovalAction','completion','-ApprovalLevel','maya','-StoreRoot',$root)
$null=Run @('approve','-TaskId','CLI-001','-Agent','Maya','-Reason','Reviewed','-StoreRoot',$root)
$done=Run @('complete','-TaskId','CLI-001','-StoreRoot',$root)
$listed=Run @('list','-TaskId','CLI-001','-StoreRoot',$root)
Check 'all CLI mutations complete workflow' ($done.status-eq'completed'-and$listed.status-eq'completed'-and$listed.reportPaths.Count-eq1)
Check 'queue and status stores exist' ((Test-Path (Join-Path $root 'tasks.json'))-and(Test-Path (Join-Path $root 'status.json')))
Write-Host "$checks CLI orchestration checks passed; synthetic store: $root"
