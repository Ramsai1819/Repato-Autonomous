$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
$root=Join-Path ([IO.Path]::GetTempPath()) ('Repato-AgentTasks-'+[guid]::NewGuid().ToString('N'));$checks=0
function Check([string]$name,[bool]$condition){if(!$condition){throw "FAILED: $name"};$script:checks++;Write-Host "PASS $name"}
function Reject([string]$name,[scriptblock]$action){try{&$action;throw "FAILED: $name accepted"}catch{if($_.Exception.Message-like'FAILED:*'){throw};$script:checks++;Write-Host "PASS $name"}}
Initialize-RepatoTaskStore $root|Out-Null
$task=New-RepatoTask $root REP-001 'Task one' 'Description' 'feat/rep-001' maya
Check 'task creation' ($task.status-eq'queued'-and(Test-Path (Join-Path $root 'status.json')))
Reject 'duplicate task IDs' {New-RepatoTask $root REP-001 duplicate duplicate 'feat/duplicate' maya|Out-Null}
$task=Claim-RepatoTask $root REP-001 Neil
Check 'agent assignment' ($task.assignedAgent-eq'Neil'-and$task.workflowStage-eq'assigned'-and$task.startedUtc)
Reject 'workflow stage skipping' {Update-RepatoTask $root REP-001 in-progress qa Neil $null $null|Out-Null}
Reject 'generic completion bypass' {Update-RepatoTask $root REP-001 completed completed Neil $null $null|Out-Null}
$task=Update-RepatoTask $root REP-001 in-progress implementation Neil 'neil.log' $null
$task=Update-RepatoTask $root REP-001 in-progress build-checks Neil $null $null
$task=Update-RepatoTask $root REP-001 passed qa Tara $null $null
Check 'state transitions' ($task.status-eq'passed'-and$task.workflowStage-eq'qa')
$task=Add-RepatoTaskReport $root REP-001 'QA/Reports/rep-001.json' Tara
Check 'report attachment' ($task.reportPaths.Count-eq 1-and$task.reportPaths[0]-eq'QA/Reports/rep-001.json')
Reject 'dangerous action needs user approval' {Request-RepatoTaskApproval $root REP-001 production-commit maya|Out-Null}
$task=Request-RepatoTaskApproval $root REP-001 production-commit user
Reject 'Maya cannot grant user approval' {Resolve-RepatoTaskApproval $root REP-001 approve Maya no|Out-Null}
$task=Resolve-RepatoTaskApproval $root REP-001 approve user approved
Check 'approval gate' ($task.approvalRequests[0].status-eq'approved'-and$task.status-eq'passed')
$task=Complete-RepatoTask $root REP-001
Check 'completion' ($task.status-eq'completed'-and$task.finishedUtc)

$failed=New-RepatoTask $root REP-FAIL 'Failure' 'Preserve failure' 'feat/fail' none
$null=Claim-RepatoTask $root REP-FAIL Neil
$failed=Update-RepatoTask $root REP-FAIL failed implementation Neil 'failure.log' 'compiler failed'
Reject 'failed task is terminal' {Update-RepatoTask $root REP-FAIL in-progress implementation Neil $null $null|Out-Null}
$stored=(Get-RepatoTasks $root REP-FAIL)[0]
Check 'failed-task preservation' ($stored.errorDetails-eq'compiler failed'-and$stored.logs[0]-eq'failure.log'-and$stored.finishedUtc)

$rejected=New-RepatoTask $root REP-REJECT 'Rejected' 'Preserve rejection' 'feat/reject' maya
$null=Claim-RepatoTask $root REP-REJECT Tara
$null=Update-RepatoTask $root REP-REJECT in-progress implementation Tara $null $null
$null=Update-RepatoTask $root REP-REJECT in-progress build-checks Tara $null $null
$null=Update-RepatoTask $root REP-REJECT passed qa Tara $null $null
$null=Request-RepatoTaskApproval $root REP-REJECT completion maya
$rejected=Resolve-RepatoTaskApproval $root REP-REJECT reject Maya 'Needs correction'
Check 'rejected approval blocks and preserves reason' ($rejected.status-eq'blocked'-and$rejected.approvalRequests[0].reason-eq'Needs correction')

$dryRoot=Join-Path $root 'dry';$preview=New-RepatoTask $dryRoot REP-DRY 'Dry run' 'No writes' 'feat/dry' maya -DryRun
Check 'dry-run safety' ($preview.taskId-eq'REP-DRY'-and!(Test-Path $dryRoot))
[IO.File]::WriteAllText((Join-Path $root 'tasks.json'),'{bad')
Reject 'malformed task data' {Read-RepatoTaskStore $root|Out-Null}
Write-Host "$checks agent orchestration checks passed; synthetic store: $root"
