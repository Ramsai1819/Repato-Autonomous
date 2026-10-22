Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvNativeContinuation.psm1') -WarningAction SilentlyContinue
$ErrorActionPreference = 'Stop'

$script:TaskStatuses = @('queued','in-progress','blocked','failed','passed','awaiting-approval','completed')
$script:WorkflowStages = @('queued','assigned','implementation','build-checks','qa','approval','completed')
$script:Agents = @('Maya','Neil','Tara')
$script:ApprovalLevels = @('none','maya','user')
$script:DangerousActions = @('production-commit','revit-launch','file-delete','addin-change','destructive-file-operation','disable-addins')

function Get-RepatoUtc { [DateTimeOffset]::UtcNow.ToString('O', [Globalization.CultureInfo]::InvariantCulture) }

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
    $required = @('taskId','title','description','assignedAgent','status','workflowStage','branchName','createdUtc','startedUtc','finishedUtc','logs','reportPaths','errorDetails','requiredApprovalLevel','approvalRequests','executorRuns','revision','history')
    foreach ($name in $required) { if ($Task.PSObject.Properties.Name -notcontains $name) { throw "Malformed task: missing $name." } }
    if ($Task.taskId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,63}$') { throw 'Malformed task ID.' }
    if ([string]::IsNullOrWhiteSpace($Task.title) -or [string]::IsNullOrWhiteSpace($Task.description) -or [string]::IsNullOrWhiteSpace($Task.branchName)) { throw 'Malformed task text or branch.' }
    if ($Task.branchName -notmatch '^(feat|fix|qa|chore)/[a-z0-9][a-z0-9._/-]{0,95}$' -or $Task.branchName.Contains('..') -or $Task.branchName.Contains('//') -or $Task.branchName.EndsWith('/')) { throw 'Malformed or unsafe task branch name.' }
    Assert-RepatoValue Status ([string]$Task.status) $script:TaskStatuses
    Assert-RepatoValue WorkflowStage ([string]$Task.workflowStage) $script:WorkflowStages
    if ($Task.assignedAgent) { Assert-RepatoValue AssignedAgent ([string]$Task.assignedAgent) $script:Agents }
    Assert-RepatoValue RequiredApprovalLevel ([string]$Task.requiredApprovalLevel) $script:ApprovalLevels
    foreach ($name in @('logs','reportPaths','approvalRequests','executorRuns','history')) { if ($Task.$name -isnot [Array]) { throw "Malformed task: $name must be an array." } }
    if ($Task.revision -isnot [long] -and $Task.revision -isnot [int]) { throw 'Malformed task revision.' }
    if($Task.createdUtc -is [datetime]){$null=[DateTimeOffset]$Task.createdUtc}
    elseif($Task.createdUtc -isnot [DateTimeOffset]){
        $createdUtc=[DateTimeOffset]::MinValue
        if(![DateTimeOffset]::TryParse([string]$Task.createdUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$createdUtc)){throw 'Malformed task creation timestamp.'}
    }
}

function Restore-RepatoTaskStoreDateMarkers($Value,[hashtable]$Markers) {
    if($null -eq $Value){return $null}
    if($Value -is [string] -and $Markers.ContainsKey($Value)){return $Markers[$Value]}
    if($Value -is [array]){
        for($i=0;$i -lt $Value.Count;$i++){$Value[$i]=Restore-RepatoTaskStoreDateMarkers $Value[$i] $Markers}
        return ,$Value
    }
    if($Value -is [System.Management.Automation.PSCustomObject]){
        foreach($property in $Value.PSObject.Properties){$property.Value=Restore-RepatoTaskStoreDateMarkers $property.Value $Markers}
    }
    $Value
}

