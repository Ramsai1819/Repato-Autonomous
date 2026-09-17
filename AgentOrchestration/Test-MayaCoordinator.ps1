$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaCoordinator.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -WarningAction SilentlyContinue
$root=Join-Path ([IO.Path]::GetTempPath()) ('Repato-Maya-'+[guid]::NewGuid().ToString('N'));$checks=0;$branch=(Get-Content 'C:\Repato-Autonomous\Source\.git\HEAD' -Raw).Trim().Replace('ref: refs/heads/','')
function Check([string]$Name,[bool]$Condition){if(!$Condition){throw "FAILED: $Name"};$script:checks++;Write-Host "PASS $Name"}
function Reject([string]$Name,[scriptblock]$Action){try{&$Action;throw "FAILED: $Name accepted"}catch{if($_.Exception.Message-like'FAILED:*'){throw};$script:checks++;Write-Host "PASS $Name"}}
function NewTask([string]$Id,[string]$Title,[string]$Description,[string]$Stage='queued'){$null=New-RepatoTask $root $Id $Title $Description $branch maya;if($Stage-ne'queued'){$null=Claim-RepatoTask $root $Id Neil;$null=Update-RepatoTask $root $Id in-progress implementation Neil $null $null}}
Initialize-RepatoTaskStore $root|Out-Null

NewTask MAYA-IMPL 'Implement grid behavior' 'Neil implementation task';NewTask MAYA-QA 'Run regression QA' 'Tara build and QA validation task';$preview=Get-MayaCyclePreview $root
Check 'queued task discovery' ($preview.QueuedCount-eq2-and$preview.Assignments.Count-eq2)
Check 'implementation routed to Neil' (($preview.Assignments|Where-Object TaskId -ceq 'MAYA-IMPL').AssignedAgent-eq'Neil')
Check 'build QA routed to Tara' (($preview.Assignments|Where-Object TaskId -ceq 'MAYA-QA').AssignedAgent-eq'Tara')
$queueBefore=(Get-FileHash (Join-Path $root 'tasks.json') -Algorithm SHA256).Hash;$cycleDry=Get-MayaCyclePreview $root;$queueAfter=(Get-FileHash (Join-Path $root 'tasks.json') -Algorithm SHA256).Hash
Check 'cycle preview side-effect prevention' (!$cycleDry.SideEffectsPerformed-and$queueBefore-eq$queueAfter)
$assigned=Invoke-MayaAssign $root MAYA-IMPL;Check 'Neil assignment' ($assigned.AssignedAgent-eq'Neil'-and$assigned.WorkflowStage-eq'assigned')
$assignedQa=Invoke-MayaAssign $root MAYA-QA;Check 'Tara assignment' ($assignedQa.AssignedAgent-eq'Tara'-and$assignedQa.WorkflowStage-eq'assigned')
Reject 'duplicate assignment prevention' {Invoke-MayaAssign $root MAYA-IMPL|Out-Null}
Reject 'classification mismatch rejection' {NewTask MAYA-MISMATCH 'Run QA validation' 'QA';Invoke-MayaAssign $root MAYA-MISMATCH Neil|Out-Null}
NewTask MAYA-TRANSITION 'Implement transition' 'feature';$null=Claim-RepatoTask $root MAYA-TRANSITION Neil
Reject 'invalid workflow transition' {Update-RepatoTask $root MAYA-TRANSITION in-progress build-checks Neil $null $null|Out-Null}

