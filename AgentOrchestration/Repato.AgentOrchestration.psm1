Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TaskStatuses = @('queued','in-progress','blocked','failed','passed','awaiting-approval','completed')
$script:WorkflowStages = @('queued','assigned','implementation','build-checks','qa','approval','completed')
$script:Agents = @('Maya','Neil','Tara')
$script:ApprovalLevels = @('none','maya','user')
$script:DangerousActions = @('production-commit','revit-launch','destructive-file-operation','disable-addins')

function Get-RepatoUtc { [DateTimeOffset]::UtcNow.ToString('O') }

function Assert-RepatoValue([string]$Name,[string]$Value,[string[]]$Allowed) {
    if ($Value -cnotin $Allowed) { throw "$Name must be one of: $($Allowed -join ', ')." }
}

function Get-RepatoStorePaths([string]$StoreRoot) {
    $root = [IO.Path]::GetFullPath($StoreRoot)
    [pscustomobject]@{ Root=$root; Queue=(Join-Path $root 'tasks.json'); Status=(Join-Path $root 'status.json'); Lock=(Join-Path $root 'store.lock') }
}

function Write-RepatoJsonAtomic([string]$Path,$Value) {
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.partial'
    try {
        $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temporary -Encoding UTF8
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}

function Initialize-RepatoTaskStore([string]$StoreRoot,[switch]$DryRun) {
    $paths = Get-RepatoStorePaths $StoreRoot
    if ($DryRun) { return $paths }
    New-Item -ItemType Directory -Path $paths.Root -Force | Out-Null
    if (!(Test-Path -LiteralPath $paths.Queue)) { Write-RepatoJsonAtomic $paths.Queue ([ordered]@{schemaVersion=1;tasks=@()}) }
    if (!(Test-Path -LiteralPath $paths.Status)) { Write-RepatoJsonAtomic $paths.Status ([ordered]@{schemaVersion=1;updatedUtc=(Get-RepatoUtc);tasks=[ordered]@{}}) }
    $paths
}

function Assert-RepatoTask($Task) {
    $required = @('taskId','title','description','assignedAgent','status','workflowStage','branchName','createdUtc','startedUtc','finishedUtc','logs','reportPaths','errorDetails','requiredApprovalLevel','approvalRequests','history')
    foreach ($name in $required) { if ($Task.PSObject.Properties.Name -notcontains $name) { throw "Malformed task: missing $name." } }
    if ($Task.taskId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,63}$') { throw 'Malformed task ID.' }
    if ([string]::IsNullOrWhiteSpace($Task.title) -or [string]::IsNullOrWhiteSpace($Task.description) -or [string]::IsNullOrWhiteSpace($Task.branchName)) { throw 'Malformed task text or branch.' }
    Assert-RepatoValue Status ([string]$Task.status) $script:TaskStatuses
    Assert-RepatoValue WorkflowStage ([string]$Task.workflowStage) $script:WorkflowStages
    if ($Task.assignedAgent) { Assert-RepatoValue AssignedAgent ([string]$Task.assignedAgent) $script:Agents }
    Assert-RepatoValue RequiredApprovalLevel ([string]$Task.requiredApprovalLevel) $script:ApprovalLevels
    foreach ($name in @('logs','reportPaths','approvalRequests','history')) { if ($Task.$name -isnot [Array]) { throw "Malformed task: $name must be an array." } }
    $null = [DateTimeOffset]::Parse($Task.createdUtc)
}

function Read-RepatoTaskStore([string]$StoreRoot) {
    $paths = Get-RepatoStorePaths $StoreRoot
    if (!(Test-Path -LiteralPath $paths.Queue -PathType Leaf)) { throw "Task queue does not exist: $($paths.Queue)" }
    try { $data = Get-Content -LiteralPath $paths.Queue -Raw | ConvertFrom-Json }
    catch { throw "Malformed task queue JSON: $($_.Exception.Message)" }
    if ($data.schemaVersion -ne 1 -or $data.PSObject.Properties.Name -notcontains 'tasks' -or $data.tasks -isnot [Array]) { throw 'Malformed task queue root.' }
    $seen = @{}
    foreach ($task in $data.tasks) {
        Assert-RepatoTask $task
        if ($seen.ContainsKey($task.taskId)) { throw "Duplicate task ID in store: $($task.taskId)" }
        $seen[$task.taskId] = $true
    }
    $data
}

function Write-RepatoTaskStore([string]$StoreRoot,$Data) {
    $paths = Get-RepatoStorePaths $StoreRoot
    $summaries = [ordered]@{}
    foreach ($task in $Data.tasks) {
        $summaries[$task.taskId] = [ordered]@{status=$task.status;workflowStage=$task.workflowStage;assignedAgent=$task.assignedAgent;branchName=$task.branchName;updatedUtc=$task.history[-1].timestampUtc}
    }
    Write-RepatoJsonAtomic $paths.Queue $Data
    Write-RepatoJsonAtomic $paths.Status ([ordered]@{schemaVersion=1;updatedUtc=(Get-RepatoUtc);tasks=$summaries})
}

function Invoke-RepatoStoreMutation([string]$StoreRoot,[scriptblock]$Mutation,[switch]$DryRun) {
    if ($DryRun) {
        $paths = Get-RepatoStorePaths $StoreRoot
        $data = if (Test-Path -LiteralPath $paths.Queue) { Read-RepatoTaskStore $StoreRoot } else { [pscustomobject]@{schemaVersion=1;tasks=[object[]]@()} }
        return & $Mutation $data $true
    }
    $paths = Initialize-RepatoTaskStore $StoreRoot
    $lock = $null
    try {
        $lock = [IO.File]::Open($paths.Lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $data = Read-RepatoTaskStore $StoreRoot
        $result = & $Mutation $data $false
        Write-RepatoTaskStore $StoreRoot $data
        return $result
    } finally { if ($lock) { $lock.Dispose() } }
}

function Add-RepatoHistory($Task,[string]$Event,[string]$Actor,[string]$Details) {
    $Task.history = [object[]]@($Task.history) + [pscustomobject]@{timestampUtc=(Get-RepatoUtc);event=$Event;actor=$Actor;details=$Details}
}

function Find-RepatoTask($Data,[string]$TaskId) {
    $matches = @($Data.tasks | Where-Object taskId -ceq $TaskId)
    if ($matches.Count -ne 1) { throw "Task not found: $TaskId" }
    $matches[0]
}

function New-RepatoTask {
    param([string]$StoreRoot,[string]$TaskId,[string]$Title,[string]$Description,[string]$BranchName,[ValidateSet('none','maya','user')][string]$RequiredApprovalLevel='maya',[switch]$DryRun)
    Invoke-RepatoStoreMutation $StoreRoot {
        param($data,$preview)
        if (@($data.tasks | Where-Object taskId -ceq $TaskId).Count) { throw "Duplicate task ID: $TaskId" }
        if ($TaskId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,63}$') { throw 'Task ID must be 3-64 safe characters.' }
        $now=Get-RepatoUtc
        $task=[pscustomobject][ordered]@{taskId=$TaskId;title=$Title;description=$Description;assignedAgent=$null;status='queued';workflowStage='queued';branchName=$BranchName;createdUtc=$now;startedUtc=$null;finishedUtc=$null;logs=[object[]]@();reportPaths=[object[]]@();errorDetails=$null;requiredApprovalLevel=$RequiredApprovalLevel;approvalRequests=[object[]]@();history=[object[]]@([pscustomobject]@{timestampUtc=$now;event='created';actor='Maya';details=$(if($preview){'dry-run preview'}else{'task queued'})})}
        Assert-RepatoTask $task
        if(!$preview){$data.tasks=[object[]]@($data.tasks)+$task}
        $task
    } -DryRun:$DryRun
}

function Get-RepatoTasks([string]$StoreRoot,[string]$TaskId) {
    $data=Read-RepatoTaskStore $StoreRoot
    if($TaskId){@($data.tasks|Where-Object taskId -ceq $TaskId)}else{@($data.tasks)}
}

function Claim-RepatoTask([string]$StoreRoot,[string]$TaskId,[string]$Agent,[switch]$DryRun) {
    Assert-RepatoValue Agent $Agent $script:Agents
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;if($task.status-cne'queued'){throw 'Only queued tasks can be claimed.'};$task.assignedAgent=$Agent;$task.status='in-progress';$task.workflowStage='assigned';$task.startedUtc=Get-RepatoUtc;Add-RepatoHistory $task 'claimed' $Agent $(if($preview){'dry-run preview'}else{'assigned'});$task} -DryRun:$DryRun
}

function Update-RepatoTask {
    param([string]$StoreRoot,[string]$TaskId,[string]$Status,[string]$WorkflowStage,[string]$Agent,[string]$LogPath,[string]$ErrorDetails,[switch]$DryRun)
    Invoke-RepatoStoreMutation $StoreRoot {
        param($data,$preview);$task=Find-RepatoTask $data $TaskId
        if($task.status -in @('completed','failed')){throw 'Completed and failed tasks are preserved and terminal.'}
        if($Agent){Assert-RepatoValue Agent $Agent $script:Agents;$task.assignedAgent=$Agent}
        if($Status){Assert-RepatoValue Status $Status $script:TaskStatuses;if($Status -in @('awaiting-approval','completed')){throw 'Use the dedicated approval or completion command for this status.'};$task.status=$Status}
        if($WorkflowStage){Assert-RepatoValue WorkflowStage $WorkflowStage $script:WorkflowStages;$old=[array]::IndexOf($script:WorkflowStages,[string]$task.workflowStage);$new=[array]::IndexOf($script:WorkflowStages,$WorkflowStage);if($new-lt$old-and$task.status-cne'blocked'){throw 'Workflow stages cannot move backward.'};if($new-gt($old+1)){throw 'Workflow stages cannot be skipped.'};if($WorkflowStage -in @('approval','completed')){throw 'Use the dedicated approval or completion command for this stage.'};$task.workflowStage=$WorkflowStage}
        if($task.status -ceq 'passed' -and $task.workflowStage -cne 'qa'){throw 'Passed status requires the QA stage.'}
        if($LogPath){$task.logs=[object[]]@($task.logs)+$LogPath}
        if($ErrorDetails){$task.errorDetails=$ErrorDetails}
        if($task.status-ceq'failed'){if([string]::IsNullOrWhiteSpace($task.errorDetails)){throw 'Failed tasks require error details.'};$task.finishedUtc=Get-RepatoUtc}
        Add-RepatoHistory $task 'updated' $(if($Agent){$Agent}else{'Maya'}) $(if($preview){'dry-run preview'}else{"status=$($task.status); stage=$($task.workflowStage)"});$task
    } -DryRun:$DryRun
}

function Add-RepatoTaskReport([string]$StoreRoot,[string]$TaskId,[string]$ReportPath,[string]$Agent='Tara',[switch]$DryRun) {
    Assert-RepatoValue Agent $Agent $script:Agents
    if([string]::IsNullOrWhiteSpace($ReportPath)){throw 'Report path is required.'}
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;if($task.status -in @('completed','failed')){throw 'Terminal task evidence cannot be changed.'};$task.reportPaths=[object[]]@($task.reportPaths)+$ReportPath;Add-RepatoHistory $task 'report-attached' $Agent $(if($preview){'dry-run preview'}else{$ReportPath});$task} -DryRun:$DryRun
}