function ConvertFrom-RepatoTaskStoreJson([string]$Json) {
    $markers=@{}
    $matches=[regex]::Matches($Json,'"(?<value>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?)"')
    for($i=$matches.Count-1;$i -ge 0;$i--){
        $match=$matches[$i];$marker='__REPATO_ISO_TIMESTAMP_'+[guid]::NewGuid().ToString('N')+'__'
        $markers[$marker]=$match.Groups['value'].Value
        $Json=$Json.Remove($match.Index,$match.Length).Insert($match.Index,'"'+$marker+'"')
    }
    $data=ConvertFrom-Json -InputObject $Json
    Restore-RepatoTaskStoreDateMarkers $data $markers
    $null = [DateTimeOffset]::Parse([string]$Task.createdUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
}

function Read-RepatoTaskStore([string]$StoreRoot) {
    $paths = Get-RepatoStorePaths $StoreRoot
    if (!(Test-Path -LiteralPath $paths.Queue -PathType Leaf)) { throw "Task queue does not exist: $($paths.Queue)" }
    try { $data = ConvertFrom-RepatoTaskStoreJson (Get-Content -LiteralPath $paths.Queue -Raw) }
    catch { throw "Malformed task queue JSON: $($_.Exception.Message)" }
    if ($data.schemaVersion -ne 1 -or $data.PSObject.Properties.Name -notcontains 'tasks' -or $data.tasks -isnot [Array]) { throw 'Malformed task queue root.' }
    $seen = @{}
    foreach ($task in $data.tasks) {
        # Backward-compatible in-memory upgrade for orchestration v1 stores.
        # It is persisted only by the next normal, locked state mutation.
        if ($task.PSObject.Properties.Name -notcontains 'executorRuns') { $task | Add-Member -NotePropertyName executorRuns -NotePropertyValue ([object[]]@()) }
        if ($task.PSObject.Properties.Name -notcontains 'revision') { $task | Add-Member -NotePropertyName revision -NotePropertyValue ([long][Math]::Max(1,@($task.history).Count)) }
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
    $Task.revision = [long]$Task.revision + 1
    $Task.history = [object[]]@($Task.history) + [pscustomobject]@{timestampUtc=(Get-RepatoUtc);event=$Event;actor=$Actor;details=$Details}
}

function Get-RepatoActiveQaApprovals {
    param([AllowEmptyCollection()][object[]]$Approvals)
    $active=@()
    foreach($approval in $Approvals) {
        if($approval.action -cne 'qa-run' -or
            ($approval.status -cne 'pending' -and !($approval.status -ceq 'approved' -and !$approval.consumedUtc))) {continue}
        $expiry=[DateTimeOffset]::MinValue
        if(![DateTimeOffset]::TryParse([string]$approval.expiresUtc,[ref]$expiry)) {
            throw 'An active QA approval has an invalid expiry and cannot be safely superseded.'
        }
        if($expiry -gt [DateTimeOffset]::UtcNow){$active+=,$approval}
    }
    ,$active
}

function Get-RepatoCanonicalQaDeploymentApprovalEvidence {
    param(
        [Parameter(Mandatory)][object]$Task,[Parameter(Mandatory)][object]$Workflow,
        [Parameter(Mandatory)][string]$BuildRequestId,[Parameter(Mandatory)][string]$CandidateSourceCommit,
        [Parameter(Mandatory)][string]$CandidateSha256,[Parameter(Mandatory)][string]$RunnerManifestPath,
        [Parameter(Mandatory)][string]$RunnerManifestSha256
    )
    $e=$Workflow.qaBuildEvidence
    if(!$Task -or !$Workflow -or !$e -or $Workflow.taskId -cne $Task.taskId -or $Workflow.qaBuildStatus -cne 'succeeded' -or
       $e.BuildRequestId -cne $BuildRequestId -or $e.CandidateSourceCommit -cne $CandidateSourceCommit -or
       $e.SourceCommit -cne $CandidateSourceCommit -or $e.ArtifactSha256 -ine $CandidateSha256 -or
       $e.DeploymentValidation -ne $true -or $e.ManifestIntegrityValidation -ne $true -or $e.QaIsolation -ne $true -or
       $e.RunnerManifestPath -cne $RunnerManifestPath -or $e.RunnerManifestSha256 -ine $RunnerManifestSha256){
        throw 'Canonical QA deployment evidence does not match the approved candidate.'
    }
    $commonGitDirectory=(& git -C $PSScriptRoot rev-parse --path-format=absolute --git-common-dir 2>$null).Trim()
    if($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commonGitDirectory)){throw 'Canonical QA repository identity could not be resolved.'}
    $trustedRoot=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $commonGitDirectory) 'QA')).TrimEnd('\')+'\'
    $manifest=[IO.Path]::GetFullPath($RunnerManifestPath)
    if(!$manifest.StartsWith($trustedRoot,[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $manifest -PathType Leaf) -or
       (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash -ine $RunnerManifestSha256){throw 'Canonical QA runner manifest is not trusted or has changed.'}
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        if($e.PSObject.Properties.Name -contains 'IndependentDeploymentValidation' -and $e.IndependentDeploymentValidation){
            $ind=$e.IndependentDeploymentValidation
            $recoveredBinding=$ind.StagingDisposition -ceq 'existing-verified-deployment'
            if($recoveredBinding){$null=New-CpvNativeContinuationBinding -Task $Task -Workflow $Workflow -ExpectedTaskRevision $Task.revision}
            if($ind.Purpose -cne 'independent-current-deployment-validation' -or $ind.TaskId -cne $Task.taskId -or
               $ind.WorkflowId -cne $Workflow.workflowId -or $ind.BuildRequestId -cne $BuildRequestId -or
               $ind.CandidateSourceCommit -cne $CandidateSourceCommit -or $ind.CandidateDllSha256 -ine $CandidateSha256 -or
               (!$recoveredBinding -and $ind.StagingDisposition -cne 'ambiguous-unresolved') -or $ind.StagingSuccessClaimed -ne $false -or
               $ind.RunnerManifestSha256 -ine $RunnerManifestSha256 -or !$ind.ValidationRequest -or !$ind.Response){
                throw 'Independent QA validation evidence is inconsistent or claims staging success.'
            }
            $originalRunnerManifestPath=$null
            if($e.PSObject.Properties.Name -contains 'OriginalRunnerManifestPath' -and $e.OriginalRunnerManifestPath){$originalRunnerManifestPath=[IO.Path]::GetFullPath([string]$e.OriginalRunnerManifestPath);if(!(Test-Path -LiteralPath $originalRunnerManifestPath -PathType Leaf) -or (Get-FileHash -LiteralPath $originalRunnerManifestPath -Algorithm SHA256).Hash -ine $RunnerManifestSha256){throw 'Original runner-manifest provenance is missing or changed.'}}
            $ops=@(if($Task.PSObject.Properties.Name -contains 'deploymentValidationOperations'){$Task.deploymentValidationOperations|Where-Object OperationId -ceq $ind.OperationId})
            if($ops.Count -ne 1){throw 'Independent QA validation operation is not uniquely bound to this task.'}
            $op=$ops[0];$r=$op.Response;$q=$op.ValidationRequest
            foreach($pair in @(@('TaskId',$Task.taskId),@('WorkflowId',$Workflow.workflowId),@('BuildRequestId',$BuildRequestId),@('CandidateSourceCommit',$CandidateSourceCommit),@('CandidateSha256',$CandidateSha256),@('QaWorkflowId',[string]$Workflow.qaWorkflowId),@('TestId',[string]$Workflow.qaWorkflowId))){if([string]$op.($pair[0]) -cne [string]$pair[1]){throw "Independent QA operation binding mismatch: $($pair[0])."}}
            $expectedPurpose=if($recoveredBinding){'RecoveredQaCurrentDeployment'}else{'IndependentAfterAmbiguousStaging'}
            if($op.ValidationPurpose -cne $expectedPurpose -or $op.RequestDisposition -cne 'completed' -or
               $op.RequestId -cne $ind.RequestId -or $q.requestId -cne $op.RequestId -or $q.taskId -cne $Task.taskId -or
               $q.workflowId -cne $Workflow.workflowId -or $q.candidateCommit -cne $CandidateSourceCommit -or
               $q.expectedCandidateSha256 -ine $CandidateSha256 -or $q.qaWorkflowId -cne $Workflow.qaWorkflowId -or
               $q.testId -cne $Workflow.qaWorkflowId){throw 'Independent QA request identity or disposition is invalid.'}
            $requestJson=ConvertTo-Json -InputObject $q -Compress -Depth 32
            $requestHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($requestJson)))).Replace('-','')
            $requestEvidence=$q.candidateEvidence
            if($requestHash -ine $op.ValidationRequestSha256 -or $requestHash -ine $ind.ValidationRequestSha256 -or
               $requestEvidence.TaskId -cne $Task.taskId -or $requestEvidence.WorkflowId -cne $Workflow.workflowId -or
               $requestEvidence.CandidateSourceCommit -cne $CandidateSourceCommit -or $requestEvidence.CandidateDllSha256 -ine $CandidateSha256 -or
               $requestEvidence.RunnerManifestPath -cne $RunnerManifestPath -or $requestEvidence.RunnerManifestSha256 -ine $RunnerManifestSha256 -or
               $requestEvidence.CandidateProvenancePath -cne $e.CandidateProvenancePath){throw 'Independent QA request provenance or hash is invalid.'}
            $responseJson=ConvertTo-Json -InputObject $r -Compress -Depth 32
            $responseHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($responseJson)))).Replace('-','')
            $indResponseJson=ConvertTo-Json -InputObject $ind.Response -Compress -Depth 32
            if($responseHash -ne ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($indResponseJson)))).Replace('-','') -or
               [int]$r.schemaVersion -ne 1 -or $r.operation -cne 'validate-qa-deployment' -or $r.requestId -cne $op.RequestId -or
               $r.succeeded -ne $true -or $r.candidateCommit -cne $CandidateSourceCommit -or
               $r.candidateSha256 -ine $CandidateSha256 -or $r.validationIdentity -ine 'RAMSAI\RepatoQA' -or
               $r.isolationPassed -ne $true -or $r.manifestIntegrityPassed -ne $true -or
               $r.runnerManifestSha256 -ine $RunnerManifestSha256 -or $r.runnerManifestPath -cne $ind.RunnerManifestPath -or
               $r.validatedRunnerManifestPath -cne $r.runnerManifestPath -or
               [IO.Path]::GetFullPath([string]$r.qaAddinRoot) -ine 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA' -or
               $r.qaWorkflowId -cne $Workflow.qaWorkflowId -or $r.testId -cne $Workflow.qaWorkflowId -or
               $e.DeployedRunnerManifestPath -cne $r.runnerManifestPath -or $e.DeployedRunnerManifestSha256 -ine $RunnerManifestSha256){throw 'Independent QA authenticated response no longer matches its operation.'}
            return [pscustomobject][ordered]@{Mode='independent-current-deployment-validation';OperationId=$op.OperationId;RequestId=$op.RequestId;ValidationRequestSha256=$requestHash;ValidationResponseSha256=$responseHash;CandidateSourceCommit=$CandidateSourceCommit;CandidateSha256=$CandidateSha256;RunnerManifestPath=$RunnerManifestPath;RunnerManifestSha256=$RunnerManifestSha256;ValidationIdentity='RAMSAI\RepatoQA';IsolationPassed=$true;ManifestIntegrityPassed=$true;StagingDisposition=$ind.StagingDisposition;StagingSuccessClaimed=$false;OriginalRunnerManifestPath=$originalRunnerManifestPath}
        }
        if($e.PSObject.Properties.Name -contains 'StagingSuccessClaimed' -and $e.StagingSuccessClaimed -eq $true){throw 'Staging success cannot be asserted without the supported staging evidence.'}
        $ops=@(if($Task.PSObject.Properties.Name -contains 'deploymentValidationOperations'){$Task.deploymentValidationOperations|Where-Object {$_.ValidationPurpose -ceq 'CanonicalAfterStaging' -and $_.TaskId -ceq $Task.taskId -and $_.WorkflowId -ceq $Workflow.workflowId -and $_.BuildRequestId -ceq $BuildRequestId -and $_.CandidateSourceCommit -ceq $CandidateSourceCommit -and $_.CandidateSha256 -ieq $CandidateSha256 -and $_.RequestDisposition -ceq 'completed'}})
        if($ops.Count -ne 1){throw 'Canonical staging-path deployment validation is not uniquely recorded.'}
        $op=$ops[0];$r=$op.Response;$expectedInstalledManifest='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin'
        if(!$r -or $r.requestId -cne $op.RequestId -or $r.succeeded -ne $true -or $r.candidateCommit -cne $CandidateSourceCommit -or
           $r.candidateSha256 -ine $CandidateSha256 -or $r.qaWorkflowId -cne $Workflow.qaWorkflowId -or $r.testId -cne $Workflow.qaWorkflowId -or $r.validationIdentity -ine 'RAMSAI\RepatoQA' -or $r.isolationPassed -ne $true -or
           $r.manifestIntegrityPassed -ne $true -or $r.runnerManifestSha256 -ine $RunnerManifestSha256 -or $r.validatedRunnerManifestPath -cne $r.runnerManifestPath -or
           [IO.Path]::GetFullPath([string]$r.qaAddinRoot) -ine 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA' -or
           [IO.Path]::GetFullPath([string]$r.runnerManifestPath) -ine $expectedInstalledManifest){throw 'Canonical staging-path validation response is invalid.'}
        $responseJson=ConvertTo-Json -InputObject $r -Compress -Depth 32
        $responseHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($responseJson)))).Replace('-','')
        [pscustomobject][ordered]@{Mode='canonical-staging-deployment-validation';OperationId=$op.OperationId;RequestId=$op.RequestId;ValidationResponseSha256=$responseHash;CandidateSourceCommit=$CandidateSourceCommit;CandidateSha256=$CandidateSha256;RunnerManifestPath=$RunnerManifestPath;RunnerManifestSha256=$RunnerManifestSha256;ValidationIdentity='RAMSAI\RepatoQA';IsolationPassed=$true;ManifestIntegrityPassed=$true;StagingSuccessClaimed=$false}
    } finally {$sha.Dispose()}
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
        $task=[pscustomobject][ordered]@{taskId=$TaskId;title=$Title;description=$Description;assignedAgent=$null;status='queued';workflowStage='queued';branchName=$BranchName;createdUtc=$now;startedUtc=$null;finishedUtc=$null;logs=[object[]]@();reportPaths=[object[]]@();errorDetails=$null;requiredApprovalLevel=$RequiredApprovalLevel;approvalRequests=[object[]]@();executorRuns=[object[]]@();revision=[long]1;history=[object[]]@([pscustomobject]@{timestampUtc=$now;event='created';actor='Maya';details=$(if($preview){'dry-run preview'}else{'task queued'})})}
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
    param([string]$StoreRoot,[string]$TaskId,[string]$Status,[string]$WorkflowStage,[string]$Agent,[string]$LogPath,[string]$ErrorDetails,
        [long]$ExpectedTaskRevision=0,[string]$ExpectedWorkflowId,[long]$ExpectedWorkflowRevision=0,[string]$ExpectedQaWorkflowId,[switch]$DryRun)
    if(($ExpectedWorkflowId -and $ExpectedTaskRevision -lt 1) -or ($ExpectedWorkflowRevision -gt 0 -and !$ExpectedWorkflowId)){throw 'Expected task/workflow compare-and-swap arguments must be supplied together.'}
    Invoke-RepatoStoreMutation $StoreRoot {
        param($data,$preview);$task=Find-RepatoTask $data $TaskId
        if($ExpectedTaskRevision -gt 0 -and [long]$task.revision -ne $ExpectedTaskRevision){throw 'Task compare-and-swap revision changed.'}
        if($task.status -in @('completed','failed')){throw 'Completed and failed tasks are preserved and terminal.'}
        if($ExpectedWorkflowId){
            $matched=@($task.deploymentWorkflows|Where-Object workflowId -ceq $ExpectedWorkflowId)
            if($ExpectedWorkflowRevision -lt 1 -or $matched.Count -ne 1 -or [string]$matched[0].taskId -cne $TaskId -or [long]$matched[0].workflowRevision -ne $ExpectedWorkflowRevision -or [string]$matched[0].qaWorkflowId -cne $ExpectedQaWorkflowId){throw 'Task/workflow compare-and-swap identity changed.'}
        }
        $taskWorkflows=if($task.PSObject.Properties.Name -contains 'deploymentWorkflows'){@($task.deploymentWorkflows)}else{@()}
        $canonicalQaTransition=($WorkflowStage -ceq 'qa' -and $task.workflowStage -ceq 'build-checks' -and @($taskWorkflows|Where-Object {$_.qaWorkflowId -ceq 'create-plan-views-v1'}).Count -gt 0)
        $activeCanonicalQaApprovals=if($canonicalQaTransition){@(Get-RepatoActiveQaApprovals -Approvals @($task.approvalRequests))}else{@()}
        if($WorkflowStage -ceq 'qa' -and $ExpectedQaWorkflowId -ceq 'create-plan-views-v1' -and !$canonicalQaTransition){throw 'Create Plan Views QA transition is duplicate or starts from an incompatible task stage.'}
        if($canonicalQaTransition){
            if($ExpectedTaskRevision -lt 1 -or !$ExpectedWorkflowId -or $ExpectedWorkflowRevision -lt 1 -or $ExpectedQaWorkflowId -cne 'create-plan-views-v1'){throw 'Create Plan Views build-checks to QA transition requires task and workflow compare-and-swap bindings.'}
            $canonicalWorkflows=@($taskWorkflows|Where-Object {$_.qaWorkflowId -ceq 'create-plan-views-v1'})
            $workflow=@($task.deploymentWorkflows|Where-Object workflowId -ceq $ExpectedWorkflowId)
            if($task.status -cne 'in-progress' -or $canonicalWorkflows.Count -ne 1 -or [string]$canonicalWorkflows[0].workflowId -cne $ExpectedWorkflowId -or $workflow.Count -ne 1 -or [string]$workflow[0].qaRunId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$' -or
               [string]$workflow[0].stage -notin @('planned','validated') -or
               $activeCanonicalQaApprovals.Count -gt 0 -or
               ($task.PSObject.Properties.Name -contains 'mayaTaraAttempt' -and $task.mayaTaraAttempt) -or
               ($task.PSObject.Properties.Name -contains 'mayaTaraExecution' -and $task.mayaTaraExecution) -or
               ($task.PSObject.Properties.Name -contains 'mayaTaraQaPacket' -and $task.mayaTaraQaPacket) -or
               ($task.PSObject.Properties.Name -contains 'mayaTaraExecutionEvidence' -and $task.mayaTaraExecutionEvidence) -or
               [string]::IsNullOrWhiteSpace([string]$workflow[0].qaModelPath) -or [string]::IsNullOrWhiteSpace([string]$workflow[0].qaSidecarPath) -or
               !(Test-Path -LiteralPath $workflow[0].qaModelPath -PathType Leaf) -or !(Test-Path -LiteralPath $workflow[0].qaSidecarPath -PathType Leaf) -or
               [string]$workflow[0].qaDisposableModelSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash -LiteralPath $workflow[0].qaModelPath -Algorithm SHA256).Hash -ine [string]$workflow[0].qaDisposableModelSha256 -or
               [string]$workflow[0].qaFixtureSha256 -notmatch '^[A-Fa-f0-9]{64}$') {throw 'Create Plan Views QA transition prerequisites are stale, duplicated, or inconsistent.'}
            $sidecar=Get-Content -LiteralPath $workflow[0].qaSidecarPath -Raw|ConvertFrom-Json
            if([string]$sidecar.fixtureId -cne [string]$workflow[0].qaFixtureId -or [string]$sidecar.sourceSha256 -ine [string]$workflow[0].qaFixtureSha256){throw 'Create Plan Views QA transition sidecar provenance changed.'}
        }
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

