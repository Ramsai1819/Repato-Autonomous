Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue

$script:MayaRepositoryRoot='C:\Repato-Autonomous\Source'
$script:MayaStages=@('queued','assigned','implementation','build-checks','qa','approval','completed')

function Assert-MayaTask($Task){Assert-RepatoTask $Task;if($Task.branchName-notmatch'^(feat|fix|qa|chore)/[a-z0-9][a-z0-9._/-]{0,95}$'){throw "Unsafe branch name: $($Task.branchName)"};if($Task.assignedAgent-and$Task.assignedAgent-notin @('Neil','Tara')){throw "Unknown assigned agent: $($Task.assignedAgent)"}}
function Get-MayaAssignment($Task){
    if($Task.assignedAgent){return [string]$Task.assignedAgent}
    $text=([string]$Task.title+' '+[string]$Task.description).ToLowerInvariant()
    if($text-match'build|qa|test|validation|regression|report|evidence'){return 'Tara'}
    'Neil'
}
function Get-MayaDecision($Task){[pscustomobject]@{TaskId=$Task.taskId;AssignedAgent=(Get-MayaAssignment $Task);CurrentStatus=$Task.status;WorkflowStage=$Task.workflowStage;BranchName=$Task.branchName;Reason=$(if((Get-MayaAssignment $Task)-ceq'Tara'){'Build/QA/validation intent'}else{'Implementation intent'})}}
function Get-MayaTasks([string]$StoreRoot){$data=Read-RepatoTaskStore $StoreRoot;foreach($task in $data.tasks){Assert-MayaTask $task};@($data.tasks)}