NewTask MAYA-RECON 'Implement feature' 'Neil implementation';$null=Claim-RepatoTask $root MAYA-RECON Neil;$null=Update-RepatoTask $root MAYA-RECON in-progress implementation Neil $null $null
$q=Get-Content (Join-Path $root 'tasks.json') -Raw|ConvertFrom-Json;$task=$q.tasks|Where-Object taskId -ceq 'MAYA-RECON';$task|Add-Member -NotePropertyName neilRuns -NotePropertyValue @([pscustomobject]@{runId='n1';agent='Neil';status='passed';finishedUtc=(Get-RepatoUtc);errorDetails=$null});$q|ConvertTo-Json -Depth 30|Set-Content (Join-Path $root 'tasks.json') -Encoding UTF8;$r1=Invoke-MayaReconcile $root MAYA-RECON
Check 'Neil result reconciles to Tara build stage' ($r1.Outcome-eq'Neil implementation result'-and$r1.WorkflowStage-eq'build-checks'-and$r1.AssignedAgent-eq'Tara')
$q=Get-Content (Join-Path $root 'tasks.json') -Raw|ConvertFrom-Json;$task=$q.tasks|Where-Object taskId -ceq 'MAYA-RECON';$task|Add-Member -NotePropertyName taraRuns -NotePropertyValue @([pscustomobject]@{runId='t1';agent='Tara';status='passed';finishedUtc=(Get-RepatoUtc);errorDetails=$null});$q|ConvertTo-Json -Depth 30|Set-Content (Join-Path $root 'tasks.json') -Encoding UTF8;$r2=Invoke-MayaReconcile $root MAYA-RECON
Check 'Tara build result reconciles to QA stage' ($r2.WorkflowStage-eq'qa'-and$r2.Status-eq'in-progress')
$r3=Invoke-MayaReconcile $root MAYA-RECON;Check 'QA result reconciles to passed' ($r3.Status-eq'passed'-and$r3.WorkflowStage-eq'qa')

NewTask MAYA-APPROVAL 'Implement and QA' 'feature';$null=Claim-RepatoTask $root MAYA-APPROVAL Neil;$null=Update-RepatoTask $root MAYA-APPROVAL in-progress implementation Neil $null $null;$null=Update-RepatoTask $root MAYA-APPROVAL in-progress build-checks Neil $null $null;$null=Update-RepatoTask $root MAYA-APPROVAL in-progress qa Tara $null $null;$null=Update-RepatoTask $root MAYA-APPROVAL passed $null Tara $null $null
$approval=Request-MayaApproval $root MAYA-APPROVAL production-commit user;Check 'approval escalation' ($approval.requiredLevel-eq'user'-and$approval.action-eq'production-commit')
Reject 'Maya self-approval prevention' {Resolve-RepatoTaskApproval $root MAYA-APPROVAL approve Maya 'self approval'|Out-Null}
Reject 'invalid user approval action' {Request-MayaApproval $root MAYA-APPROVAL completion user|Out-Null}

$failed=NewTask MAYA-FAIL 'Implement risky change' 'feature';Fail-MayaTask $root MAYA-FAIL 'blocked by validation'|Out-Null;$failedTask=Get-MayaStatus $root MAYA-FAIL|Select-Object -First 1;Check 'failed-task preservation' ($failedTask.Status-eq'failed'-and$failedTask.ErrorDetails-eq'blocked by validation');Reject 'terminal failed task preserved' {Fail-MayaTask $root MAYA-FAIL 'second failure'|Out-Null}
$bad=Join-Path $root malformed;Initialize-RepatoTaskStore $bad|Out-Null;[IO.File]::WriteAllText((Join-Path $bad 'tasks.json'),'{bad');Reject 'malformed task rejection' {Get-MayaStatus $bad|Out-Null}
$lock=[IO.File]::Open((Join-Path $root 'store.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);try{Reject 'concurrent coordinator protection' {Invoke-MayaAssign $root MAYA-QA|Out-Null}}finally{$lock.Dispose()}
$unknown=Join-Path $PSScriptRoot 'Invoke-RepatoMayaCoordinator.ps1';$old=$ErrorActionPreference;$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $unknown maya-status -TaskId MAYA-IMPL -UnknownParam value -StoreRoot $root 2>$null|Out-Null;$exit=$LASTEXITCODE;$ErrorActionPreference=$old;Check 'invalid CLI argument rejection' ($exit-ne0)
Write-Host "$checks Maya coordinator checks passed; synthetic store: $root"