function Request-RepatoTaskApproval([string]$StoreRoot,[string]$TaskId,[string]$Action,[string]$ApprovalLevel,[switch]$DryRun,[string]$BindingHash='',[int]$ExpiryMinutes=30) {
    Assert-RepatoValue ApprovalLevel $ApprovalLevel $script:ApprovalLevels
    if($Action -in $script:DangerousActions -and $ApprovalLevel-cne'user'){throw "$Action requires user approval."}
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;if($task.status-cne'passed'-or$task.workflowStage-cne'qa'){throw 'Approval can be requested only after QA has passed.'};$request=[pscustomobject]@{requestId=[guid]::NewGuid().ToString('N');action=$Action;requiredLevel=$ApprovalLevel;status='pending';bindingHash=$BindingHash;previousStatus='passed';requestedRevision=[long]0;approvedRevision=$null;requestedUtc=Get-RepatoUtc;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes($ExpiryMinutes).ToString('O');decidedUtc=$null;decidedBy=$null;reason=$null;consumedUtc=$null};$task.approvalRequests=[object[]]@($task.approvalRequests)+$request;$task.status='awaiting-approval';$task.workflowStage='approval';Add-RepatoHistory $task 'approval-requested' 'Maya' $(if($preview){'dry-run preview'}else{$Action});$request.requestedRevision=[long]$task.revision;$task} -DryRun:$DryRun
}