function Get-MayaCyclePreview([string]$StoreRoot){
    $tasks=Get-MayaTasks $StoreRoot;$decisions=@($tasks|Where-Object status -ceq 'queued'|ForEach-Object{Get-MayaDecision $_})
    [pscustomobject]@{Mode='DryRun';RepositoryRoot=$script:MayaRepositoryRoot;QueuedCount=$decisions.Count;Assignments=$decisions;SideEffectsPerformed=$false;ApprovalEscalations=@($tasks|Where-Object{$_.status-ceq'passed'-and$_.workflowStage-ceq'qa'-and$_.requiredApprovalLevel-ne'none'}|ForEach-Object{[pscustomobject]@{TaskId=$_.taskId;RequiredApprovalLevel=$_.requiredApprovalLevel}})}
}
function Invoke-MayaAssign([string]$StoreRoot,[string]$TaskId,[string]$Agent,[switch]$DryRun){
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;Assert-MayaTask $task;if($task.status-cne'queued'){throw 'Only queued tasks can be assigned.'};$expected=Get-MayaAssignment $task;if($Agent-and$Agent-cne$expected){throw "Agent $Agent does not match Maya classification ($expected)."};$target=if($Agent){$Agent}else{$expected};if($target-notin@('Neil','Tara')){throw 'Only Neil or Tara may be assigned.'};if(!$preview){$task.assignedAgent=$target;$task.status='in-progress';$task.workflowStage='assigned';$task.startedUtc=Get-RepatoUtc;Add-RepatoHistory $task 'maya-assigned' 'Maya' "agent=$target"};[pscustomobject]@{TaskId=$TaskId;AssignedAgent=$target;Status=$(if($preview){'queued'}else{'in-progress'});WorkflowStage=$(if($preview){'queued'}else{'assigned'});SideEffectsPerformed=(!$preview)}} -DryRun:$DryRun
}
function Get-MayaStatus([string]$StoreRoot,[string]$TaskId){$tasks=Get-MayaTasks $StoreRoot;if($TaskId){$tasks=@($tasks|Where-Object taskId -ceq $TaskId)};@($tasks|ForEach-Object{[pscustomobject]@{TaskId=$_.taskId;Title=$_.title;AssignedAgent=$_.assignedAgent;Status=$_.status;WorkflowStage=$_.workflowStage;BranchName=$_.branchName;Revision=$_.revision;Logs=@($_.logs);Reports=@($_.reportPaths);PendingApprovals=@($_.approvalRequests|Where-Object status -ceq 'pending');ExecutorRuns=@($_.executorRuns);NeilRuns=@($_.neilRuns);TaraRuns=@($_.taraRuns);ErrorDetails=$_.errorDetails;HistoryCount=@($_.history).Count}})}
function Invoke-MayaReconcile([string]$StoreRoot,[string]$TaskId,[switch]$DryRun){
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;Assert-MayaTask $task;$allRuns=@();foreach($run in @($task.executorRuns)){if($run){$allRuns+=$run}};foreach($run in @($task.neilRuns)){if($run){$run|Add-Member -NotePropertyName sourceAgent -NotePropertyValue 'Neil' -Force;$allRuns+=$run}};foreach($run in @($task.taraRuns)){if($run){$run|Add-Member -NotePropertyName sourceAgent -NotePropertyValue 'Tara' -Force;$allRuns+=$run}};$failed=@($allRuns|Where-Object { $_.status -eq 'failed' });if($failed.Count){if(!$preview-and$task.status-notin@('failed','completed')){$task.status='failed';$task.finishedUtc=Get-RepatoUtc;$task.errorDetails=if($failed[-1].errorDetails){$failed[-1].errorDetails}else{'Executor run failed.'};Add-RepatoHistory $task 'maya-reconciled-failed' 'Maya' "failedRuns=$($failed.Count)"};return [pscustomobject]@{TaskId=$TaskId;Outcome='failed';FailedRuns=$failed.Count;Status=$task.status;WorkflowStage=$task.workflowStage;Preserved=$true;SideEffectsPerformed=(!$preview)}}
        $successful=@();foreach($candidate in $allRuns){if([string]$candidate.status -eq 'passed' -or [string]$candidate.status -eq 'completed'){$successful+=$candidate}};$successful=@($successful|Sort-Object finishedUtc)
        if(!$successful.Count){return [pscustomobject]@{TaskId=$TaskId;Outcome='no-result';Status=$task.status;WorkflowStage=$task.workflowStage;SideEffectsPerformed=$false}}
        $latest=$successful[-1];$event=$null
        if($latest.sourceAgent-ceq'Neil'-or$latest.agent-ceq'Neil'){$event='Neil implementation result';if($task.workflowStage-ceq'implementation' -and !$preview){$task.workflowStage='build-checks';$task.assignedAgent='Tara';Add-RepatoHistory $task 'maya-reconciled-neil' 'Maya' 'Implementation passed; routed to Tara build checks.'}}
        elseif($task.workflowStage-ceq'build-checks'-and !$preview){$task.workflowStage='qa';$task.assignedAgent='Tara';Add-RepatoHistory $task 'maya-reconciled-build' 'Maya' 'Build passed; routed to Tara QA.';$event='Tara build result'}
        elseif($task.workflowStage-ceq'qa'-and !$preview){$task.status='passed';Add-RepatoHistory $task 'maya-reconciled-qa' 'Maya' 'QA result passed.';$event='Tara QA result'}
        [pscustomobject]@{TaskId=$TaskId;Outcome=$(if($event){$event}else{'already-reconciled'});Status=$task.status;WorkflowStage=$task.workflowStage;AssignedAgent=$task.assignedAgent;RunId=$latest.runId;SideEffectsPerformed=(!$preview)}
    } -DryRun:$DryRun
}
function Request-MayaApproval([string]$StoreRoot,[string]$TaskId,[string]$Action,[ValidateSet('maya','user')][string]$ApprovalLevel='maya',[int]$ExpiryMinutes=30,[switch]$DryRun){
    if($ApprovalLevel-ceq'user'-and$Action-notin @('production-commit','revit-launch','file-delete','addin-change','destructive-file-operation','disable-addins')){throw 'User approval is reserved for explicitly dangerous actions.'}
    $result=Request-RepatoTaskApproval $StoreRoot $TaskId $Action $ApprovalLevel -ExpiryMinutes $ExpiryMinutes -DryRun:$DryRun
    if($DryRun){[pscustomobject]@{TaskId=$TaskId;Action=$Action;RequiredLevel=$ApprovalLevel;Mode='DryRun';SideEffectsPerformed=$false}}
    else{$task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId;@($task.approvalRequests|Where-Object status -ceq 'pending')[-1]}
}
function Fail-MayaTask([string]$StoreRoot,[string]$TaskId,[string]$ErrorDetails,[switch]$DryRun){if([string]::IsNullOrWhiteSpace($ErrorDetails)){throw 'Failure details are required.'};Update-RepatoTask $StoreRoot $TaskId failed $null $null $null $ErrorDetails -DryRun:$DryRun}

Export-ModuleMember -Function Get-MayaCyclePreview,Invoke-MayaAssign,Get-MayaStatus,Invoke-MayaReconcile,Request-MayaApproval,Fail-MayaTask