function Request-RepatoTaskApproval([string]$StoreRoot,[string]$TaskId,[string]$Action,[string]$ApprovalLevel,[switch]$DryRun) {
    Assert-RepatoValue ApprovalLevel $ApprovalLevel $script:ApprovalLevels
    if($Action -in $script:DangerousActions -and $ApprovalLevel-cne'user'){throw "$Action requires user approval."}
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;if($task.status-cne'passed'-or$task.workflowStage-cne'qa'){throw 'Approval can be requested only after QA has passed.'};$request=[pscustomobject]@{requestId=[guid]::NewGuid().ToString('N');action=$Action;requiredLevel=$ApprovalLevel;status='pending';requestedUtc=Get-RepatoUtc;decidedUtc=$null;decidedBy=$null;reason=$null};$task.approvalRequests=[object[]]@($task.approvalRequests)+$request;$task.status='awaiting-approval';$task.workflowStage='approval';Add-RepatoHistory $task 'approval-requested' 'Maya' $(if($preview){'dry-run preview'}else{$Action});$task} -DryRun:$DryRun
}

function Resolve-RepatoTaskApproval([string]$StoreRoot,[string]$TaskId,[string]$Decision,[string]$Actor,[string]$Reason,[switch]$DryRun) {
    Assert-RepatoValue Actor $Actor @('Maya','user');Assert-RepatoValue Decision $Decision @('approve','reject')
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;$pending=@($task.approvalRequests|Where-Object{$_.status -ceq 'pending'});if($task.status -cne 'awaiting-approval' -or $pending.Count -ne 1){throw 'Task must have exactly one pending approval.'};$request=$pending[0];if($request.requiredLevel -ceq 'user' -and $Actor -cne 'user'){throw 'This action requires user approval.'};$request.status=$(if($Decision -ceq 'approve'){'approved'}else{'rejected'});$request.decidedUtc=Get-RepatoUtc;$request.decidedBy=$Actor;$request.reason=$Reason;$task.status=$(if($Decision -ceq 'approve'){'passed'}else{'blocked'});Add-RepatoHistory $task ('approval-'+$Decision) $Actor $(if($preview){'dry-run preview'}else{$Reason});$task} -DryRun:$DryRun
}

function Complete-RepatoTask([string]$StoreRoot,[string]$TaskId,[switch]$DryRun) {
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;if($task.status -cne 'passed' -or $task.workflowStage -cne 'approval'){throw 'Task must pass QA and the approval stage before completion.'};if($task.requiredApprovalLevel -cne 'none'){ $approved=@($task.approvalRequests|Where-Object{$_.status -ceq 'approved' -and ($_.requiredLevel -ceq $task.requiredApprovalLevel -or $_.requiredLevel -ceq 'user')});if(!$approved.Count){throw 'Required approval has not been granted.'} };$task.status='completed';$task.workflowStage='completed';$task.finishedUtc=Get-RepatoUtc;Add-RepatoHistory $task 'completed' 'Maya' $(if($preview){'dry-run preview'}else{'task completed'});$task} -DryRun:$DryRun
}

Export-ModuleMember -Function Initialize-RepatoTaskStore,Read-RepatoTaskStore,New-RepatoTask,Get-RepatoTasks,Claim-RepatoTask,Update-RepatoTask,Add-RepatoTaskReport,Request-RepatoTaskApproval,Resolve-RepatoTaskApproval,Complete-RepatoTask