function Resolve-RepatoTaskApproval([string]$StoreRoot,[string]$TaskId,[string]$Decision,[string]$Actor,[string]$Reason,[switch]$DryRun) {
    Assert-RepatoValue Actor $Actor @('Maya','user');Assert-RepatoValue Decision $Decision @('approve','reject')
    Invoke-RepatoStoreMutation $StoreRoot {
        param($data,$preview)
        $task=Find-RepatoTask $data $TaskId;$pending=@($task.approvalRequests|Where-Object{$_.status -ceq 'pending'})
        if($task.status -cne 'awaiting-approval' -or $pending.Count -ne 1){throw 'Task must have exactly one pending approval.'}
        $request=$pending[0]
        if([long]$request.requestedRevision -ne [long]$task.revision -or [DateTimeOffset]::Parse($request.expiresUtc)-le[DateTimeOffset]::UtcNow){throw 'Approval request expired or task changed.'}
        if($request.PSObject.Properties.Name -contains 'executionBinding' -and $request.executionBinding){
            $binding=$request.executionBinding;$json=ConvertTo-Json -InputObject $binding -Depth 20 -Compress;$sha=[Security.Cryptography.SHA256]::Create();try{$hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}finally{$sha.Dispose()}
            if($hash -ine [string]$request.bindingHash -or [string]$binding.TaskId -cne $TaskId){throw 'Bound QA approval payload hash or task identity is invalid.'}
            $workflows=@($task.deploymentWorkflows|Where-Object {[string]$_.workflowId -ceq [string]$binding.WorkflowId})
            if($workflows.Count -ne 1){$available=@($task.deploymentWorkflows|ForEach-Object {[string]$_.workflowId}) -join ',';throw "Bound QA approval workflow identity is invalid: task=$TaskId; workflow=$($binding.WorkflowId); matches=$($workflows.Count); available=$available."};$e=$workflows[0].qaBuildEvidence
            $preparation=if($workflows[0].PSObject.Properties['qaFixturePreparationEvidence']){$workflows[0].qaFixturePreparationEvidence}else{$null}
            if($preparation -and $preparation.PSObject.Properties['RecoveredProvenanceSha256']){
                if($request.action -cne 'qa-run' -or $Actor -cne 'user' -or $request.requiredLevel -cne 'user' -or !$binding.PSObject.Properties['NativeContinuation']){throw 'Recovered preparation requires fresh bound native user authorization.'}
                Assert-CpvNativeContinuationBinding -Task $task -Workflow $workflows[0] -Binding $binding.NativeContinuation
            }elseif($binding.PSObject.Properties['NativeContinuation']){throw 'Native continuation has no verified recovered preparation.'}
            $plan=$binding.ExecutionPlan
            if([string]$binding.BuildRequestId -cne [string]$e.BuildRequestId -or [string]$binding.CandidateSourceCommit -cne [string]$e.CandidateSourceCommit -or [string]$binding.CandidateSha256 -ine [string]$e.ArtifactSha256 -or [string]$binding.RunnerManifestPath -ine [string]$e.RunnerManifestPath -or [string]$binding.RunnerManifestSha256 -ine [string]$e.RunnerManifestSha256 -or !$e.DeploymentValidation -or !$e.ManifestIntegrityValidation -or !$e.QaIsolation -or [string]$binding.RunId -cne [string]$workflows[0].qaRunId -or [string]$binding.ModelPath -ine [string]$workflows[0].qaModelPath -or [string]$binding.SidecarPath -ine [string]$workflows[0].qaSidecarPath -or [string]$binding.FixtureId -cne [string]$workflows[0].qaFixtureId -or [string]$binding.FixtureSha256 -ine [string]$workflows[0].qaFixtureSha256 -or [string]$plan.TaskId -cne $TaskId -or [string]$plan.WorkflowId -cne [string]$binding.WorkflowId -or [string]$plan.QaWorkflowId -cne [string]$binding.QaWorkflowId -or [string]$plan.Stage -cne 'qa-prepared' -or [string]$plan.NextAgent -cne 'Tara' -or [string]$plan.NextOperation -cne 'canonical-execution-record' -or $plan.SideEffectsPerformed -ne $false){throw 'Bound QA approval no longer matches candidate or execution evidence.'}
            $currentDeploymentBinding=Get-RepatoCanonicalQaDeploymentApprovalEvidence -Task $task -Workflow $workflows[0] -BuildRequestId $binding.BuildRequestId -CandidateSourceCommit $binding.CandidateSourceCommit -CandidateSha256 $binding.CandidateSha256 -RunnerManifestPath $binding.RunnerManifestPath -RunnerManifestSha256 $binding.RunnerManifestSha256
            $currentDeploymentJson=ConvertTo-Json -InputObject $currentDeploymentBinding -Depth 20 -Compress;$approvedDeploymentJson=ConvertTo-Json -InputObject $binding.DeploymentValidationEvidence -Depth 20 -Compress
            if($currentDeploymentJson -cne $approvedDeploymentJson){throw 'Bound QA approval deployment-validation operation or authenticated response changed.'}
            $trustedRoots=Get-RepatoCanonicalQaTrustedRoots
            $candidateDirectory=[IO.Path]::GetFullPath([string]$e.CandidateDirectory);$runnerPath=[IO.Path]::GetFullPath([string]$binding.RunnerManifestPath)
            if(!(Test-RepatoPathWithinTrustedRoot -Path $candidateDirectory -Root $trustedRoots.CandidateRoot)){throw 'Bound QA candidate directory is outside the authorized primary-repository candidate root.'}
            if(!(Test-RepatoPathWithinTrustedRoot -Path $runnerPath -Root $trustedRoots.QaRoot)){throw 'Bound QA runner manifest is outside the authorized primary-repository QA root.'}
            foreach($pair in @(@($e.ArtifactPath,$binding.CandidateSha256),@($binding.RunnerManifestPath,$binding.RunnerManifestSha256),@($e.CandidateProvenancePath,$binding.CandidateProvenanceSha256),@($binding.ModelPath,$binding.ModelSha256),@($binding.SidecarPath,$binding.SidecarSha256))){if(!(Test-Path -LiteralPath $pair[0] -PathType Leaf) -or (Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ine $pair[1]){throw 'Bound QA approval file evidence changed.'}}
        }
        if($request.requiredLevel -ceq 'user' -and $Actor -cne 'user'){throw 'This action requires user approval.'}
        $request.status=$(if($Decision -ceq 'approve'){'approved'}else{'rejected'});$request.decidedUtc=Get-RepatoUtc;$request.decidedBy=$Actor;$request.reason=$Reason;$task.status=$(if($Decision -ceq'approve'){$request.previousStatus}else{'blocked'});Add-RepatoHistory $task ('approval-'+$Decision) $Actor $(if($preview){'dry-run preview'}else{$Reason});if($Decision -ceq'approve'){$request.approvedRevision=[long]$task.revision};$task
    } -DryRun:$DryRun
}

function Get-RepatoCanonicalQaTrustedRoots {
    $worktreeRoot=(& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null).Trim()
    if($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($worktreeRoot)){throw 'Approval source worktree identity could not be resolved.'}
    $worktreeRoot=[IO.Path]::GetFullPath($worktreeRoot)
    $moduleRoot=[IO.Path]::GetFullPath($PSScriptRoot)
    if(!$moduleRoot.StartsWith($worktreeRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Approval module is outside its Git worktree root.'}

    $commonGitDirectory=(& git -C $worktreeRoot rev-parse --path-format=absolute --git-common-dir 2>$null).Trim()
    if($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commonGitDirectory)){throw 'Approval primary-repository identity could not be resolved.'}
    $commonGitDirectory=[IO.Path]::GetFullPath($commonGitDirectory)
    if([IO.Path]::GetFileName($commonGitDirectory) -cne '.git'){throw 'Approval repository common directory is not the expected .git directory.'}
    $primaryRoot=[IO.Path]::GetFullPath((Split-Path -Parent $commonGitDirectory))
    if(!(Test-Path -LiteralPath $primaryRoot -PathType Container)){throw 'Approval primary-repository root is missing.'}
    $primaryTop=(& git -C $primaryRoot rev-parse --show-toplevel 2>$null).Trim()
    $primaryCommon=(& git -C $primaryRoot rev-parse --path-format=absolute --git-common-dir 2>$null).Trim()
    if($LASTEXITCODE -ne 0 -or [IO.Path]::GetFullPath($primaryTop) -ine $primaryRoot -or
        [IO.Path]::GetFullPath($primaryCommon) -ine $commonGitDirectory){throw 'Approval primary-repository root does not match the isolated worktree Git identity.'}

    [pscustomobject]@{
        WorktreeRoot=$worktreeRoot
        PrimaryRepositoryRoot=$primaryRoot
        CandidateRoot=[IO.Path]::GetFullPath((Join-Path $primaryRoot 'DeploymentCandidates\AgentBuilds'))
        QaRoot=[IO.Path]::GetFullPath((Join-Path $primaryRoot 'QA'))
    }
}

function Test-RepatoPathWithinTrustedRoot {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Root)
    if([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)){return $false}
    $canonicalPath=[IO.Path]::GetFullPath($Path)
    $canonicalRoot=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
    $canonicalPath.StartsWith($canonicalRoot,[StringComparison]::OrdinalIgnoreCase)
}

function Complete-RepatoTask([string]$StoreRoot,[string]$TaskId,[switch]$DryRun) {
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;if($task.status -cne 'passed' -or $task.workflowStage -cne 'approval'){throw 'Task must pass QA and the approval stage before completion.'};if($task.requiredApprovalLevel -cne 'none'){ $approved=@($task.approvalRequests|Where-Object{$_.status -ceq 'approved' -and ($_.requiredLevel -ceq $task.requiredApprovalLevel -or $_.requiredLevel -ceq 'user')});if(!$approved.Count){throw 'Required approval has not been granted.'} };$task.status='completed';$task.workflowStage='completed';$task.finishedUtc=Get-RepatoUtc;Add-RepatoHistory $task 'completed' 'Maya' $(if($preview){'dry-run preview'}else{'task completed'});$task} -DryRun:$DryRun
}

function Get-RepatoExecutorActionCatalog($Task) {
    $worktree = 'C:\Repato-Autonomous\Worktrees\' + $Task.taskId
    [ordered]@{
        'validate-branch'=[pscustomobject]@{Agents=@('Neil','Tara');Phase='assigned';Approval='none';Command="git branch --show-current # expect $($Task.branchName)"}
        'create-worktree'=[pscustomobject]@{Agents=@('Neil');Phase='assigned';Approval='none';Command="git worktree add `"$worktree`" `"$($Task.branchName)`""}
        'validate-worktree'=[pscustomobject]@{Agents=@('Neil','Tara');Phase='assigned';Approval='none';Command="git worktree list --porcelain # expect $worktree"}
        'production-edit'=[pscustomobject]@{Agents=@('Neil');Phase='implementation';Approval='none';Command='<Neil production edit plan supplied by the task; preview only>'}
        'build-release'=[pscustomobject]@{Agents=@('Tara');Phase='build-checks';Approval='none';Command='dotnet build ".\Forma.RevitConnector.csproj" -c Release -p:RevitInstallDir="E:\revit\Revit 2025"'}
        'run-agent-tests'=[pscustomobject]@{Agents=@('Tara');Phase='build-checks';Approval='none';Command='powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\AgentOrchestration\Test-AgentExecutor.ps1'}
        'run-qa-tests'=[pscustomobject]@{Agents=@('Tara');Phase='qa';Approval='none';Command='Get-ChildItem .\QA -Filter Test-*.ps1 | ForEach-Object { powershell.exe -NoProfile -ExecutionPolicy Bypass -File $_.FullName }'}
        'production-commit'=[pscustomobject]@{Agents=@('Neil');Phase='approval';Approval='user';Command="git commit # exact staged diff and message require separate review"}
        'revit-launch'=[pscustomobject]@{Agents=@('Tara');Phase='qa';Approval='user';Command='E:\revit\Revit 2025\Revit.exe # approved disposable QA request only'}
        'file-delete'=[pscustomobject]@{Agents=@('Neil','Tara');Phase='implementation';Approval='user';Command='<delete exact approved path only>'}
        'addin-change'=[pscustomobject]@{Agents=@('Tara');Phase='qa';Approval='user';Command='<install, replace, disable, or remove exact approved add-in path only>'}
    }
}

function Get-RepatoExecutorPlanHash($Actions) {
    $json = $Actions | ConvertTo-Json -Depth 8 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $algorithm=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-','')}
    finally{$algorithm.Dispose()}
}

function Find-RepatoExecutorRun($Task,[string]$ExecutionId) {
    $runs=@($Task.executorRuns|Where-Object executionId -ceq $ExecutionId)
    if($runs.Count-ne1){throw "Executor run not found: $ExecutionId"};$runs[0]
}

function New-RepatoExecutorPlan([string]$StoreRoot,[string]$TaskId,[string]$Agent,[string[]]$Actions,[switch]$DryRun) {
    Assert-RepatoValue Agent $Agent @('Neil','Tara')
    if(!$Actions.Count){throw 'At least one executor action is required.'}
    Invoke-RepatoStoreMutation $StoreRoot {
        param($data,$preview);$task=Find-RepatoTask $data $TaskId;Assert-RepatoTask $task
        if($task.status -in @('failed','completed','blocked','awaiting-approval')){throw 'Task status does not permit executor planning.'}
        if(@($task.executorRuns|Where-Object status -in @('planned','claimed','validated')).Count){throw 'An active executor run already exists.'}
        $catalog=Get-RepatoExecutorActionCatalog $task;$resolved=@()
        foreach($name in $Actions){if(!$catalog.Contains($name)){throw "Unknown executor action: $name"};$definition=$catalog[$name];if($Agent-cnotin$definition.Agents){throw "$Agent is not allowed to perform $name"};$resolved+=[pscustomobject]@{name=$name;phase=$definition.Phase;approvalLevel=$definition.Approval;command=$definition.Command}}
        if(@($resolved.phase|Sort-Object -Unique).Count-ne1){throw 'One executor plan may contain actions from only one workflow phase.'}
        $current=[array]::IndexOf($script:WorkflowStages,[string]$task.workflowStage);$target=[array]::IndexOf($script:WorkflowStages,[string]$resolved[0].phase)
        if($target-lt$current-or$target-gt($current+1)){throw "Executor action phase $($resolved[0].phase) is invalid from task stage $($task.workflowStage)."}
        $run=[pscustomobject][ordered]@{executionId=[guid]::NewGuid().ToString('N');mode='DryRun';agent=$Agent;status='planned';phase=$resolved[0].phase;actions=[object[]]$resolved;planHash=(Get-RepatoExecutorPlanHash $resolved);plannedUtc=Get-RepatoUtc;startedUtc=$null;validatedUtc=$null;finishedUtc=$null;logs=[object[]]@();reports=[object[]]@();evidence=[object[]]@();errorDetails=$null}
        if(!$preview){$task.executorRuns=[object[]]@($task.executorRuns)+$run;Add-RepatoHistory $task 'executor-planned' 'Maya' "execution=$($run.executionId); hash=$($run.planHash)"}
        $run
    } -DryRun:$DryRun
}

function Claim-RepatoExecutorRun([string]$StoreRoot,[string]$TaskId,[string]$ExecutionId,[string]$Agent,[switch]$DryRun) {
    Assert-RepatoValue Agent $Agent @('Neil','Tara')
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;$run=Find-RepatoExecutorRun $task $ExecutionId;if($run.status-cne'planned'){throw 'Executor run was already claimed or finished.'};if($run.agent-cne$Agent){throw 'Executor agent does not match the plan.'};if($task.status-cne'queued'-and$task.status-cne'in-progress'-and$task.status-cne'passed'){throw 'Task status cannot be claimed.'};if(!$preview){$run.status='claimed';$run.startedUtc=Get-RepatoUtc;$task.assignedAgent=$Agent;if($task.status-ceq'queued'){$task.status='in-progress';$task.workflowStage='assigned';$task.startedUtc=$run.startedUtc};Add-RepatoHistory $task 'executor-claimed' $Agent "execution=$ExecutionId"};$run} -DryRun:$DryRun
}

function Test-RepatoExecutorRun([string]$StoreRoot,[string]$TaskId,[string]$ExecutionId,[switch]$DryRun) {
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;$run=Find-RepatoExecutorRun $task $ExecutionId;if($run.status-cne'claimed'-and$run.status-cne'validated'){throw 'Executor run must be claimed before validation.'};$catalog=Get-RepatoExecutorActionCatalog $task;foreach($action in $run.actions){if(!$catalog.Contains($action.name)-or$run.agent-cnotin$catalog[$action.name].Agents-or$action.command-cne$catalog[$action.name].Command){throw 'Executor plan no longer matches the allowlist.'}};if((Get-RepatoExecutorPlanHash $run.actions)-cne$run.planHash){throw 'Executor plan hash mismatch.'};if(!$preview){$run.status='validated';$run.validatedUtc=Get-RepatoUtc;Add-RepatoHistory $task 'executor-validated' $run.agent "execution=$ExecutionId"};[pscustomobject]@{TaskId=$TaskId;ExecutionId=$ExecutionId;Valid=$true;Mode='DryRun';Branch=$task.branchName;Actions=$run.actions}} -DryRun:$DryRun
}

function Request-RepatoExecutorApproval([string]$StoreRoot,[string]$TaskId,[string]$ExecutionId,[string]$Action,[int]$ExpiryMinutes=30,[switch]$DryRun) {
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;$run=Find-RepatoExecutorRun $task $ExecutionId;if($run.status-cne'validated'){throw 'Executor run must be validated before approval.'};$planned=@($run.actions|Where-Object{$_.name -ceq $Action});if($planned.Count-ne1){throw 'Approval action is not uniquely present in the plan.'};if($planned[0].approvalLevel-cne'user'){throw 'This executor action does not require approval.'};if(@($task.approvalRequests|Where-Object{$_.status -ceq 'pending'}).Count){throw 'Task already has a pending approval.'};$request=[pscustomobject]@{requestId=[guid]::NewGuid().ToString('N');action=$Action;requiredLevel='user';status='pending';bindingHash=$run.planHash;previousStatus=$task.status;requestedRevision=[long]0;approvedRevision=$null;requestedUtc=Get-RepatoUtc;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes($ExpiryMinutes).ToString('O');decidedUtc=$null;decidedBy=$null;reason=$null;consumedUtc=$null};if(!$preview){$task.approvalRequests=[object[]]@($task.approvalRequests)+$request;$task.status='awaiting-approval';Add-RepatoHistory $task 'executor-approval-requested' 'Maya' "execution=$ExecutionId; action=$Action; hash=$($run.planHash)";$request.requestedRevision=[long]$task.revision};$request} -DryRun:$DryRun
}

function Assert-RepatoExecutorApprovals($Task,$Run) {
    foreach($action in @($Run.actions|Where-Object{$_.approvalLevel -ceq 'user'})){
        $matches=@($Task.approvalRequests|Where-Object{$_.action-ceq$action.name-and$_.status-ceq'approved'-and$_.bindingHash-ceq$Run.planHash-and$_.consumedUtc-eq$null})
        if($matches.Count-ne1){throw "Missing or mismatched approval for $($action.name)."}
        $approval=$matches[0]
        if([DateTimeOffset]::Parse($approval.expiresUtc)-le[DateTimeOffset]::UtcNow-or[long]$approval.approvedRevision-ne[long]$Task.revision){throw "Expired approval or task changed after approval for $($action.name)."}
    }
}

function Get-RepatoExecutorPreview([string]$StoreRoot,[string]$TaskId,[string]$ExecutionId) {
    $paths=Get-RepatoStorePaths $StoreRoot;$lock=$null
    try{$lock=[IO.File]::Open($paths.Lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$run=Find-RepatoExecutorRun $task $ExecutionId;if($run.status-cne'validated'){throw 'Executor run is not validated.'};if((Get-RepatoExecutorPlanHash $run.actions)-cne$run.planHash){throw 'Executor plan hash mismatch.'};Assert-RepatoExecutorApprovals $task $run;[pscustomobject]@{TaskId=$TaskId;ExecutionId=$ExecutionId;Mode='DryRun';WouldExecute=$run.actions;SideEffectsPerformed=$false;ApprovalCheckedUtc=Get-RepatoUtc}}
    finally{if($lock){$lock.Dispose()}}
}

function Complete-RepatoExecutorRun([string]$StoreRoot,[string]$TaskId,[string]$ExecutionId,[string[]]$LogPaths,[string[]]$ReportPaths,[string[]]$EvidencePaths,[switch]$DryRun) {
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;$run=Find-RepatoExecutorRun $task $ExecutionId;if($run.status-cne'validated'){throw 'Only a validated executor run can complete.'};Assert-RepatoExecutorApprovals $task $run;if(!$preview){foreach($approval in @($task.approvalRequests|Where-Object{$_.bindingHash-ceq$run.planHash-and$_.status-ceq'approved'})){$approval.consumedUtc=Get-RepatoUtc};$run.status='completed';$run.finishedUtc=Get-RepatoUtc;$run.logs=[object[]]@($LogPaths);$run.reports=[object[]]@($ReportPaths);$run.evidence=[object[]]@($EvidencePaths);$task.logs=[object[]]@($task.logs)+[object[]]@($LogPaths);$task.reportPaths=[object[]]@($task.reportPaths)+[object[]]@($ReportPaths)+[object[]]@($EvidencePaths);$current=[array]::IndexOf($script:WorkflowStages,[string]$task.workflowStage);$target=[array]::IndexOf($script:WorkflowStages,[string]$run.phase);if($target-eq($current+1)){$task.workflowStage=$run.phase};Add-RepatoHistory $task 'executor-completed' $run.agent "execution=$ExecutionId; dry-run actions only"};$run} -DryRun:$DryRun
}

function Fail-RepatoExecutorRun([string]$StoreRoot,[string]$TaskId,[string]$ExecutionId,[string]$ErrorDetails,[string[]]$LogPaths,[string[]]$ReportPaths,[switch]$DryRun) {
    if([string]::IsNullOrWhiteSpace($ErrorDetails)){throw 'Executor failure details are required.'}
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;$run=Find-RepatoExecutorRun $task $ExecutionId;if($run.status -in @('completed','failed')){throw 'Executor run is already terminal.'};if(!$preview){$run.status='failed';$run.finishedUtc=Get-RepatoUtc;$run.errorDetails=$ErrorDetails;$run.logs=[object[]]@($LogPaths);$run.reports=[object[]]@($ReportPaths);$task.status='failed';$task.finishedUtc=$run.finishedUtc;$task.errorDetails=$ErrorDetails;$task.logs=[object[]]@($task.logs)+[object[]]@($LogPaths);$task.reportPaths=[object[]]@($task.reportPaths)+[object[]]@($ReportPaths);Add-RepatoHistory $task 'executor-failed' $run.agent "execution=$ExecutionId; $ErrorDetails"};$run} -DryRun:$DryRun
}

Export-ModuleMember -Function Get-RepatoUtc,Get-RepatoStorePaths,Write-RepatoJsonAtomic,Assert-RepatoTask,Read-RepatoTaskStore,Invoke-RepatoStoreMutation,Add-RepatoHistory,Find-RepatoTask,Initialize-RepatoTaskStore,New-RepatoTask,Get-RepatoTasks,Claim-RepatoTask,Update-RepatoTask,Add-RepatoTaskReport,Request-RepatoTaskApproval,Resolve-RepatoTaskApproval,Complete-RepatoTask,New-RepatoExecutorPlan,Claim-RepatoExecutorRun,Test-RepatoExecutorRun,Request-RepatoExecutorApproval,Get-RepatoExecutorPreview,Complete-RepatoExecutorRun,Fail-RepatoExecutorRun,Get-RepatoCanonicalQaDeploymentApprovalEvidence
