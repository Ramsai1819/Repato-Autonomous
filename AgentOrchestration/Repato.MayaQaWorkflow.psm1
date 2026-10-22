Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvNativeContinuation.psm1') -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvRecoveredProvenance.psm1') -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -WarningAction SilentlyContinue
. (Join-Path $PSScriptRoot 'MayaQa.TaraExecution.ps1')
Import-Module (Join-Path $PSScriptRoot 'Repato.CandidateEvidence.psm1') -Force -WarningAction SilentlyContinue
$script:MayaQaRootOverrideForTests=$null
$script:Definitions = @{
    'welcome-smoke' = @{ FixtureId='CreateLevelsEmpty'; Source='CreateLevelsEmpty.rvt'; Prep=$null; TestId='welcome-supervised-dialog-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'welcome-supervised-dialog-v1' = @{ FixtureId='CreateLevelsEmpty'; Source='CreateLevelsEmpty.rvt'; Prep=$null; TestId='welcome-supervised-dialog-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'create-grids-world-axis-v1' = @{ FixtureId='CreateGridsEmptyPlan'; Source='CreateGridsEmptyPlan.rvt'; Prep='Prepare-CreateGridsQaRun.ps1'; TestId='create-grids-world-axis-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
        'create-levels' = @{ FixtureId='CreateLevelsEmpty'; Source='CreateLevelsEmpty.rvt'; Prep='Prepare-CreateLevelsQaRun.ps1'; TestId='create-levels-elevations-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'create-levels-elevations-v1' = @{ FixtureId='CreateLevelsEmpty'; Source='CreateLevelsEmpty.rvt'; Prep='Prepare-CreateLevelsQaRun.ps1'; TestId='create-levels-elevations-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'grid-bubble-visibility-v1' = @{ FixtureId='GridBubbleVisibilityEmpty'; Source='GridBubbleVisibilityEmpty.rvt'; Prep='Prepare-GridBubbleVisibilityQaRun.ps1'; TestId='grid-bubble-visibility-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'grid-bubble-offset-v1' = @{ FixtureId='GridBubbleOffsetEmpty'; Source='GridBubbleOffsetEmpty.rvt'; Prep='Prepare-GridBubbleOffsetQaRun.ps1'; TestId='grid-bubble-offset-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'grid-resequence-v1' = @{ FixtureId='GridResequenceEmpty'; Source='GridResequenceEmpty.rvt'; Prep='Prepare-GridResequenceQaRun.ps1'; TestId='grid-resequence-v1'; NativeTestId='grid-resequence-all-directions-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'grid-resequence-all-directions-v1' = @{ FixtureId='GridResequenceEmpty'; Source='GridResequenceEmpty.rvt'; Prep='Prepare-GridResequenceQaRun.ps1'; TestId='grid-resequence-v1'; NativeTestId='grid-resequence-all-directions-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'create-plan-views-v1' = @{ FixtureId='CreatePlanViewsEmpty'; Source='CreatePlanViewsEmpty.rvt'; Prep='Prepare-CreatePlanViewsQaRun.ps1'; TestId='create-plan-views-v1'; NativeTestId='create-plan-views-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
}
function Get-MayaQaWorkflowDefinition { param([Parameter(Mandatory)][string]$WorkflowId)
    if (-not $script:Definitions.ContainsKey($WorkflowId)) { throw "Unsupported QA workflow ID: $WorkflowId" }
    [pscustomobject]$script:Definitions[$WorkflowId]
}
function Resolve-MayaQaWorkflowId {
    param([Parameter(Mandatory)][string]$WorkflowId)
    return [string](Get-MayaQaWorkflowDefinition $WorkflowId).TestId
}
function Get-MayaQaNativeTestId {
    param([Parameter(Mandatory)][object]$Definition)
    if ($Definition.PSObject.Properties.Name -contains 'NativeTestId' -and $Definition.NativeTestId) { return [string]$Definition.NativeTestId }
    return [string]$Definition.TestId
}
function Get-MayaQaRequestIntent {
    param([Parameter(Mandatory)][string]$Request)
    $text = $Request.Trim().ToLowerInvariant()
    $offset = $null
    if ($text -match '(?<value>-?\d+(?:\.\d+)?)\s*mm\b') { $offset = [decimal]$Matches.value }
    $direction = $null
    $directionMap = @{
        'bottom\s+to\s+top' = 'BottomToTop'
        'top\s+to\s+bottom' = 'TopToBottom'
        'left\s+to\s+right' = 'LeftToRight'
        'right\s+to\s+left' = 'RightToLeft'
    }
    foreach ($pattern in $directionMap.Keys) { if ($text -match $pattern) { $direction = $directionMap[$pattern]; break } }
    $levels=@();if($text -match '\blevels?\s+(?<list>.*?)(?:\s+at\s|\s+using\s|\s+named\s|$)'){$levels=@([regex]::Matches($Matches.list,'\d+')|ForEach-Object{[int]$_.Value})}
    $scale=if($text -match '(?<scale>\d+\s*:\s*\d+)'){$Matches.scale -replace '\s',''}else{$null}
    [pscustomobject]@{
        GridSelection = if ($text -match 'selected\s+grids?|selected\s+grid') { 'selected-grids' } else { $null }
        BubbleSides = @(@('left','right','top','bottom') | Where-Object { $text -match "\b$_\b" })
        OffsetMillimetres = $offset
        ResequenceDirection = $direction
        CustomNamingIntent = if ($text -match 'custom\s+naming|name|naming|label|prefix|number') { $Request } else { $null }
        SelectedLevels = $levels
        ViewType = if ($text -match 'floor\s+plan') { 'floor-plan' } elseif ($text -match 'ceiling\s+plan') { 'ceiling-plan' } else { $null }
        Scale = $scale
        TemplateIntent = if ($text -match 'template|using\s+the') { $Request } else { $null }
    }
}
function Get-MayaQaWorkflowCatalog {
    @($script:Definitions.GetEnumerator() | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{WorkflowId=$_.Key;FixtureId=$_.Value.FixtureId;TestId=$_.Value.TestId;PreparationScript=$_.Value.Prep;Capabilities=@($_.Value.Capabilities);SupervisedExecutionRequired=$true;RevitLaunchByCoordinator=$false;RealDeploymentByCoordinator=$false;DryRunSupported=$true}
    })
}
function Resolve-MayaQaTaskStoreIdentity {
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId
    )
    $errors = [System.Collections.Generic.List[string]]::new()
    $data = $null
    try { $data = Read-RepatoTaskStore $StoreRoot } catch { $errors.Add("Task store read failed: $($_.Exception.Message)") }
    $tasks = if ($data -and $data.PSObject.Properties.Name -contains 'tasks') { @($data.tasks) } else { @() }
    $taskMatches = @($tasks | Where-Object { $_.PSObject.Properties.Name -contains 'taskId' -and $_.taskId -ceq $TaskId })
    if ($taskMatches.Count -ne 1) {
        $ids = @($taskMatches | ForEach-Object { [string]$_.taskId }) -join ', '
        $errors.Add("Exact TaskId '$TaskId' matched $($taskMatches.Count) records: [$ids]")
    }
    $workflowMatches = @()
    if ($taskMatches.Count -eq 1) {
        $task = $taskMatches[0]
        if ($task.PSObject.Properties.Name -contains 'mayaPlan') {
            $workflowMatches = @($task | Where-Object { $_.mayaPlan.WorkflowId -ceq $WorkflowId })
        }
        if ($workflowMatches.Count -ne 1) {
            $errors.Add("Exact orchestration WorkflowId '$WorkflowId' did not resolve within TaskId '$TaskId'; matches=$($workflowMatches.Count)")
        }
    }
    $catalogMatches = @($script:Definitions.GetEnumerator() | Where-Object { $_.Key -ceq $QaWorkflowId } | ForEach-Object {
        [pscustomobject]@{ WorkflowId = $_.Key; TestId = $_.Value.TestId }
    })
    if ($catalogMatches.Count -ne 1) {
        $errors.Add("Exact QA catalog QaWorkflowId/TestId '$QaWorkflowId' matched $($catalogMatches.Count) definitions")
    }
    $handoffMatches=@();$attemptMatches=@();$runMatches=@()
    if($taskMatches.Count -eq 1){
        $task=$taskMatches[0]
        $packet=if($task.PSObject.Properties.Name -contains 'mayaTaraQaPacket'){$task.mayaTaraQaPacket}else{$null}
        $attempt=if($task.PSObject.Properties.Name -contains 'mayaTaraAttempt'){$task.mayaTaraAttempt}else{$null}
        if($packet -and $packet.HandoffId -ceq $packet.HandoffId){$handoffMatches=@($packet|Where-Object{$_.TaskId -ceq $TaskId -and $_.WorkflowId -ceq $WorkflowId -and $_.QaWorkflowId -ceq $QaWorkflowId})}
        if($attempt){$attemptMatches=@($attempt|Where-Object{$_.TaskId -ceq $TaskId -and $_.WorkflowId -ceq $WorkflowId -and $_.RunId -ceq $attempt.RunId})}
        if($attemptMatches.Count -eq 1){$runMatches=@($attemptMatches|Where-Object{$_.RunId -ceq $attempt.RunId})}
        if($handoffMatches.Count -ne 1){$errors.Add("Exact persisted Handoff link matched $($handoffMatches.Count) records")}
        if($attemptMatches.Count -ne 1){$errors.Add("Exact persisted Attempt link matched $($attemptMatches.Count) records")}
        if($runMatches.Count -ne 1){$errors.Add("Exact persisted Run link matched $($runMatches.Count) records")}
    }
    [pscustomobject]@{
        TaskMatchCount = $taskMatches.Count
        WorkflowMatchCount = $workflowMatches.Count
        QaCatalogMatchCount = $catalogMatches.Count
        HandoffMatchCount = $handoffMatches.Count
        AttemptMatchCount = $attemptMatches.Count
        RunMatchCount = $runMatches.Count
        SelectedTaskId = if ($taskMatches.Count -eq 1) { $TaskId } else { $null }
        SelectedWorkflowId = if ($workflowMatches.Count -eq 1) { $WorkflowId } else { $null }
        SelectedQaWorkflowId = if ($catalogMatches.Count -eq 1) { $catalogMatches[0].WorkflowId } else { $null }
        SelectedHandoffId = if($handoffMatches.Count -eq 1){$taskMatches[0].mayaTaraQaPacket.HandoffId}else{$null}
        SelectedAttemptId = if($attemptMatches.Count -eq 1){$taskMatches[0].mayaTaraAttempt.AttemptId}else{$null}
        SelectedRunId = if($runMatches.Count -eq 1){$taskMatches[0].mayaTaraAttempt.RunId}else{$null}
        Errors = @($errors)
    }
}
function Assert-MayaQaExecutionIdentity {
    param([object]$Record,[object]$Resolved)
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','HandoffId','AttemptId','RunId') { if([string]$Record.$n -cne [string]$Resolved.('Selected'+$n)) { throw "Execution identity mismatch: $n" } }
    if($Record.QaWorkflowId -cne $Record.TestId){throw 'Execution QA catalog identity mismatch.'}
}
function New-MayaQaExecutionRecord {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][object]$Preflight,[switch]$DryRun)
    $expected=@{TaskId=$TaskId;WorkflowId=$Preflight.WorkflowId;QaWorkflowId=$Preflight.QaWorkflowId}
    $resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $Preflight.WorkflowId $Preflight.QaWorkflowId
    if(@($resolved.Errors).Count){throw ('Canonical execution identity invalid: '+(@($resolved.Errors)-join '; '))}
    foreach($n in 'HandoffId','AttemptId','RunId'){if([string]$Preflight.$n -cne [string]$resolved.('Selected'+$n)){throw "Canonical execution identity mismatch: $n"}}
    $record=[ordered]@{SchemaVersion='maya-tara-execution-v1';TaskId=$resolved.SelectedTaskId;WorkflowId=$resolved.SelectedWorkflowId;QaWorkflowId=$resolved.SelectedQaWorkflowId;TestId=$Preflight.TestId;HandoffId=$resolved.SelectedHandoffId;AttemptId=$resolved.SelectedAttemptId;RunId=$resolved.SelectedRunId;ArtifactPath=$Preflight.ArtifactPath;ArtifactSha256=$Preflight.ArtifactSha256;RunnerManifestPath=$Preflight.RunnerManifest;ValidatedRunnerManifestPath=$Preflight.ValidatedRunnerManifestPath;RunnerManifestSha256=$Preflight.RunnerManifestSha256;ValidatedRunnerManifestSha256=$Preflight.ValidatedRunnerManifestSha256;AuthoritativeFixturePath=$Preflight.FixturePath;AuthoritativeFixtureSha256=$Preflight.FixtureSha256;DisposableRuntimeRoot=([IO.Path]::GetDirectoryName($Preflight.DisposableFixturePath));DisposableModelPath=$Preflight.DisposableFixturePath;DisposableModelSha256=$Preflight.DisposableFixtureSha256;IsolationPolicyPath=$Preflight.Isolation.PolicyPath;IsolationPolicySha256=$Preflight.Isolation.PolicySha256;IsolationAllowed=[bool]$Preflight.Isolation.Allowed;ClaimOwner=$null;ClaimId=$null;ClaimedUtc=$null;ClaimStatus='unclaimed';Stage='prepared';ExecutionStatus='Prepared';PreparedUtc=Get-RepatoUtc;LaunchingUtc=$null;LaunchedUtc=$null;ExecutingUtc=$null;EvidenceCollectedUtc=$null;RollbackStartedUtc=$null;RollbackVerifiedUtc=$null;VerifiedUtc=$null;CompletedUtc=$null;FailedUtc=$null;NativeProcessId=$null;RequestPath=$null;ResultPath=$null;ReportPath=$null;EvidencePath=$null;ReceiptPath=$null;RollbackStatus='Required';VerificationStatus='Pending';CompletionStatus='Pending';FailureCode=$null;FailureDetails=$null;TaskRevisionAtPrepare=$null;TaskRevisionAtClaim=$null;SideEffectsPerformed=$false}
    $record.FixturePreparationEvidence=$Preflight.FixturePreparationEvidence
    if($DryRun){$record.SideEffectsPerformed=$false;return [pscustomobject]$record}
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;$existing=if($task.PSObject.Properties.Name -contains 'mayaTaraExecution'){$task.mayaTaraExecution}else{$null};if($existing){Assert-MayaQaExecutionIdentity $existing $resolved;if($existing.Stage -cne 'prepared' -or $existing.ExecutionStatus -cne 'Prepared'){throw 'Existing Maya Tara execution is not reusable.'};foreach($n in 'ArtifactSha256','RunnerManifestSha256','AuthoritativeFixtureSha256','DisposableModelSha256'){if([string]$existing.$n -cne [string]$record.$n){throw "Existing execution hash mismatch: $n"}};return $existing};$record.TaskRevisionAtPrepare=[long]$task.revision;$task|Add-Member NoteProperty mayaTaraExecution ([pscustomobject]$record) -Force;Add-RepatoHistory $task 'maya-tara-execution-prepared' 'Maya' "attempt=$($record.AttemptId); run=$($record.RunId)";$task.mayaTaraExecution} -DryRun:$DryRun
}
function Claim-MayaQaExecutionRecord {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$ClaimOwner,[Parameter(Mandatory)][object]$Preflight)
    if($ClaimOwner -cne 'Tara'){throw 'Canonical native execution claims must be owned by Tara.'}
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;if($task.PSObject.Properties.Name -notcontains 'mayaTaraExecution'){throw 'Maya Tara execution is not prepared.'};$r=$task.mayaTaraExecution;foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','RunId'){if([string]$r.$n -cne [string]$Preflight.$n){throw "Execution identity mismatch: $n"}};$attempt=if($task.PSObject.Properties.Name -contains 'mayaTaraAttempt'){$task.mayaTaraAttempt}else{$null};if(!$attempt -or $attempt.AttemptId -cne $r.AttemptId -or $attempt.RunId -cne $r.RunId){throw 'Maya Tara attempt is not current.'};$approvedRoot=[IO.Path]::GetFullPath((Get-MayaQaRuntimeRoot)).TrimEnd('\');$candidate=[string]$attempt.RuntimeRoot;if([string]::IsNullOrWhiteSpace($candidate) -or ![IO.Path]::IsPathRooted($candidate)){throw 'Maya Tara RuntimeRoot is missing or relative.'};try{$candidate=[IO.Path]::GetFullPath($candidate)}catch{throw 'Maya Tara RuntimeRoot normalization failed.'};$inside=($candidate -ieq $approvedRoot) -or $candidate.StartsWith($approvedRoot+'\',[StringComparison]::OrdinalIgnoreCase);if(!$inside){throw 'Maya Tara RuntimeRoot escaped the approved QA runtime root.'};if([DateTimeOffset]::Parse($attempt.RequestExpiresUtc) -le [DateTimeOffset]::UtcNow){throw 'Maya Tara attempt is expired.'};if([long]$task.revision -ne ([long]$r.TaskRevisionAtPrepare+1)){throw 'Prepared execution revision is stale or task changed after preparation.'};if($r.Stage -ne 'prepared' -or $r.ExecutionStatus -ne 'Prepared' -or $r.ClaimStatus -ne 'unclaimed'){throw 'Maya Tara execution is not claimable.'};$r.ClaimId=[guid]::NewGuid().ToString('N');$r.ClaimOwner=$ClaimOwner;$r.ClaimedUtc=Get-RepatoUtc;$r.ClaimStatus='claimed';$r.Stage='claimed';$r.ExecutionStatus='Claimed';$r.TaskRevisionAtClaim=[long]$task.revision;Add-RepatoHistory $task 'maya-tara-execution-claimed' $ClaimOwner "claim=$($r.ClaimId); attempt=$($r.AttemptId); run=$($r.RunId)";$r}
}
function Get-MayaQaAttemptDurationMinutes { 30 }
function Test-MayaQaFixturePreparationRecord {
    param([Parameter(Mandatory)][string]$QaRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$SourceSha256,[Parameter(Mandatory)]$Evidence)
    $qa=[IO.Path]::GetFullPath($QaRoot);$runs=[IO.Path]::GetFullPath((Join-Path $qa 'TestRuns'));$prefix=$runs.TrimEnd('\')+'\';$requestPath=[IO.Path]::GetFullPath([string]$Evidence.RequestPath);$resultPath=[IO.Path]::GetFullPath([string]$Evidence.ResultPath);$modelPath=[IO.Path]::GetFullPath([string]$Evidence.PreparedModelPath)
    foreach($path in @($requestPath,$resultPath,$modelPath)){if(!$path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $path -PathType Leaf)){throw 'Recorded fixture preparation evidence path is missing or outside QA TestRuns.'}}
    if((Get-FileHash -LiteralPath $requestPath -Algorithm SHA256).Hash -ine $Evidence.RequestSha256 -or (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash -ine $Evidence.ResultSha256 -or (Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash -ine $Evidence.PreparedModelSha256){throw 'Recorded fixture preparation evidence hash mismatch.'}
    try{$request=Get-Content -LiteralPath $requestPath -Raw|ConvertFrom-Json;$result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json}catch{throw 'Recorded fixture preparation evidence is malformed.'}
    if((Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash -ine $SourceSha256 -or [string]$request.operation -cne 'prepare-disposable-create-plan-views-fixture' -or [string]$request.requestPath -ine $requestPath -or [string]$request.outputPath -ine $resultPath -or [string]$request.modelPath -ine $modelPath -or [string]$request.modelSha256 -ine $SourceSha256 -or [string]$request.taskId -cne $TaskId -or [string]$request.workflowId -cne $WorkflowId -or [string]$request.attemptId -cne $Evidence.AttemptId -or [string]$request.runId -cne $Evidence.RunId -or [string]$request.attemptId -cnotmatch '^[a-fA-F0-9]{32}$' -or [string]$request.runId -cnotmatch '^[a-fA-F0-9]{32}$' -or [string]$result.Status -cne 'Passed' -or [string]$result.Operation -cne [string]$request.operation -or [string]$result.TaskId -cne $TaskId -or [string]$result.WorkflowId -cne $WorkflowId -or [string]$result.AttemptId -cne $Evidence.AttemptId -or [string]$result.RunId -cne $Evidence.RunId -or [string]$result.ModelPath -ine $modelPath -or [string]$result.SourceModelSha256 -ine $SourceSha256 -or [string]$result.PreparedModelSha256 -ine $Evidence.PreparedModelSha256){throw 'Recorded fixture preparation request/result identity or model hash mismatch.'}
    $true
}
function Read-MayaQaFixturePreparationRecord {
    param([Parameter(Mandatory)][string]$QaRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$SourceSha256,[Parameter(Mandatory)][string]$ResultPath)
    $result=[IO.Path]::GetFullPath($ResultPath);$runs=[IO.Path]::GetFullPath((Join-Path $QaRoot 'TestRuns')).TrimEnd('\')+'\'
    if(!$result.StartsWith($runs,[StringComparison]::OrdinalIgnoreCase) -or !$result.EndsWith('.request.json.preparation.json',[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $result -PathType Leaf)){throw 'Fixture preparation result path is not an authenticated QA result.'}
    $request=$result.Substring(0,$result.Length-('.preparation.json'.Length));if(!(Test-Path -LiteralPath $request -PathType Leaf)){throw 'Correlated fixture preparation request is missing.'}
    try{$rq=Get-Content -LiteralPath $request -Raw|ConvertFrom-Json;$rs=Get-Content -LiteralPath $result -Raw|ConvertFrom-Json}catch{throw 'Fixture preparation request/result is malformed.'}
    $e=[pscustomobject]@{RequestPath=$request;RequestSha256=(Get-FileHash -LiteralPath $request -Algorithm SHA256).Hash;ResultPath=$result;ResultSha256=(Get-FileHash -LiteralPath $result -Algorithm SHA256).Hash;AttemptId=[string]$rq.attemptId;RunId=[string]$rq.runId;SourceSha256=$SourceSha256;PreparedModelPath=[IO.Path]::GetFullPath([string]$rq.modelPath);PreparedModelSha256=[string]$rs.PreparedModelSha256}
    $null=Test-MayaQaFixturePreparationRecord -QaRoot $QaRoot -TaskId $TaskId -WorkflowId $WorkflowId -SourcePath $SourcePath -SourceSha256 $SourceSha256 -Evidence $e
    $e
}
function Test-MayaQaHistoricalPacketContinuation {
    param([Parameter(Mandatory)]$Task,[Parameter(Mandatory)]$Packet,[Parameter(Mandatory)]$CurrentAttempt,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaRoot)
    $source=@($Task.mayaTaraExecutionHistory|Where-Object {$_.AttemptId -ceq $Packet.AttemptId -and $_.RunId -ceq $Packet.RunId})
    if($source.Count -ne 1){throw 'Expired recovery packet identity is not backed by one archived execution.'};$source=$source[0]
    $sourceAttempt=@($Task.mayaTaraAttemptHistory|Where-Object {$_.AttemptId -ceq $Packet.AttemptId -and $_.RunId -ceq $Packet.RunId})
    if($sourceAttempt.Count -ne 1){throw 'Expired recovery packet identity is not backed by one archived attempt.'}
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId'){if([string]$Packet.$n -cne [string]$source.$n){throw "Expired recovery historical packet execution mismatch: $n"}};if($source.TaskId -cne $TaskId -or $source.WorkflowId -cne $WorkflowId -or $CurrentAttempt.TaskId -cne $TaskId -or $CurrentAttempt.WorkflowId -cne $WorkflowId){throw 'Expired recovery historical packet task or workflow identity mismatch.'}
    foreach($pair in @(@('ArtifactPath','ArtifactPath'),@('ArtifactSha256','ArtifactSha256'),@('RunnerManifestPath','RunnerManifestPath'),@('RunnerManifestSha256','RunnerManifestSha256'),@('FixturePath','AuthoritativeFixturePath'),@('FixtureSha256','AuthoritativeFixtureSha256'),@('ModelPath','DisposableModelPath'),@('DisposableModelSha256','DisposableModelSha256'))){if([string]$Packet.($pair[0]) -ine [string]$source.($pair[1])){throw "Expired recovery historical packet execution mismatch: $($pair[0])"}}
    if([IO.Path]::GetFullPath($Packet.SidecarPath) -ine [IO.Path]::GetFullPath($source.DisposableModelPath+'.fixture.json')){throw 'Expired recovery historical packet sidecar identity mismatch.'}
    $qa=[IO.Path]::GetFullPath($QaRoot);$runRoot=[IO.Path]::GetFullPath((Join-Path $qa 'TestRuns'));$reportRoot=[IO.Path]::GetFullPath((Join-Path $qa 'Reports'));$model=[IO.Path]::GetFullPath($source.DisposableModelPath)
    if(!$model.StartsWith($runRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $model -PathType Leaf) -or (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ine $source.DisposableModelSha256){throw 'Expired recovery historical packet model evidence is invalid.'}
    $sidecarPath=[IO.Path]::GetFullPath($source.DisposableModelPath+'.fixture.json');if(!(Test-Path -LiteralPath $sidecarPath -PathType Leaf)){throw 'Expired recovery historical packet fixture sidecar is missing.'};try{$sidecar=Get-Content -LiteralPath $sidecarPath -Raw|ConvertFrom-Json}catch{throw 'Expired recovery historical packet fixture sidecar is malformed.'};if([string]$sidecar.fixtureId -cne [string](Get-MayaQaWorkflowDefinition $Packet.QaWorkflowId).FixtureId -or [string]$sidecar.sourceSha256 -ine [string]$source.AuthoritativeFixtureSha256){throw 'Expired recovery historical packet fixture sidecar identity mismatch.'}
    if(!$source.ResultPath -or !$source.ReportPath -or !$source.ResultSha256 -or !$source.ReportSha256){throw 'Expired recovery historical packet has no complete result and report evidence.'}
    $resultPath=[IO.Path]::GetFullPath($source.ResultPath);$reportPath=[IO.Path]::GetFullPath($source.ReportPath)
    if(!$resultPath.StartsWith($runRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or !$reportPath.StartsWith($reportRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $resultPath -PathType Leaf) -or !(Test-Path -LiteralPath $reportPath -PathType Leaf) -or (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash -ine $source.ResultSha256 -or (Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash -ine $source.ReportSha256){throw 'Expired recovery historical packet result or report integrity check failed.'}
    try{$result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json;$report=Get-Content -LiteralPath $reportPath -Raw|ConvertFrom-Json}catch{throw 'Expired recovery historical packet result or report is malformed.'}
    foreach($evidence in @($result,$report)){foreach($n in 'TaskId','AttemptId','RunId'){if([string]$evidence.$n -cne [string]$source.$n){throw "Expired recovery historical packet report identity mismatch: $n"}};if([string]$evidence.Status -cne 'Failed'){throw 'Expired recovery historical packet report is not a recorded failed run.'}}
    $seen=@{};$edge=$source
    for($i=0;$i -le @($Task.mayaTaraExecutionHistory).Count;$i++){
        $key=[string]$edge.AttemptId+'/'+[string]$edge.RunId;if($seen.ContainsKey($key)){throw 'Expired recovery historical packet replacement chain contains a cycle.'};$seen[$key]=$true
        if($edge.ReplacementAttemptId -ceq $CurrentAttempt.AttemptId -and $edge.ReplacementRunId -ceq $CurrentAttempt.RunId){return $source}
        if([string]::IsNullOrWhiteSpace([string]$edge.ReplacementAttemptId) -or [string]::IsNullOrWhiteSpace([string]$edge.ReplacementRunId)){break}
        $next=@($Task.mayaTaraExecutionHistory|Where-Object {$_.AttemptId -ceq $edge.ReplacementAttemptId -and $_.RunId -ceq $edge.ReplacementRunId})
        if($next.Count -ne 1){break};$next=$next[0];$nextAttempt=@($Task.mayaTaraAttemptHistory|Where-Object {$_.AttemptId -ceq $next.AttemptId -and $_.RunId -ceq $next.RunId});if($nextAttempt.Count -ne 1 -or $next.TaskId -cne $TaskId -or $next.WorkflowId -cne $WorkflowId -or $next.HandoffId -cne $source.HandoffId -or $next.TestId -cne $source.TestId){throw 'Expired recovery historical packet replacement-chain identity mismatch.'};$edge=$next
    }
    throw 'Expired recovery historical packet has no verified replacement chain to the current attempt and run.'
}
function Recover-MayaQaExpiredExecutionRecord {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[ValidateRange(1,1440)][Nullable[int]]$AttemptDurationMinutes,[string]$RuntimeRoot,[long]$ExpectedTaskRevision=0,[switch]$DryRun)
    if($null -eq $AttemptDurationMinutes){$AttemptDurationMinutes=Get-MayaQaAttemptDurationMinutes}
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;if($ExpectedTaskRevision -gt 0 -and [long]$task.revision -ne $ExpectedTaskRevision){throw 'Recovery task revision is stale.'}
    if($task.PSObject.Properties.Name -notcontains 'mayaTaraExecution' -or $task.PSObject.Properties.Name -notcontains 'mayaTaraAttempt'){throw 'Canonical Maya Tara execution and attempt are required.'}
    $old=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt;$resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $task.mayaPlan.WorkflowId $task.mayaPlan.QaWorkflowId;if(@($resolved.Errors).Count){throw ('Canonical recovery identity invalid: '+(@($resolved.Errors)-join '; '))}
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','HandoffId','AttemptId','RunId'){if([string]$old.$n -cne [string]$resolved.('Selected'+$n)){throw "Recovery identity mismatch: $n"}}
    $claimedRecovery=($old.Stage -ceq 'claimed' -and $old.ExecutionStatus -ceq 'Claimed' -and $old.ClaimStatus -ceq 'claimed')
    $preparedRecovery=($old.Stage -ceq 'prepared' -and $old.ExecutionStatus -ceq 'Prepared' -and $old.ClaimStatus -ceq 'unclaimed' -and !$old.ClaimId -and !$old.ClaimOwner)
    if(!$claimedRecovery -and !$preparedRecovery){throw 'Execution is not eligible for automatic recovery.'}
    if($claimedRecovery -and ($old.ClaimOwner -cne 'Tara' -or [string]::IsNullOrWhiteSpace([string]$old.ClaimId))){throw 'Claimed execution has invalid ownership or claim identity.'}
    foreach($n in 'NativeProcessId','LaunchingUtc','LaunchedUtc','ExecutingUtc','RequestPath','ResultPath','ReportPath','EvidencePath','ReceiptPath'){if($old.PSObject.Properties.Name -contains $n -and $old.$n){throw "Execution contains launch evidence: $n"}}
    if($old.SideEffectsPerformed){throw 'Execution has side effects and requires reconciliation.'}
    if([DateTimeOffset]::Parse($attempt.RequestExpiresUtc) -gt [DateTimeOffset]::UtcNow){throw 'Current Maya Tara attempt is not expired.'}
    foreach($n in 'RequestPath','ResultPath','ReportPath','EvidencePath','ReceiptPath'){if($old.PSObject.Properties.Name -contains $n -and $old.$n){throw 'Execution contains native evidence and cannot be auto-recovered.'}}
    if($task.PSObject.Properties.Name -contains 'mayaTaraExecutionHistory' -and @($task.mayaTaraExecutionHistory|Where-Object{$_.AttemptId -ceq $attempt.AttemptId}).Count){throw 'Expired attempt was already recovered.'}
    $qa=[IO.Path]::GetFullPath((Get-MayaQaRoot));$source=[IO.Path]::GetFullPath($old.AuthoritativeFixturePath);$fixtures=[IO.Path]::GetFullPath((Join-Path $qa 'Fixtures'));$runs=[IO.Path]::GetFullPath($(if($RuntimeRoot){$RuntimeRoot}else{Get-MayaQaRuntimeRoot}));$prefix=$fixtures.TrimEnd('\')+'\';if(!$source.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Authoritative fixture escaped approved fixture root.'};$sourceHash=(Get-FileHash $source -Algorithm SHA256).Hash;if($sourceHash -ine $old.AuthoritativeFixtureSha256){throw 'Authoritative fixture hash mismatch.'}
    $packet=$null;$retainPreparationEvidence=$false;$recoveryModelSource=$source;$recoveryModelHash=$sourceHash
    if($task.PSObject.Properties.Name -contains 'mayaTaraQaPacket' -and $task.mayaTaraQaPacket -and $task.mayaTaraQaPacket.SchemaVersion -ceq 'maya-tara-qa-packet-v3'){
        $packet=$task.mayaTaraQaPacket;$plan=$task.mayaPlan;$workflow=Get-DeployWorkflow $StoreRoot $TaskId $resolved.SelectedWorkflowId;$e=$workflow.qaBuildEvidence
        if(!$plan -or $plan.TaskId -cne $TaskId -or $plan.WorkflowId -cne $resolved.SelectedWorkflowId -or $plan.QaWorkflowId -cne $resolved.SelectedQaWorkflowId -or $plan.Stage -cne 'qa-prepared' -or $plan.NextAgent -cne 'Tara' -or $plan.NextOperation -cne 'canonical-execution-record' -or $plan.SideEffectsPerformed -ne $false){throw 'Expired recovery canonical plan is invalid.'}
        if($packet.SchemaVersion -cne 'maya-tara-qa-packet-v3' -or $packet.Stage -cne 'prepared' -or $packet.SideEffectsPerformed -ne $false -or $packet.TaskId -cne $TaskId -or $packet.WorkflowId -cne $resolved.SelectedWorkflowId -or $packet.QaWorkflowId -cne $resolved.SelectedQaWorkflowId -or $packet.TestId -cne $old.TestId -or $packet.HandoffId -cne $old.HandoffId -or $packet.HandoffId -cne $resolved.SelectedHandoffId){throw 'Expired recovery packet identity is invalid.'}
        $packetSource=$null;if($packet.AttemptId -cne $attempt.AttemptId -or $packet.RunId -cne $attempt.RunId){$packetSource=Test-MayaQaHistoricalPacketContinuation -Task $task -Packet $packet -CurrentAttempt $attempt -TaskId $TaskId -WorkflowId $resolved.SelectedWorkflowId -QaRoot $qa}
        if(!$e -or $workflow.qaBuildStatus -cne 'succeeded' -or $e.BuildStatus -cne 'succeeded' -or $e.EvidenceSource -cne 'FrozenCandidate' -or $e.SourceCommit -cne $e.CandidateSourceCommit -or $e.ArtifactPath -cne $old.ArtifactPath -or $e.ArtifactSha256 -ine $old.ArtifactSha256 -or $e.ArtifactSha256 -ine $packet.ArtifactSha256 -or $e.RunnerManifestPath -cne $old.RunnerManifestPath -or $e.RunnerManifestSha256 -ine $old.RunnerManifestSha256 -or !$e.DeploymentValidation -or !$e.ManifestIntegrityValidation -or !$e.QaIsolation -or !$old.IsolationAllowed){throw 'Expired recovery candidate, manifest, or isolation evidence is invalid.'}
        $null=Test-MayaQaFrozenCandidate -CandidateDirectory $e.CandidateDirectory -CandidateDllPath $e.ArtifactPath -ExpectedSha256 $e.ArtifactSha256 -ExpectedSourceCommit $e.CandidateSourceCommit -QaWorkflowId $resolved.SelectedQaWorkflowId
        $packetModelSource=if($packetSource){$packetSource}else{$old};if((Get-FileHash -LiteralPath $e.ManifestPath -Algorithm SHA256).Hash -ine $e.ManifestSha256 -or $packet.ArtifactPath -cne $e.ArtifactPath -or $packet.ManifestPath -cne $e.ManifestPath -or $packet.ManifestSha256 -ine $e.ManifestSha256 -or $packet.FixtureSha256 -ine $sourceHash -or [IO.Path]::GetFullPath($packet.FixturePath) -ine $source -or $packet.DisposableModelSha256 -ine $packetModelSource.DisposableModelSha256){throw 'Expired recovery packet or frozen artifact hashes are invalid.'}
        if(!$e.Isolation -or !$e.Isolation.Allowed -or $e.Isolation.PolicyPath -cne $old.IsolationPolicyPath -or $e.Isolation.PolicySha256 -ine $old.IsolationPolicySha256 -or !(Test-Path -LiteralPath $old.IsolationPolicyPath -PathType Leaf) -or (Get-FileHash -LiteralPath $old.IsolationPolicyPath -Algorithm SHA256).Hash -ine $old.IsolationPolicySha256){throw 'Expired recovery isolation policy validation failed.'}
        if([IO.Path]::GetFullPath($packet.ModelPath) -ine [IO.Path]::GetFullPath($packetModelSource.DisposableModelPath) -or [IO.Path]::GetFullPath($packet.SidecarPath) -ine [IO.Path]::GetFullPath($packetModelSource.DisposableModelPath+'.fixture.json')){throw 'Expired recovery packet model identity is invalid.'}
        if($packetSource -and (ConvertTo-Json -InputObject $packet.FixturePreparationEvidence -Depth 20 -Compress) -cne (ConvertTo-Json -InputObject $packetSource.FixturePreparationEvidence -Depth 20 -Compress)){throw 'Expired recovery historical packet fixture preparation evidence mismatch.'}
        if($old.FixturePreparationEvidence){$prep=$old.FixturePreparationEvidence;$null=Test-MayaQaFixturePreparationRecord -QaRoot $qa -TaskId $TaskId -WorkflowId $resolved.SelectedWorkflowId -SourcePath $source -SourceSha256 $sourceHash -Evidence $prep;if((Get-FileHash -LiteralPath $old.DisposableModelPath -Algorithm SHA256).Hash -ine $old.DisposableModelSha256){throw 'Expired recovery disposable model hash mismatch.'};if($old.DisposableModelSha256 -ieq $sourceHash){$recoveryModelSource=[IO.Path]::GetFullPath([string]$prep.PreparedModelPath);$recoveryModelHash=[string]$prep.PreparedModelSha256;$retainPreparationEvidence=$true}elseif($old.DisposableModelSha256 -ieq $prep.PreparedModelSha256){$recoveryModelSource=[IO.Path]::GetFullPath([string]$old.DisposableModelPath);$recoveryModelHash=[string]$old.DisposableModelSha256;$retainPreparationEvidence=$true}else{throw 'Expired recovery disposable model has no correlated preparation evidence.'}}elseif($old.DisposableModelSha256 -ine $sourceHash){throw 'Expired recovery model requires missing fixture preparation evidence.'}
        if(@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'}).Count){throw 'A pending QA approval already exists for expired recovery.'}
    }
    $newAttempt=[guid]::NewGuid().ToString('N');$newRun=[guid]::NewGuid().ToString('N');$runtime=[IO.Path]::GetFullPath((Join-Path $runs ($newRun+'-recovery')));$runPrefix=$runs.TrimEnd('\')+'\';if(!$runtime.StartsWith($runPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Recovery runtime escaped approved QA root.'};if($runtime -ieq ([IO.Path]::GetDirectoryName($old.DisposableModelPath))){throw 'Historical runtime cannot be reused.'};if(Test-Path -LiteralPath $runtime){throw 'Recovery runtime already exists.'}
    $model=Join-Path $runtime 'model.rvt';$sidecar=$model+'.fixture.json';$def=Get-MayaQaWorkflowDefinition $resolved.SelectedQaWorkflowId
    if(!$DryRun){try{New-Item -ItemType Directory -Path $runtime|Out-Null;Copy-Item -LiteralPath $recoveryModelSource -Destination $model;$modelHash=(Get-FileHash $model -Algorithm SHA256).Hash;if($modelHash -ine $recoveryModelHash){throw 'Recovered disposable model hash mismatch.'};$side=[ordered]@{fixtureId=$def.FixtureId;sourceSha256=$sourceHash};if($retainPreparationEvidence){$prep=$old.FixturePreparationEvidence;$side.preparedModelSha256=$prep.PreparedModelSha256;$side.fixturePreparationRequestPath=$prep.RequestPath;$side.fixturePreparationRequestSha256=$prep.RequestSha256;$side.fixturePreparationResultPath=$prep.ResultPath;$side.fixturePreparationResultSha256=$prep.ResultSha256;$side.fixturePreparationAttemptId=$prep.AttemptId;$side.fixturePreparationRunId=$prep.RunId};if($resolved.SelectedQaWorkflowId -eq 'grid-bubble-visibility-v1' -or $resolved.SelectedQaWorkflowId -eq 'grid-bubble-offset-v1'){$side.requiredGridNames=@('A','B','C','D','1','2','3','4')};if($resolved.SelectedQaWorkflowId -eq 'grid-resequence-v1'){$side.requiredGridNames=@('1','2','3','3.2','4','A','A.1','B','C')};$side|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $sidecar -Encoding UTF8;$check=Get-Content -LiteralPath $sidecar -Raw|ConvertFrom-Json;if(!(Test-Path -LiteralPath $model -PathType Leaf) -or $check.fixtureId -cne $def.FixtureId -or $check.sourceSha256 -ine $sourceHash -or (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ine $modelHash -or ($retainPreparationEvidence -and ([string]$check.preparedModelSha256 -ine [string]$prep.PreparedModelSha256 -or [string]$check.fixturePreparationRequestSha256 -ine [string]$prep.RequestSha256 -or [string]$check.fixturePreparationResultSha256 -ine [string]$prep.ResultSha256))){throw 'Recovered disposable model or fixture sidecar validation failed.'}}catch{if(Test-Path -LiteralPath $runtime){Remove-Item -LiteralPath $runtime -Recurse -Force -ErrorAction SilentlyContinue};throw}}else{$modelHash=$recoveryModelHash}
    $newExpiry=[DateTimeOffset]::UtcNow.AddMinutes($AttemptDurationMinutes).ToString('O');$newAttemptRecord=[pscustomobject][ordered]@{SchemaVersion='maya-tara-execution-request-v1';AttemptId=$newAttempt;TaskId=$TaskId;WorkflowId=$resolved.SelectedWorkflowId;RunId=$newRun;RuntimeRoot=$runtime;RequestExpiresUtc=$newExpiry;Stage='prepared';Success=$false;RequestPath=$null}
    $newExec=[ordered]@{};foreach($p in $old.PSObject.Properties){$newExec[$p.Name]=$p.Value};$newExec.AttemptId=$newAttempt;$newExec.RunId=$newRun;$newExec.DisposableRuntimeRoot=$runtime;$newExec.DisposableModelPath=$model;$newExec.DisposableModelSha256=$modelHash;$newExec.FixturePreparationEvidence=if($retainPreparationEvidence){$old.FixturePreparationEvidence}else{$null};$newExec.Stage='prepared';$newExec.ExecutionStatus='Prepared';$newExec.ClaimStatus='unclaimed';$newExec.ClaimOwner=$null;$newExec.ClaimId=$null;$newExec.ClaimedUtc=$null;$newExec.TaskRevisionAtPrepare=$null;$newExec.TaskRevisionAtClaim=$null;$newExec.NativeProcessId=$null;$newExec.SideEffectsPerformed=$false;$newExec.PreparedUtc=Get-RepatoUtc;$newExec.FailureCode=$null;$newExec.FailureDetails=$null
    if($DryRun){return [pscustomobject]@{Mode='DryRun';TaskId=$TaskId;WorkflowId=$resolved.SelectedWorkflowId;QaWorkflowId=$resolved.SelectedQaWorkflowId;HandoffId=$resolved.SelectedHandoffId;OldAttemptId=$attempt.AttemptId;OldRunId=$attempt.RunId;NewAttemptId=$newAttempt;NewRunId=$newRun;RuntimeRoot=$runtime;DisposableModelPath=$model;DisposableModelSha256=$modelHash;SideEffectsPerformed=$false}}
    try{Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$nowAttempt=$t.mayaTaraAttempt;$nowExec=$t.mayaTaraExecution;if($t.revision -ne $task.revision -or $nowAttempt.AttemptId -cne $attempt.AttemptId -or $nowAttempt.RunId -cne $attempt.RunId -or $nowExec.AttemptId -cne $old.AttemptId -or $nowExec.RunId -cne $old.RunId){throw 'Recovery compare-and-swap failed: task changed.'};if([DateTimeOffset]::Parse($nowAttempt.RequestExpiresUtc)-gt[DateTimeOffset]::UtcNow){throw 'Current attempt is no longer expired.'};if($packet){$nowPacket=$t.mayaTaraQaPacket;$nowPlan=$t.mayaPlan;$nowWorkflows=@($t.deploymentWorkflows|Where-Object workflowId -ceq $resolved.SelectedWorkflowId);if(!$nowPacket -or (ConvertTo-Json -InputObject $nowPacket -Depth 20 -Compress) -cne (ConvertTo-Json -InputObject $packet -Depth 20 -Compress) -or !$nowPlan -or $nowPlan.TaskId -cne $plan.TaskId -or $nowPlan.WorkflowId -cne $plan.WorkflowId -or $nowPlan.QaWorkflowId -cne $plan.QaWorkflowId -or $nowPlan.Stage -cne $plan.Stage -or $nowWorkflows.Count -ne 1 -or [long]$nowWorkflows[0].workflowRevision -ne [long]$workflow.workflowRevision -or $nowWorkflows[0].qaBuildEvidence.ArtifactSha256 -ine $e.ArtifactSha256 -or $nowWorkflows[0].qaBuildEvidence.RunnerManifestSha256 -ine $e.RunnerManifestSha256){throw 'Recovery compare-and-swap failed: packet, plan, or candidate changed.'};if(@($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'}).Count){throw 'Recovery compare-and-swap failed: pending QA approval appeared.'}};$archived=[pscustomobject]$old;$archived|Add-Member NoteProperty Stage 'expired' -Force;$archived|Add-Member NoteProperty ExecutionStatus 'Expired' -Force;$archived|Add-Member NoteProperty ClaimStatus 'expired' -Force;$archived|Add-Member NoteProperty FailureCode 'attempt-expired' -Force;$archived|Add-Member NoteProperty FailureDetails 'Unclaimed prepared attempt expired before native launch.' -Force;$archived|Add-Member NoteProperty ExpiredUtc (Get-RepatoUtc) -Force;$archived|Add-Member NoteProperty ReplacementAttemptId $newAttempt -Force;$archived|Add-Member NoteProperty ReplacementRunId $newRun -Force;if($t.PSObject.Properties.Name -notcontains 'mayaTaraExecutionHistory'){$t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@()) -Force};if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force};$t.mayaTaraExecutionHistory=[object[]]@($t.mayaTaraExecutionHistory)+$archived;$t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$nowAttempt;$t.mayaTaraAttempt=$newAttemptRecord;$newExec.TaskRevisionAtPrepare=[long]$t.revision;$t.mayaTaraExecution=[pscustomobject]$newExec;if($packet){if($t.PSObject.Properties.Name -notcontains 'mayaTaraQaPacketHistory'){$t|Add-Member NoteProperty mayaTaraQaPacketHistory ([object[]]@()) -Force};$archivedPacket=ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $packet -Depth 20 -Compress);$t.mayaTaraQaPacketHistory=[object[]]@($t.mayaTaraQaPacketHistory)+[pscustomobject]@{Packet=$archivedPacket;AttemptId=$packet.AttemptId;RunId=$packet.RunId;ArchivedUtc=Get-RepatoUtc};$t.mayaTaraQaPacket=[pscustomobject][ordered]@{SchemaVersion='maya-tara-qa-packet-v3';HandoffId=$old.HandoffId;TaskId=$TaskId;WorkflowId=$resolved.SelectedWorkflowId;QaWorkflowId=$resolved.SelectedQaWorkflowId;TestId=$old.TestId;RunId=$newRun;AttemptId=$newAttempt;ArtifactPath=$e.ArtifactPath;ArtifactSha256=$e.ArtifactSha256;ManifestPath=$e.ManifestPath;ManifestSha256=$e.ManifestSha256;RunnerManifestPath=$e.RunnerManifestPath;RunnerManifestSha256=$e.RunnerManifestSha256;ModelPath=$model;SidecarPath=$sidecar;FixturePath=$source;FixtureSha256=$sourceHash;DisposableModelSha256=$modelHash;FixturePreparationEvidence=if($retainPreparationEvidence){$old.FixturePreparationEvidence}else{$null};RequestExpiresUtc=$newExpiry;Stage='prepared';SideEffectsPerformed=$false;StoreRoot=$StoreRoot}};Add-RepatoHistory $t 'maya-tara-attempt-recovered' 'Maya' "expiredAttempt=$($attempt.AttemptId); expiredRun=$($attempt.RunId); replacementAttempt=$newAttempt; replacementRun=$newRun";$t.mayaTaraExecution}}catch{if(!$DryRun -and (Test-Path -LiteralPath $runtime)){Remove-Item -LiteralPath $runtime -Recurse -Force -ErrorAction SilentlyContinue};throw}
}
function Remove-MayaQaExpiredOrphanedPreparation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$ExpectedFailedAttemptId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$ExpectedOrphanedRunId,
        [scriptblock]$ProcessProvider,
        [switch]$DryRun
    )
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    if($task.status -cne 'in-progress' -or $task.workflowStage -cne 'build-checks'){throw 'Expired orphaned preparation archival requires the replacement build-checks state.'}
    $retirement=if($task.PSObject.Properties['mayaQaCandidateReplacementRetirement']){$task.mayaQaCandidateReplacementRetirement}else{$null}
    if(!$retirement -or !$retirement.PSObject.Properties['WorkflowId'] -or $retirement.WorkflowId -cne $WorkflowId -or
        !$retirement.PSObject.Properties['FailedAttemptId'] -or [string]$retirement.FailedAttemptId -cne $ExpectedFailedAttemptId -or
        !$retirement.PSObject.Properties['RecoveredAttemptId'] -or !$retirement.PSObject.Properties['RecoveredRunId'] -or
        $retirement.ConsumedApprovalPreserved -ne $true -or $retirement.NativeLaunchAbsent -ne $true){throw 'Candidate-replacement retirement identity is invalid for expired orphaned preparation archival.'}
    foreach($name in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){if($task.PSObject.Properties[$name] -and $null -ne $task.$name){throw 'Active Tara execution state prevents expired orphaned preparation archival.'}}
    if(Test-MayaQaHasActiveCanonicalExecutionApproval -Approvals @($task.approvalRequests)){throw 'An unexpired QA approval prevents expired orphaned preparation archival.'}
    $processes=@();if($ProcessProvider){$processes=@(& $ProcessProvider)}else{$processes=@(Get-Process -Name Revit -ErrorAction SilentlyContinue)}
    if($processes.Count){throw 'Expired orphaned preparation archival is blocked while Revit is running.'}
    $workflows=@($task.deploymentWorkflows|Where-Object {$_.workflowId -ceq $WorkflowId -and $_.taskId -ceq $TaskId})
    if($workflows.Count -ne 1){throw 'Expired orphaned preparation archival workflow identity is ambiguous.'}
    $w=$workflows[0]
    foreach($name in 'qaRunId','qaModelPath','qaSidecarPath'){if($w.PSObject.Properties[$name]){throw 'Expired orphaned preparation archival found an active QA run binding.'}}
    if(!$w.PSObject.Properties['qaFixturePreparationEvidence'] -or !$w.qaFixturePreparationEvidence){throw 'No expired orphaned preparation evidence is present.'}
    $prior=$w.qaFixturePreparationEvidence
    if([string]$prior.AttemptId -cne $ExpectedFailedAttemptId -or [string]$prior.RunId -cne $ExpectedOrphanedRunId){throw 'Expired orphaned preparation identity does not match the archived replacement attempt.'}
    if(!$w.PSObject.Properties['qaDisposableModelSha256'] -or [string]$w.qaDisposableModelSha256 -ine [string]$prior.PreparedModelSha256){throw 'Expired orphaned disposable model hash is missing or does not match the preparation evidence.'}
    $consumedApprovals=@($task.approvalRequests|Where-Object {$_.PSObject.Properties['requestId'] -and $_.PSObject.Properties['action'] -and $_.PSObject.Properties['status'] -and $_.requestId -ceq [string]$retirement.ApprovalRequestId -and $_.action -ceq 'qa-run'})
    if($consumedApprovals.Count -ne 1 -or $consumedApprovals[0].status -cne 'approved' -or !$consumedApprovals[0].consumedUtc){throw 'Candidate-replacement consumed approval identity is invalid.'}
    if($consumedApprovals[0].PSObject.Properties['executionBinding'] -and $consumedApprovals[0].executionBinding -and $consumedApprovals[0].executionBinding.PSObject.Properties['RunId'] -and [string]$consumedApprovals[0].executionBinding.RunId -and [string]$consumedApprovals[0].executionBinding.RunId -ine $ExpectedOrphanedRunId){throw 'Consumed approval run identity does not match the orphaned preparation run.'}
    $archivedRunOk=$false
    if($w.PSObject.Properties['qaHandoffHistory']){
        $archivedRunOk=(@(@($w.qaHandoffHistory)|Where-Object {$_ -and [string]$_.RunId -ceq $ExpectedOrphanedRunId}).Count -eq 1)
    }
    $archivedFailureCount=0
    if($task.PSObject.Properties['mayaTaraExecutionHistory']){$archivedFailureCount=@(@($task.mayaTaraExecutionHistory)|Where-Object {$_.AttemptId -ceq $ExpectedFailedAttemptId}).Count}
    if(!$archivedRunOk -or $archivedFailureCount -lt 1){throw 'Archived prior run identity is required before expired orphaned preparation archival.'}
    if($w.PSObject.Properties['qaFixturePreparationEvidenceHistory']){
        if(@(@($w.qaFixturePreparationEvidenceHistory)|Where-Object {$_ -and $_.Evidence -and (ConvertTo-Json -InputObject $_.Evidence -Depth 20 -Compress) -ceq (ConvertTo-Json -InputObject $prior -Depth 20 -Compress)}).Count){throw 'Expired orphaned preparation evidence is already archived.'}
    }
    $qaRoot=Get-MayaQaRoot
    if(!$w.PSObject.Properties['qaWorkflowId'] -or [string]::IsNullOrWhiteSpace([string]$w.qaWorkflowId)){throw 'Expired orphaned preparation archival requires the QA workflow identity.'}
    $def=Get-MayaQaWorkflowDefinition ([string]$w.qaWorkflowId)
    $sourceFixture=[IO.Path]::GetFullPath((Join-Path (Join-Path $qaRoot 'Fixtures') ([string]$def.Source)))
    if(!(Test-Path -LiteralPath $sourceFixture -PathType Leaf)){throw 'Approved fixture is missing for expired orphaned preparation validation.'}
    $sourceFixtureHash=(Get-FileHash -LiteralPath $sourceFixture -Algorithm SHA256).Hash
    $null=Test-MayaQaFixturePreparationRecord -QaRoot $qaRoot -TaskId $TaskId -WorkflowId $WorkflowId -SourcePath $sourceFixture -SourceSha256 $sourceFixtureHash -Evidence $prior
    $priorRequest=Get-Content -LiteralPath ([string]$prior.RequestPath) -Raw|ConvertFrom-Json
    $rawExpiry=$priorRequest.expiresUtc;$priorExpiry=[DateTimeOffset]::MinValue
    $expiryValid=[DateTimeOffset]::TryParse([string]$rawExpiry,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$priorExpiry)
    if(!$expiryValid -and $rawExpiry -is [datetime]){$priorExpiry=[DateTimeOffset]::new($rawExpiry);$expiryValid=$true}
    if(!$expiryValid){throw 'Expired orphaned preparation request expiry is invalid.'}
    if($priorExpiry -gt [DateTimeOffset]::UtcNow){throw 'The orphaned preparation request has not expired.'}
    $taskRevision=[long]$task.revision;$workflowRevision=[long]$w.workflowRevision
    if($DryRun){return [pscustomobject]@{Status='DryRun';TaskId=$TaskId;WorkflowId=$WorkflowId;OrphanedAttemptId=[string]$prior.AttemptId;OrphanedRunId=[string]$prior.RunId;PreparedModelSha256=[string]$prior.PreparedModelSha256;RetirementFailedAttemptId=[string]$retirement.FailedAttemptId;SideEffectsPerformed=$false}}
    Invoke-RepatoStoreMutation $StoreRoot {
        param($current,$preview)
        $t=Find-RepatoTask $current $TaskId
        if([long]$t.revision -ne $taskRevision){throw 'Expired orphaned preparation archival compare-and-swap failed: task revision changed.'}
        $ws=@($t.deploymentWorkflows|Where-Object {$_.workflowId -ceq $WorkflowId -and $_.taskId -ceq $TaskId})
        if($ws.Count -ne 1 -or [long]$ws[0].workflowRevision -ne $workflowRevision){throw 'Expired orphaned preparation archival compare-and-swap failed: workflow changed.'}
        $cw=$ws[0]
        if(!$cw.PSObject.Properties['qaFixturePreparationEvidence'] -or !$cw.qaFixturePreparationEvidence -or (ConvertTo-Json -InputObject $cw.qaFixturePreparationEvidence -Depth 20 -Compress) -cne (ConvertTo-Json -InputObject $prior -Depth 20 -Compress)){throw 'Expired orphaned preparation evidence changed before archival.'}
        if($cw.PSObject.Properties.Name -notcontains 'qaFixturePreparationEvidenceHistory'){$cw|Add-Member NoteProperty qaFixturePreparationEvidenceHistory ([object[]]@()) -Force}
        $archiveCopy=ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $prior -Depth 20 -Compress)
        $cw.qaFixturePreparationEvidenceHistory=[object[]]@(@($cw.qaFixturePreparationEvidenceHistory))+[pscustomobject][ordered]@{Evidence=$archiveCopy;ArchivedUtc=Get-RepatoUtc;Reason='expired-orphaned-preparation-superseded';SupersededByAttemptId=$null;SupersededByRunId=$null}
        foreach($name in 'qaFixturePreparationEvidence','qaDisposableModelSha256'){$cw.PSObject.Properties.Remove($name)}
        $cw.workflowRevision=[long]$cw.workflowRevision+1
        Add-RepatoHistory $t 'maya-qa-expired-orphaned-preparation-archived' 'Maya' "workflow=$WorkflowId; orphanedAttempt=$($prior.AttemptId); orphanedRun=$($prior.RunId); preparedModelSha256=$($prior.PreparedModelSha256)"
        [pscustomobject]@{Status='Archived';TaskId=$TaskId;WorkflowId=$WorkflowId;OrphanedAttemptId=[string]$prior.AttemptId;OrphanedRunId=[string]$prior.RunId;PreparedModelSha256=[string]$prior.PreparedModelSha256;WorkflowRevision=[long]$cw.workflowRevision;TaskRevision=[long]$t.revision;SideEffectsPerformed=$true}
    }
}
function Repair-MayaQaRecoveredFixturePreparation {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][long]$ExpectedTaskRevision,[string]$FixturePreparationResultPath,[switch]$DryRun)
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId;if(!$task -or [long]$task.revision -ne $ExpectedTaskRevision){throw 'Fixture reconciliation task revision is stale.'}
    $attempt=$task.mayaTaraAttempt;$execution=$task.mayaTaraExecution;$packet=$task.mayaTaraQaPacket;$resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $task.mayaPlan.WorkflowId $task.mayaPlan.QaWorkflowId
    if(@($resolved.Errors).Count){throw ('Fixture reconciliation canonical identity invalid: '+(@($resolved.Errors)-join '; '))}
    if(!$attempt -or !$execution -or !$packet -or $attempt.AttemptId -cne $resolved.SelectedAttemptId -or $attempt.RunId -cne $resolved.SelectedRunId -or $execution.AttemptId -cne $attempt.AttemptId -or $execution.RunId -cne $attempt.RunId -or $packet.AttemptId -cne $attempt.AttemptId -or $packet.RunId -cne $attempt.RunId){throw 'Fixture reconciliation current attempt, execution, and packet identities do not match.'}
    if($execution.Stage -cne 'prepared' -or $execution.ExecutionStatus -cne 'Prepared' -or $execution.ClaimStatus -cne 'unclaimed' -or $execution.ClaimId -or $execution.ClaimOwner -or $execution.NativeProcessId -or $execution.RequestPath -or $execution.ResultPath -or $execution.ReportPath -or $execution.EvidencePath -or $execution.ReceiptPath -or $execution.SideEffectsPerformed){throw 'Fixture reconciliation execution is not untouched and unclaimed.'}
    if($execution.FixturePreparationEvidence -or $packet.FixturePreparationEvidence){throw 'Fixture reconciliation is already complete or conflicts with current preparation evidence.'}
    if([DateTimeOffset]::Parse($attempt.RequestExpiresUtc) -le [DateTimeOffset]::UtcNow){throw 'Fixture reconciliation attempt is expired.'}
    if(@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'}).Count){throw 'Fixture reconciliation cannot run with a pending QA approval.'}
    $parents=@($task.mayaTaraExecutionHistory|Where-Object {$_.PSObject.Properties.Name -contains 'ReplacementAttemptId' -and $_.PSObject.Properties.Name -contains 'ReplacementRunId' -and $_.ReplacementAttemptId -ceq $attempt.AttemptId -and $_.ReplacementRunId -ceq $attempt.RunId -and $_.TaskId -ceq $TaskId -and $_.WorkflowId -ceq $resolved.SelectedWorkflowId})
    if($parents.Count -ne 1){throw 'Fixture reconciliation has no unique authoritative recovery record.'}
    $parent=$parents[0];$workflow=Get-DeployWorkflow $StoreRoot $TaskId $resolved.SelectedWorkflowId;$e=$workflow.qaBuildEvidence;$source=[IO.Path]::GetFullPath($execution.AuthoritativeFixturePath);$sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;$qa=[IO.Path]::GetFullPath((Get-MayaQaRoot));$runs=[IO.Path]::GetFullPath((Get-MayaQaRuntimeRoot))
    if($parent.HandoffId -cne $execution.HandoffId -or $parent.TestId -cne $execution.TestId -or $parent.ArtifactSha256 -ine $execution.ArtifactSha256 -or $parent.RunnerManifestSha256 -ine $execution.RunnerManifestSha256 -or $parent.AuthoritativeFixturePath -cne $source -or $parent.AuthoritativeFixtureSha256 -ine $sourceHash -or $execution.DisposableModelSha256 -ine $sourceHash){throw 'Fixture reconciliation current model or recovery evidence does not match the authoritative source fixture.'}
    $prep=$null
    if($parent.FixturePreparationEvidence){$historicalMatches=@();foreach($entry in $task.mayaTaraQaPacketHistory){try{$historic=Test-MayaQaHistoricalPacketContinuation -Task $task -Packet $entry.Packet -CurrentAttempt $attempt -TaskId $TaskId -WorkflowId $resolved.SelectedWorkflowId -QaRoot $qa;if($historic.FixturePreparationEvidence -and (ConvertTo-Json -InputObject $historic.FixturePreparationEvidence -Depth 20 -Compress) -ceq (ConvertTo-Json -InputObject $parent.FixturePreparationEvidence -Depth 20 -Compress) -and $historic.DisposableModelSha256 -ieq [string]$historic.FixturePreparationEvidence.PreparedModelSha256){$historicalMatches+=,$historic}}catch{}};if($historicalMatches.Count -ne 1){throw 'Fixture reconciliation has no unique verified historical packet/preparation record.'};$prep=$historicalMatches[0].FixturePreparationEvidence}
    elseif($FixturePreparationResultPath){$prep=Read-MayaQaFixturePreparationRecord -QaRoot $qa -TaskId $TaskId -WorkflowId $resolved.SelectedWorkflowId -SourcePath $source -SourceSha256 $sourceHash -ResultPath $FixturePreparationResultPath}
    else{throw 'Fixture reconciliation requires authenticated preparation evidence.'}
    $null=Test-MayaQaFixturePreparationRecord -QaRoot $qa -TaskId $TaskId -WorkflowId $resolved.SelectedWorkflowId -SourcePath $source -SourceSha256 $sourceHash -Evidence $prep
    if($prep.RunId -cne $attempt.RunId){throw 'Fixture preparation result is not correlated to the current replacement run.'}
    $currentModelHash=(Get-FileHash -LiteralPath $execution.DisposableModelPath -Algorithm SHA256).Hash
    if([IO.Path]::GetFullPath($prep.PreparedModelPath) -ieq [IO.Path]::GetFullPath($execution.DisposableModelPath)){
        if($currentModelHash -ine $prep.PreparedModelSha256){throw 'In-place prepared model does not match authenticated fixture-preparation evidence.'}
    }elseif($currentModelHash -ine $sourceHash){throw 'Unprepared replacement model changed before fixture reconciliation.'}
    $policy=$execution.IsolationPolicyPath;if(!$execution.IsolationAllowed -or !(Test-Path -LiteralPath $policy -PathType Leaf) -or (Get-FileHash -LiteralPath $policy -Algorithm SHA256).Hash -ine $execution.IsolationPolicySha256){throw 'Fixture reconciliation isolation policy validation failed.'}
    $null=Test-MayaQaFrozenCandidate -CandidateDirectory $e.CandidateDirectory -CandidateDllPath $e.ArtifactPath -ExpectedSha256 $e.ArtifactSha256 -ExpectedSourceCommit $e.CandidateSourceCommit -QaWorkflowId $resolved.SelectedQaWorkflowId
    if($e.ArtifactPath -cne $execution.ArtifactPath -or $e.ArtifactSha256 -ine $execution.ArtifactSha256 -or $e.RunnerManifestPath -cne $execution.RunnerManifestPath -or $e.RunnerManifestSha256 -ine $execution.RunnerManifestSha256){throw 'Fixture reconciliation candidate binding is invalid.'}
    $runtime=[IO.Path]::GetFullPath((Join-Path $runs ($attempt.RunId+'-fixture-reconciled')));$prefix=$runs.TrimEnd('\')+'\';if(!$runtime.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $runtime)){throw 'Fixture reconciliation runtime is invalid or already exists.'}
    $model=Join-Path $runtime 'model.rvt';$sidecar=$model+'.fixture.json';if($DryRun){return [pscustomobject]@{Mode='DryRun';TaskId=$TaskId;AttemptId=$attempt.AttemptId;RunId=$attempt.RunId;RuntimeRoot=$runtime;DisposableModelPath=$model;DisposableModelSha256=$prep.PreparedModelSha256;SideEffectsPerformed=$false}}
    try{New-Item -ItemType Directory -Path $runtime|Out-Null;Copy-Item -LiteralPath $prep.PreparedModelPath -Destination $model;if((Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ine $prep.PreparedModelSha256){throw 'Fixture reconciliation prepared model hash mismatch.'};$def=Get-MayaQaWorkflowDefinition $resolved.SelectedQaWorkflowId;$side=[ordered]@{fixtureId=$def.FixtureId;sourceSha256=$sourceHash;preparedModelSha256=$prep.PreparedModelSha256;fixturePreparationRequestPath=$prep.RequestPath;fixturePreparationRequestSha256=$prep.RequestSha256;fixturePreparationResultPath=$prep.ResultPath;fixturePreparationResultSha256=$prep.ResultSha256;fixturePreparationAttemptId=$prep.AttemptId;fixturePreparationRunId=$prep.RunId};$side|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $sidecar -Encoding UTF8;$null=Test-MayaQaCorrelatedDisposableFixtureProvenance -QaRoot $qa -TaskId $TaskId -WorkflowId $resolved.SelectedWorkflowId -FixtureId $def.FixtureId -SourcePath $source -SourceSha256 $sourceHash -RuntimeRoot $runtime -ModelPath $model -ModelSha256 $prep.PreparedModelSha256
        Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$a=$t.mayaTaraAttempt;$x=$t.mayaTaraExecution;$p=$t.mayaTaraQaPacket;$workflows=@($t.deploymentWorkflows|Where-Object workflowId -ceq $resolved.SelectedWorkflowId);if([long]$t.revision -ne $ExpectedTaskRevision -or $a.AttemptId -cne $attempt.AttemptId -or $a.RunId -cne $attempt.RunId -or $x.AttemptId -cne $execution.AttemptId -or $x.RunId -cne $execution.RunId -or $x.Stage -cne 'prepared' -or (ConvertTo-Json -InputObject $p -Depth 20 -Compress) -cne (ConvertTo-Json -InputObject $packet -Depth 20 -Compress) -or $workflows.Count -ne 1 -or [long]$workflows[0].workflowRevision -ne [long]$workflow.workflowRevision){throw 'Fixture reconciliation compare-and-swap failed.'};if(@($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'}).Count){throw 'Fixture reconciliation compare-and-swap found a pending QA approval.'};if($t.PSObject.Properties.Name -notcontains 'mayaTaraQaPacketHistory'){$t|Add-Member NoteProperty mayaTaraQaPacketHistory ([object[]]@()) -Force};$archivedPacket=ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $p -Depth 20 -Compress);$t.mayaTaraQaPacketHistory=[object[]]@($t.mayaTaraQaPacketHistory)+[pscustomobject]@{Packet=$archivedPacket;AttemptId=$p.AttemptId;RunId=$p.RunId;ArchivedUtc=Get-RepatoUtc;Reason='prepared model rebound to verified fixture-preparation evidence'};$x.DisposableRuntimeRoot=$runtime;$x.DisposableModelPath=$model;$x.DisposableModelSha256=$prep.PreparedModelSha256;$x.FixturePreparationEvidence=$prep;$a.RuntimeRoot=$runtime;$p.ModelPath=$model;$p.SidecarPath=$sidecar;$p.DisposableModelSha256=$prep.PreparedModelSha256;$p.FixturePreparationEvidence=$prep;Add-RepatoHistory $t 'maya-tara-recovered-fixture-preparation-reconciled' 'Maya' "attempt=$($a.AttemptId); run=$($a.RunId); sourcePreparationAttempt=$($prep.AttemptId); sourcePreparationRun=$($prep.RunId)";$x}
    }catch{if(Test-Path -LiteralPath $runtime){Remove-Item -LiteralPath $runtime -Recurse -Force -ErrorAction SilentlyContinue};throw}
}
function Set-MayaQaRecoveredFixtureReadyState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][long]$ExpectedTaskRevision)
    $snapshot=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    if([long]$snapshot.revision -ne $ExpectedTaskRevision -or $snapshot.status -cne 'in-progress' -or $snapshot.workflowStage -cne 'approval'){throw 'Recovered fixture-ready transition state is stale or incompatible.'}
    $a=$snapshot.mayaTaraAttempt;$x=$snapshot.mayaTaraExecution;$p=$snapshot.mayaTaraQaPacket
    if(!$a -or !$x -or !$p -or $x.Stage -cne 'prepared' -or $x.ExecutionStatus -cne 'Prepared' -or $x.ClaimStatus -cne 'unclaimed' -or !$x.FixturePreparationEvidence -or $a.AttemptId -cne $x.AttemptId -or $a.RunId -cne $x.RunId -or $p.AttemptId -cne $x.AttemptId -or $p.RunId -cne $x.RunId){throw 'Recovered fixture-ready transition requires one prepared correlated replacement.'}
    if([DateTimeOffset]::Parse($a.RequestExpiresUtc) -le [DateTimeOffset]::UtcNow){throw 'Recovered replacement attempt expired before approval preparation.'}
    if(@($snapshot.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'}).Count){throw 'Recovered fixture-ready transition found a pending approval.'}
    $null=Test-MayaQaFixturePreparationRecord -QaRoot (Get-MayaQaRoot) -TaskId $TaskId -WorkflowId $x.WorkflowId -SourcePath $x.AuthoritativeFixturePath -SourceSha256 $x.AuthoritativeFixtureSha256 -Evidence $x.FixturePreparationEvidence
    Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)$t=Find-RepatoTask $d $TaskId;if([long]$t.revision -ne $ExpectedTaskRevision -or $t.status -cne 'in-progress' -or $t.workflowStage -cne 'approval' -or $t.mayaTaraAttempt.AttemptId -cne $a.AttemptId -or $t.mayaTaraExecution.AttemptId -cne $x.AttemptId){throw 'Recovered fixture-ready compare-and-swap failed.'};Add-RepatoHistory $t 'maya-tara-recovered-fixture-ready' 'Maya' "attempt=$($a.AttemptId); run=$($a.RunId)";$t.mayaTaraExecution.TaskRevisionAtPrepare=[long]$t.revision;$t}
}
function Invoke-MayaQaFixtureBlockedRecovery {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('begin','finalize')][string]$Operation,[Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [long]$ExpectedTaskRevision=0,[string]$RuntimeRoot,[string]$FixturePreparationResultPath,[string]$ReportDirectory,[string]$QaAddinRoot,[string]$RevitInstallDir='E:\revit\Revit 2025',
        [ValidateRange(7200,86400)][int]$TimeoutSeconds=7200,[string]$ExpiredApprovalRequestId,[string]$ExpiredAttemptId,[string]$ExpiredRunId,
        [string]$ExpectedCandidateSourceCommit,[string]$ExpectedCandidateSha256,[string]$LaunchAgentRuntimeVersion,[ValidateRange(1,240)][int]$ApprovalExpiryMinutes=180,
        [scriptblock]$SessionValidationInvoker,[scriptblock]$FixturePlanInvoker,[switch]$DryRun)
    if($Operation -ceq 'begin'){
        foreach($n in 'ReportDirectory','QaAddinRoot'){if([string]::IsNullOrWhiteSpace([string](Get-Variable $n -ValueOnly))){throw "Begin recovery requires $n."}}
        $before=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId;$oldAttemptId=[string]$before.mayaTaraAttempt.AttemptId;$oldRunId=[string]$before.mayaTaraAttempt.RunId
        $recovered=Recover-MayaQaExpiredExecutionRecord -StoreRoot $StoreRoot -TaskId $TaskId -ExpectedTaskRevision $ExpectedTaskRevision -AttemptDurationMinutes 240 -RuntimeRoot $RuntimeRoot -DryRun:$DryRun
        if($DryRun){return $recovered}
        $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId;$x=$task.mayaTaraExecution;$def=Get-MayaQaWorkflowDefinition $x.QaWorkflowId
        Import-Module (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -WarningAction SilentlyContinue
        $context=[pscustomobject]@{QaRoot=(Get-MayaQaRoot);SourceFixturePath=$x.AuthoritativeFixturePath;FixtureId=$def.FixtureId;FixtureSha256=$x.AuthoritativeFixtureSha256;ModelSha256=$x.DisposableModelSha256;FixturePreparationEvidence=$null;TestId=$x.TestId;ArtifactPath=$x.ArtifactPath;ArtifactSha256=$x.ArtifactSha256;ManifestPath=$x.RunnerManifestPath;ManifestSha256=$x.RunnerManifestSha256;TaskId=$x.TaskId;WorkflowId=$x.WorkflowId;QaWorkflowId=$x.QaWorkflowId;HandoffId=$x.HandoffId;AttemptId=$x.AttemptId;RunId=$x.RunId;ClaimId=$null}
        $plan=if($FixturePlanInvoker){& $FixturePlanInvoker $task $x $context $TimeoutSeconds}else{New-TaraRevitQaPlan -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $x.WorkflowId -QaWorkflowId $x.QaWorkflowId -RunId $x.RunId -ModelPath $x.DisposableModelPath -SidecarPath ($x.DisposableModelPath+'.fixture.json') -ReportDirectory $ReportDirectory -RevitInstallDir $RevitInstallDir -QaAddinRoot $QaAddinRoot -TimeoutSeconds $TimeoutSeconds -Context $context -FixturePreparation -DryRun -SessionValidationInvoker $SessionValidationInvoker}
        if(!$plan -or [int]$plan.TimeoutSeconds -lt 7200 -or !$plan.FixturePreparation){throw 'Supported fixture-preparation plan did not preserve the required timeout or mode.'}
        return [pscustomobject]@{Stage='fixture-preparation-authorized';TaskId=$TaskId;OldAttemptId=$oldAttemptId;OldRunId=$oldRunId;NewAttemptId=$task.mayaTaraAttempt.AttemptId;NewRunId=$task.mayaTaraAttempt.RunId;TaskRevision=$task.revision;PreparationPlan=$plan;ApprovalCreated=$false;RevitLaunched=$false}
    }
    foreach($n in 'FixturePreparationResultPath','ExpiredApprovalRequestId','ExpiredAttemptId','ExpiredRunId','ExpectedCandidateSourceCommit','ExpectedCandidateSha256','LaunchAgentRuntimeVersion'){if([string]::IsNullOrWhiteSpace([string](Get-Variable $n -ValueOnly))){throw "Finalize recovery requires $n."}}
    $snapshot=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    if([long]$snapshot.revision -ne $ExpectedTaskRevision){throw 'Fixture finalization task revision is stale.'}
    $current=$snapshot.mayaTaraExecution;$packet=$snapshot.mayaTaraQaPacket;$attempt=$snapshot.mayaTaraAttempt
    $alreadyReconciled=($current.FixturePreparationEvidence -and $packet.FixturePreparationEvidence -and (ConvertTo-Json -InputObject $current.FixturePreparationEvidence -Depth 20 -Compress) -ceq (ConvertTo-Json -InputObject $packet.FixturePreparationEvidence -Depth 20 -Compress))
    if($alreadyReconciled){
        if($snapshot.status -cne 'in-progress' -or $snapshot.workflowStage -cne 'approval' -or $current.Stage -cne 'prepared' -or $current.ExecutionStatus -cne 'Prepared' -or $current.ClaimStatus -cne 'unclaimed' -or $current.ClaimId -or $current.NativeProcessId -or $current.RequestPath -or $current.ResultPath -or $current.ReportPath -or $current.EvidencePath -or $current.ReceiptPath -or $current.SideEffectsPerformed -or $attempt.AttemptId -cne $current.AttemptId -or $attempt.RunId -cne $current.RunId -or $current.FixturePreparationEvidence.RunId -cne $attempt.RunId -or $current.DisposableModelSha256 -ine $current.FixturePreparationEvidence.PreparedModelSha256 -or (Get-FileHash -LiteralPath $current.DisposableModelPath -Algorithm SHA256).Hash -ine $current.FixturePreparationEvidence.PreparedModelSha256){throw 'Persisted fixture-ready state is not safe to resume.'}
        if(@($snapshot.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'}).Count){throw 'Fixture finalization cannot resume with an existing pending QA approval.'}
        $null=Test-MayaQaFixturePreparationRecord -QaRoot (Get-MayaQaRoot) -TaskId $TaskId -WorkflowId $current.WorkflowId -SourcePath $current.AuthoritativeFixturePath -SourceSha256 $current.AuthoritativeFixtureSha256 -Evidence $current.FixturePreparationEvidence
        $ready=$snapshot
    }else{
        if($current.FixturePreparationEvidence -or $packet.FixturePreparationEvidence){throw 'Fixture finalization found conflicting partial evidence.'}
        $null=Repair-MayaQaRecoveredFixturePreparation -StoreRoot $StoreRoot -TaskId $TaskId -ExpectedTaskRevision $ExpectedTaskRevision -FixturePreparationResultPath $FixturePreparationResultPath
        $afterRepair=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
        $null=Set-MayaQaRecoveredFixtureReadyState -StoreRoot $StoreRoot -TaskId $TaskId -ExpectedTaskRevision ([long]$afterRepair.revision)
        $ready=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    }
    $approval=Request-MayaQaRecoveredExpiredAttemptApproval -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $ready.mayaTaraExecution.WorkflowId -ExpiredApprovalRequestId $ExpiredApprovalRequestId -ExpiredAttemptId $ExpiredAttemptId -ExpiredRunId $ExpiredRunId -RecoveredAttemptId $ready.mayaTaraAttempt.AttemptId -RecoveredRunId $ready.mayaTaraAttempt.RunId -ExpectedTaskRevision ([long]$ready.revision) -ExpectedCandidateSourceCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256 -LaunchAgentRuntimeVersion $LaunchAgentRuntimeVersion -ExpiryMinutes $ApprovalExpiryMinutes
    [pscustomobject]@{Stage='approval-required';TaskId=$TaskId;AttemptId=$ready.mayaTaraAttempt.AttemptId;RunId=$ready.mayaTaraAttempt.RunId;ApprovalRequest=$approval.Request;ApprovalRequestId=$approval.Request.requestId;RevitLaunched=$false}
}
function Recover-MayaQaTerminalLaunchFailure {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[string]$RuntimeRoot,[ValidateRange(1,1440)][Nullable[int]]$AttemptDurationMinutes,[scriptblock]$ManifestValidationBoundary,[switch]$DryRun)
    if($null -eq $AttemptDurationMinutes){$AttemptDurationMinutes=Get-MayaQaAttemptDurationMinutes}
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$old=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if(!$old -or !$attempt){throw 'Canonical Maya Tara execution and attempt are required.'}
    $resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $task.mayaPlan.WorkflowId $task.mayaPlan.QaWorkflowId;if(@($resolved.Errors).Count){throw ('Canonical retry identity invalid: '+(@($resolved.Errors)-join '; '))}
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','HandoffId','AttemptId','RunId'){if([string]$old.$n -cne [string]$resolved.('Selected'+$n)){throw "Retry identity mismatch: $n"}}
    if($old.TestId -cne $resolved.SelectedQaWorkflowId -or $attempt.AttemptId -cne $old.AttemptId -or $attempt.RunId -cne $old.RunId){throw 'Retry current attempt identity mismatch.'}
    if($old.Stage -cne 'launch-failed' -or $old.ExecutionStatus -cne 'LaunchFailed' -or $old.FailureCode -cne 'native-process-start-failed'){throw 'Execution is not an eligible terminal launch failure.'}
    foreach($n in 'NativeProcessId','LaunchedUtc','ExecutingUtc','ResultPath','ReportPath','ReceiptPath'){if($old.PSObject.Properties.Name -contains $n -and $old.$n){throw "Launch-failure retry contains prohibited evidence: $n"}}
    if($old.SideEffectsPerformed){throw 'Launch-failure retry has side effects and requires reconciliation.'}
    $qa=[IO.Path]::GetFullPath((Get-MayaQaRoot));$fixtures=[IO.Path]::GetFullPath((Join-Path $qa 'Fixtures'));$source=[IO.Path]::GetFullPath($old.AuthoritativeFixturePath);$fixturePrefix=$fixtures.TrimEnd('\')+'\';if(!$source.StartsWith($fixturePrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Authoritative fixture escaped approved fixture root.'};if(!(Test-Path -LiteralPath $source -PathType Leaf) -or (Get-FileHash $source -Algorithm SHA256).Hash -ine $old.AuthoritativeFixtureSha256){throw 'Authoritative fixture hash mismatch.'}
    foreach($pair in @(@('ArtifactPath','ArtifactSha256'),@('IsolationPolicyPath','IsolationPolicySha256'))){$p=[string]$old.($pair[0]);$h=[string]$old.($pair[1]);if(!$p -or !$h -or !(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-FileHash $p -Algorithm SHA256).Hash -ine $h){throw "Canonical $($pair[0]) hash validation failed."}}
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $resolved.SelectedWorkflowId;$buildEvidence=$workflow.qaBuildEvidence;$deployedManifest=[IO.Path]::GetFullPath([string]$buildEvidence.DeployedRunnerManifestPath);$deployedManifestHash=[string]$buildEvidence.DeployedRunnerManifestSha256;if([string]$buildEvidence.RunnerManifestPath -cne [string]$old.RunnerManifestPath -or [string]$buildEvidence.RunnerManifestSha256 -ine [string]$old.RunnerManifestSha256 -or $deployedManifestHash -ine [string]$old.RunnerManifestSha256){throw 'Terminal recovery runner-manifest provenance or deployment evidence mismatch.'}
    $manifestValidation=if($ManifestValidationBoundary){& $ManifestValidationBoundary $deployedManifest $deployedManifestHash}else{try{$item=Get-Item -LiteralPath $deployedManifest -ErrorAction Stop;if(!$item.PSIsContainer){[pscustomobject]@{Accessible=$true;HashMatches=((Get-FileHash -LiteralPath $deployedManifest -Algorithm SHA256).Hash -ieq $deployedManifestHash)}}else{[pscustomobject]@{Accessible=$false;HashMatches=$false}}}catch [System.UnauthorizedAccessException]{[pscustomobject]@{Accessible=$false;HashMatches=$false}}catch{throw 'Canonical deployed runner manifest is missing.'}}
    if($manifestValidation.Accessible){if(!$manifestValidation.HashMatches){throw 'Canonical deployed runner manifest hash validation failed.'}}else{
        $evidencePath=[string]$old.EvidencePath;$evidenceHash=[string]$old.EvidenceSha256
        if([string]::IsNullOrWhiteSpace($evidencePath) -or [string]::IsNullOrWhiteSpace($evidenceHash) -or !(Test-Path -LiteralPath $evidencePath -PathType Leaf)){throw 'Canonical prepared manifest evidence is missing.'}
        if((Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash -ine $evidenceHash){throw 'Canonical prepared manifest evidence hash mismatch.'}
        try{$ev=Get-Content -LiteralPath $evidencePath -Raw|ConvertFrom-Json}catch{throw 'Canonical prepared manifest evidence is malformed.'}
        foreach($n in 'EvidenceVersion','EvidencePurpose','ValidationStatus','TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','CanonicalRunId','DeployedRunnerManifestPath','DeployedRunnerManifestSha256','IsolationPolicySha256','ValidatedUtc'){if($ev.PSObject.Properties.Name -notcontains $n){throw "Canonical prepared manifest evidence is missing: $n"}}
        foreach($n in 'ClaimId','NativeRunId'){if($ev.PSObject.Properties.Name -contains $n -and -not [string]::IsNullOrWhiteSpace([string]$ev.$n)){throw "Canonical prepared manifest evidence contains prohibited field: $n"}}
        if([int]$ev.EvidenceVersion -ne 1 -or [string]$ev.EvidencePurpose -cne 'PreparedManifestAttestation' -or [string]$ev.ValidationStatus -cne 'Passed'){throw 'Canonical prepared manifest evidence did not pass validation.'}
        foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId'){if([string]$ev.$n -cne [string]$old.$n){throw "Canonical prepared manifest evidence identity mismatch: $n"}}
        if([string]$ev.CanonicalRunId -cne [string]$old.RunId -or [IO.Path]::GetFullPath([string]$ev.DeployedRunnerManifestPath) -ine $deployedManifest -or [string]$ev.DeployedRunnerManifestSha256 -ine $deployedManifestHash -or [string]$ev.IsolationPolicySha256 -ine [string]$old.IsolationPolicySha256){throw 'Canonical prepared manifest evidence identity or hash mismatch.'}
        try{$null=[DateTimeOffset]::Parse([string]$ev.ValidatedUtc)}catch{throw 'Canonical prepared manifest evidence timestamp is invalid.'}
    }
    if(!$old.IsolationAllowed){throw 'Canonical isolation policy is not allowed.'}
    if($task.PSObject.Properties.Name -contains 'mayaTaraExecutionHistory' -and @($task.mayaTaraExecutionHistory|Where-Object{$_.AttemptId -ceq $old.AttemptId}).Count){throw 'Terminal launch failure was already archived.'}
    $modelSource=$source;$modelHash=$old.AuthoritativeFixtureSha256;$prep=$old.FixturePreparationEvidence;if($prep){$null=Test-MayaQaFixturePreparationRecord -QaRoot $qa -TaskId $TaskId -WorkflowId $resolved.SelectedWorkflowId -SourcePath $source -SourceSha256 $old.AuthoritativeFixtureSha256 -Evidence $prep;$modelSource=[IO.Path]::GetFullPath([string]$prep.PreparedModelPath);$modelHash=[string]$prep.PreparedModelSha256}
    $runs=[IO.Path]::GetFullPath($(if($RuntimeRoot){$RuntimeRoot}else{Get-MayaQaRuntimeRoot}));$runPrefix=$runs.TrimEnd('\')+'\';$newAttempt=[guid]::NewGuid().ToString('N');$newRun=[guid]::NewGuid().ToString('N');$runtime=[IO.Path]::GetFullPath((Join-Path $runs ($newRun+'-retry')));if(!$runtime.StartsWith($runPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Retry runtime escaped approved runtime root.'};$model=Join-Path $runtime 'model.rvt';$sidecar=$model+'.fixture.json';$def=Get-MayaQaWorkflowDefinition $resolved.SelectedQaWorkflowId
    if(!$DryRun){New-Item -ItemType Directory -Path $runtime -Force|Out-Null;Copy-Item $modelSource $model -Force;if((Get-FileHash $model -Algorithm SHA256).Hash -ine $modelHash){throw 'Retry disposable model hash mismatch.'};$side=[ordered]@{fixtureId=$def.FixtureId;sourceSha256=$old.AuthoritativeFixtureSha256};if($prep){$side.preparedModelSha256=$prep.PreparedModelSha256;$side.fixturePreparationRequestPath=$prep.RequestPath;$side.fixturePreparationRequestSha256=$prep.RequestSha256;$side.fixturePreparationResultPath=$prep.ResultPath;$side.fixturePreparationResultSha256=$prep.ResultSha256;$side.fixturePreparationAttemptId=$prep.AttemptId;$side.fixturePreparationRunId=$prep.RunId};if($resolved.SelectedQaWorkflowId -eq 'grid-bubble-visibility-v1' -or $resolved.SelectedQaWorkflowId -eq 'grid-bubble-offset-v1'){$side.requiredGridNames=@('A','B','C','D','1','2','3','4')};if($resolved.SelectedQaWorkflowId -eq 'grid-resequence-v1'){$side.requiredGridNames=@('1','2','3','3.2','4','A','A.1','B','C')};$side|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $sidecar -Encoding UTF8;$check=Get-Content -LiteralPath $sidecar -Raw|ConvertFrom-Json;if(!(Test-Path -LiteralPath $model -PathType Leaf) -or !(Test-Path -LiteralPath $sidecar -PathType Leaf) -or $check.fixtureId -cne $def.FixtureId -or $check.sourceSha256 -ine $old.AuthoritativeFixtureSha256 -or (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ine $modelHash -or ($prep -and ([string]$check.preparedModelSha256 -ine [string]$prep.PreparedModelSha256 -or [string]$check.fixturePreparationResultSha256 -ine [string]$prep.ResultSha256))){throw 'Retry disposable model or fixture sidecar validation failed.'}}
    $expiry=[DateTimeOffset]::UtcNow.AddMinutes($AttemptDurationMinutes).ToString('O');$newAttemptRecord=[pscustomobject][ordered]@{SchemaVersion='maya-tara-execution-request-v1';AttemptId=$newAttempt;TaskId=$TaskId;WorkflowId=$resolved.SelectedWorkflowId;RunId=$newRun;RuntimeRoot=$runtime;RequestExpiresUtc=$expiry;Stage='prepared';Success=$false;RequestPath=$null}
    $newExec=[ordered]@{};foreach($p in $old.PSObject.Properties){$newExec[$p.Name]=$p.Value};$newExec.AttemptId=$newAttempt;$newExec.RunId=$newRun;$newExec.DisposableRuntimeRoot=$runtime;$newExec.DisposableModelPath=$model;$newExec.DisposableModelSha256=$modelHash;$newExec.ClaimId=$null;$newExec.ClaimOwner=$null;$newExec.ClaimedUtc=$null;$newExec.ClaimStatus='unclaimed';$newExec.Stage='prepared';$newExec.ExecutionStatus='Prepared';$newExec.PreparedUtc=Get-RepatoUtc;$newExec.LaunchingUtc=$null;$newExec.LaunchedUtc=$null;$newExec.ExecutingUtc=$null;$newExec.EvidenceCollectedUtc=$null;$newExec.RollbackVerifiedUtc=$null;$newExec.VerifiedUtc=$null;$newExec.CompletedUtc=$null;$newExec.FailedUtc=$null;$newExec.NativeProcessId=$null;$newExec.RequestPath=$null;$newExec.ResultPath=$null;$newExec.ReportPath=$null;$newExec.EvidencePath=$null;$newExec|Add-Member NoteProperty EvidenceSha256 $null -Force;$newExec.ReceiptPath=$null;$newExec.RollbackStatus='Required';$newExec.VerificationStatus='Pending';$newExec.CompletionStatus='Pending';$newExec.FailureCode=$null;$newExec.FailureDetails=$null;$newExec.TaskRevisionAtPrepare=$null;$newExec.TaskRevisionAtClaim=$null;$newExec.SideEffectsPerformed=$false
    $newExec.ValidatedRunnerManifestPath=$deployedManifest;$newExec.ValidatedRunnerManifestSha256=$deployedManifestHash;$newExec.EvidenceSha256=$null;$newExec.NativeRequestId=$null
    if($DryRun){return [pscustomobject]@{Mode='DryRun';OldAttemptId=$old.AttemptId;OldRunId=$old.RunId;NewAttemptId=$newAttempt;NewRunId=$newRun;RuntimeRoot=$runtime;SideEffectsPerformed=$false}}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$now=$t.mayaTaraExecution;if($t.revision -ne $task.revision -or $now.AttemptId -cne $old.AttemptId -or $now.RunId -cne $old.RunId -or $now.Stage -cne 'launch-failed' -or $now.FailureCode -cne 'native-process-start-failed'){throw 'Terminal launch-failure retry compare-and-swap failed.'};if($t.PSObject.Properties.Name -notcontains 'mayaTaraExecutionHistory'){$t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@()) -Force};$archived=[pscustomobject]$now;$archived|Add-Member NoteProperty ArchivedUtc (Get-RepatoUtc) -Force;$archived|Add-Member NoteProperty ReplacementAttemptId $newAttempt -Force;$archived|Add-Member NoteProperty ReplacementRunId $newRun -Force;$t.mayaTaraExecutionHistory=[object[]]@($t.mayaTaraExecutionHistory)+$archived;if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force};$t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$t.mayaTaraAttempt;$t.mayaTaraAttempt=$newAttemptRecord;$newExec.TaskRevisionAtPrepare=[long]$t.revision;$t.mayaTaraExecution=[pscustomobject]$newExec;Add-RepatoHistory $t 'maya-tara-terminal-launch-failure-recovered' 'Maya' "failedAttempt=$($old.AttemptId); failedRun=$($old.RunId); replacementAttempt=$newAttempt; replacementRun=$newRun";$t.mayaTaraExecution}
}

function Complete-MayaQaTerminalLaunchFailureCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$AttemptId,
        [Parameter(Mandatory)][string]$ClaimId,
        [scriptblock]$ProcessInspector,
        [switch]$DryRun
    )
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    if(!$task){throw 'Cleanup task was not found.'};$execution=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if(!$execution -or !$attempt){throw 'Canonical terminal execution and attempt are required.'}
    if($execution.TaskId -cne $TaskId -or $execution.AttemptId -cne $AttemptId -or $attempt.AttemptId -cne $AttemptId){throw 'Cleanup identity mismatch.'}
    if($execution.Stage -ceq 'rollback-verified' -and $execution.RollbackStatus -ceq 'Verified' -and $execution.ClaimStatus -ceq 'released'){
        if($execution.PSObject.Properties.Name -notcontains 'ReleasedClaimId' -or [string]$execution.ReleasedClaimId -cne $ClaimId){throw 'Cleanup idempotency claim identity mismatch.'}
        return [pscustomobject]@{Mode='AlreadyCompleted';TaskId=$TaskId;AttemptId=$AttemptId;ClaimId=$ClaimId;RollbackStatus='Verified';ClaimStatus='released';RequestEvidencePreserved=$true;ReplacementAttemptCreated=$false;SideEffectsPerformed=$false}
    }
    if($execution.ClaimId -cne $ClaimId -or $execution.ClaimOwner -ne 'Tara' -or $execution.ClaimStatus -cne 'claimed'){throw 'Cleanup claim identity mismatch.'}
    if($execution.Stage -cne 'launch-failed' -or $execution.ExecutionStatus -cne 'LaunchFailed' -or $execution.FailureCode -cne 'native-process-start-failed' -or $execution.RollbackStatus -cne 'Required'){throw 'Execution is not an eligible terminal launch failure.'}
    foreach($n in 'NativeProcessId','LaunchedUtc','ExecutingUtc','ResultPath','ReportPath','ReceiptPath','EvidencePath'){if($execution.PSObject.Properties.Name -contains $n -and $execution.$n){throw "Cleanup found prohibited terminal evidence: $n"}}
    if($execution.SideEffectsPerformed){throw 'Cleanup found recorded side effects.'}
    $live=if($ProcessInspector){& $ProcessInspector $execution}else{if($execution.NativeProcessId){try{Get-Process -Id ([int]$execution.NativeProcessId) -ErrorAction Stop}catch{$null}}else{$null}}
    if($live){throw 'Cleanup is fail-closed while an attempt process is live or ambiguous.'}
    $fixture=[IO.Path]::GetFullPath([string]$execution.AuthoritativeFixturePath);if(!(Test-Path -LiteralPath $fixture -PathType Leaf) -or (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash -ine [string]$execution.AuthoritativeFixtureSha256){throw 'Authoritative fixture integrity failed.'}
    $model=[string]$execution.DisposableModelPath;$runtime=[IO.Path]::GetFullPath([string]$execution.DisposableRuntimeRoot);if(!(Test-Path -LiteralPath $model -PathType Leaf) -or !(Test-Path -LiteralPath $runtime -PathType Container)){throw 'Disposable runtime is missing.'};if((Get-FileHash -LiteralPath $execution.AuthoritativeFixturePath -Algorithm SHA256).Hash -ine [string]$execution.AuthoritativeFixtureSha256 -or (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ine [string]$execution.DisposableModelSha256){throw 'Authoritative source fixture or disposable model hash validation failed.'};if(!$execution.FixturePreparationEvidence -and [string]$execution.DisposableModelSha256 -ine [string]$execution.AuthoritativeFixtureSha256){throw 'Disposable model differs from source fixture without correlated preparation evidence.'};if($execution.FixturePreparationEvidence -and ([string]$execution.FixturePreparationEvidence.PreparedModelSha256 -ine [string]$execution.DisposableModelSha256 -or [string]$execution.FixturePreparationEvidence.SourceSha256 -ine [string]$execution.AuthoritativeFixtureSha256)){throw 'Disposable model or source fixture does not match correlated preparation evidence.'}
    $request=[string]$execution.RequestPath;if([string]::IsNullOrWhiteSpace($request) -or !(Test-Path -LiteralPath $request -PathType Leaf)){throw 'Request evidence cannot be safely preserved.'};$requestFull=[IO.Path]::GetFullPath($request);$runtimeFull=[IO.Path]::GetFullPath($runtime);if(!$requestFull.StartsWith($runtimeFull.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Request evidence is outside the disposable runtime contract.'}
    $archiveRoot=[IO.Path]::GetFullPath((Join-Path (Join-Path $StoreRoot 'archives') ('terminal-launch-failures\'+$TaskId+'\'+$AttemptId)));if(!$archiveRoot.StartsWith([IO.Path]::GetFullPath((Join-Path $StoreRoot 'archives')).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Cleanup archive escaped the approved store archive root.'}
    if($DryRun){return [pscustomobject]@{Mode='DryRun';TaskId=$TaskId;AttemptId=$AttemptId;ClaimId=$ClaimId;ArchiveRoot=$archiveRoot;RequestEvidencePreserved=$true;ReplacementAttemptCreated=$false;SideEffectsPerformed=$false}}
    if(Test-Path -LiteralPath $archiveRoot){throw 'Cleanup archive already exists; refusing duplicate destructive cleanup.'}
    New-Item -ItemType Directory -Path (Split-Path $archiveRoot -Parent) -Force|Out-Null;Move-Item -LiteralPath $runtime -Destination $archiveRoot
    $archivedRequest=Join-Path $archiveRoot (Split-Path $request -Leaf)
    $null=Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if([long]$t.revision -ne [long]$task.revision -or $x.AttemptId -cne $AttemptId -or $x.ClaimId -cne $ClaimId -or $x.Stage -cne 'launch-failed' -or $x.RollbackStatus -cne 'Required'){throw 'Cleanup compare-and-swap failed.'};$x|Add-Member NoteProperty OriginalDisposableRuntimeRoot $runtime -Force;$x|Add-Member NoteProperty ArchivedRuntimeRoot $archiveRoot -Force;$x|Add-Member NoteProperty ReleasedClaimId $ClaimId -Force;$x.RequestPath=$archivedRequest;$x.ClaimStatus='released';$x.ClaimOwner=$null;$x.ClaimId=$null;$x.Stage='rollback-verified';$x.ExecutionStatus='RollbackVerified';$x.RollbackStatus='Verified';$x.RollbackVerifiedUtc=Get-RepatoUtc;$x|Add-Member NoteProperty CleanupCompletedUtc (Get-RepatoUtc) -Force;$x.SideEffectsPerformed=$false;Add-RepatoHistory $t 'maya-tara-terminal-launch-failure-cleanup-completed' 'Maya' "attempt=$AttemptId; archivedRuntime=$archiveRoot";$x}
    [pscustomobject]@{Mode='Completed';TaskId=$TaskId;AttemptId=$AttemptId;ClaimId=$ClaimId;RollbackStatus='Verified';ClaimStatus='released';ArchiveRoot=$archiveRoot;RequestEvidencePath=$archivedRequest;RequestEvidencePreserved=$true;ReplacementAttemptCreated=$false;ReplacementRuntimeCreated=$false;SideEffectsPerformed=$false}
}

function Complete-MayaQaRunnerStartupFailureReconciliation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$AttemptId,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$ClaimId,
        [Parameter(Mandatory)][string]$NativeRequestId,
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][string]$ProcessStartedUtc,
        [Parameter(Mandatory)][string]$RequestPath,
        [Parameter(Mandatory)][string]$RequestSha256,
        [Parameter(Mandatory)][string]$JournalPath,
        [Parameter(Mandatory)][string]$JournalSha256,
        [Parameter(Mandatory)][string]$AgentLedgerPath,
        [Parameter(Mandatory)][string]$AgentPayloadHash,
        [Parameter(Mandatory)][string]$FailureDetails,
        [Parameter(Mandatory)][string]$ManualPromptEvidence,
        [switch]$ManualLoadOnceAcknowledged,
        [scriptblock]$ProcessInspector,
        [switch]$DryRun
    )
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$x=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if(!$x -or !$attempt -or $task.taskId -cne $TaskId -or $x.TaskId -cne $TaskId -or $x.AttemptId -cne $AttemptId -or $attempt.AttemptId -cne $AttemptId -or $x.RunId -cne $RunId -or $attempt.RunId -cne $RunId -or $x.ClaimId -cne $ClaimId -or $x.NativeRequestId -cne $NativeRequestId){throw 'Runner-startup reconciliation identity mismatch.'}
    if($x.Stage -cne 'launch-failed' -or $x.ExecutionStatus -cne 'LaunchFailed' -or $x.FailureCode -cne 'native-process-start-failed'){throw 'Execution is not the expected client launch-failed record.'}
    foreach($n in 'NativeProcessId','LaunchedUtc','ExecutingUtc','ResultPath','ReportPath','ReceiptPath','EvidencePath','RunnerStartupEvidence'){if($x.PSObject.Properties.Name -contains $n -and $x.$n){throw "Runner-startup reconciliation found preexisting evidence: $n"}}
    if($x.SideEffectsPerformed){throw 'Runner-startup reconciliation found reported QA side effects.'}
    if(!$ManualLoadOnceAcknowledged -or [string]::IsNullOrWhiteSpace($ManualPromptEvidence)){throw 'Explicit manual Load Once evidence is required.'}
    try{$started=Get-MayaQaNormalizedUtc -Value $ProcessStartedUtc -Context 'Observed Revit process start time'}catch{throw 'Observed Revit process start time is invalid.'}
    if($ProcessId -le 0 -or $ProcessId -ne 44920){throw 'Observed Revit PID does not match the authorized attempt evidence.'}
    $requestFull=[IO.Path]::GetFullPath($RequestPath);if($requestFull -ine [IO.Path]::GetFullPath([string]$x.RequestPath) -or !(Test-Path -LiteralPath $requestFull -PathType Leaf)){throw 'Request evidence path does not match the persisted operation.'}
    if((Get-FileHash -LiteralPath $requestFull -Algorithm SHA256).Hash -ine $RequestSha256){throw 'Request evidence hash mismatch.'}
    try{$request=Get-Content -LiteralPath $requestFull -Raw|ConvertFrom-Json}catch{throw 'Request evidence is malformed.'}
    foreach($pair in @(@('taskId',$TaskId),@('workflowId',[string]$x.WorkflowId),@('qaWorkflowId',[string]$x.QaWorkflowId),@('testId',[string]$x.TestId),@('attemptId',$AttemptId),@('runId',$RunId),@('claimId',$ClaimId),@('requestId',$NativeRequestId))){if([string]$request.($pair[0]) -cne [string]$pair[1]){throw "Request binding mismatch: $($pair[0])"}}
    if([IO.Path]::GetFullPath([string]$request.requestPath) -ine $requestFull -or [string]$request.requestSha256 -notmatch '^[a-fA-F0-9]{64}$' -or (Get-MayaQaCanonicalRequestSha256 $request) -ine [string]$request.requestSha256){throw 'Request path or embedded integrity binding is invalid.'}
    $resultPath=$requestFull+'.result.json';if(Test-Path -LiteralPath $resultPath){throw 'A request-bound result exists; startup-failure reconciliation is not eligible.'}
    $journalFull=[IO.Path]::GetFullPath($JournalPath);if(!(Test-Path -LiteralPath $journalFull -PathType Leaf) -or (Get-FileHash -LiteralPath $journalFull -Algorithm SHA256).Hash -ine $JournalSha256){throw 'Revit journal evidence is missing or has changed.'}
    $journal=Get-Content -LiteralPath $journalFull -Raw
    foreach($needle in @('API_ERROR { Starting External Application: Repato Create Plan Views QA','Repato.Revit.TestRunner.CreatePlanViewsQaApplication','TaskDialog "Revit cannot run the external application "Repato Create Plan Views QA"','TaskDialog_Security_Unsigned_File_Loading','AddInCodeSigningStatus: Unsigned','AddInLoadFailureMessage: NoError')){if(!$journal.Contains($needle)){throw "Journal does not prove expected startup evidence: $needle"}}
    try{$ledger=Get-Content -LiteralPath $AgentLedgerPath -Raw|ConvertFrom-Json}catch{throw 'Launch Agent replay ledger is missing or malformed.'}
    $ledgerMatches=@($ledger|Where-Object{$_.RequestId -ceq $NativeRequestId -and $_.RunId -ceq $RunId -and $_.PayloadHash -ceq $AgentPayloadHash})
    if($ledgerMatches.Count -ne 1 -or $AgentPayloadHash -notmatch '^[a-fA-F0-9]{64}$'){throw 'Launch Agent ledger does not conclusively bind the received request.'}
    $ledgerSeen=[DateTimeOffset]::Parse([string]$ledgerMatches[0].SeenUtc);if([Math]::Abs(($started-$ledgerSeen).TotalSeconds) -gt 10){throw 'Observed Revit start time is not bound closely to Launch Agent receipt time.'}
    $live=if($ProcessInspector){& $ProcessInspector $ProcessId $started}else{Get-Process -Id $ProcessId -ErrorAction SilentlyContinue};if($live){throw 'Observed Revit process is still live; reconciliation is fail-closed.'}
    $evidence=[pscustomobject][ordered]@{Disposition='Revit launched; runner startup failed; no QA result';TaskId=$TaskId;AttemptId=$AttemptId;RunId=$RunId;ClaimId=$ClaimId;NativeRequestId=$NativeRequestId;ProcessId=$ProcessId;ProcessStartedUtc=$started.ToUniversalTime().ToString('O');ProcessExitConfirmed=$true;RequestPath=$requestFull;RequestFileSha256=$RequestSha256;RequestEmbeddedSha256=$request.requestSha256;ResultPath=$resultPath;ResultAbsent=$true;ReportPath=$null;JournalPath=$journalFull;JournalSha256=$JournalSha256;AgentLedgerPath=[IO.Path]::GetFullPath($AgentLedgerPath);AgentPayloadHash=$AgentPayloadHash;AgentSeenUtc=$ledgerMatches[0].SeenUtc;ManualLoadOnceAcknowledged=$true;ManualPromptEvidence=$ManualPromptEvidence;RunnerFailureDetails=$FailureDetails;RecordedUtc=Get-RepatoUtc}
    if($DryRun){return [pscustomobject]@{Mode='DryRun';TaskId=$TaskId;AttemptId=$AttemptId;RunId=$RunId;RequestId=$NativeRequestId;Disposition=$evidence.Disposition;Evidence=$evidence;ReplacementAttemptCreated=$false;StoreRevision=$task.revision}}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$z=$t.mayaTaraExecution;if([long]$t.revision -ne [long]$task.revision -or $z.AttemptId -cne $AttemptId -or $z.RunId -cne $RunId -or $z.ClaimId -cne $ClaimId -or $z.NativeRequestId -cne $NativeRequestId -or $z.Stage -cne 'launch-failed' -or $z.FailureCode -cne 'native-process-start-failed'){throw 'Runner-startup reconciliation compare-and-swap failed.'};$z.NativeProcessId=$ProcessId;$z.LaunchedUtc=$evidence.ProcessStartedUtc;$z.Stage='runner-startup-failed';$z.ExecutionStatus='RunnerStartupFailed';$z.ClaimStatus='runner-startup-failed';$z.FailureCode='runner-startup-failed';$z.FailureDetails=$FailureDetails;$z.FailedUtc=Get-RepatoUtc;$z.ResultPath=$resultPath;$z.ReportPath=$null;$z.ReceiptPath=$null;$z|Add-Member NoteProperty RunnerStartupEvidence $evidence -Force;$t.mayaTaraAttempt.Stage='runner-startup-failed';$t.mayaTaraAttempt.Success=$false;Add-RepatoHistory $t 'maya-tara-runner-startup-failed' 'Tara' "attempt=$AttemptId; run=$RunId; request=$NativeRequestId; pid=$ProcessId; manualLoadOnce=true; resultAbsent=true";$z}
}

function Complete-MayaQaPreAttemptOrphanRuntimeCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$RunId,
        [switch]$DryRun
    )
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    $workflows=@($task.deploymentWorkflows|Where-Object{$_.taskId -ceq $TaskId -and $_.qaRunId -ceq $RunId})
    if($workflows.Count -ne 1){throw 'Pre-attempt cleanup RunId did not resolve to exactly one persisted QA workflow.'}
    $workflow=$workflows[0]
    $attempt=if($task.PSObject.Properties.Name -contains 'mayaTaraAttempt'){$task.mayaTaraAttempt}else{$null}
    $execution=if($task.PSObject.Properties.Name -contains 'mayaTaraExecution'){$task.mayaTaraExecution}else{$null}
    if($attempt -and (! [string]::IsNullOrWhiteSpace([string]$attempt.AttemptId) -or ($attempt.PSObject.Properties.Name -contains 'ClaimId' -and ![string]::IsNullOrWhiteSpace([string]$attempt.ClaimId)))){throw 'Pre-attempt cleanup requires no canonical AttemptId or ClaimId.'}
    if($execution){throw 'Pre-attempt cleanup requires no canonical Maya Tara execution.'}
    if($task.PSObject.Properties.Name -contains 'mayaTaraQaPacket' -and $task.mayaTaraQaPacket){throw 'Pre-attempt cleanup requires no QA handoff.'}
    foreach($item in @($task.executorRuns)){
        if($item -and (($item.PSObject.Properties.Name -contains 'RunId' -and [string]$item.RunId -ceq $RunId) -or ($item.PSObject.Properties.Name -contains 'RequestPath' -and $item.RequestPath))){throw 'Pre-attempt cleanup found native execution evidence.'}
    }
    foreach($p in 'qaReportPath','qaReceiptPath','qaEvidencePath','qaResultPath'){
        if($workflow.PSObject.Properties.Name -contains $p -and ![string]::IsNullOrWhiteSpace([string]$workflow.$p)){throw "Pre-attempt cleanup found native evidence: $p."}
    }
    $model=[IO.Path]::GetFullPath([string]$workflow.qaModelPath);$sidecar=[IO.Path]::GetFullPath([string]$workflow.qaSidecarPath)
    $runtime=[IO.Path]::GetFullPath((Split-Path $model -Parent));$canonical=[IO.Path]::GetFullPath((Get-MayaQaRuntimeRoot));$prefix=$canonical.TrimEnd('\')+'\'
    if(!$runtime.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or $runtime -ieq $canonical){throw 'Persisted disposable runtime is outside the canonical QA TestRuns root.'}
    if([IO.Path]::GetDirectoryName($sidecar) -ine $runtime -or [IO.Path]::GetFileName($model) -cne 'model.rvt' -or [IO.Path]::GetFileName($sidecar) -cne 'model.rvt.fixture.json'){throw 'Persisted model or sidecar escapes the exact disposable runtime.'}
    $fixture=[IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) 'Fixtures'));$candidate=[IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) '..\DeploymentCandidates'));$source=[IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) '..'))
    foreach($p in @($model,$sidecar,$runtime)){if($p -ieq $fixture -or $p.StartsWith($fixture.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($candidate.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or $p -ieq $source){throw 'Pre-attempt cleanup target overlaps fixture, candidate, or source data.'}}
    $auditName='PreAttemptRuntimeCleanupStatus';$existingStatus=if($task.PSObject.Properties.Name -contains $auditName){[string]$task.$auditName}else{$null}
    if($existingStatus -ceq 'Completed' -and !(Test-Path -LiteralPath $runtime)){return [pscustomobject]@{Mode='AlreadyCleaned';TaskId=$TaskId;RunId=$RunId;RuntimePath=$runtime;SideEffectsPerformed=$false}}
    if($DryRun){return [pscustomobject]@{Mode='DryRun';TaskId=$TaskId;RunId=$RunId;RuntimePath=$runtime;RuntimeExists=(Test-Path -LiteralPath $runtime -PathType Container);SideEffectsPerformed=$false}}
    $revision=[long]$task.revision
    $pending=Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;if([long]$t.revision -ne $revision){throw 'Pre-attempt cleanup compare-and-swap failed.'};if($t.PSObject.Properties.Name -contains 'PreAttemptRuntimeCleanupStatus' -and $t.PreAttemptRuntimeCleanupStatus -ceq 'Completed'){return $t};$t|Add-Member NoteProperty PreAttemptRuntimeCleanupStatus 'Pending' -Force;$t|Add-Member NoteProperty PreAttemptRuntimeCleanupUtc (Get-RepatoUtc) -Force;$t|Add-Member NoteProperty CleanedRunId $RunId -Force;$t|Add-Member NoteProperty CleanedRuntimePath $runtime -Force;Add-RepatoHistory $t 'maya-qa-pre-attempt-runtime-cleanup-started' 'Maya' "run=$RunId; runtime=$runtime";$t}
    if(Test-Path -LiteralPath $runtime){Remove-Item -LiteralPath $runtime -Recurse -Force}
    if(Test-Path -LiteralPath $runtime){throw 'Pre-attempt disposable runtime could not be removed.'}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;if([string]$t.PreAttemptRuntimeCleanupStatus -cne 'Pending' -or [string]$t.CleanedRunId -cne $RunId -or [string]$t.CleanedRuntimePath -ine $runtime){throw 'Pre-attempt cleanup completion compare-and-swap failed.'};$t.PreAttemptRuntimeCleanupStatus='Completed';$t.PreAttemptRuntimeCleanupUtc=Get-RepatoUtc;Add-RepatoHistory $t 'maya-qa-pre-attempt-runtime-cleanup-completed' 'Maya' "run=$RunId; runtime=$runtime";$t}|Out-Null
    [pscustomobject]@{Mode='Completed';TaskId=$TaskId;RunId=$RunId;RuntimePath=$runtime;RuntimeRemoved=$true;SideEffectsPerformed=$false}
}

function Complete-MayaQaPreparedAttemptCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$AttemptId,[switch]$DryRun)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    if($task.PSObject.Properties.Name -contains 'PreAttemptCleanup' -and [string]$task.PreAttemptCleanup.Status -ceq 'Completed'){$oldPath=[string]$task.PreAttemptCleanup.RuntimePath;if(!(Test-Path -LiteralPath $oldPath)){return [pscustomobject]@{Mode='AlreadyCompleted';TaskId=$TaskId;WorkflowId=$WorkflowId;RunId=$RunId;AttemptId=$AttemptId;RuntimePath=$oldPath;ReplacementAttemptCreated=$false;SideEffectsPerformed=$false}};throw 'Prepared-attempt cleanup is already completed but its runtime still exists.'}
    if($task.PSObject.Properties.Name -notcontains 'mayaTaraAttempt' -or !$task.mayaTaraAttempt){throw 'Prepared-attempt cleanup requires one current canonical attempt.'};$attempt=$task.mayaTaraAttempt
    foreach($n in 'TaskId','WorkflowId','RunId','AttemptId'){if($attempt.PSObject.Properties.Name -notcontains $n -or [string]$attempt.$n -cne [string]$(if($n -eq 'TaskId'){$TaskId}elseif($n -eq 'WorkflowId'){$WorkflowId}elseif($n -eq 'RunId'){$RunId}else{$AttemptId})){throw "Prepared-attempt cleanup identity mismatch: $n"}}
    $attemptHistory=if($task.PSObject.Properties.Name -contains 'mayaTaraAttemptHistory'){@($task.mayaTaraAttemptHistory)}else{@()};$attempts=@($attemptHistory|Where-Object{$_.AttemptId -ceq $AttemptId});if($attempts.Count){throw 'Prepared-attempt cleanup found ambiguous historical attempt evidence.'}
    if($task.PSObject.Properties.Name -contains 'mayaTaraExecution' -and $task.mayaTaraExecution){throw 'Prepared-attempt cleanup rejects an execution record.'}
    $packet=if($task.PSObject.Properties.Name -contains 'mayaTaraQaPacket'){$task.mayaTaraQaPacket}else{$null};if(!$packet){throw 'Prepared-attempt cleanup requires the prepared QA handoff.'}
    foreach($n in 'TaskId','WorkflowId','RunId','AttemptId'){if($packet.PSObject.Properties.Name -notcontains $n -or [string]$packet.$n -cne [string]$(if($n -eq 'TaskId'){$TaskId}elseif($n -eq 'WorkflowId'){$WorkflowId}elseif($n -eq 'RunId'){$RunId}else{$AttemptId})){throw "Prepared-attempt handoff identity mismatch: $n"}}
    foreach($obj in @($attempt,$packet)){$names=@($obj.PSObject.Properties.Name);foreach($n in 'ClaimId','NativeProcessId','RequestPath','ResultPath','ReportPath','ReceiptPath','LaunchAgentAccepted','NativeRequestSent','RevitLaunched','QaRunnerStarted'){if($names -contains $n -and $obj.$n){throw "Prepared-attempt cleanup found prohibited evidence: $n"}}}
    $runtime=[IO.Path]::GetFullPath([string]$attempt.RuntimeRoot);$canonical=[IO.Path]::GetFullPath((Get-MayaQaRuntimeRoot));$prefix=$canonical.TrimEnd('\')+'\';if(!$runtime.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or $runtime -ieq $canonical){throw 'Prepared-attempt runtime escaped canonical QA TestRuns.'}
    $model=[IO.Path]::GetFullPath([string]$packet.ModelPath);$side=[IO.Path]::GetFullPath([string]$packet.SidecarPath);if([IO.Path]::GetDirectoryName($model) -ine $runtime -or [IO.Path]::GetDirectoryName($side) -ine $runtime -or [IO.Path]::GetFileName($model) -cne 'model.rvt' -or [IO.Path]::GetFileName($side) -cne 'model.rvt.fixture.json'){throw 'Prepared-attempt runtime ownership/path validation failed.'}
    $ownerMatches=@($data.tasks|Where-Object{$attemptProperty=$_.PSObject.Properties['mayaTaraAttempt'];$candidate=if($null -ne $attemptProperty){$attemptProperty.Value}else{$null};if($null -ne $candidate -and $candidate.PSObject.Properties.Name -contains 'RuntimeRoot' -and -not [string]::IsNullOrWhiteSpace([string]$candidate.RuntimeRoot) -and [IO.Path]::GetFullPath([string]$candidate.RuntimeRoot) -ieq $runtime){$true}else{$false}});if($ownerMatches.Count -ne 1 -or $ownerMatches[0].taskId -cne $TaskId){throw 'Prepared-attempt runtime ownership is ambiguous.'}
    $fixture=[IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) 'Fixtures'));$candidate=[IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) '..\DeploymentCandidates'));$source=[IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) '..'));$store=[IO.Path]::GetFullPath($StoreRoot);foreach($p in @($runtime,$model,$side)){if($p -ieq $store -or $p.StartsWith($store.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or $p -ieq $fixture -or $p.StartsWith($fixture.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($candidate.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or $p -ieq $source){throw 'Prepared-attempt cleanup target overlaps protected data.'}}
    $revision=[long]$task.revision;if($DryRun){return [pscustomobject]@{Mode='DryRun';TaskId=$TaskId;WorkflowId=$WorkflowId;RunId=$RunId;AttemptId=$AttemptId;RuntimePath=$runtime;SideEffectsPerformed=$false}}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;if([long]$t.revision -ne $revision -or $t.mayaTaraAttempt.AttemptId -cne $AttemptId -or $t.mayaTaraAttempt.RunId -cne $RunId -or ($t.PSObject.Properties.Name -contains 'mayaTaraExecution' -and $t.mayaTaraExecution)){throw 'Prepared-attempt cleanup compare-and-swap failed.'};$t|Add-Member NoteProperty PreAttemptCleanup ([pscustomobject]@{Status='Pending';Mode='PreparedAttemptCleanup';TaskId=$TaskId;WorkflowId=$WorkflowId;RunId=$RunId;AttemptId=$AttemptId;RuntimePath=$runtime;StartedUtc=Get-RepatoUtc}) -Force;Add-RepatoHistory $t 'maya-qa-prepared-attempt-cleanup-started' 'Maya' "attempt=$AttemptId; runtime=$runtime";$t}|Out-Null
    if(Test-Path -LiteralPath $runtime){Remove-Item -LiteralPath $runtime -Recurse -Force};if(Test-Path -LiteralPath $runtime){throw 'Prepared-attempt runtime removal failed.'}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;if([string]$t.PreAttemptCleanup.Status -cne 'Pending' -or [string]$t.PreAttemptCleanup.AttemptId -cne $AttemptId -or [string]$t.PreAttemptCleanup.RuntimePath -ine $runtime){throw 'Prepared-attempt cleanup completion compare-and-swap failed.'};$archived=[pscustomobject]$t.mayaTaraAttempt;$archived|Add-Member NoteProperty Stage 'abandoned-preparation' -Force;$archived|Add-Member NoteProperty CleanupReason 'Preparation failed before execution record, claim, or native boundary.' -Force;$archived|Add-Member NoteProperty CleanupCompletedUtc (Get-RepatoUtc) -Force;if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force};$t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$archived;$t.mayaTaraAttempt=$null;$t.PreAttemptCleanup.Status='Completed';$t.PreAttemptCleanup|Add-Member NoteProperty RuntimeRemoved $true -Force;$t.PreAttemptCleanup|Add-Member NoteProperty CompletedUtc (Get-RepatoUtc) -Force;Add-RepatoHistory $t 'maya-qa-prepared-attempt-cleanup-completed' 'Maya' "attempt=$AttemptId; runtime=$runtime";$t}|Out-Null
    [pscustomobject]@{Mode='Completed';TaskId=$TaskId;WorkflowId=$WorkflowId;RunId=$RunId;AttemptId=$AttemptId;RuntimePath=$runtime;RuntimeRemoved=$true;ReplacementAttemptCreated=$false;ClaimCreated=$false;NativeRequestSent=$false;RevitLaunched=$false;SideEffectsPerformed=$false}
}
function Archive-MayaQaUnlaunchedPreparedExecution {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$AttemptId,[Parameter(Mandatory)][string]$RunId,[scriptblock]$ProcessProvider,[switch]$DryRun)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    $attempt=$task.mayaTaraAttempt;$execution=$task.mayaTaraExecution
    if(!$attempt -or !$execution){throw 'Unlaunched prepared execution and attempt are required.'}
    foreach($pair in @(@('TaskId',$TaskId),@('WorkflowId',$WorkflowId),@('AttemptId',$AttemptId),@('RunId',$RunId))){if([string]$attempt.($pair[0]) -cne $pair[1] -or [string]$execution.($pair[0]) -cne $pair[1]){throw "Prepared execution archive identity mismatch: $($pair[0])."}}
    if($attempt.Stage -cne 'prepared' -or $execution.Stage -cne 'prepared' -or $execution.ExecutionStatus -cne 'Prepared' -or $execution.ClaimStatus -cne 'unclaimed'){throw 'Only an unclaimed prepared execution may be archived.'}
    foreach($n in 'ClaimOwner','ClaimId','ClaimedUtc','NativeProcessId','RequestPath','ResultPath','ReportPath','ReceiptPath','LaunchingUtc','LaunchedUtc','ExecutingUtc'){if($attempt.PSObject.Properties.Name -contains $n -and $attempt.$n -or $execution.PSObject.Properties.Name -contains $n -and $execution.$n){throw "Prepared execution archive found launch evidence: $n."}}
    $inheritedApproval=$execution.ManualLoadOnceEvidence
    if($inheritedApproval){$prior=@($task.mayaTaraExecutionHistory|Where-Object {$_.AttemptId -ceq [string]$inheritedApproval.AttemptId -and $_.RunId -ceq [string]$inheritedApproval.RunId -and $_.ManualLoadOnceEvidence -and $_.ManualLoadOnceEvidence.NativeRequestId -ceq [string]$inheritedApproval.NativeRequestId});if([string]$inheritedApproval.AttemptId -ceq $AttemptId -or [string]$inheritedApproval.RunId -ceq $RunId -or [string]$inheritedApproval.ConfirmedBy -cne 'user' -or [string]$inheritedApproval.Action -cne 'Load Once' -or $prior.Count -ne 1){throw 'Prepared execution archive found approval not correlated to an archived prior attempt.'}}
    if($execution.SideEffectsPerformed -or $execution.VerificationStatus -ceq 'Verified' -or $execution.CompletionStatus -ceq 'Completed'){throw 'Prepared execution archive found side effects or terminal evidence.'}
    $revits=if($ProcessProvider){@(& $ProcessProvider)}else{@(Get-Process -Name Revit -ErrorAction SilentlyContinue)};if(@($revits).Count){throw 'Prepared execution archive is blocked while Revit is running.'}
    $runtime=[IO.Path]::GetFullPath([string]$execution.DisposableRuntimeRoot);$runs=[IO.Path]::GetFullPath((Get-MayaQaRuntimeRoot));$prefix=$runs.TrimEnd('\')+'\'
    if(!$runtime.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or $runtime -ieq $runs){throw 'Prepared execution archive runtime is outside canonical QA TestRuns.'}
    $model=[IO.Path]::GetFullPath([string]$execution.DisposableModelPath);if([IO.Path]::GetDirectoryName($model) -ine $runtime -or !(Test-Path -LiteralPath $model -PathType Leaf) -or (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ine [string]$execution.DisposableModelSha256){throw 'Prepared execution archive model identity/hash validation failed.'}
    if(-not [string]::IsNullOrWhiteSpace([string]$execution.RequestPath) -and (Test-Path -LiteralPath ([string]$execution.RequestPath))){throw 'Prepared execution archive found a native request.'}
    $revision=[long]$task.revision
    if($DryRun){return [pscustomobject]@{Status='DryRun';TaskId=$TaskId;WorkflowId=$WorkflowId;AttemptId=$AttemptId;RunId=$RunId;RuntimePreserved=$true;NativeLaunchAbsent=$true;SideEffectsPerformed=$false}}
    Invoke-RepatoStoreMutation $StoreRoot {
        param($current,$preview)
        $t=Find-RepatoTask $current $TaskId
        if([long]$t.revision -ne $revision -or $t.mayaTaraAttempt.AttemptId -cne $AttemptId -or $t.mayaTaraExecution.AttemptId -cne $AttemptId -or $t.mayaTaraExecution.RunId -cne $RunId){throw 'Prepared execution archive compare-and-swap failed.'}
        $archivedAttempt=[pscustomobject]$t.mayaTaraAttempt;$archivedAttempt.Stage='abandoned-preparation';$archivedAttempt|Add-Member NoteProperty CleanupReason 'Superseded before claim/native launch so frozen-candidate and deployment gates can run.' -Force;$archivedAttempt|Add-Member NoteProperty ArchivedUtc (Get-RepatoUtc) -Force
        $archivedExecution=[pscustomobject]$t.mayaTaraExecution;$archivedExecution.Stage='abandoned-preparation';$archivedExecution.ExecutionStatus='PreparedAttemptSuperseded';$archivedExecution.FailureCode='prepared-candidate-superseded';$archivedExecution.FailureDetails='Unlaunched preparation archived before required candidate/deployment validation.';$archivedExecution|Add-Member NoteProperty RuntimePreserved $true -Force;$archivedExecution|Add-Member NoteProperty ArchivedUtc (Get-RepatoUtc) -Force;if($inheritedApproval){$archivedExecution|Add-Member NoteProperty InheritedApprovalNotApplicableToPreparedAttempt $true -Force}
        if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force};$t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$archivedAttempt
        if($t.PSObject.Properties.Name -notcontains 'mayaTaraExecutionHistory'){$t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@()) -Force};$t.mayaTaraExecutionHistory=[object[]]@($t.mayaTaraExecutionHistory)+$archivedExecution
        foreach($n in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){$t.PSObject.Properties.Remove($n)}
        $w=@($t.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId);if($w.Count -ne 1){throw 'Prepared execution archive workflow identity is ambiguous.'}
        foreach($n in 'qaHandoffId','qaHandoff','qaRunId','qaModelPath','qaSidecarPath','qaFixtureId','qaFixtureSha256','qaTestId','qaReportPath','qaReportSha256','qaEvidence','qaVerificationStatus','qaCompletionStatus','qaCompletedUtc'){$w[0].PSObject.Properties.Remove($n)}
        Add-RepatoHistory $t 'maya-tara-unlaunched-preparation-archived' 'Maya' "attempt=$AttemptId; run=$RunId; runtimePreserved=true; nativeLaunch=false"
        [pscustomobject]@{Status='Archived';TaskId=$TaskId;WorkflowId=$WorkflowId;AttemptId=$AttemptId;RunId=$RunId;RuntimePreserved=$true;NativeLaunchAbsent=$true;SideEffectsPerformed=$true}
    }
}
function Accept-MayaQaPreparedManifestAttestation {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$AttemptId,[Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$EvidencePath,[Parameter(Mandatory)][string]$EvidenceSha256,[scriptblock]$StoreMutationBoundary)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$execution=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if(!$task -or !$execution -or !$attempt){throw 'Canonical terminal execution and attempt are required.'}
    $resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $task.mayaPlan.WorkflowId $task.mayaPlan.QaWorkflowId;if(@($resolved.Errors).Count){throw ('Canonical attestation identity invalid: '+(@($resolved.Errors)-join '; '))}
    if($execution.TaskId -cne $TaskId -or $execution.AttemptId -cne $AttemptId -or $execution.RunId -cne $RunId -or $attempt.AttemptId -cne $AttemptId -or $attempt.RunId -cne $RunId){throw 'Attestation canonical identity mismatch.'}
    if($execution.Stage -cne 'launch-failed' -or $execution.ExecutionStatus -cne 'LaunchFailed' -or $execution.FailureCode -cne 'native-process-start-failed'){throw 'Execution is not eligible for prepared manifest attestation.'}
    if($execution.SideEffectsPerformed){throw 'Terminal execution has side effects.'};foreach($n in 'NativeProcessId','ResultPath','ReportPath','ReceiptPath','EvidencePath','EvidenceSha256'){if($execution.PSObject.Properties.Name -contains $n -and $execution.$n){throw "Terminal execution already contains $n."}}
    if(!$execution.IsolationAllowed){throw 'Isolation is not allowed.'};if(!(Test-Path -LiteralPath $EvidencePath -PathType Leaf)){throw 'Prepared manifest evidence is missing.'};if((Get-FileHash -LiteralPath $EvidencePath -Algorithm SHA256).Hash -ine $EvidenceSha256){throw 'Prepared manifest evidence hash mismatch.'};try{$e=Get-Content -LiteralPath $EvidencePath -Raw|ConvertFrom-Json}catch{throw 'Prepared manifest evidence is malformed.'}
    foreach($n in 'EvidenceVersion','EvidencePurpose','ValidationStatus','TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','CanonicalRunId','DeployedRunnerManifestPath','DeployedRunnerManifestSha256','IsolationPolicySha256','ValidatedUtc'){if($e.PSObject.Properties.Name -notcontains $n){throw "Prepared manifest evidence is missing: $n"}};foreach($n in 'ClaimId','NativeRunId'){if($e.PSObject.Properties.Name -contains $n -and -not [string]::IsNullOrWhiteSpace([string]$e.$n)){throw "Prepared manifest evidence contains prohibited field: $n"}}
    if([int]$e.EvidenceVersion -ne 1 -or [string]$e.EvidencePurpose -cne 'PreparedManifestAttestation' -or [string]$e.ValidationStatus -cne 'Passed'){throw 'Prepared manifest evidence did not pass validation.'};foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId'){if([string]$e.$n -cne [string]$execution.$n){throw "Prepared manifest evidence identity mismatch: $n"}};if([string]$e.CanonicalRunId -cne [string]$execution.RunId -or [string]$e.DeployedRunnerManifestPath -cne [string]$execution.RunnerManifestPath -or [string]$e.DeployedRunnerManifestSha256 -ine [string]$execution.RunnerManifestSha256 -or [string]$e.IsolationPolicySha256 -ine [string]$execution.IsolationPolicySha256){throw 'Prepared manifest evidence identity or hash mismatch.'};try{$null=[DateTimeOffset]::Parse([string]$e.ValidatedUtc)}catch{throw 'Prepared manifest evidence timestamp is invalid.'}
    $cas={param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($t.revision -ne $task.revision -or $x.TaskId -cne $execution.TaskId -or $x.AttemptId -cne $AttemptId -or $x.RunId -cne $RunId -or $x.Stage -cne 'launch-failed' -or $x.ExecutionStatus -cne 'LaunchFailed' -or $x.FailureCode -cne 'native-process-start-failed' -or $x.SideEffectsPerformed -or $x.NativeProcessId -or $x.ResultPath -or $x.ReportPath -or $x.ReceiptPath -or $x.EvidencePath -or $x.EvidenceSha256){throw 'Prepared manifest attestation compare-and-swap failed.'};$x|Add-Member NoteProperty EvidencePath $EvidencePath -Force;$x|Add-Member NoteProperty EvidenceSha256 $EvidenceSha256 -Force;Add-RepatoHistory $t 'maya-tara-prepared-manifest-attestation-accepted' 'Tara' "attempt=$AttemptId; run=$RunId";$x}
    if($StoreMutationBoundary){& $StoreMutationBoundary $StoreRoot $cas}else{Invoke-RepatoStoreMutation $StoreRoot $cas}
}
function Recover-MayaQaAbandonedNativeExecution {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[string]$RuntimeRoot,[ValidateRange(1,1440)][Nullable[int]]$AttemptDurationMinutes,[switch]$DryRun)
    if($null -eq $AttemptDurationMinutes){$AttemptDurationMinutes=Get-MayaQaAttemptDurationMinutes}
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$old=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if(!$old -or !$attempt){throw 'Canonical Maya Tara execution and attempt are required.'}
    $resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $task.mayaPlan.WorkflowId $task.mayaPlan.QaWorkflowId;if(@($resolved.Errors).Count){throw ('Canonical abandoned-execution identity invalid: '+(@($resolved.Errors)-join '; '))}
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','HandoffId','AttemptId','RunId'){if([string]$old.$n -cne [string]$resolved.('Selected'+$n)){throw "Abandoned-execution identity mismatch: $n"}}
    if($old.Stage -cne 'executing' -or $old.ExecutionStatus -cne 'Executing' -or $old.ClaimOwner -cne 'Tara' -or [string]::IsNullOrWhiteSpace([string]$old.ClaimId)){throw 'Execution is not an eligible executing Tara claim.'}
    if(!$old.NativeProcessId -or [int]$old.NativeProcessId -le 0){throw 'Executing record has no native process identity.'}
    try{$live=Get-Process -Id ([int]$old.NativeProcessId) -ErrorAction Stop}catch{$live=$null}
    if($live){throw "Recorded native PID $($old.NativeProcessId) is still present; recovery is fail-closed for live, reused, or ambiguous processes."}
    if([DateTimeOffset]::Parse($attempt.RequestExpiresUtc) -gt [DateTimeOffset]::UtcNow){throw 'Executing attempt is not expired.'}
    foreach($n in 'ResultPath','ReportPath','EvidencePath','ReceiptPath','CompletedUtc','VerifiedUtc','RollbackVerifiedUtc'){if($old.PSObject.Properties.Name -contains $n -and $old.$n){throw "Abandoned execution contains prohibited terminal evidence: $n"}}
    if($old.VerificationStatus -eq 'Verified' -or $old.CompletionStatus -eq 'Completed' -or $old.SideEffectsPerformed){throw 'Abandoned execution has terminal or side-effect evidence and requires reconciliation.'}
    if($task.PSObject.Properties.Name -contains 'mayaTaraExecutionHistory' -and @($task.mayaTaraExecutionHistory|Where-Object{$_.AttemptId -ceq $old.AttemptId}).Count){throw 'Abandoned execution was already archived.'}
    $qa=[IO.Path]::GetFullPath((Get-MayaQaRoot));$source=[IO.Path]::GetFullPath($old.AuthoritativeFixturePath);$fixtures=[IO.Path]::GetFullPath((Join-Path $qa 'Fixtures'));$prefix=$fixtures.TrimEnd('\')+'\';if(!$source.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $source -PathType Leaf)){throw 'Authoritative fixture is outside the approved fixture root or missing.'};$sourceHash=(Get-FileHash $source -Algorithm SHA256).Hash;if($sourceHash -ine $old.AuthoritativeFixtureSha256){throw 'Authoritative fixture hash mismatch.'}
    $runs=[IO.Path]::GetFullPath($(if($RuntimeRoot){$RuntimeRoot}else{Get-MayaQaRuntimeRoot}));$runPrefix=$runs.TrimEnd('\')+'\';$newAttempt=[guid]::NewGuid().ToString('N');$newRun=[guid]::NewGuid().ToString('N');$runtime=[IO.Path]::GetFullPath((Join-Path $runs ($newRun+'-recovery')));if(!$runtime.StartsWith($runPrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Recovery runtime escaped approved QA root.'};$model=Join-Path $runtime 'model.rvt';
    $sidecar=$model+'.fixture.json';$def=Get-MayaQaWorkflowDefinition $resolved.SelectedQaWorkflowId
    if(!$DryRun){New-Item -ItemType Directory -Path $runtime -Force|Out-Null;Copy-Item $source $model -Force;if((Get-FileHash $model -Algorithm SHA256).Hash -ine $sourceHash){throw 'Recovered disposable model hash mismatch.'};$side=[ordered]@{fixtureId=$def.FixtureId;sourceSha256=$sourceHash};if($resolved.SelectedQaWorkflowId -eq 'grid-bubble-visibility-v1' -or $resolved.SelectedQaWorkflowId -eq 'grid-bubble-offset-v1'){$side.requiredGridNames=@('A','B','C','D','1','2','3','4')};if($resolved.SelectedQaWorkflowId -eq 'grid-resequence-v1'){$side.requiredGridNames=@('1','2','3','3.2','4','A','A.1','B','C')};$side|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $sidecar -Encoding UTF8;$check=Get-Content -LiteralPath $sidecar -Raw|ConvertFrom-Json;if(!(Test-Path -LiteralPath $model -PathType Leaf) -or !(Test-Path -LiteralPath $sidecar -PathType Leaf) -or $check.fixtureId -cne $def.FixtureId -or $check.sourceSha256 -ine $sourceHash -or (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ine $sourceHash){throw 'Recovered disposable model or fixture sidecar validation failed.'}}
    $expiry=[DateTimeOffset]::UtcNow.AddMinutes($AttemptDurationMinutes).ToString('O');$newAttemptRecord=[pscustomobject][ordered]@{SchemaVersion='maya-tara-execution-request-v1';AttemptId=$newAttempt;TaskId=$TaskId;WorkflowId=$resolved.SelectedWorkflowId;RunId=$newRun;RuntimeRoot=$runtime;RequestExpiresUtc=$expiry;Stage='prepared';Success=$false;RequestPath=$null};$newExec=[ordered]@{};foreach($p in $old.PSObject.Properties){$newExec[$p.Name]=$p.Value};$newExec.AttemptId=$newAttempt;$newExec.RunId=$newRun;$newExec.DisposableRuntimeRoot=$runtime;$newExec.DisposableModelPath=$model;$newExec.DisposableModelSha256=$sourceHash;$newExec.PreparedUtc=Get-RepatoUtc;$newExec.LaunchingUtc=$null;$newExec.LaunchedUtc=$null;$newExec.ExecutingUtc=$null;$newExec.EvidenceCollectedUtc=$null;$newExec.RollbackStartedUtc=$null;$newExec.RollbackVerifiedUtc=$null;$newExec.VerifiedUtc=$null;$newExec.CompletedUtc=$null;$newExec.FailedUtc=$null;$newExec.ClaimId=$null;$newExec.ClaimOwner=$null;$newExec.ClaimedUtc=$null;$newExec.ClaimStatus='unclaimed';$newExec.Stage='prepared';$newExec.ExecutionStatus='Prepared';$newExec.NativeProcessId=$null;$newExec.RequestPath=$null;$newExec.ResultPath=$null;$newExec.ReportPath=$null;$newExec.EvidencePath=$null;$newExec.ReceiptPath=$null;$newExec.RollbackStatus='Required';$newExec.VerificationStatus='Pending';$newExec.CompletionStatus='Pending';$newExec.FailureCode=$null;$newExec.FailureDetails=$null;$newExec.SideEffectsPerformed=$false;$newExec.TaskRevisionAtPrepare=$null;$newExec.TaskRevisionAtClaim=$null
    if($DryRun){return [pscustomobject]@{Mode='DryRun';OldAttemptId=$old.AttemptId;OldRunId=$old.RunId;NewAttemptId=$newAttempt;NewRunId=$newRun;RuntimeRoot=$runtime;SideEffectsPerformed=$false}}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($t.revision -ne $task.revision -or $x.AttemptId -cne $old.AttemptId -or $x.RunId -cne $old.RunId -or $x.Stage -cne 'executing' -or $x.NativeProcessId -ne $old.NativeProcessId){throw 'Abandoned-execution recovery compare-and-swap failed.'};$archived=[pscustomobject]$x;$archived|Add-Member NoteProperty ArchivedUtc (Get-RepatoUtc) -Force;$archived|Add-Member NoteProperty Stage 'abandoned' -Force;$archived|Add-Member NoteProperty ExecutionStatus 'Abandoned' -Force;$archived|Add-Member NoteProperty ClaimStatus 'abandoned' -Force;$archived|Add-Member NoteProperty FailureCode 'native-process-exited-before-result' -Force;$archived|Add-Member NoteProperty FailureDetails 'Recorded native process disappeared before correlated native result or evidence was produced.' -Force;$archived|Add-Member NoteProperty AbandonedUtc (Get-RepatoUtc) -Force;$archived|Add-Member NoteProperty ReplacementAttemptId $newAttempt -Force;$archived|Add-Member NoteProperty ReplacementRunId $newRun -Force;if($t.PSObject.Properties.Name -notcontains 'mayaTaraExecutionHistory'){$t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@()) -Force};$t.mayaTaraExecutionHistory=[object[]]@($t.mayaTaraExecutionHistory)+$archived;if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force};$t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$t.mayaTaraAttempt;$t.mayaTaraAttempt=$newAttemptRecord;$newExec.TaskRevisionAtPrepare=[long]$t.revision;$t.mayaTaraExecution=[pscustomobject]$newExec;Add-RepatoHistory $t 'maya-tara-abandoned-native-recovered' 'Maya' "abandonedAttempt=$($old.AttemptId); abandonedRun=$($old.RunId); replacementAttempt=$newAttempt; replacementRun=$newRun";$t.mayaTaraExecution}
}
function Repair-MayaQaPreparedExecutionLifecycle {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$AttemptId,[Parameter(Mandatory)][string]$RunId,[string]$EvidencePath,[string]$EvidenceSha256,[scriptblock]$ManifestValidationBoundary,[scriptblock]$StoreMutationBoundary)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$x=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if(!$x -or !$attempt){throw 'Canonical Maya Tara execution and attempt are required.'}
    if($x.TaskId -cne $TaskId -or $x.AttemptId -cne $AttemptId -or $x.RunId -cne $RunId -or $attempt.AttemptId -cne $AttemptId -or $attempt.RunId -cne $RunId){throw 'Prepared lifecycle repair identity mismatch.'}
    foreach($pair in @(@('Stage','prepared'),@('ExecutionStatus','Prepared'),@('ClaimStatus','unclaimed'))){if([string]$x.($pair[0]) -cne $pair[1]){throw 'Prepared lifecycle repair requires an unclaimed prepared execution.'}}
    foreach($n in 'ClaimOwner','ClaimId','ClaimedUtc','NativeProcessId','RequestPath','ResultPath','ReportPath','EvidencePath','ReceiptPath'){if($x.PSObject.Properties.Name -contains $n -and $null -ne $x.$n -and [string]$x.$n){throw "Prepared lifecycle repair found prohibited state: $n"}}
    foreach($n in 'CompletedUtc','VerifiedUtc','RollbackVerifiedUtc'){if($x.PSObject.Properties.Name -contains $n -and $x.$n){throw "Prepared lifecycle repair found terminal state: $n"}}
    if($x.SideEffectsPerformed -or $x.VerificationStatus -eq 'Verified' -or $x.CompletionStatus -eq 'Completed'){throw 'Prepared lifecycle repair found side effects or terminal status.'}
    if($x.PSObject.Properties.Name -contains 'LifecycleRepairUtc' -and $x.LifecycleRepairUtc){throw 'Prepared lifecycle repair was already performed.'}
    if($x.PSObject.Properties.Name -contains 'LaunchingUtc' -and $null -eq $x.LaunchingUtc -and $x.PreparedUtc -and [long]$task.revision -eq ([long]$x.TaskRevisionAtPrepare+1) -and [string]::IsNullOrWhiteSpace([string]$x.EvidenceSha256)){throw 'Prepared lifecycle repair was already performed or state is already clean.'}
    $resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $task.mayaPlan.WorkflowId $task.mayaPlan.QaWorkflowId;if(@($resolved.Errors).Count){throw ('Prepared lifecycle repair identity invalid: '+(@($resolved.Errors)-join '; '))}
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','HandoffId','AttemptId','RunId'){if([string]$x.$n -cne [string]$resolved.('Selected'+$n)){throw "Prepared lifecycle repair canonical identity mismatch: $n"}}
    foreach($pair in @(@('ArtifactPath','ArtifactSha256'),@('AuthoritativeFixturePath','AuthoritativeFixtureSha256'),@('DisposableModelPath','DisposableModelSha256'),@('IsolationPolicyPath','IsolationPolicySha256'))){$p=[string]$x.($pair[0]);$h=[string]$x.($pair[1]);if(!$p -or !$h -or !(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-FileHash $p -Algorithm SHA256).Hash -ine $h){throw "Prepared lifecycle repair hash validation failed: $($pair[0])"}}
    $manifestValidation=if($ManifestValidationBoundary){& $ManifestValidationBoundary $x.RunnerManifestPath $x.RunnerManifestSha256}else{$accessible=Test-Path -LiteralPath $x.RunnerManifestPath -PathType Leaf;if($accessible){[pscustomobject]@{Accessible=$true;HashMatches=((Get-FileHash -LiteralPath $x.RunnerManifestPath -Algorithm SHA256).Hash -ieq [string]$x.RunnerManifestSha256)}}else{[pscustomobject]@{Accessible=$false;HashMatches=$false}}}
    if($manifestValidation.Accessible){if(!$manifestValidation.HashMatches){throw 'Prepared lifecycle repair hash validation failed: RunnerManifestPath'}}else{if([string]::IsNullOrWhiteSpace($EvidencePath) -or [string]::IsNullOrWhiteSpace($EvidenceSha256)){throw 'Prepared lifecycle repair requires authenticated manifest evidence.'};if(!(Test-Path -LiteralPath $EvidencePath -PathType Leaf) -or (Get-FileHash -LiteralPath $EvidencePath -Algorithm SHA256).Hash -ine $EvidenceSha256){throw 'Prepared lifecycle repair evidence hash validation failed.'};try{$ev=Get-Content -LiteralPath $EvidencePath -Raw|ConvertFrom-Json}catch{throw 'Prepared lifecycle repair evidence is malformed.'};$preparedPurpose=($ev.PSObject.Properties.Name -contains 'EvidencePurpose' -and [string]$ev.EvidencePurpose -ceq 'PreparedManifestAttestation');if($preparedPurpose){$required=@('EvidenceVersion','EvidencePurpose','ValidationStatus','TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','CanonicalRunId','DeployedRunnerManifestPath','DeployedRunnerManifestSha256','IsolationPolicySha256','ValidatedUtc');foreach($n in $required){if($ev.PSObject.Properties.Name -notcontains $n){throw "Prepared lifecycle repair evidence is missing: $n"}};foreach($n in 'ClaimId','NativeRunId'){if($ev.PSObject.Properties.Name -contains $n -and -not [string]::IsNullOrWhiteSpace([string]$ev.$n)){throw "Prepared lifecycle repair prepared evidence contains prohibited field: $n"}}}else{$required=@('EvidenceVersion','ValidationStatus','TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','CanonicalRunId','ClaimId','NativeRunId','DeployedRunnerManifestPath','DeployedRunnerManifestSha256','IsolationPolicySha256','ValidatedUtc');foreach($n in $required){if($ev.PSObject.Properties.Name -notcontains $n){throw "Prepared lifecycle repair evidence is missing: $n"}}};if([int]$ev.EvidenceVersion -ne 1 -or [string]$ev.ValidationStatus -cne 'Passed'){throw 'Prepared lifecycle repair evidence did not pass validation.'};foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId'){if([string]$ev.$n -cne [string]$x.$n){throw "Prepared lifecycle repair evidence identity mismatch: $n"}};if(!$preparedPurpose -and -not [string]::IsNullOrWhiteSpace([string]$ev.ClaimId)){throw 'Prepared lifecycle repair evidence contains a fabricated claim identity.'};if([string]$ev.CanonicalRunId -cne [string]$x.RunId -or [string]$ev.DeployedRunnerManifestPath -cne [string]$x.RunnerManifestPath -or [string]$ev.DeployedRunnerManifestSha256 -ine [string]$x.RunnerManifestSha256 -or [string]$ev.IsolationPolicySha256 -ine [string]$x.IsolationPolicySha256){throw 'Prepared lifecycle repair evidence identity or hash mismatch.'};try{$null=[DateTimeOffset]::Parse([string]$ev.ValidatedUtc)}catch{throw 'Prepared lifecycle repair evidence timestamp is invalid.'}}    if(!$x.IsolationAllowed){throw 'Prepared lifecycle repair requires allowed isolation.'}
    $oldRevision=[long]$task.revision;$now=Get-RepatoUtc;$expiry=([DateTimeOffset]::Parse($now)).AddMinutes((Get-MayaQaAttemptDurationMinutes)).ToString('O')
    $cas={param($current,$preview)$t=Find-RepatoTask $current $TaskId;$r=$t.mayaTaraExecution;$a=$t.mayaTaraAttempt;if([long]$t.revision -ne $oldRevision -or $r.AttemptId -cne $AttemptId -or $r.RunId -cne $RunId -or $a.AttemptId -cne $AttemptId -or $a.RunId -cne $RunId){throw 'Prepared lifecycle repair compare-and-swap failed.'};if($r.Stage -cne 'prepared' -or $r.ExecutionStatus -cne 'Prepared' -or $r.ClaimStatus -cne 'unclaimed' -or $r.ClaimId -or $r.ClaimOwner -or $r.NativeProcessId -or $r.RequestPath -or $r.ResultPath -or $r.ReportPath -or $r.EvidencePath -or $r.SideEffectsPerformed){throw 'Prepared lifecycle repair state changed before mutation.'};$r.PreparedUtc=$now;$r.LaunchingUtc=$null;$r.LaunchedUtc=$null;$r.ExecutingUtc=$null;$r.EvidenceCollectedUtc=$null;$r.RollbackStartedUtc=$null;$r.RollbackVerifiedUtc=$null;$r.VerifiedUtc=$null;$r.CompletedUtc=$null;$r.FailedUtc=$null;$r.NativeProcessId=$null;$r.ClaimOwner=$null;$r.ClaimId=$null;$r.ClaimedUtc=$null;$r.RequestPath=$null;$r.ResultPath=$null;$r.ReportPath=$null;$r.EvidencePath=$null;$r|Add-Member NoteProperty EvidenceSha256 $null -Force;$r.ReceiptPath=$null;$r.FailureCode=$null;$r.FailureDetails=$null;$r.Stage='prepared';$r.ExecutionStatus='Prepared';$r.ClaimStatus='unclaimed';$r.RollbackStatus='Required';$r.VerificationStatus='Pending';$r.CompletionStatus='Pending';$r.SideEffectsPerformed=$false;$a.RequestExpiresUtc=$expiry;$a.Stage='prepared';$a.Success=$false;$a.RequestPath=$null;Add-RepatoHistory $t 'maya-tara-prepared-lifecycle-repaired' 'Maya' "attempt=$AttemptId; run=$RunId";$r};if($StoreMutationBoundary){& $StoreMutationBoundary $StoreRoot $cas}else{Invoke-RepatoStoreMutation $StoreRoot $cas}
}
function Recover-MayaQaInvalidNativeClaim {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[string]$RuntimeRoot,[ValidateRange(1,1440)][Nullable[int]]$AttemptDurationMinutes)
    if($null -eq $AttemptDurationMinutes){$AttemptDurationMinutes=Get-MayaQaAttemptDurationMinutes};$data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$old=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if(!$old -or !$attempt -or $old.Stage -cne 'claimed' -or $old.ExecutionStatus -cne 'Claimed' -or $old.ClaimStatus -cne 'claimed' -or $old.ClaimOwner -ceq 'Tara'){throw 'Execution is not an eligible invalid native claim.'}
    foreach($n in 'NativeProcessId','LaunchingUtc','LaunchedUtc','ExecutingUtc','RequestPath','ResultPath','ReportPath','EvidencePath','ReceiptPath','CompletedUtc','VerifiedUtc','RollbackVerifiedUtc'){if($old.PSObject.Properties.Name -contains $n -and $old.$n){throw "Invalid claim contains launch or terminal evidence: $n"}};if($old.SideEffectsPerformed -or $old.VerificationStatus -eq 'Verified' -or $old.CompletionStatus -eq 'Completed'){throw 'Invalid claim has side effects or terminal verification evidence.'};if([string]::IsNullOrWhiteSpace([string]$old.ClaimId)){throw 'Invalid claim has no claim identity.'}
    $resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $task.mayaPlan.WorkflowId $task.mayaPlan.QaWorkflowId;if(@($resolved.Errors).Count){throw ('Invalid claim identity invalid: '+(@($resolved.Errors)-join '; '))};$qa=[IO.Path]::GetFullPath((Get-MayaQaRoot));$source=[IO.Path]::GetFullPath($old.AuthoritativeFixturePath);$fixtures=[IO.Path]::GetFullPath((Join-Path $qa 'Fixtures'));if(!$source.StartsWith($fixtures.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $source -PathType Leaf) -or (Get-FileHash $source -Algorithm SHA256).Hash -ine $old.AuthoritativeFixtureSha256){throw 'Authoritative fixture validation failed.'};foreach($pair in @(@('ArtifactPath','ArtifactSha256'),@('RunnerManifestPath','RunnerManifestSha256'),@('IsolationPolicyPath','IsolationPolicySha256'))){$p=[string]$old.($pair[0]);if(!$p -or !(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-FileHash $p -Algorithm SHA256).Hash -ine $old.($pair[1])){throw "Canonical $($pair[0]) validation failed."}};if(!$old.IsolationAllowed){throw 'Isolation is not allowed.'}
    $runs=[IO.Path]::GetFullPath($(if($RuntimeRoot){$RuntimeRoot}else{Get-MayaQaRuntimeRoot}));$newAttempt=[guid]::NewGuid().ToString('N');$newRun=[guid]::NewGuid().ToString('N');$runtime=[IO.Path]::GetFullPath((Join-Path $runs ($newRun+'-invalid-claim-recovery')));$model=Join-Path $runtime 'model.rvt';if(!$runtime.StartsWith($runs.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Recovery runtime escaped root.'};New-Item -ItemType Directory -Path $runtime -Force|Out-Null;Copy-Item $source $model -Force;$hash=(Get-FileHash $model -Algorithm SHA256).Hash;$newExpiry=[DateTimeOffset]::UtcNow.AddMinutes($AttemptDurationMinutes).ToString('O');$newAttemptRecord=[pscustomobject][ordered]@{SchemaVersion='maya-tara-execution-request-v1';AttemptId=$newAttempt;TaskId=$TaskId;WorkflowId=$resolved.SelectedWorkflowId;RunId=$newRun;RuntimeRoot=$runtime;RequestExpiresUtc=$newExpiry;Stage='prepared';Success=$false;RequestPath=$null};$newExec=[ordered]@{};foreach($p in $old.PSObject.Properties){$newExec[$p.Name]=$p.Value};$newExec.AttemptId=$newAttempt;$newExec.RunId=$newRun;$newExec.DisposableRuntimeRoot=$runtime;$newExec.DisposableModelPath=$model;$newExec.DisposableModelSha256=$hash;$newExec.ClaimOwner=$null;$newExec.ClaimId=$null;$newExec.ClaimedUtc=$null;$newExec.ClaimStatus='unclaimed';$newExec.Stage='prepared';$newExec.ExecutionStatus='Prepared';$newExec.PreparedUtc=Get-RepatoUtc;$newExec.TaskRevisionAtPrepare=$null;$newExec.TaskRevisionAtClaim=$null;$newExec.NativeProcessId=$null;$newExec.RequestPath=$null;$newExec.ResultPath=$null;$newExec.ReportPath=$null;$newExec.EvidencePath=$null;$newExec.ReceiptPath=$null;$newExec.RollbackStatus='Required';$newExec.VerificationStatus='Pending';$newExec.CompletionStatus='Pending';$newExec.FailureCode=$null;$newExec.FailureDetails=$null;$newExec.SideEffectsPerformed=$false
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($t.revision -ne $task.revision -or $x.AttemptId -cne $old.AttemptId -or $x.RunId -cne $old.RunId -or $x.ClaimId -cne $old.ClaimId -or $x.ClaimOwner -ceq 'Tara' -or $x.Stage -cne 'claimed' -or $x.NativeProcessId -or $x.RequestPath -or $x.SideEffectsPerformed){throw 'Invalid-claim recovery compare-and-swap failed.'};$arch=[pscustomobject]$x;$arch|Add-Member NoteProperty Stage 'invalid-claim' -Force;$arch|Add-Member NoteProperty ExecutionStatus 'InvalidClaim' -Force;$arch|Add-Member NoteProperty FailureCode 'invalid-native-claim-owner' -Force;$arch|Add-Member NoteProperty FailureDetails 'Claim was created by a non-Tara owner and no native launch occurred.' -Force;$arch|Add-Member NoteProperty ArchivedUtc (Get-RepatoUtc) -Force;$arch|Add-Member NoteProperty ReplacementAttemptId $newAttempt -Force;$arch|Add-Member NoteProperty ReplacementRunId $newRun -Force;if($t.PSObject.Properties.Name -notcontains 'mayaTaraExecutionHistory'){$t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@()) -Force};$t.mayaTaraExecutionHistory=[object[]]@($t.mayaTaraExecutionHistory)+$arch;if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force};$t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$t.mayaTaraAttempt;$t.mayaTaraAttempt=$newAttemptRecord;$newExec.TaskRevisionAtPrepare=[long]$t.revision;$t.mayaTaraExecution=[pscustomobject]$newExec;Add-RepatoHistory $t 'maya-tara-invalid-claim-recovered' 'Tara' "invalidClaim=$($old.ClaimId); replacementAttempt=$newAttempt; replacementRun=$newRun";$t.mayaTaraExecution}
}
function Recover-MayaQaInvalidNativeClaim {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[string]$RuntimeRoot,[ValidateRange(1,1440)][Nullable[int]]$AttemptDurationMinutes)
    if($null -eq $AttemptDurationMinutes){$AttemptDurationMinutes=Get-MayaQaAttemptDurationMinutes};$data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$old=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if(!$old -or !$attempt -or $old.Stage -cne 'claimed' -or $old.ExecutionStatus -cne 'Claimed' -or $old.ClaimStatus -cne 'claimed' -or $old.ClaimOwner -ceq 'Tara'){throw 'Execution is not an eligible invalid native claim.'}
    foreach($n in 'NativeProcessId','LaunchingUtc','LaunchedUtc','ExecutingUtc','RequestPath','ResultPath','ReportPath','EvidencePath','ReceiptPath','CompletedUtc','VerifiedUtc','RollbackVerifiedUtc'){if($old.PSObject.Properties.Name -contains $n -and $old.$n){throw "Invalid claim contains launch or terminal evidence: $n"}};if($old.SideEffectsPerformed -or $old.VerificationStatus -eq 'Verified' -or $old.CompletionStatus -eq 'Completed'){throw 'Invalid claim has side effects or terminal verification evidence.'};if([string]::IsNullOrWhiteSpace([string]$old.ClaimId)){throw 'Invalid claim has no claim identity.'}
    $resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $task.mayaPlan.WorkflowId $task.mayaPlan.QaWorkflowId;if(@($resolved.Errors).Count){throw ('Invalid claim identity invalid: '+(@($resolved.Errors)-join '; '))};$qa=[IO.Path]::GetFullPath((Get-MayaQaRoot));$source=[IO.Path]::GetFullPath($old.AuthoritativeFixturePath);$fixtures=[IO.Path]::GetFullPath((Join-Path $qa 'Fixtures'));if(!$source.StartsWith($fixtures.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $source -PathType Leaf)){throw 'Authoritative fixture validation failed.'};$sourceHash=(Get-FileHash $source -Algorithm SHA256).Hash;if($sourceHash -ine $old.AuthoritativeFixtureSha256){throw 'Authoritative fixture hash mismatch.'};foreach($pair in @(@('ArtifactPath','ArtifactSha256'),@('RunnerManifestPath','RunnerManifestSha256'),@('IsolationPolicyPath','IsolationPolicySha256'))){$p=[string]$old.($pair[0]);if(!$p -or !(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-FileHash $p -Algorithm SHA256).Hash -ine $old.($pair[1])){throw "Canonical $($pair[0]) validation failed."}};if(!$old.IsolationAllowed){throw 'Isolation is not allowed.'}
    $runs=[IO.Path]::GetFullPath($(if($RuntimeRoot){$RuntimeRoot}else{Get-MayaQaRuntimeRoot}));$newAttempt=[guid]::NewGuid().ToString('N');$newRun=[guid]::NewGuid().ToString('N');$runtime=[IO.Path]::GetFullPath((Join-Path $runs ($newRun+'-invalid-claim-recovery')));if(!$runtime.StartsWith($runs.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Recovery runtime escaped root.'};$model=Join-Path $runtime 'model.rvt';$sidecar=$model+'.fixture.json';New-Item -ItemType Directory -Path $runtime -Force|Out-Null;Copy-Item $source $model -Force;$modelHash=(Get-FileHash $model -Algorithm SHA256).Hash;if($modelHash -ine $sourceHash){throw 'Recovered disposable model hash mismatch.'};$def=Get-MayaQaWorkflowDefinition $resolved.SelectedQaWorkflowId;$side=[ordered]@{fixtureId=$def.FixtureId;sourceSha256=$sourceHash};if($resolved.SelectedQaWorkflowId -eq 'grid-bubble-visibility-v1' -or $resolved.SelectedQaWorkflowId -eq 'grid-bubble-offset-v1'){$side.requiredGridNames=@('A','B','C','D','1','2','3','4')};if($resolved.SelectedQaWorkflowId -eq 'grid-resequence-v1'){$side.requiredGridNames=@('1','2','3','3.2','4','A','A.1','B','C')};$side|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $sidecar -Encoding UTF8;$check=Get-Content -LiteralPath $sidecar -Raw|ConvertFrom-Json;if($check.fixtureId -cne $def.FixtureId -or $check.sourceSha256 -ine $sourceHash){throw 'Recovered fixture sidecar validation failed.'}
    $expiry=[DateTimeOffset]::UtcNow.AddMinutes($AttemptDurationMinutes).ToString('O');$newAttemptRecord=[pscustomobject][ordered]@{SchemaVersion='maya-tara-execution-request-v1';AttemptId=$newAttempt;TaskId=$TaskId;WorkflowId=$resolved.SelectedWorkflowId;RunId=$newRun;RuntimeRoot=$runtime;RequestExpiresUtc=$expiry;Stage='prepared';Success=$false;RequestPath=$null};$newExec=[ordered]@{};foreach($p in $old.PSObject.Properties){$newExec[$p.Name]=$p.Value};$newExec.AttemptId=$newAttempt;$newExec.RunId=$newRun;$newExec.DisposableRuntimeRoot=$runtime;$newExec.DisposableModelPath=$model;$newExec.DisposableModelSha256=$modelHash;$newExec.ClaimOwner=$null;$newExec.ClaimId=$null;$newExec.ClaimedUtc=$null;$newExec.ClaimStatus='unclaimed';$newExec.Stage='prepared';$newExec.ExecutionStatus='Prepared';$newExec.PreparedUtc=Get-RepatoUtc;$newExec.TaskRevisionAtPrepare=$null;$newExec.TaskRevisionAtClaim=$null;$newExec.NativeProcessId=$null;$newExec.RequestPath=$null;$newExec.ResultPath=$null;$newExec.ReportPath=$null;$newExec.EvidencePath=$null;$newExec.ReceiptPath=$null;$newExec.RollbackStatus='Required';$newExec.VerificationStatus='Pending';$newExec.CompletionStatus='Pending';$newExec.FailureCode=$null;$newExec.FailureDetails=$null;$newExec.SideEffectsPerformed=$false
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($t.revision -ne $task.revision -or $x.AttemptId -cne $old.AttemptId -or $x.RunId -cne $old.RunId -or $x.ClaimId -cne $old.ClaimId -or $x.ClaimOwner -ceq 'Tara' -or $x.Stage -cne 'claimed' -or $x.NativeProcessId -or $x.RequestPath -or $x.SideEffectsPerformed){throw 'Invalid-claim recovery compare-and-swap failed.'};$arch=[pscustomobject]$x;$arch|Add-Member NoteProperty Stage 'invalid-claim' -Force;$arch|Add-Member NoteProperty ExecutionStatus 'InvalidClaim' -Force;$arch|Add-Member NoteProperty FailureCode 'invalid-native-claim-owner' -Force;$arch|Add-Member NoteProperty FailureDetails 'Claim was created by a non-Tara owner and no native launch occurred.' -Force;$arch|Add-Member NoteProperty ArchivedUtc (Get-RepatoUtc) -Force;$arch|Add-Member NoteProperty ReplacementAttemptId $newAttempt -Force;$arch|Add-Member NoteProperty ReplacementRunId $newRun -Force;if($t.PSObject.Properties.Name -notcontains 'mayaTaraExecutionHistory'){$t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@()) -Force};$t.mayaTaraExecutionHistory=[object[]]@($t.mayaTaraExecutionHistory)+$arch;if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force};$t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$t.mayaTaraAttempt;$t.mayaTaraAttempt=$newAttemptRecord;$newExec.TaskRevisionAtPrepare=[long]$t.revision;$t.mayaTaraExecution=[pscustomobject]$newExec;Add-RepatoHistory $t 'maya-tara-invalid-claim-recovered' 'Tara' "invalidClaim=$($old.ClaimId); replacementAttempt=$newAttempt; replacementRun=$newRun";$t.mayaTaraExecution}
}
function Test-MayaQaCorrelatedDisposableFixtureProvenance {
    param([Parameter(Mandatory)][string]$QaRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$FixtureId,[Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$SourceSha256,[Parameter(Mandatory)][string]$RuntimeRoot,[Parameter(Mandatory)][string]$ModelPath,[Parameter(Mandatory)][string]$ModelSha256)
    $qa=[IO.Path]::GetFullPath($QaRoot);$source=[IO.Path]::GetFullPath($SourcePath);$runtime=[IO.Path]::GetFullPath($RuntimeRoot);$model=[IO.Path]::GetFullPath($ModelPath);$fixtures=Join-Path $qa 'Fixtures';$runs=Join-Path $qa 'TestRuns'
    if(!$source.StartsWith(([IO.Path]::GetFullPath($fixtures)).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or !$model.StartsWith($runtime.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $source -PathType Leaf) -or !(Test-Path -LiteralPath $model -PathType Leaf)){throw 'Recorded disposable fixture identity/hash validation failed.'}
    if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ine $SourceSha256 -or (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ine $ModelSha256){throw 'Recorded disposable fixture identity/hash validation failed.'}
    $sidePath=$model+'.fixture.json';if(!(Test-Path -LiteralPath $sidePath -PathType Leaf)){throw 'Recorded disposable fixture provenance sidecar is missing.'}
    try{$side=Read-CpvFixtureProvenance -SidecarPath $sidePath}catch{throw "Recorded disposable fixture provenance sidecar is malformed: $($_.Exception.Message)"}
    if([string]$side.fixtureId -cne $FixtureId -or [string]$side.sourceSha256 -ine $SourceSha256 -or [string]$side.preparedModelSha256 -ine $ModelSha256){throw 'Recorded disposable fixture provenance hashes do not match.'}
    $requestPath=[IO.Path]::GetFullPath([string]$side.fixturePreparationRequestPath);$resultPath=[IO.Path]::GetFullPath([string]$side.fixturePreparationResultPath);$runsPrefix=([IO.Path]::GetFullPath($runs)).TrimEnd('\')+'\'
    if(!$requestPath.StartsWith($runsPrefix,[StringComparison]::OrdinalIgnoreCase) -or !$resultPath.StartsWith($runsPrefix,[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $requestPath -PathType Leaf) -or !(Test-Path -LiteralPath $resultPath -PathType Leaf) -or (Get-FileHash -LiteralPath $requestPath -Algorithm SHA256).Hash -ine [string]$side.fixturePreparationRequestSha256 -or (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash -ine [string]$side.fixturePreparationResultSha256){throw 'Recorded disposable fixture preparation evidence is missing or has a hash mismatch.'}
    try{$request=Get-Content -LiteralPath $requestPath -Raw|ConvertFrom-Json;$result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json}catch{throw 'Recorded disposable fixture preparation evidence is malformed.'}
    $prepModel=[IO.Path]::GetFullPath([string]$request.modelPath)
    if(!$prepModel.StartsWith($runsPrefix,[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $prepModel -PathType Leaf) -or (Get-FileHash -LiteralPath $prepModel -Algorithm SHA256).Hash -ine $ModelSha256 -or [string]$request.operation -cne 'prepare-disposable-create-plan-views-fixture' -or [string]$request.taskId -cne $TaskId -or [string]$request.workflowId -cne $WorkflowId -or [string]$request.modelSha256 -ine $SourceSha256 -or [string]$request.requestPath -ine $requestPath -or [string]$request.outputPath -ine $resultPath -or [string]$request.attemptId -cne [string]$side.fixturePreparationAttemptId -or [string]$request.runId -cne [string]$side.fixturePreparationRunId -or [string]$result.Status -cne 'Passed' -or [string]$result.TaskId -cne $TaskId -or [string]$result.WorkflowId -cne $WorkflowId -or [string]$result.AttemptId -cne [string]$request.attemptId -or [string]$result.RunId -cne [string]$request.runId -or [string]$result.ModelPath -ine [string]$request.modelPath -or [string]$result.SourceModelSha256 -ine $SourceSha256 -or [string]$result.PreparedModelSha256 -ine $ModelSha256){throw 'Recorded disposable fixture preparation provenance does not correlate.'}
    $true
}

function Register-MayaQaCorrelatedStartupFailure {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$AttemptId,[Parameter(Mandatory)][string]$ClaimId,[Parameter(Mandatory)][long]$ExpectedTaskRevision)
    $t=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId;$x=$t.mayaTaraExecution
    if([long]$t.revision -ne $ExpectedTaskRevision -or $x.Stage -cne 'executing' -or $x.ExecutionStatus -cne 'Executing' -or $x.AttemptId -cne $AttemptId -or $x.ClaimId -cne $ClaimId -or $x.ClaimOwner -cne 'Tara'){throw 'Exact executing startup-failure identity is required.'}
    $resultPath=$x.RequestPath+'.result.json';$result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
    $reportPath=[IO.Path]::GetFullPath([string]$result.ReportPath)
    if(!$reportPath.StartsWith([IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) 'Reports')).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Startup failure report escaped QA root.'}
    $report=Get-Content -LiteralPath $reportPath -Raw|ConvertFrom-Json
    foreach($document in @($result,$report)){
        foreach($n in 'TaskId','WorkflowId','TestId','AttemptId','RunId','ClaimId'){if([string]$document.$n -cne [string]$x.$n){throw "Startup failure evidence identity mismatch: $n"}}
        if([string]$document.RequestId -cne [string]$x.NativeRequestId -or $document.Status -cne 'Failed'){throw 'Startup failure result/report status mismatch.'}
    }
    if($report.RollbackStatus -cne 'NotStarted' -or @($report.CreatedIds).Count -or @($report.ChangedIds).Count -or @($report.DeletedIds).Count -or @($report.Errors).Count -ne 1 -or $report.Errors[0] -notmatch 'Start a fresh Revit 2025 QA session with no open documents\.' -or $report.AssemblyIdentity.Sha256 -ine $x.ArtifactSha256){throw 'Report does not prove the expected pre-transaction startup rejection.'}
    if((Get-FileHash -LiteralPath $x.DisposableModelPath -Algorithm SHA256).Hash -ine $x.DisposableModelSha256){throw 'Disposable model changed after startup failure.'}
    if(Get-Process -Id $x.NativeProcessId -ErrorAction SilentlyContinue){throw 'Stop the exact failed QA process before recording terminal failure.'}
    $resultHash=(Get-FileHash $resultPath -Algorithm SHA256).Hash;$reportHash=(Get-FileHash $reportPath -Algorithm SHA256).Hash
    Invoke-RepatoStoreMutation $StoreRoot {
        param($data,$preview)
        $current=Find-RepatoTask $data $TaskId;$r=$current.mayaTaraExecution
        if([long]$current.revision -ne $ExpectedTaskRevision -or $r.Stage -cne 'executing' -or $r.AttemptId -cne $AttemptId -or $r.ClaimId -cne $ClaimId -or (Get-FileHash $resultPath).Hash -ine $resultHash -or (Get-FileHash $reportPath).Hash -ine $reportHash){throw 'Startup failure compare-and-swap evidence changed.'}
        $r.Stage='qa-failed';$r.ExecutionStatus='QaFailed';$r.ClaimStatus='qa-failed';$r.FailureCode='native-qa-failed';$r.FailureDetails=[string]$report.Errors[0];$r.FailedUtc=Get-RepatoUtc;$r.ResultPath=$resultPath;$r.ReportPath=$reportPath;$r.ReceiptPath=$resultPath;$r.RollbackStatus='NotStarted';$r.VerificationStatus='Failed';$r.CompletionStatus='Failed'
        $r|Add-Member NoteProperty ResultSha256 $resultHash -Force;$r|Add-Member NoteProperty ReportSha256 $reportHash -Force
        $current.mayaTaraAttempt.Stage='qa-failed';$current.mayaTaraAttempt.Success=$false;$current.status='blocked';$current.workflowStage='qa';$current.errorDetails=$r.FailureDetails
        Add-RepatoHistory $current 'maya-tara-correlated-startup-failure-recorded' 'Tara' "attempt=$AttemptId; request=$($r.NativeRequestId); no model changes reported; no second dispatch"
        $r
    }
}
Export-ModuleMember -Function Register-MayaQaCorrelatedStartupFailure

function Get-MayaQaApprovalAttemptRunIdentity {
    param([Parameter(Mandatory)]$Request)
    $attempt=$null;$run=$null
    if($Request.PSObject.Properties.Name -contains 'attemptId'){$attempt=[string]$Request.attemptId}
    if($Request.PSObject.Properties.Name -contains 'runId'){$run=[string]$Request.runId}
    $binding=if($Request.PSObject.Properties.Name -contains 'recoveryBinding'){$Request.recoveryBinding}elseif($Request.PSObject.Properties.Name -contains 'executionBinding'){$Request.executionBinding}else{$null}
    if($binding){
        if(!$attempt -and $binding.PSObject.Properties.Name -contains 'AttemptId'){$attempt=[string]$binding.AttemptId}
        if(!$run -and $binding.PSObject.Properties.Name -contains 'RunId'){$run=[string]$binding.RunId}
    }
    [pscustomobject]@{AttemptId=$attempt;RunId=$run}
}
function Recover-MayaQaCorrelatedNativeFailure {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[string]$RuntimeRoot,[scriptblock]$ProcessInspector,[ValidateRange(1,1440)][Nullable[int]]$AttemptDurationMinutes)
    if($null -eq $AttemptDurationMinutes){$AttemptDurationMinutes=Get-MayaQaAttemptDurationMinutes};
    $data=Read-RepatoTaskStore $StoreRoot;
    $task=Find-RepatoTask $data $TaskId;
    if($task.status -cne 'in-progress' -or $task.workflowStage -cne 'approval'){throw 'Native-failure recovery requires the canonical in-progress approval stage.'}
    $old=$task.mayaTaraExecution;
    $attempt=$task.mayaTaraAttempt
    if(!$old -or !$attempt -or $old.Stage -cne 'executing' -or $old.ExecutionStatus -cne 'Executing' -or $old.ClaimOwner -cne 'Tara' -or [string]::IsNullOrWhiteSpace([string]$old.ClaimId) -or !$old.NativeProcessId -or !$old.RequestPath){throw 'Execution is not an eligible executing Tara failure.'};
    foreach($n in 'ResultPath','ReportPath','ReceiptPath','VerifiedUtc','CompletedUtc','RollbackVerifiedUtc'){if($old.PSObject.Properties.Name -contains $n -and $old.$n){throw "Failure recovery found consumed evidence: $n"}};
    if($old.EvidencePath -and [string]::IsNullOrWhiteSpace([string]$old.EvidenceSha256)){throw 'Failure recovery found unauthenticated evidence.'}
    if($old.VerificationStatus -ceq 'Verified'){throw 'Already-verified execution is not eligible for correlated native-failure recovery.'};
    if($old.CompletionStatus -ceq 'Completed'){throw 'Already-completed execution is not eligible for correlated native-failure recovery.'};
    if($old.SideEffectsPerformed){throw 'Failure recovery found side effects.'}
    $resolved=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $task.mayaPlan.WorkflowId $task.mayaPlan.QaWorkflowId;
    if(@($resolved.Errors).Count){throw ('Failure identity invalid: '+(@($resolved.Errors)-join ';
     '))};
    $identity=[pscustomobject]@{NativeRequestId=$old.NativeRequestId;
    TaskId=$old.TaskId;
    WorkflowId=$old.WorkflowId;
    QaWorkflowId=$old.QaWorkflowId;
    TestId=$old.TestId;
    HandoffId=$old.HandoffId;
    AttemptId=$old.AttemptId;
    RunId=$old.RunId;
    ClaimId=$old.ClaimId};
    if(![IO.Path]::GetFileName($old.RequestPath)){throw 'Request path is invalid.'};
    $resultPath=$old.RequestPath+'.result.json';
    if(!(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'Correlated native result is missing.'};
    try{$request=Get-Content $old.RequestPath -Raw|ConvertFrom-Json;
    $receipt=Get-Content $resultPath -Raw|ConvertFrom-Json}catch{throw 'Correlated native request/result is malformed.'};
    if([IO.Path]::GetFullPath([string]$request.modelPath) -ine [IO.Path]::GetFullPath([string]$old.DisposableModelPath) -or [string]$request.modelSha256 -ine [string]$old.DisposableModelSha256){throw 'Native request model path/hash does not match the canonical disposable model binding.'}
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','RunId','ClaimId'){$v=if($request.PSObject.Properties.Name -contains ('canonical'+$n)){$request.('canonical'+$n)}else{$request.$n};
    if([string]$v -cne [string]$identity.$n){throw "Request identity mismatch: $n"}};
    if([string]$request.requestId -cne [string]$old.NativeRequestId -or [string]$receipt.RequestId -cne [string]$old.NativeRequestId -or [string]$receipt.RunId -cne [string]$old.RunId -or [string]$receipt.Status -cne 'Failed'){throw 'Native result correlation/status failed.'};
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','AttemptId','RunId','ClaimId'){if([string]$receipt.$n -cne [string]$identity.$n){throw "Native receipt identity mismatch: $n"}};
    if([string]::IsNullOrWhiteSpace([string]$receipt.ReportPath) -or !(Test-Path -LiteralPath $receipt.ReportPath -PathType Leaf)){throw 'Correlated native report is missing.'};
    try{$report=Get-Content $receipt.ReportPath -Raw|ConvertFrom-Json}catch{throw 'Correlated native report is malformed.'};
    if($report.TestId -cne $old.TestId -or [string]$report.RunId -cne [string]$receipt.RunId -or $report.Status -cne 'Failed'){throw 'Native report identity/status failed.'};
    foreach($n in 'RequestId','TaskId','WorkflowId','AttemptId','ClaimId'){if([string]$report.$n -cne [string]$(if($n -ceq 'RequestId'){$old.NativeRequestId}else{$identity.$n})){throw "Native report identity mismatch: $n"}};
    $modelPathFailure=@($report.Errors|Where-Object {[string]$_ -match 'An existing \.rvt file is required\.'}).Count -gt 0
    $reportDocumentPath=if($report.PSObject.Properties.Name -contains 'DocumentPath'){[string]$report.DocumentPath}else{''}
    if($modelPathFailure -and ($report.RollbackStatus -cne 'NotStarted' -or ![string]::IsNullOrWhiteSpace($reportDocumentPath) -or @($report.CreatedIds).Count -or @($report.ChangedIds).Count -or @($report.DeletedIds).Count -or @($report.Screenshots).Count)){throw 'Model-path failure report contains document, mutation, rollback, or screenshot evidence inconsistent with pre-open rejection.'}
    if([string]::IsNullOrWhiteSpace([string]$old.LaunchedUtc)){throw 'Correlated native failure has no recorded launch timestamp.'}
    try{$launchedUtc=Get-MayaQaNormalizedUtc -Value ([string]$old.LaunchedUtc) -Context 'Correlated native launch timestamp'}catch{throw 'Correlated native launch or attempt expiry timestamp is invalid.'}
    try{$attemptExpiresUtc=[DateTimeOffset]::Parse([string]$attempt.RequestExpiresUtc)}catch{throw 'Correlated native launch or attempt expiry timestamp is invalid.'}
    if($launchedUtc -ge $attemptExpiresUtc){throw 'Recorded native launch did not occur within the exact attempt authorization window.'}
    $matchingApprovals=@($task.approvalRequests|Where-Object {
        $identity=Get-MayaQaApprovalAttemptRunIdentity $_
        if(!($_.action -ceq 'qa-run' -and $_.status -ceq 'approved' -and
        (!$identity.AttemptId -or $identity.AttemptId -ceq [string]$old.AttemptId) -and
        $identity.RunId -ceq [string]$old.RunId)){return $false}
        $approvedExpiresUtc=[DateTimeOffset]::MinValue;$approvedRequestedUtc=[DateTimeOffset]::MinValue;$approvedDecidedUtc=[DateTimeOffset]::MinValue
        try{
            $approvedExpiresUtc=[DateTimeOffset]::Parse([string]$_.expiresUtc)
            $approvedRequestedUtc=[DateTimeOffset]::Parse([string]$_.requestedUtc)
            $approvedDecidedUtc=[DateTimeOffset]::Parse([string]$_.decidedUtc)
        }catch{return $false}
        $approvedExpiresUtc -gt $launchedUtc -and $approvedRequestedUtc -le $launchedUtc -and $approvedDecidedUtc -le $launchedUtc
    })
    if($matchingApprovals.Count -ne 1){throw 'Exactly one approved qa-run request bound to the failed attempt and run, authorizing the recorded launch, is required for consumption bookkeeping.'}
    $approvedRequest=$matchingApprovals[0];$approvalBinding=if($approvedRequest.PSObject.Properties.Name -contains 'recoveryBinding'){$approvedRequest.recoveryBinding}elseif($approvedRequest.PSObject.Properties.Name -contains 'executionBinding'){$approvedRequest.executionBinding}else{$null}
    if(!$approvalBinding -or $approvedRequest.requiredLevel -cne 'user' -or $approvedRequest.decidedBy -cne 'user' -or !$approvedRequest.approvedRevision){throw 'Failed execution has no exact human-approved QA binding.'}
    $bindingJson=ConvertTo-Json -InputObject $approvalBinding -Depth 20 -Compress;$bindingSha=[Security.Cryptography.SHA256]::Create();try{$actualBindingHash=([BitConverter]::ToString($bindingSha.ComputeHash([Text.Encoding]::UTF8.GetBytes($bindingJson)))).Replace('-','')}finally{$bindingSha.Dispose()}
    foreach($pair in @(@('TaskId',$TaskId),@('WorkflowId',[string]$old.WorkflowId),@('QaWorkflowId',[string]$old.QaWorkflowId),@('RunId',[string]$old.RunId),@('CandidateSha256',[string]$old.ArtifactSha256),@('ModelPath',[string]$old.DisposableModelPath),@('ModelSha256',[string]$old.DisposableModelSha256))){
        $actualValue=if($approvalBinding.PSObject.Properties.Name -contains $pair[0]){$approvalBinding.($pair[0])}else{$null}
        if([string]$actualValue -ine [string]$pair[1]){throw "Human approval binding mismatch: $($pair[0])"}
    }
    if($approvalBinding.PSObject.Properties.Name -contains 'AttemptId' -and [string]$approvalBinding.AttemptId -ine [string]$old.AttemptId){throw 'Human approval binding mismatch: AttemptId'}
    if($actualBindingHash -ine [string]$approvedRequest.bindingHash -or [DateTimeOffset]::Parse([string]$approvedRequest.expiresUtc) -le $launchedUtc -or [DateTimeOffset]::Parse([string]$approvedRequest.requestedUtc) -gt $launchedUtc -or [DateTimeOffset]::Parse([string]$approvedRequest.decidedUtc) -gt $launchedUtc){throw 'Human approval hash, decision time, or expiry does not authorize the recorded launch.'}
    if($approvalBinding.PSObject.Properties.Name -contains 'SourceRunnerManifestPath' -and ([string]$approvalBinding.SourceRunnerManifestPath -ine [string]$old.RunnerManifestPath -or [string]$approvalBinding.SourceRunnerManifestSha256 -ine [string]$old.RunnerManifestSha256)){throw 'Human approval source runner-manifest binding mismatch.'}
    if($approvalBinding.PSObject.Properties.Name -contains 'DeployedRunnerManifestPath' -and ([string]$approvalBinding.DeployedRunnerManifestPath -ine [string]$old.ValidatedRunnerManifestPath -or [string]$approvalBinding.DeployedRunnerManifestSha256 -ine [string]$old.ValidatedRunnerManifestSha256)){throw 'Human approval deployed runner-manifest binding mismatch.'}
    $failureDetails = 'Native QA report returned Failed without failure details.'
    $failureDetailsProperty = $report.PSObject.Properties['FailureDetails']
    if ($null -ne $failureDetailsProperty) {
        $candidateFailureDetails = [string]$failureDetailsProperty.Value
        if (-not [string]::IsNullOrWhiteSpace($candidateFailureDetails)) {
            $failureDetails = $candidateFailureDetails
        }
    }
    if([string]$failureDetails -eq 'Native QA report returned Failed without failure details.' -and @($report.Errors).Count -gt 0){$failureDetails=[string]$report.Errors[0]}
    $requestExpired=($failureDetails -match 'QA request expired before execution' -and $report.RollbackStatus -ceq 'NotStarted' -and [string]::IsNullOrWhiteSpace([string]$report.DocumentPath) -and @($report.CreatedIds).Count -eq 0 -and @($report.ChangedIds).Count -eq 0 -and @($report.DeletedIds).Count -eq 0 -and @($report.Assertions|Where-Object {$_.Id -cne 'request-identity' -or $_.Passed -ne $true}).Count -eq 0 -and @($report.Assertions|Where-Object {$_.Id -ceq 'request-identity' -and $_.Passed -eq $true}).Count -eq 1)
    if($ProcessInspector){$live=&$ProcessInspector ([int]$old.NativeProcessId) $old}else{try{$live=Get-Process -Id ([int]$old.NativeProcessId) -ErrorAction Stop}catch{$live=$null}};
    if($live){throw 'Recorded native PID is live or ambiguous;
     failure recovery is fail-closed.'}
    $recordedSource=[IO.Path]::GetFullPath($old.AuthoritativeFixturePath);
    $oldRuntime=[IO.Path]::GetFullPath($old.DisposableRuntimeRoot);$oldModel=[IO.Path]::GetFullPath($old.DisposableModelPath);
    $fixtureDefinition=Get-MayaQaWorkflowDefinition $resolved.SelectedQaWorkflowId
    $null=Test-MayaQaCorrelatedDisposableFixtureProvenance -QaRoot (Get-MayaQaRoot) -TaskId $TaskId -WorkflowId $resolved.SelectedWorkflowId -FixtureId $fixtureDefinition.FixtureId -SourcePath $recordedSource -SourceSha256 $old.AuthoritativeFixtureSha256 -RuntimeRoot $oldRuntime -ModelPath $oldModel -ModelSha256 $old.DisposableModelSha256;
    $fixtures=[IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) 'Fixtures'));$definition=Get-MayaQaWorkflowDefinition $resolved.SelectedQaWorkflowId;$source=[IO.Path]::GetFullPath((Join-Path $fixtures $definition.Source));
    if(!$source.StartsWith($fixtures.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $source -PathType Leaf) -or (Get-FileHash $source -Algorithm SHA256).Hash -ine $old.AuthoritativeFixtureSha256){throw 'Approved source fixture validation failed.'};
    foreach($pair in @(@('ArtifactPath','ArtifactSha256'),@('DisposableModelPath','DisposableModelSha256'),@('IsolationPolicyPath','IsolationPolicySha256'))){if(!(Test-Path $old.($pair[0])) -or (Get-FileHash $old.($pair[0]) -Algorithm SHA256).Hash -ine $old.($pair[1])){throw "Hash validation failed: $($pair[0])"}};
    $manifestValidated=$false
    $writer=$null;$reader=$null
    try {
        if(!(Test-Path -LiteralPath $old.RunnerManifestPath -PathType Leaf)){throw 'Runner manifest is inaccessible or missing.'}
        if((Get-FileHash -LiteralPath $old.RunnerManifestPath -Algorithm SHA256).Hash -ine $old.RunnerManifestSha256){throw 'Hash validation failed: RunnerManifestPath'}
        $manifestValidated=$true
    } catch {
        if($_.Exception.Message -eq 'Hash validation failed: RunnerManifestPath'){throw}
        $evidencePath=[string]$old.EvidencePath;$evidenceHash=[string]$old.EvidenceSha256
        if([string]::IsNullOrWhiteSpace($evidencePath) -or [string]::IsNullOrWhiteSpace($evidenceHash) -or !(Test-Path -LiteralPath $evidencePath -PathType Leaf)){throw 'Correlated Tara manifest evidence is missing or invalid.'}
        if((Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash -ine $evidenceHash){throw 'Correlated Tara manifest evidence hash mismatch.'}
        try{$evidencePayload=Get-Content -LiteralPath $evidencePath -Raw|ConvertFrom-Json}catch{throw 'Correlated Tara manifest evidence is malformed.'}
        foreach($n in 'EvidenceVersion','ValidationStatus','TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','CanonicalRunId','ClaimId','NativeRunId','DeployedRunnerManifestPath','DeployedRunnerManifestSha256','IsolationPolicySha256','ValidatedUtc'){if($evidencePayload.PSObject.Properties.Name -notcontains $n){throw "Correlated Tara manifest evidence is missing: $n"}}
        if([int]$evidencePayload.EvidenceVersion -ne 1 -or [string]$evidencePayload.ValidationStatus -cne 'Passed'){throw 'Correlated Tara manifest validation did not pass.'}
        foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','ClaimId'){if([string]$evidencePayload.$n -cne [string]$old.$n){throw "Tara manifest evidence identity mismatch: $n"}}
        if([string]$evidencePayload.CanonicalRunId -cne [string]$old.RunId -or [string]$evidencePayload.DeployedRunnerManifestPath -cne [string]$old.RunnerManifestPath -or [string]$evidencePayload.DeployedRunnerManifestSha256 -ine [string]$old.RunnerManifestSha256 -or [string]$evidencePayload.IsolationPolicySha256 -ine [string]$old.IsolationPolicySha256){throw 'Correlated Tara manifest evidence identity or hash mismatch.'}
        try{$null=[DateTimeOffset]::Parse([string]$evidencePayload.ValidatedUtc)}catch{throw 'Correlated Tara manifest evidence timestamp is invalid.'}
        if([string]$evidencePayload.NativeRunId -cne [string]$receipt.RunId){throw 'Correlated Tara native RunId evidence mismatch.'}
        $manifestValidated=$true
    }
    if(!$manifestValidated){throw 'Runner manifest validation failed.'}
    if(!$old.IsolationAllowed){throw 'Isolation is not allowed.'}
    $oldSidecar=Get-Content -LiteralPath ($oldModel+'.fixture.json') -Raw|ConvertFrom-Json
    $preparationEvidence=$old.FixturePreparationEvidence
    if(!$preparationEvidence){$preparationEvidence=Read-MayaQaFixturePreparationRecord -QaRoot (Get-MayaQaRoot) -TaskId $TaskId -WorkflowId $resolved.SelectedWorkflowId -SourcePath $source -SourceSha256 $old.AuthoritativeFixtureSha256 -ResultPath ([string]$oldSidecar.fixturePreparationResultPath)}
    $null=Test-MayaQaFixturePreparationRecord -QaRoot (Get-MayaQaRoot) -TaskId $TaskId -WorkflowId $resolved.SelectedWorkflowId -SourcePath $source -SourceSha256 $old.AuthoritativeFixtureSha256 -Evidence $preparationEvidence
    if([string]$preparationEvidence.PreparedModelSha256 -ine [string]$old.DisposableModelSha256){throw 'Correlated fixture-preparation evidence does not match the failed disposable model.'}
    $replacementModelSource=[IO.Path]::GetFullPath([string]$preparationEvidence.PreparedModelPath)
    $replacementModelHash=[string]$preparationEvidence.PreparedModelSha256
    $runs=[IO.Path]::GetFullPath($(if($RuntimeRoot){$RuntimeRoot}else{Get-MayaQaRuntimeRoot}));
    $newAttempt=[guid]::NewGuid().ToString('N');
    $newRun=[guid]::NewGuid().ToString('N');
    $runtime=Join-Path $runs ($newRun+'-qa-failure-recovery');
    $model=Join-Path $runtime 'model.rvt';
    $sidecar=$model+'.fixture.json';
    New-Item $runtime -ItemType Directory -Force|Out-Null;
    Copy-Item -LiteralPath $replacementModelSource -Destination $model -Force;
    $hash=(Get-FileHash $model -Algorithm SHA256).Hash;
    $def=$fixtureDefinition;
    $side=[ordered]@{fixtureId=$def.FixtureId;sourceSha256=$old.AuthoritativeFixtureSha256}
    $side.preparedModelSha256=$preparationEvidence.PreparedModelSha256;$side.fixturePreparationRequestPath=$preparationEvidence.RequestPath;$side.fixturePreparationRequestSha256=$preparationEvidence.RequestSha256;$side.fixturePreparationResultPath=$preparationEvidence.ResultPath;$side.fixturePreparationResultSha256=$preparationEvidence.ResultSha256;$side.fixturePreparationAttemptId=$preparationEvidence.AttemptId;$side.fixturePreparationRunId=$preparationEvidence.RunId
    if($resolved.SelectedQaWorkflowId -eq 'grid-bubble-visibility-v1' -or $resolved.SelectedQaWorkflowId -eq 'grid-bubble-offset-v1'){$side.requiredGridNames=@('A','B','C','D','1','2','3','4')}
    if($resolved.SelectedQaWorkflowId -eq 'grid-resequence-v1' -or $resolved.SelectedQaWorkflowId -eq 'grid-resequence-all-directions-v1'){$side.requiredGridNames=@('1','2','3','3.2','4','A','A.1','B','C')}
    $side|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $sidecar -Encoding UTF8;
    if(!(Test-Path -LiteralPath $model -PathType Leaf) -or !(Test-Path -LiteralPath $sidecar -PathType Leaf) -or $hash -ine $replacementModelHash){throw 'Replacement model/sidecar preparation failed.'}
    $null=Test-MayaQaCorrelatedDisposableFixtureProvenance -QaRoot (Get-MayaQaRoot) -TaskId $TaskId -WorkflowId $resolved.SelectedWorkflowId -FixtureId $def.FixtureId -SourcePath $source -SourceSha256 $old.AuthoritativeFixtureSha256 -RuntimeRoot $runtime -ModelPath $model -ModelSha256 $hash
    $expiry=[DateTimeOffset]::UtcNow.AddMinutes($AttemptDurationMinutes).ToString('O');
    $newAttemptRecord=[pscustomobject][ordered]@{SchemaVersion='maya-tara-execution-request-v1';
    AttemptId=$newAttempt;
    TaskId=$TaskId;
    WorkflowId=$resolved.SelectedWorkflowId;
    RunId=$newRun;
    RuntimeRoot=$runtime;
    RequestExpiresUtc=$expiry;
    Stage='prepared';
    Success=$false;
    RequestPath=$null};
    $newExec=[ordered]@{};
    foreach($p in $old.PSObject.Properties){$newExec[$p.Name]=$p.Value};
    $newExec.AttemptId=$newAttempt;
    $newExec.RunId=$newRun;
    $newExec.DisposableRuntimeRoot=$runtime;
    $newExec.DisposableModelPath=$model;
    $newExec.DisposableModelSha256=$hash;
    $newExec.FixturePreparationEvidence=$preparationEvidence;
    $newExec.ClaimOwner=$null;
    $newExec.ClaimId=$null;
    $newExec.ClaimedUtc=$null;
    $newExec.ClaimStatus='unclaimed';
    $newExec.Stage='prepared';
    $newExec.ExecutionStatus='Prepared';
    $newExec.PreparedUtc=Get-RepatoUtc;
    foreach($n in 'LaunchingUtc','LaunchedUtc','ExecutingUtc','EvidenceCollectedUtc','RollbackStartedUtc','RollbackVerifiedUtc','VerifiedUtc','CompletedUtc','FailedUtc'){$newExec[$n]=$null}
    $newExec.TaskRevisionAtPrepare=$null;
    $newExec.TaskRevisionAtClaim=$null;
    $newExec.NativeProcessId=$null;
    $newExec.RequestPath=$null;
    $newExec.ResultPath=$null;
    $newExec.ReportPath=$null;
    $newExec.EvidencePath=$null;
    $newExec.EvidenceSha256=$null;
    if($newExec.Contains('EvidenceValidationStatus')){$newExec.EvidenceValidationStatus=$null}
    $newExec.ReceiptPath=$null;
    $newExec.RollbackStatus='Required';
    $newExec.VerificationStatus='Pending';
    $newExec.CompletionStatus='Pending';
    $newExec.FailureCode=$null;
    $newExec.FailureDetails=$null;
    $newExec.SideEffectsPerformed=$false
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;
    $x=$t.mayaTaraExecution;
    if($t.revision -ne $task.revision -or $t.status -cne 'in-progress' -or $t.workflowStage -cne 'approval' -or $x.AttemptId -cne $old.AttemptId -or $x.RunId -cne $old.RunId -or $x.ClaimId -cne $old.ClaimId -or $x.Stage -cne 'executing' -or $x.NativeProcessId -ne $old.NativeProcessId){throw 'QA failure recovery compare-and-swap failed.'};
    $currentApprovals=@($t.approvalRequests|Where-Object {
        $identity=Get-MayaQaApprovalAttemptRunIdentity $_
        $_.requestId -ceq $approvedRequest.requestId -and $_.action -ceq 'qa-run' -and $_.status -ceq 'approved' -and
        (!$identity.AttemptId -or $identity.AttemptId -ceq [string]$old.AttemptId) -and
        $identity.RunId -ceq [string]$old.RunId -and $_.bindingHash -ceq $approvedRequest.bindingHash
    })
    if($currentApprovals.Count -ne 1 -or $currentApprovals[0].decidedBy -cne 'user'){throw 'Failed attempt human approval changed during recovery compare-and-swap.'}
    if($currentApprovals[0].consumedUtc -and [DateTimeOffset]::Parse([string]$currentApprovals[0].consumedUtc) -ne $launchedUtc){throw 'Human approval consumption timestamp conflicts with the recorded native launch.'}
    if(!$currentApprovals[0].consumedUtc){$currentApprovals[0].consumedUtc=$launchedUtc.ToString('O')}
    if($currentApprovals[0].consumedUtc -and [DateTimeOffset]::Parse([string]$currentApprovals[0].consumedUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) -ne $launchedUtc){throw 'Human approval consumption timestamp conflicts with the recorded native launch.'}
    if(!$currentApprovals[0].consumedUtc){$currentApprovals[0].consumedUtc=$launchedUtc.ToString('O', [Globalization.CultureInfo]::InvariantCulture)}
    $arch=[pscustomobject]$x;
    $arch|Add-Member NoteProperty Stage 'qa-failed' -Force;
    $arch|Add-Member NoteProperty ExecutionStatus 'QaFailed' -Force;
    $arch|Add-Member NoteProperty ClaimStatus 'qa-failed' -Force;
    $arch|Add-Member NoteProperty FailureCode $(if($requestExpired){'request-expired'}else{'native-qa-failed'}) -Force;
    $arch|Add-Member NoteProperty FailureDetails $failureDetails -Force;
    $arch|Add-Member NoteProperty FailedUtc (Get-RepatoUtc) -Force;
    $arch|Add-Member NoteProperty ResultPath $resultPath -Force;
    $arch|Add-Member NoteProperty ReportPath $receipt.ReportPath -Force;
    $arch|Add-Member NoteProperty ReceiptPath $resultPath -Force;
    $arch|Add-Member NoteProperty ResultSha256 (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash -Force;
    $arch|Add-Member NoteProperty ReportSha256 (Get-FileHash -LiteralPath $receipt.ReportPath -Algorithm SHA256).Hash -Force;
    $arch|Add-Member NoteProperty ReplacementAttemptId $newAttempt -Force;
    $arch|Add-Member NoteProperty ReplacementRunId $newRun -Force;
    if($t.PSObject.Properties.Name -notcontains 'mayaTaraExecutionHistory'){$t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@()) -Force};
    $t.mayaTaraExecutionHistory=[object[]]@($t.mayaTaraExecutionHistory)+$arch;
    if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force};
    $t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$t.mayaTaraAttempt;
    $t.mayaTaraAttempt=$newAttemptRecord;
    $newExec.TaskRevisionAtPrepare=[long]$t.revision;
    $t.mayaTaraExecution=[pscustomobject]$newExec;
    $t.status='in-progress';$t.workflowStage='approval'
    Add-RepatoHistory $t 'maya-tara-correlated-native-failure-recovered' 'Tara' "failedAttempt=$($old.AttemptId);
     failedRun=$($old.RunId);
     replacementAttempt=$newAttempt;
     failureCode=$arch.FailureCode";
    $t.mayaTaraExecution}
}

function Prepare-MayaQaAfterExpiredFailureRecovery {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$FailedAttemptId,[Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedCandidateSha256,[Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{40}$')][string]$ExpectedCandidateSourceCommit,[switch]$DryRun)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    $archives=@($task.mayaTaraExecutionHistory|Where-Object {$_.AttemptId -ceq $FailedAttemptId -and $_.FailureCode -ceq 'request-expired'})
    if($archives.Count -ne 1){throw 'Exact terminal request-expired attempt archive is required.'}
    $failed=$archives[0];$attempt=$task.mayaTaraAttempt;$execution=$task.mayaTaraExecution
    if(!$attempt -or !$execution -or $attempt.AttemptId -cne $failed.ReplacementAttemptId -or $attempt.RunId -cne $failed.ReplacementRunId -or $execution.AttemptId -cne $attempt.AttemptId -or $execution.RunId -cne $attempt.RunId -or $execution.Stage -cne 'prepared' -or $execution.ExecutionStatus -cne 'Prepared' -or $execution.ClaimId -or $execution.NativeProcessId -or $execution.RequestPath -or $execution.SideEffectsPerformed){throw 'Request-expired recovery replacement is not an exact unlaunched prepared identity.'}
    if($failed.ManualLoadOnceEvidence.AttemptId -cne $FailedAttemptId -or $failed.ManualLoadOnceEvidence.RunId -cne $failed.RunId -or $failed.ManualLoadOnceEvidence.NativeRequestId -cne $failed.NativeRequestId){throw 'Archived manual approval identity does not match the failed attempt.'}
    foreach($pair in @(@($failed.ResultPath,$failed.ResultSha256),@($failed.ReportPath,$failed.ReportSha256))){if(!$pair[0] -or !$pair[1] -or !(Test-Path -LiteralPath $pair[0] -PathType Leaf) -or (Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ine $pair[1]){throw 'Archived request-expired result/report hash validation failed.'}}
    $receipt=Get-Content -LiteralPath $failed.ResultPath -Raw|ConvertFrom-Json;$report=Get-Content -LiteralPath $failed.ReportPath -Raw|ConvertFrom-Json
    if($receipt.Status -cne 'Failed' -or $receipt.RequestId -cne $failed.NativeRequestId -or $receipt.TaskId -cne $TaskId -or $receipt.WorkflowId -cne $failed.WorkflowId -or $receipt.AttemptId -cne $FailedAttemptId -or $receipt.RunId -cne $failed.RunId -or $receipt.ClaimId -cne $failed.ClaimId -or $receipt.ReportPath -cne $failed.ReportPath -or $report.Status -cne 'Failed' -or $report.RollbackStatus -cne 'NotStarted' -or $report.Errors.Count -ne 1 -or $report.Errors[0] -notmatch 'QA request expired before execution' -or ![string]::IsNullOrWhiteSpace([string]$report.DocumentPath) -or @($report.CreatedIds).Count -or @($report.ChangedIds).Count -or @($report.DeletedIds).Count -or @($report.Assertions|Where-Object {$_.Id -cne 'request-identity' -or $_.Passed -ne $true}).Count){throw 'Archived terminal expiry evidence failed exact request/report correlation.'}
    if(Get-Process -Id ([int]$failed.NativeProcessId) -ErrorAction SilentlyContinue){throw 'Failed native Revit process is still present.'}
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $failed.WorkflowId;$e=$workflow.qaBuildEvidence
    if(!$e -or !$e.DeploymentValidation -or !$e.ManifestIntegrityValidation -or !$e.QaIsolation -or $e.CandidateSourceCommit -cne $ExpectedCandidateSourceCommit -or $e.ArtifactSha256 -ine $ExpectedCandidateSha256 -or $execution.ArtifactSha256 -ine $ExpectedCandidateSha256){throw 'Fresh canonical preparation gates or candidate identity are not satisfied.'}
    $snapshot=[pscustomobject][ordered]@{ArchivedUtc=Get-RepatoUtc;Reason='Unlaunched recovery record superseded by canonical re-preparation after exact request-expired failure';Attempt=$attempt;Execution=$execution;Plan=$task.mayaPlan;QaPacket=$task.mayaTaraQaPacket;WorkflowRunId=$workflow.qaRunId;WorkflowModelPath=$workflow.qaModelPath;WorkflowHandoffId=$workflow.qaHandoffId;WorkflowHandoff=$workflow.qaHandoff;FailedAttemptId=$FailedAttemptId}
    if($DryRun){return [pscustomobject]@{Status='DryRun';FailedAttemptId=$FailedAttemptId;ReplacementAttemptId=$attempt.AttemptId;ReplacementRunId=$attempt.RunId;ResultPath=$failed.ResultPath;ReportPath=$failed.ReportPath;EvidencePreserved=$true;RevitProcessAbsent=$true;QaLaunchPerformed=$false;SideEffectsPerformed=$false}}
    $taskRevision=[long]$task.revision;$workflowRevision=[long]$workflow.workflowRevision
    Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)
        $t=Find-RepatoTask $d $TaskId;$ws=@($t.deploymentWorkflows|Where-Object workflowId -ceq $failed.WorkflowId)
        if([long]$t.revision -ne $taskRevision -or $ws.Count -ne 1 -or [long]$ws[0].workflowRevision -ne $workflowRevision -or $t.mayaTaraAttempt.AttemptId -cne $attempt.AttemptId -or $t.mayaTaraExecution.AttemptId -cne $attempt.AttemptId){throw 'Expired-failure continuation compare-and-swap failed.'}
        if($t.PSObject.Properties.Name -notcontains 'mayaTaraRecoveryPreparationHistory'){$t|Add-Member NoteProperty mayaTaraRecoveryPreparationHistory ([object[]]@()) -Force};$t.mayaTaraRecoveryPreparationHistory=[object[]]@($t.mayaTaraRecoveryPreparationHistory)+$snapshot
        foreach($n in 'mayaPlan','mayaTaraQaPacket','mayaTaraAttempt','mayaTaraExecution','mayaTaraExecutionEvidence'){$t.PSObject.Properties.Remove($n)}
        $w=$ws[0];if($w.PSObject.Properties.Name -notcontains 'qaHandoffHistory'){$w|Add-Member NoteProperty qaHandoffHistory ([object[]]@()) -Force};if($w.qaHandoff){$w.qaHandoffHistory=[object[]]@($w.qaHandoffHistory)+[pscustomobject]@{HandoffId=$w.qaHandoffId;Handoff=$w.qaHandoff;RunId=$w.qaRunId;ArchivedUtc=Get-RepatoUtc;Reason='Superseded before any fresh QA launch after prior request expired'}}
        foreach($n in 'qaHandoffId','qaHandoff','qaApprovalId','qaApprovalStatus','qaRunId','qaModelPath','qaSidecarPath','qaFixtureId','qaFixtureSha256','qaTestId','qaReportPath','qaReportSha256','qaEvidence','qaVerificationStatus','qaCompletionStatus','qaCompletedUtc'){$w.PSObject.Properties.Remove($n)};$w.workflowRevision=[long]$w.workflowRevision+1
        foreach($q in @($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -in @('pending','approved')})){$q.status='superseded';$q.reason='Replaced after archived request-expired attempt before fresh canonical preparation.'}
        Add-RepatoHistory $t 'maya-tara-expired-failure-preparation-reset' 'Maya' "failedAttempt=$FailedAttemptId; unlaunchedRecoveryAttempt=$($attempt.AttemptId); result=$($failed.ResultPath); report=$($failed.ReportPath)"
        [pscustomobject]@{TaskId=$TaskId;WorkflowId=$failed.WorkflowId;FailedAttemptId=$FailedAttemptId;EvidencePreserved=$true;ApprovalRefreshRequired=$true;QaLaunchPerformed=$false}
    }
}

function Archive-MayaQaRecoveredAttemptForCandidateReplacement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$FailedAttemptId,
        [Parameter(Mandatory)][string]$RecoveredAttemptId,
        [Parameter(Mandatory)][string]$RecoveredRunId,
        [Parameter(Mandatory)][long]$ExpectedTaskRevision,
        [scriptblock]$ProcessProvider,
        [switch]$DryRun
    )
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    if(!$task -or [long]$task.revision -ne $ExpectedTaskRevision){throw 'Candidate-replacement retirement task revision is stale.'}
    if($task.status -cne 'in-progress' -or $task.workflowStage -cne 'approval'){throw 'Candidate-replacement retirement requires the recovered in-progress approval state.'}
    $attempt=$task.mayaTaraAttempt;$execution=$task.mayaTaraExecution
    if(!$attempt -or !$execution -or $attempt.AttemptId -cne $RecoveredAttemptId -or $attempt.RunId -cne $RecoveredRunId -or $execution.AttemptId -cne $RecoveredAttemptId -or $execution.RunId -cne $RecoveredRunId -or $execution.TaskId -cne $TaskId -or $execution.WorkflowId -cne $WorkflowId){throw 'Recovered candidate-replacement attempt identity mismatch.'}
    if($attempt.Stage -cne 'prepared' -or $execution.Stage -cne 'prepared' -or $execution.ExecutionStatus -cne 'Prepared' -or $execution.ClaimStatus -cne 'unclaimed' -or $execution.SideEffectsPerformed){throw 'Only the exact unlaunched recovered prepared attempt may be retired.'}
    foreach($n in 'ClaimId','ClaimOwner','ClaimedUtc','NativeProcessId','RequestPath','ResultPath','ReportPath','ReceiptPath','LaunchingUtc','LaunchedUtc','ExecutingUtc') { if(($attempt.PSObject.Properties.Name -contains $n -and $attempt.$n) -or ($execution.PSObject.Properties.Name -contains $n -and $execution.$n)){throw "Recovered prepared attempt contains prohibited launch evidence: $n"} }
    if(!$execution.FixturePreparationEvidence -or !$execution.DisposableModelPath -or !$execution.DisposableModelSha256 -or !(Test-Path -LiteralPath $execution.DisposableModelPath -PathType Leaf) -or (Get-FileHash -LiteralPath $execution.DisposableModelPath -Algorithm SHA256).Hash -ine $execution.DisposableModelSha256){throw 'Recovered prepared model binding is missing or invalid.'}
    $failed=@($task.mayaTaraExecutionHistory|Where-Object {$_.AttemptId -ceq $FailedAttemptId -and $_.FailureCode -ceq 'native-qa-failed' -and $_.ReplacementAttemptId -ceq $RecoveredAttemptId -and $_.ReplacementRunId -ceq $RecoveredRunId})
    if($failed.Count -ne 1){throw 'Exact archived native QA failure and recovered-attempt edge are required.'}
    foreach($pair in @(@($failed[0].ResultPath,$failed[0].ResultSha256),@($failed[0].ReportPath,$failed[0].ReportSha256))){if(!$pair[0] -or !$pair[1] -or !(Test-Path -LiteralPath $pair[0] -PathType Leaf) -or (Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ine $pair[1]){throw 'Archived failed receipt/report hash validation failed.'}}
    if([string]$execution.AuthoritativeFixturePath -and [string]$execution.AuthoritativeFixtureSha256 -match '^[A-Fa-f0-9]{64}$'){$source=[IO.Path]::GetFullPath([string]$execution.AuthoritativeFixturePath);$fixtureId=[string](Get-MayaQaWorkflowDefinition ([string]$execution.QaWorkflowId)).FixtureId;$qaRoot=Get-MayaQaRoot;$null=Test-MayaQaCorrelatedDisposableFixtureProvenance -QaRoot $qaRoot -TaskId $TaskId -WorkflowId $WorkflowId -FixtureId $fixtureId -SourcePath $source -SourceSha256 ([string]$execution.AuthoritativeFixtureSha256) -RuntimeRoot ([string]$execution.DisposableRuntimeRoot) -ModelPath ([string]$execution.DisposableModelPath) -ModelSha256 ([string]$execution.DisposableModelSha256)}else{throw 'Recovered prepared model lacks authoritative fixture identity for provenance validation.'}
    $approved=@($task.approvalRequests|Where-Object {
        $action=$_.PSObject.Properties['action'];$status=$_.PSObject.Properties['status'];$consumed=$_.PSObject.Properties['consumedUtc']
        if(!$action -or !$status -or !$consumed){return $false}
        if([string]$action.Value -cne 'qa-run' -or [string]$status.Value -cne 'approved'){return $false}
        if([string]::IsNullOrWhiteSpace([string]$consumed.Value)){return $false}
        $identity=Get-MayaQaApprovalAttemptRunIdentity $_
        (!$identity.AttemptId -or $identity.AttemptId -ceq $FailedAttemptId) -and $identity.RunId -ceq [string]$failed[0].RunId
    })
    if($approved.Count -ne 1){throw 'Exact consumed approval for the failed native attempt is required before candidate replacement.'}
    $workflows=@($task.deploymentWorkflows|Where-Object {$_.workflowId -ceq $WorkflowId -and $_.taskId -ceq $TaskId})
    if($workflows.Count -ne 1){throw 'Candidate-replacement workflow identity is ambiguous.'};$workflow=$workflows[0]
    $packet=$task.mayaTaraQaPacket;$packetModel=if($packet -and $packet.ModelPath){[IO.Path]::GetFullPath([string]$packet.ModelPath)}else{''}
    $packetRecovered=($packet -and $packet.TaskId -ceq $TaskId -and $packet.WorkflowId -ceq $WorkflowId -and $packet.AttemptId -ceq $RecoveredAttemptId -and $packet.RunId -ceq $RecoveredRunId -and $packetModel -ieq [IO.Path]::GetFullPath([string]$execution.DisposableModelPath) -and [IO.Path]::GetFullPath([string]$packet.SidecarPath) -ieq [IO.Path]::GetFullPath(([string]$execution.DisposableModelPath)+'.fixture.json'))
    $packetFailed=($packet -and $packet.TaskId -ceq $TaskId -and $packet.WorkflowId -ceq $WorkflowId -and $packet.AttemptId -ceq $FailedAttemptId -and $packet.RunId -ceq [string]$failed[0].RunId -and $packetModel -ieq [IO.Path]::GetFullPath([string]$failed[0].DisposableModelPath))
    if(!$packetRecovered -and !$packetFailed){throw 'QA packet does not bind either the exact failed attempt or recovered prepared attempt.'}
    if($workflow.qaWorkflowId -cne [string]$execution.QaWorkflowId -or $workflow.qaRunId -cne [string]$failed[0].RunId -or [IO.Path]::GetFullPath([string]$workflow.qaModelPath) -ine [IO.Path]::GetFullPath([string]$failed[0].DisposableModelPath) -or [string]$failed[0].WorkflowId -cne $WorkflowId){throw 'Workflow binding does not match the archived failed attempt/run/model.'}
    $processes=@();if($ProcessProvider){$processes=@(& $ProcessProvider)}else{$processes=@(Get-Process -Name Revit -ErrorAction SilentlyContinue)};if($processes.Count){throw 'Candidate-replacement retirement is blocked while Revit is running.'}
    $workflowRevision=[long]$workflow.workflowRevision
    $priorRetirement=if($task.PSObject.Properties.Name -contains 'mayaQaCandidateReplacementRetirement'){$task.mayaQaCandidateReplacementRetirement}else{$null}
    if($priorRetirement -and $priorRetirement.PSObject.Properties.Name -contains 'RecoveredAttemptId' -and [string]$priorRetirement.RecoveredAttemptId -ceq $RecoveredAttemptId){throw 'Recovered attempt was already retired for candidate replacement.'}
    $packetBinding=if($packetRecovered){'recovered-attempt'}else{'failed-attempt'}
    $snapshot=[pscustomobject][ordered]@{ArchivedUtc=Get-RepatoUtc;Reason='Runner correction requires a versioned candidate; recovered attempt was prepared but never claimed or launched';FailedAttemptId=$FailedAttemptId;RecoveredAttemptId=$RecoveredAttemptId;RecoveredRunId=$RecoveredRunId;PreparedAttempt=[pscustomobject]$attempt;PreparedExecution=[pscustomobject]$execution;QaPacket=[pscustomobject]$packet;QaPacketBinding=$packetBinding;Plan=$task.mayaPlan;WorkflowRunId=$workflow.qaRunId;WorkflowModelPath=$workflow.qaModelPath;WorkflowHandoffId=$workflow.qaHandoffId;WorkflowHandoff=$workflow.qaHandoff;ApprovalRequestId=$approved[0].requestId}
    if($DryRun){return [pscustomobject]@{Status='DryRun';TaskId=$TaskId;FailedAttemptId=$FailedAttemptId;RecoveredAttemptId=$RecoveredAttemptId;RecoveredRunId=$RecoveredRunId;FailedEvidencePreserved=$true;ConsumedApprovalPreserved=$true;RevitAbsent=$true;NativeLaunchPerformed=$false;SideEffectsPerformed=$false}}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)
        $t=Find-RepatoTask $current $TaskId;$ws=@($t.deploymentWorkflows|Where-Object {$_.workflowId -ceq $WorkflowId -and $_.taskId -ceq $TaskId})
        if([long]$t.revision -ne $ExpectedTaskRevision -or $ws.Count -ne 1 -or [long]$ws[0].workflowRevision -ne $workflowRevision -or [string]$ws[0].qaRunId -cne [string]$workflow.qaRunId -or [string]$ws[0].qaModelPath -cne [string]$workflow.qaModelPath -or $t.status -cne 'in-progress' -or $t.workflowStage -cne 'approval' -or $t.mayaTaraAttempt.AttemptId -cne $RecoveredAttemptId -or $t.mayaTaraExecution.AttemptId -cne $RecoveredAttemptId -or [string]$t.mayaTaraQaPacket.AttemptId -cne [string]$packet.AttemptId -or [string]$t.mayaTaraQaPacket.RunId -cne [string]$packet.RunId -or [string]$t.mayaTaraQaPacket.ModelPath -cne [string]$packet.ModelPath){throw 'Candidate-replacement retirement compare-and-swap failed.'}
        $q=@($t.approvalRequests|Where-Object {$req=$_.PSObject.Properties['requestId'];$status=$_.PSObject.Properties['status'];$consumed=$_.PSObject.Properties['consumedUtc'];$req -and $status -and $consumed -and [string]$req.Value -ceq [string]$approved[0].requestId -and [string]$status.Value -ceq 'approved' -and [string]$consumed.Value -ceq [string]$approved[0].consumedUtc -and (($identity=Get-MayaQaApprovalAttemptRunIdentity $_) -and (!$identity.AttemptId -or $identity.AttemptId -ceq $FailedAttemptId) -and $identity.RunId -ceq [string]$failed[0].RunId)});if($q.Count -ne 1){throw 'Consumed failure approval changed during candidate-replacement retirement.'}
        $archAttempt=[pscustomobject]$t.mayaTaraAttempt;$archAttempt.Stage='abandoned-preparation';$archAttempt|Add-Member NoteProperty CleanupReason 'Retired before claim/native launch to build corrected replacement candidate.' -Force;$archAttempt|Add-Member NoteProperty ArchivedUtc (Get-RepatoUtc) -Force
        $archExecution=[pscustomobject]$t.mayaTaraExecution;$archExecution.Stage='abandoned-preparation';$archExecution.ExecutionStatus='PreparedAttemptSuperseded';$archExecution|Add-Member NoteProperty FailureCode 'candidate-replacement-required' -Force;$archExecution|Add-Member NoteProperty FailureDetails 'Prepared recovered attempt was never claimed or launched; a corrected versioned candidate is required.' -Force;$archExecution|Add-Member NoteProperty ArchivedUtc (Get-RepatoUtc) -Force;$archExecution|Add-Member NoteProperty RuntimePreserved $true -Force
        if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force};$t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$archAttempt
        $t.mayaTaraExecutionHistory=[object[]]@($t.mayaTaraExecutionHistory)+$archExecution
        if($t.PSObject.Properties.Name -notcontains 'mayaQaCandidateReplacementHistory'){$t|Add-Member NoteProperty mayaQaCandidateReplacementHistory ([object[]]@()) -Force};$t.mayaQaCandidateReplacementHistory=[object[]]@($t.mayaQaCandidateReplacementHistory)+$snapshot
        foreach($n in 'mayaPlan','mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){$t.PSObject.Properties.Remove($n)}
        $w=$ws[0];if($w.PSObject.Properties.Name -notcontains 'qaHandoffHistory'){$w|Add-Member NoteProperty qaHandoffHistory ([object[]]@()) -Force};$w.qaHandoffHistory=[object[]]@($w.qaHandoffHistory)+[pscustomobject]@{HandoffId=$w.qaHandoffId;Handoff=$w.qaHandoff;RunId=$w.qaRunId;ArchivedUtc=Get-RepatoUtc;Reason='Superseded before fresh candidate build; no native launch occurred'}
        foreach($n in 'qaHandoffId','qaHandoff','qaApprovalId','qaApprovalStatus','qaRunId','qaModelPath','qaSidecarPath','qaFixtureId','qaFixtureSha256','qaTestId','qaReportPath','qaReportSha256','qaEvidence','qaVerificationStatus','qaCompletionStatus','qaCompletedUtc'){$w.PSObject.Properties.Remove($n)};$w.workflowRevision=[long]$w.workflowRevision+1
        $priorRetirementRecord=if($t.PSObject.Properties['mayaQaCandidateReplacementRetirement']){$t.mayaQaCandidateReplacementRetirement}else{$null}
        if($priorRetirementRecord){$t.mayaQaCandidateReplacementHistory=[object[]]@($t.mayaQaCandidateReplacementHistory)+$priorRetirementRecord}
        $t|Add-Member NoteProperty mayaQaCandidateReplacementRetirement ([pscustomobject]@{WorkflowId=$WorkflowId;FailedAttemptId=$FailedAttemptId;RecoveredAttemptId=$RecoveredAttemptId;RecoveredRunId=$RecoveredRunId;RetiredUtc=Get-RepatoUtc;ApprovalRequestId=$approved[0].requestId;ConsumedApprovalPreserved=$true;NativeLaunchAbsent=$true}) -Force
        $t.status='in-progress';$t.workflowStage='build-checks';Add-RepatoHistory $t 'maya-qa-recovered-attempt-retired-for-candidate-replacement' 'Maya' "failedAttempt=$FailedAttemptId; recoveredAttempt=$RecoveredAttemptId; run=$RecoveredRunId; consumedApprovalPreserved=true"
        [pscustomobject]@{Status='Retired';TaskId=$TaskId;WorkflowId=$WorkflowId;FailedAttemptId=$FailedAttemptId;RecoveredAttemptId=$RecoveredAttemptId;RecoveredRunId=$RecoveredRunId;FailedEvidencePreserved=$true;ConsumedApprovalPreserved=$true;TaskStage='build-checks';NativeLaunchPerformed=$false}
    }
}
function Get-MayaQaCanonicalNativeResult {
    param([Parameter(Mandatory)][string]$RequestPath,[string]$ResultPath,[Parameter(Mandatory)][object]$Identity,[ValidateRange(1,86400)][int]$TimeoutSeconds=7200,[scriptblock]$SecurityPromptProvider)
    if(!(Test-Path -LiteralPath $RequestPath -PathType Leaf)){throw 'Canonical request is missing.'}
    try{$request=Get-Content -LiteralPath $RequestPath -Raw|ConvertFrom-Json}catch{throw 'Canonical request JSON is malformed.'}
    if($request.PSObject.Properties.Name -contains 'requestId' -and [string]$request.requestId -cne [string]$Identity.NativeRequestId){throw 'Native request identity mismatch: requestId'}
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','RunId','ClaimId'){$rp=if($request.PSObject.Properties.Name -contains ('canonical'+$n)){[string]$request.('canonical'+$n)}elseif($request.PSObject.Properties.Name -contains $n){[string]$request.$n}else{$null};$legacyV2HandoffOmission=($n -ceq 'HandoffId' -and [int]$request.schemaVersion -eq 2 -and [string]::IsNullOrWhiteSpace($rp));if(!$legacyV2HandoffOmission -and $rp -cne [string]$Identity.$n){throw "Canonical request identity mismatch: $n"}}
    $result=if($ResultPath){$ResultPath}else{$RequestPath+'.result.json'};$deadline=[DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    if(!$SecurityPromptProvider){if(!(Get-Command Get-TaraSecurityPrompt -ErrorAction SilentlyContinue)){Import-Module (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -WarningAction SilentlyContinue};$SecurityPromptProvider={Get-TaraSecurityPrompt}}
    while(!(Test-Path -LiteralPath $result -PathType Leaf)){
        $prompt=& $SecurityPromptProvider
        if($prompt){$title=[string]$prompt.Title;$text=[string]$prompt.Text;throw "Revit security prompt requires a human decision; no UI interaction was performed. $title $text"}
        if([DateTimeOffset]::UtcNow -ge $deadline){throw 'Canonical native result wait timed out.'};Start-Sleep -Milliseconds 250
    }
    try{$receipt=Get-Content -LiteralPath $result -Raw|ConvertFrom-Json}catch{throw 'Canonical native result JSON is malformed.'}
    if(!$receipt){throw 'Canonical native result identity mismatch.'}
    foreach($n in 'RequestId','TaskId','WorkflowId','QaWorkflowId','AttemptId','RunId','ClaimId'){$expected=if($n -ceq 'RequestId'){$Identity.NativeRequestId}else{$Identity.$n};if($receipt.PSObject.Properties.Name -notcontains $n -or [string]$receipt.$n -cne [string]$expected){throw "Canonical native result identity mismatch: $n"}}
    if($receipt.PSObject.Properties.Name -contains 'ExpiresUtc' -and [DateTimeOffset]::Parse($receipt.ExpiresUtc) -lt [DateTimeOffset]::UtcNow){throw 'Canonical native result is stale or expired.'}
    if([string]::IsNullOrWhiteSpace([string]$receipt.ReportPath) -or !(Test-Path -LiteralPath $receipt.ReportPath -PathType Leaf)){throw 'Canonical native report is missing.'}
    try{$report=Get-Content -LiteralPath $receipt.ReportPath -Raw|ConvertFrom-Json}catch{throw 'Canonical native report JSON is malformed.'}
    if($report.TestId -cne $Identity.TestId -or $report.Status -cne 'Passed'){throw 'Canonical native report identity/status failed.'}
    foreach($n in 'TaskId','AttemptId','RunId'){if($report.PSObject.Properties.Name -notcontains $n -or [string]$report.$n -cne [string]$Identity.$n){throw "Canonical native report identity mismatch: $n"}}
    $assertions=@($report.Assertions);$verified=($assertions.Count -gt 0 -and @($assertions|Where-Object{$_.Passed -isnot [bool] -or !$_.Passed}).Count -eq 0)
    $ep=if($receipt.PSObject.Properties.Name -contains 'EvidencePath' -and $receipt.EvidencePath){$receipt.EvidencePath}else{$receipt.ReportPath};$eh=$null;if(Test-Path -LiteralPath $ep -PathType Leaf){$eh=(Get-FileHash -LiteralPath $ep -Algorithm SHA256).Hash};[pscustomobject]@{RequestId=$Identity.RequestId;TaskId=$Identity.TaskId;WorkflowId=$Identity.WorkflowId;QaWorkflowId=$Identity.QaWorkflowId;TestId=$Identity.TestId;HandoffId=$Identity.HandoffId;AttemptId=$Identity.AttemptId;RunId=$Identity.RunId;ClaimId=$Identity.ClaimId;ResultPath=$result;ReportPath=$receipt.ReportPath;EvidencePath=$ep;EvidenceSha256=$eh;EvidenceValidationStatus=$(if($receipt.Status -ceq 'Passed' -and $report.Status -ceq 'Passed'){'Passed'}else{$null});ReceiptPath=$result;EvidenceAccepted=($receipt.Status -ceq 'Passed' -and $report.Status -ceq 'Passed');RollbackProven=($report.RollbackStatus -ceq 'RolledBack');Verified=$verified}
}
function Resume-MayaQaCanonicalExecution {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$ClaimId,[string]$ResultPath,[ValidateRange(1,86400)][int]$TimeoutSeconds=7200,[switch]$DryRun,[scriptblock]$SecurityPromptProvider)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$r=$task.mayaTaraExecution
    if(!$r -or $r.Stage -cne 'executing' -or $r.ExecutionStatus -cne 'Executing'){throw 'Canonical execution is not resumable from its current stage.'}
    if(!$r.NativeProcessId){throw 'Canonical executing execution has no native process ID.'};if($r.ClaimId -cne $ClaimId -or $r.ClaimOwner -cne 'Tara'){throw 'Canonical resume claim identity mismatch.'};if(!$r.RequestPath){throw 'Canonical executing execution has no request path.'};if([string]$r.NativeRequestId -notmatch '^[a-fA-F0-9]{32}$'){throw 'Canonical executing execution has no valid persisted native request ID.'}
    $identity=[pscustomobject]@{RequestId=[IO.Path]::GetFileName($r.RequestPath);NativeRequestId=$r.NativeRequestId;TaskId=$r.TaskId;WorkflowId=$r.WorkflowId;QaWorkflowId=$r.QaWorkflowId;TestId=$r.TestId;HandoffId=$r.HandoffId;AttemptId=$r.AttemptId;RunId=$r.RunId;ClaimId=$r.ClaimId}
    if($DryRun){return [pscustomobject]@{Mode='DryRun';Stage=$r.Stage;NativeProcessId=$r.NativeProcessId;RequestPath=$r.RequestPath;ResultPath=$(if($ResultPath){$ResultPath}else{$r.RequestPath+'.result.json'});SideEffectsPerformed=$false}}
    $result=Get-MayaQaCanonicalNativeResult $r.RequestPath $ResultPath $identity $TimeoutSeconds $SecurityPromptProvider
    if(!$result.EvidenceAccepted){throw 'Native evidence was not accepted.'};Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'executing' -or $x.ClaimId -cne $ClaimId -or $x.NativeProcessId -ne $r.NativeProcessId){throw 'Canonical resume compare-and-swap failed.'};$x.Stage='evidence-collected';$x.ExecutionStatus='EvidenceCollected';$x.ResultPath=$result.ResultPath;$x.ReportPath=$result.ReportPath;$x.EvidencePath=$result.EvidencePath;$x|Add-Member NoteProperty EvidenceSha256 $result.EvidenceSha256 -Force;$x|Add-Member NoteProperty EvidenceValidationStatus $result.EvidenceValidationStatus -Force;$x.ReceiptPath=$result.ReceiptPath;Add-RepatoHistory $t 'maya-tara-evidence-collected' 'Tara' 'resumed correlated native evidence accepted';$x}
    if(!$result.RollbackProven){throw 'Rollback proof is required.'};Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'evidence-collected'){throw 'Canonical rollback transition out of order.'};$x.Stage='rollback-verified';$x.ExecutionStatus='RollbackVerified';$x.RollbackStatus='Verified';$x.RollbackVerifiedUtc=Get-RepatoUtc;Add-RepatoHistory $t 'maya-tara-rollback-verified' 'Tara' 'resumed native rollback evidence accepted';$x}
    if(!$result.Verified){throw 'QA verification failed.'};Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'rollback-verified'){throw 'Canonical verification transition out of order.'};$x.Stage='verified';$x.ExecutionStatus='Verified';$x.VerificationStatus='Verified';$x.VerifiedUtc=Get-RepatoUtc;Add-RepatoHistory $t 'maya-tara-verified' 'Tara' 'resumed QA verification accepted';$x}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'verified'){throw 'Canonical completion transition out of order.'};$x.Stage='completed';$x.ExecutionStatus='Completed';$x.CompletionStatus='Completed';$x.CompletedUtc=Get-RepatoUtc;Add-RepatoHistory $t 'maya-tara-completed' 'Tara' 'resumed canonical execution completed';$x}
}
function Get-MayaQaCatalogDryRun { param([string]$WorkflowId)
    $items=if($WorkflowId){$null=Get-MayaQaWorkflowDefinition $WorkflowId; @(Get-MayaQaWorkflowCatalog | Where-Object WorkflowId -ceq $WorkflowId)}else{@(Get-MayaQaWorkflowCatalog)}
    $items=@($items); [pscustomobject]@{Workflows=$items;SupportedWorkflowCount=$items.Count;SideEffectsPerformed=$false;RevitLaunchPerformed=$false;DeploymentPerformed=$false;StoreWritePerformed=$false}
}
function Get-MayaQaNormalizedUtc {
    param([Parameter(Mandatory)][string]$Value,[Parameter(Mandatory)][string]$Context)
    if([string]::IsNullOrWhiteSpace($Value)){throw "$Context timestamp is missing."}
    $candidate=[DateTimeOffset]::MinValue
    if([DateTimeOffset]::TryParse($Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$candidate)){return $candidate.ToUniversalTime()}
    $local=[DateTime]::MinValue
    if([DateTime]::TryParse($Value,[Globalization.CultureInfo]::CurrentCulture,[Globalization.DateTimeStyles]::None,[ref]$local) -or
        [DateTime]::TryParse($Value,[Globalization.CultureInfo]::CurrentCulture,[Globalization.DateTimeStyles]::AllowWhiteSpaces,[ref]$local) -or
        [DateTime]::TryParse($Value,[Globalization.CultureInfo]('en-US'),[Globalization.DateTimeStyles]::None,[ref]$local) -or
        [DateTime]::TryParse($Value,[Globalization.CultureInfo]('en-US'),[Globalization.DateTimeStyles]::AllowWhiteSpaces,[ref]$local)){
        return [DateTimeOffset]::new($local,[TimeZoneInfo]::Local.GetUtcOffset($local))
    }
    throw "$Context timestamp is invalid: '$Value'."
}
function ConvertTo-MayaQaNormalizedUtcString {
    param([Parameter(Mandatory)][string]$Value,[Parameter(Mandatory)][string]$Context)
    (Get-MayaQaNormalizedUtc -Value $Value -Context $Context).ToString('O')
}
function Invoke-MayaQaProcessLauncher {
    param([Parameter(Mandatory)][string]$Executable,[string]$Arguments,[scriptblock]$Launcher,[hashtable]$EnvironmentVariables,[object]$LaunchRequest)
    if($Launcher){$p=& $Launcher $Executable $Arguments;if(!$p -or !$p.Pid){throw 'Injected process launcher returned no PID.'};return [pscustomobject]@{Pid=[int]$p.Pid;StartedUtc=$(if($p.StartedUtc){ConvertTo-MayaQaNormalizedUtcString -Value ([string]$p.StartedUtc) -Context 'Injected process launcher start timing'}else{Get-RepatoUtc})}}
    if($Arguments){throw 'QA launch agent does not accept arbitrary Revit arguments.'}
    if(!$LaunchRequest){throw 'RepatoQA v2 launch request is required.'}
    Invoke-MayaQaLaunchAgentRequest -Request $LaunchRequest -Executable $Executable
}
function Invoke-MayaQaLaunchAgentRequest {
    param([Parameter(Mandatory)][object]$Request,[Parameter(Mandatory)][string]$Executable,[ValidateRange(100,30000)][int]$TimeoutMilliseconds=5000,[ValidateRange(1024,32768)][int]$MaxResponseBytes=32768,[scriptblock]$ResponseProvider,[int]$ExpectedSessionId)
    $pipe=$null;$writer=$null;$reader=$null;$original=$null
    try {
        if([string]$Request.operation -cne 'launch-revit-qa' -or [int]$Request.schemaVersion -ne 2){throw 'Invalid v2 launch request.'}
        if($ResponseProvider){$response=& $ResponseProvider $Request}
        else {
            if([string]$Request.requestPath -notlike '*.request.json' -or !(Test-Path -LiteralPath $Request.requestPath -PathType Leaf)){throw 'Launch request path is missing.'}
            $pipe=[IO.Pipes.NamedPipeClientStream]::new('.', 'Repato\QaLaunch', [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::WriteThrough)
            $pipe.Connect($TimeoutMilliseconds)
            $json=$Request|ConvertTo-Json -Compress -Depth 10
            if([Text.Encoding]::UTF8.GetByteCount($json) -gt 32768){throw 'Launch request is oversized.'}
            $writer=[IO.StreamWriter]::new($pipe,[Text.Encoding]::UTF8,1024,$true);$writer.AutoFlush=$true
            $writeTask=$writer.WriteLineAsync($json);if(!$writeTask.Wait($TimeoutMilliseconds)){throw 'Launch request write timed out.'};$reader=[IO.StreamReader]::new($pipe,[Text.Encoding]::UTF8,$false,1024,$true)
            $readTask=$reader.ReadLineAsync();if(!$readTask.Wait($TimeoutMilliseconds)){throw 'Launch response read timed out.'};$line=$readTask.Result
            if([string]::IsNullOrWhiteSpace($line) -or [Text.Encoding]::UTF8.GetByteCount($line) -gt $MaxResponseBytes){throw 'Launch response is missing or oversized.'}
            try{$response=$line|ConvertFrom-Json -ErrorAction Stop}catch{throw 'Launch response JSON is malformed.'}
        }
        foreach($n in 'schemaVersion','operation','requestId','correlationId','accepted','pid','user','sid','sessionId','launchUtc','imagePath','requestPath','taskId','workflowId','qaWorkflowId','testId','attemptId','runId','failureCode'){if($response.PSObject.Properties.Name -notcontains $n){throw "Launch response missing $n."}}
        if([int]$response.schemaVersion -ne 2 -or [string]$response.operation -cne 'launch-revit-qa'){throw 'Unexpected launch response contract.'}
        if([string]$response.requestId -cne [string]$Request.requestId -or [string]$response.correlationId -cne [string]$Request.requestId){throw 'Launch response correlation mismatch.'}
        foreach($n in 'taskId','workflowId','qaWorkflowId','testId','attemptId','runId','requestPath'){if([string]$response.$n -cne [string]$Request.$n){throw "Launch response identity mismatch: $n."}}
        if(-not [bool]$response.accepted){if([string]::IsNullOrWhiteSpace([string]$response.failureCode)){throw 'Rejected launch response has no failure code.'};throw "RepatoQA launch rejected: $($response.failureCode)"}
        if([int]$response.pid -le 0 -or [string]$response.user -ine 'RAMSAI\RepatoQA' -or [string]$response.sid -ine 'S-1-5-21-1031246752-3872016183-2454652381-1015'){throw 'Accepted launch identity is invalid.'}
        $expectedSession=if($ExpectedSessionId){@($ExpectedSessionId)}else{$currentIdentity=[Security.Principal.WindowsIdentity]::GetCurrent().Name;if($currentIdentity -ine 'RAMSAI\RepatoQA'){throw 'Launch response validation must run as RAMSAI\RepatoQA.'};@((Get-Process -Id $PID -ErrorAction Stop).SessionId)}
        if(!$expectedSession -or !(@($expectedSession) -contains ([int]$response.sessionId))){throw 'Accepted launch session is not the authenticated RepatoQA session.'}
        if([IO.Path]::GetFullPath([string]$response.imagePath) -ine [IO.Path]::GetFullPath($Executable)){throw 'Accepted launch image mismatch.'}
        if([string]$response.failureCode){throw 'Accepted launch response contains a failure code.'}
        [pscustomobject]@{Pid=[int]$response.pid;StartedUtc=(ConvertTo-MayaQaNormalizedUtcString -Value ([string]$response.launchUtc) -Context 'Launch agent start timing');Response=$response}
    } catch { $original=$_.Exception;throw } finally {
        try{if($reader){$reader.Dispose()}}catch{}
        try{if($writer){$writer.Dispose()}}catch{}
        try{if($pipe){$pipe.Dispose()}}catch{}
    }
}
function Invoke-MayaQaLaunchAgentHealth {
    param([ValidateRange(100,10000)][int]$TimeoutMilliseconds=3000)
    $pipe=[IO.Pipes.NamedPipeClientStream]::new('.', 'Repato\QaLaunch', [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::WriteThrough)
    $writer=$null;$reader=$null
    try {
        $pipe.Connect($TimeoutMilliseconds)
          $writer=[IO.StreamWriter]::new($pipe,[Text.Encoding]::UTF8,1024,$true);$writer.AutoFlush=$true
        $writeTask=$writer.WriteLineAsync((@{schemaVersion=1;operation='health'}|ConvertTo-Json -Compress))
        if(!$writeTask.Wait($TimeoutMilliseconds)){throw 'Health request write timed out.'}
          $reader=[IO.StreamReader]::new($pipe,[Text.Encoding]::UTF8,$false,1024,$true)
        $readTask=$reader.ReadLineAsync()
        if(!$readTask.Wait($TimeoutMilliseconds)){throw 'Health response read timed out.'}
        $line=$readTask.Result
        if([string]::IsNullOrWhiteSpace($line) -or $line.Length -gt 32768){throw 'Invalid health response.'}
        $h=$line|ConvertFrom-Json
        foreach($n in 'schemaVersion','operation','ready','user','sid','sessionId','interactive'){if($h.PSObject.Properties.Name -notcontains $n){throw "Health response missing $n."}}
        if([int]$h.schemaVersion -ne 1 -or [string]$h.operation -cne 'health'){throw 'Unexpected health response.'}
        [pscustomobject]@{ProtocolVersion=[int]$h.schemaVersion;Operation=[string]$h.operation;Ready=[bool]$h.ready;User=[string]$h.user;SID=[string]$h.sid;SessionId=[int]$h.sessionId;UserInteractive=[bool]$h.interactive}
      } finally {
          try { if($reader){$reader.Dispose()} } catch { }
          try { if($writer){$writer.Dispose()} } catch { }
          try { if($pipe){$pipe.Dispose()} } catch { }
      }
}
function Invoke-MayaQaLaunchAgentPreflightReadonly {
    param([ValidateRange(100,30000)][int]$TimeoutMilliseconds=5000,[ValidateRange(1024,32768)][int]$MaxResponseBytes=32768,[scriptblock]$ResponseProvider,
        [object]$CandidateEvidence,[string]$TaskId,[string]$WorkflowId,[string]$QaWorkflowId,[string]$TestId,[string]$CandidateCommit,[string]$ExpectedCandidateSha256)
    $request=[ordered]@{schemaVersion=1;operation='preflight-readonly'};$pipe=$null;$writer=$null;$reader=$null
    if($CandidateEvidence){
        if(!$TaskId -or !$WorkflowId -or $QaWorkflowId -cne 'create-plan-views-v1' -or $TestId -cne $QaWorkflowId -or
            $CandidateCommit -notmatch '^[A-Fa-f0-9]{40}$' -or $ExpectedCandidateSha256 -notmatch '^[A-Fa-f0-9]{64}$') {throw 'Candidate-aware preflight requires exact task, workflow and candidate identity.'}
        foreach($pair in @(@('TaskId',$TaskId),@('WorkflowId',$WorkflowId),@('QaWorkflowId',$QaWorkflowId),@('TestId',$TestId),@('CandidateSourceCommit',$CandidateCommit),@('CandidateDllSha256',$ExpectedCandidateSha256),@('NeilBuildArtifactSha256',$ExpectedCandidateSha256))){
            $property=$CandidateEvidence.PSObject.Properties[$pair[0]]
            if(!$property -or [string]$property.Value -ine [string]$pair[1]){throw "Candidate-aware preflight evidence binding mismatch: $($pair[0])."}
        }
        foreach($pair in @(@('taskId',$TaskId),@('workflowId',$WorkflowId),@('qaWorkflowId',$QaWorkflowId),@('testId',$TestId),@('candidateCommit',$CandidateCommit),@('expectedCandidateSha256',$ExpectedCandidateSha256),@('candidateEvidence',$CandidateEvidence))){$request[$pair[0]]=$pair[1]}
    } elseif($TaskId -or $WorkflowId -or $QaWorkflowId -or $TestId -or $CandidateCommit -or $ExpectedCandidateSha256){throw 'Candidate-aware preflight evidence is required.'}
    try {
        if($ResponseProvider){$response=& $ResponseProvider ([pscustomobject]$request)}
        else {
            $pipe=[IO.Pipes.NamedPipeClientStream]::new('.', 'Repato\QaLaunch', [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::WriteThrough);$pipe.Connect($TimeoutMilliseconds)
            $json=$request|ConvertTo-Json -Depth 12 -Compress;$writer=[IO.StreamWriter]::new($pipe,[Text.Encoding]::UTF8,1024,$true);$writer.AutoFlush=$true;$writeTask=$writer.WriteLineAsync($json);if(!$writeTask.Wait($TimeoutMilliseconds)){throw 'Preflight request write timed out.'};$reader=[IO.StreamReader]::new($pipe,[Text.Encoding]::UTF8,$false,1024,$true);$readTask=$reader.ReadLineAsync();if(!$readTask.Wait($TimeoutMilliseconds)){throw 'Preflight response read timed out.'};$line=$readTask.Result;if([string]::IsNullOrWhiteSpace($line) -or [Text.Encoding]::UTF8.GetByteCount($line) -gt $MaxResponseBytes){throw 'Preflight response is missing or oversized.'};try{$response=$line|ConvertFrom-Json -ErrorAction Stop}catch{throw 'Preflight response JSON is malformed.'}
        }
        foreach($n in 'schemaVersion','operation','succeeded','executionIdentity','qaAddinRoot','runnerManifestPath','expectedRunnerManifestSha256','checks'){if($response.PSObject.Properties.Name -notcontains $n){throw "Preflight response missing $n."}}
        if([int]$response.schemaVersion -ne 1 -or [string]$response.operation -cne 'preflight-readonly'){throw 'Unexpected preflight response contract.'}
        if([string]$response.executionIdentity -ine 'RAMSAI\RepatoQA'){throw 'Preflight execution identity is invalid.'}
        [pscustomobject]@{Succeeded=[bool]$response.succeeded;ExecutionIdentity=[string]$response.executionIdentity;QaAddinRoot=[string]$response.qaAddinRoot;RunnerManifestPath=[string]$response.runnerManifestPath;ExpectedRunnerManifestSha256=[string]$response.expectedRunnerManifestSha256;Checks=@($response.checks);FailureCode=[string]$response.failureCode;Response=$response}
    } finally {try{if($reader){$reader.Dispose()}}catch{};try{if($writer){$writer.Dispose()}}catch{};try{if($pipe){$pipe.Dispose()}}catch{}}
}
function Test-MayaQaPostStageCandidateHashMismatch {
    param([Parameter(Mandatory)][object]$Preflight,[Parameter(Mandatory)][string]$ExpectedCandidateSha256)
    if($Preflight.Succeeded){return $false}
    $failed=@($Preflight.Checks|Where-Object {!$_.passed})
    if($failed.Count -ne 1 -or [string]$failed[0].name -cne 'deployed-candidate-dll-integrity'){return $false}
    $expectedRoot=[IO.Path]::GetFullPath('C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA')
    $expectedDll=[IO.Path]::GetFullPath((Join-Path $expectedRoot 'Repato.Revit.dll'))
    if([string]$failed[0].status -cne 'hash-mismatch' -or [string]::IsNullOrWhiteSpace([string]$failed[0].path) -or [IO.Path]::GetFullPath([string]$failed[0].path) -ine $expectedDll -or
       [string]::IsNullOrWhiteSpace([string]$Preflight.QaAddinRoot) -or [IO.Path]::GetFullPath([string]$Preflight.QaAddinRoot) -ine $expectedRoot){return $false}
    $detail=[string]$failed[0].detail
    $actualMatch=[regex]::Match($detail,'(?:^|;)actual=([A-Fa-f0-9]{64})(?:;|$)')
    $pinnedMatch=[regex]::Match($detail,'(?:^|;)expected=([A-Fa-f0-9]{64})(?:;|$)')
    if(!$actualMatch.Success -or !$pinnedMatch.Success -or $actualMatch.Groups[1].Value -ine $ExpectedCandidateSha256 -or $pinnedMatch.Groups[1].Value -ieq $ExpectedCandidateSha256){return $false}
    $true
}
function Read-MayaQaBoundedPipeLine {
    param([Parameter(Mandatory)][IO.StreamReader]$Reader,[ValidateRange(100,30000)][int]$TimeoutMilliseconds=5000,[ValidateRange(1024,32768)][int]$MaxResponseBytes=32768,[Parameter(Mandatory)][string]$Operation)
    $readTask=$Reader.ReadLineAsync()
    if(!$readTask.Wait($TimeoutMilliseconds)){throw "$Operation response read timed out; request disposition is ambiguous."}
    $line=$readTask.Result
    if([string]::IsNullOrWhiteSpace($line)){throw "$Operation response is missing."}
    if([Text.Encoding]::UTF8.GetByteCount($line) -gt $MaxResponseBytes){throw "$Operation response is oversized."}
    $line
}
function Invoke-MayaQaLaunchAgentFrozenCandidateStaging {
    param([Parameter(Mandatory)][string]$CandidateCommit,[Parameter(Mandatory)][string]$ExpectedCandidateSha256,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$TestId,[ValidateRange(100,30000)][int]$TimeoutMilliseconds=5000,[object]$CandidateEvidence,[string]$TaskId,[string]$WorkflowId)
    if($CandidateEvidence){if(!$TaskId -or !$WorkflowId){throw 'Generic staging requires canonical task and workflow identity.'};$request=[ordered]@{schemaVersion=1;operation='stage-frozen-candidate-for-qa';requestId=[guid]::NewGuid().ToString('N');candidateCommit=$CandidateCommit;expectedCandidateSha256=$ExpectedCandidateSha256;taskId=$TaskId;workflowId=$WorkflowId;qaWorkflowId=$QaWorkflowId;testId=$TestId;candidateEvidence=$CandidateEvidence}}else{
        if($CandidateCommit -cne 'fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3' -or $ExpectedCandidateSha256 -cne '7EC1C819C771DCE4EC4ADCADB93B0245D243F6675EC0F0B070B03303B1F412C2' -or $QaWorkflowId -cne 'create-plan-views-v1' -or $TestId -cne $QaWorkflowId){throw 'Frozen candidate staging identity is not authoritative.'}
        $request=[ordered]@{schemaVersion=1;operation='stage-frozen-candidate-for-qa';requestId=[guid]::NewGuid().ToString('N');candidateCommit=$CandidateCommit;expectedCandidateSha256=$ExpectedCandidateSha256;qaWorkflowId=$QaWorkflowId;testId=$TestId}
    }
    $pipe=[IO.Pipes.NamedPipeClientStream]::new('.', 'Repato\QaLaunch', [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::WriteThrough);$writer=$null;$reader=$null
    try{$pipe.Connect($TimeoutMilliseconds);$writer=[IO.StreamWriter]::new($pipe,[Text.Encoding]::UTF8,1024,$true);$writer.AutoFlush=$true;$writeTask=$writer.WriteLineAsync(($request|ConvertTo-Json -Compress));if(!$writeTask.Wait($TimeoutMilliseconds)){throw 'Staging request write timed out; request disposition is ambiguous.'};$reader=[IO.StreamReader]::new($pipe,[Text.Encoding]::UTF8,$false,1024,$true);$line=Read-MayaQaBoundedPipeLine -Reader $reader -TimeoutMilliseconds $TimeoutMilliseconds -MaxResponseBytes 32768 -Operation 'Staging';$r=$line|ConvertFrom-Json;if([int]$r.schemaVersion -ne 1 -or [string]$r.operation -cne $request.operation -or [string]$r.requestId -cne $request.requestId){throw 'Staging response identity mismatch.'};if(!$r.succeeded -or [string]$r.candidateCommit -cne $CandidateCommit -or [string]$r.candidateSha256 -ine $ExpectedCandidateSha256 -or [string]$r.qaWorkflowId -cne $QaWorkflowId -or [string]$r.testId -cne $TestId -or [string]$r.stagingIdentity -ine 'RAMSAI\RepatoQA' -or !$r.isolationPassed){throw "Frozen candidate staging rejected: $($r.errorCode)"};$r}finally{try{if($reader){$reader.Dispose()}}catch{};try{if($writer){$writer.Dispose()}}catch{};try{$pipe.Dispose()}catch{}}
}
function Normalize-MayaQaDeploymentValidationResponse {
    param([Parameter(Mandatory)][object]$Response,[Parameter(Mandatory)][string]$CandidateCommit,[Parameter(Mandatory)][string]$ExpectedCandidateSha256,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$TestId,[string]$ExpectedRequestId)
    foreach($n in 'schemaVersion','operation','requestId','succeeded','validationIdentity','candidateCommit','qaWorkflowId','testId','candidateSha256','isolationPassed','qaAddinRoot'){if($Response.PSObject.Properties.Name -notcontains $n){throw "Deployment validation response missing $n."}}
    if($ExpectedRequestId -and [string]$Response.requestId -cne $ExpectedRequestId){throw 'Deployment validation response request identity mismatch.'}
    $integrityProperty=$Response.PSObject.Properties['manifestIntegrityPassed'];if($integrityProperty -and !$integrityProperty.Value){throw 'Runtime manifest integrity evidence rejected deployment.'}
    foreach($n in 'runnerManifestPath','runnerManifestSha256','manifestIntegrityPassed'){if($Response.PSObject.Properties.Name -notcontains $n -or $null -eq $Response.$n){throw "Deployment validation response missing $n."}}
    if($Response.manifestIntegrityPassed -isnot [bool] -or !$Response.manifestIntegrityPassed){throw 'Runtime manifest integrity evidence rejected deployment.'}
    if([int]$Response.schemaVersion -ne 1 -or [string]$Response.operation -cne 'validate-qa-deployment' -or [string]$Response.validationIdentity -ine 'RAMSAI\RepatoQA' -or !$Response.succeeded -or [string]$Response.candidateCommit -ine $CandidateCommit -or [string]$Response.qaWorkflowId -cne $QaWorkflowId -or [string]$Response.testId -cne $TestId -or [string]$Response.candidateSha256 -ine $ExpectedCandidateSha256 -or !$Response.isolationPassed){throw "RepatoQA deployment validation rejected: $($Response.errorCode)"}
    $expectedRoot='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA';$qaRoot=[IO.Path]::GetFullPath([string]$Response.qaAddinRoot);if($qaRoot -ine $expectedRoot -or $qaRoot.Contains('..')){throw 'Deployment validation returned a non-canonical QA add-in root.'}
    $sourceManifest=[IO.Path]::GetFullPath((Join-Path (Join-Path $PSScriptRoot '..\QA') 'Repato.CreatePlanViews.TestRunner.addin'));if(!(Test-Path -LiteralPath $sourceManifest -PathType Leaf)){throw 'Trusted QA runner source manifest is missing.'};$trustedHash=(Get-FileHash -LiteralPath $sourceManifest -Algorithm SHA256).Hash;$canonicalPath=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($qaRoot)) 'Repato.CreatePlanViews.TestRunner.addin'))
    $pathProperty=$Response.PSObject.Properties['runnerManifestPath'];if([string]::IsNullOrWhiteSpace([string]$pathProperty.Value) -or [IO.Path]::GetFullPath([string]$pathProperty.Value) -ine $canonicalPath){throw 'Deployment validation returned a non-canonical runner manifest path.'}
    $hashProperty=$Response.PSObject.Properties['runnerManifestSha256'];if([string]$hashProperty.Value -notmatch '^[A-Fa-f0-9]{64}$' -or [string]$hashProperty.Value -ine $trustedHash){throw 'Runtime runner manifest hash conflicts with trusted source evidence.'}
    $Response|Add-Member NoteProperty runnerManifestPath $canonicalPath -Force;$Response|Add-Member NoteProperty runnerManifestSha256 $trustedHash -Force;$Response|Add-Member NoteProperty validatedRunnerManifestPath $canonicalPath -Force;$Response|Add-Member NoteProperty manifestIntegrityEvidenceAvailable ([bool]$integrityProperty) -Force;$Response|Add-Member NoteProperty manifestIntegrityPassed ($(if($integrityProperty){[bool]$integrityProperty.Value}else{$null})) -Force;$Response
}
function Assert-MayaQaDeploymentValidationResponseEnvelope {
    param([Parameter(Mandatory)][object]$Response,[Parameter(Mandatory)][string]$ExpectedRequestId)
    foreach($n in 'schemaVersion','operation','requestId','succeeded','validationIdentity','qaWorkflowId','testId','candidateSha256','isolationPassed','qaAddinRoot'){if($Response.PSObject.Properties.Name -notcontains $n){throw "Deployment validation response missing $n."}}
    if([int]$Response.schemaVersion -ne 1 -or [string]$Response.operation -cne 'validate-qa-deployment'){throw 'Deployment validation response contract is invalid.'}
    if([string]$Response.requestId -cne $ExpectedRequestId){throw 'Deployment validation response request identity mismatch.'}
    $Response
}
function Invoke-MayaQaLaunchAgentDeploymentValidation {
    param([Parameter(Mandatory)][string]$CandidateCommit,[Parameter(Mandatory)][string]$ExpectedCandidateSha256,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$TestId,[ValidateRange(100,30000)][int]$TimeoutMilliseconds=5000,[object]$CandidateEvidence,[string]$TaskId,[string]$WorkflowId,[string]$RequestId)
    if([string]::IsNullOrWhiteSpace($RequestId)){$RequestId=[guid]::NewGuid().ToString('N')}else{$parsedRequestId=[guid]::Empty;if(![guid]::TryParse($RequestId,[ref]$parsedRequestId)){throw 'Deployment validation request identity is invalid.'}}
    if($CandidateEvidence){if(!$TaskId -or !$WorkflowId){throw 'Generic deployment validation requires canonical task and workflow identity.'};$request=[ordered]@{schemaVersion=1;operation='validate-qa-deployment';requestId=$RequestId;candidateCommit=$CandidateCommit;expectedCandidateSha256=$ExpectedCandidateSha256;taskId=$TaskId;workflowId=$WorkflowId;qaWorkflowId=$QaWorkflowId;testId=$TestId;candidateEvidence=$CandidateEvidence}}else{
        if($CandidateCommit -cne 'fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3' -or $ExpectedCandidateSha256 -cne '7EC1C819C771DCE4EC4ADCADB93B0245D243F6675EC0F0B070B03303B1F412C2' -or $QaWorkflowId -cne 'create-plan-views-v1' -or $TestId -cne $QaWorkflowId){throw 'Deployment validation identity is not authoritative.'}
        $request=[ordered]@{schemaVersion=1;operation='validate-qa-deployment';requestId=$RequestId;candidateCommit=$CandidateCommit;expectedCandidateSha256=$ExpectedCandidateSha256;qaWorkflowId=$QaWorkflowId;testId=$TestId}
    };$pipe=[IO.Pipes.NamedPipeClientStream]::new('.', 'Repato\QaLaunch', [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::WriteThrough);$writer=$null;$reader=$null
    try{$pipe.Connect($TimeoutMilliseconds);$writer=[IO.StreamWriter]::new($pipe,[Text.Encoding]::UTF8,1024,$true);$writer.AutoFlush=$true;$writeTask=$writer.WriteLineAsync(($request|ConvertTo-Json -Compress));if(!$writeTask.Wait($TimeoutMilliseconds)){throw 'Deployment validation request write timed out; request disposition is ambiguous.'};$reader=[IO.StreamReader]::new($pipe,[Text.Encoding]::UTF8,$false,1024,$true);$r=(Read-MayaQaBoundedPipeLine -Reader $reader -TimeoutMilliseconds $TimeoutMilliseconds -MaxResponseBytes 32768 -Operation 'Deployment validation')|ConvertFrom-Json;Assert-MayaQaDeploymentValidationResponseEnvelope -Response $r -ExpectedRequestId $RequestId}finally{try{if($reader){$reader.Dispose()}}catch{};try{if($writer){$writer.Dispose()}}catch{};try{$pipe.Dispose()}catch{}}
}
function ConvertTo-MayaQaCanonicalRequestJson {
    param([Parameter(Mandatory)][object]$Request)
    $ordered=[ordered]@{}
    $properties=if($Request -is [System.Collections.IDictionary]){@($Request.GetEnumerator()|ForEach-Object{[pscustomobject]@{Name=$_.Key;Value=$_.Value}})}else{@($Request.PSObject.Properties|ForEach-Object{[pscustomobject]@{Name=$_.Name;Value=$_.Value}})}
    foreach($p in @($properties|Sort-Object Name)){$ordered[$p.Name]=$p.Value}
    ($ordered|ConvertTo-Json -Compress -Depth 20).Replace('+','\u002B')
}
function Get-MayaQaCanonicalRequestSha256 {
    param([Parameter(Mandatory)][object]$Request)
    $placeholder=[ordered]@{}
    $properties=if($Request -is [System.Collections.IDictionary]){@($Request.GetEnumerator()|ForEach-Object{[pscustomobject]@{Name=$_.Key;Value=$_.Value}})}else{@($Request.PSObject.Properties|ForEach-Object{[pscustomobject]@{Name=$_.Name;Value=$_.Value}})}
    foreach($p in @($properties|Sort-Object Name)){$placeholder[$p.Name]=if($p.Name -ceq 'requestSha256'){('0'*64)}else{$p.Value}}
    $json=ConvertTo-MayaQaCanonicalRequestJson $placeholder
    $sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}finally{$sha.Dispose()}
}
function Invoke-MayaQaCanonicalNativeCore {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$ClaimId,[object]$Result,[Parameter(Mandatory)][string]$Executable,[string]$Arguments,[scriptblock]$ProcessLauncher,[scriptblock]$ManifestValidationBoundary,[switch]$DryRun)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$r=$task.mayaTaraExecution
    if(!$r){throw 'Canonical execution is missing.'};if($r.Stage -cne 'claimed' -or $r.ExecutionStatus -cne 'Claimed' -or $r.ClaimStatus -cne 'claimed'){throw 'Execution is not claimed.'};if($r.ClaimOwner -cne 'Tara' -or $r.ClaimId -cne $ClaimId){throw 'Claim identity mismatch.'};if([DateTimeOffset]::Parse($task.mayaTaraAttempt.RequestExpiresUtc)-le[DateTimeOffset]::UtcNow){throw 'Attempt expired before native launch.'};if([long]$task.revision -ne ([long]$r.TaskRevisionAtClaim+1)){throw 'Claimed execution revision is stale.'}
    if($null -ne $Result){foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','RunId','ClaimId'){if($Result.PSObject.Properties.Name -contains $n -and [string]$Result.$n -cne [string]$r.$n){throw "Result identity mismatch: $n"}}}
    if($DryRun){return [pscustomobject]@{Stage='claimed';ProcessStarted=$false;NativeProcessId=$null;TaskRevision=$task.revision}}
    $requestId=[guid]::NewGuid().ToString('N');$runtimeRoot=[IO.Path]::GetFullPath([string]$r.DisposableRuntimeRoot);$runsRoot=([IO.Path]::GetFullPath((Get-MayaQaRuntimeRoot))).TrimEnd('\')+'\';if(!$runtimeRoot.StartsWith($runsRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Canonical disposable runtime root is outside the approved QA runtime root.'};if(!(Test-Path -LiteralPath $runtimeRoot -PathType Container)){throw 'Canonical disposable runtime root is missing.'};$request=Join-Path $runtimeRoot ('maya-tara-'+$r.RunId+'.request.json');if($r.QaWorkflowId -cne 'create-plan-views-v1'){throw 'Canonical native startup contract is not supported for the selected QA workflow.'};if($r.PSObject.Properties.Name -notcontains 'ValidatedRunnerManifestPath' -or $r.PSObject.Properties.Name -notcontains 'ValidatedRunnerManifestSha256'){throw 'Validated deployed runner-manifest evidence is missing.'};$validatedManifest=[IO.Path]::GetFullPath([string]$r.ValidatedRunnerManifestPath);$validatedManifestHash=[string]$r.ValidatedRunnerManifestSha256;$profileRoot=[IO.Path]::GetFullPath('C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025');$manifestAllowed=if($ManifestValidationBoundary){& $ManifestValidationBoundary $validatedManifest $validatedManifestHash}else{$validatedManifest.StartsWith($profileRoot.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)};if(!$manifestAllowed -or !(Test-Path -LiteralPath $validatedManifest -PathType Leaf) -or $validatedManifestHash -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash -LiteralPath $validatedManifest -Algorithm SHA256).Hash -ine $validatedManifestHash -or $validatedManifestHash -ine [string]$r.RunnerManifestSha256){throw 'Validated deployed runner-manifest path or hash is invalid.'};$prep=$r.FixturePreparationEvidence;if(!$prep){throw 'Canonical Create Plan Views launch requires correlated fixture-preparation evidence.'};$requestObject=[ordered]@{schemaVersion=2;operation='launch-revit-qa';requestId=$requestId;taskId=$r.TaskId;workflowId=$r.WorkflowId;qaWorkflowId=$r.QaWorkflowId;testId=$r.TestId;handoffId=$r.HandoffId;attemptId=$r.AttemptId;runId=$r.RunId;claimId=$r.ClaimId;requestPath=$request;requestSha256=('0'*64);modelPath=$r.DisposableModelPath;modelSha256=$r.DisposableModelSha256;fixtureSha256=$r.AuthoritativeFixtureSha256;fixturePreparationRequestPath=$prep.RequestPath;fixturePreparationRequestSha256=$prep.RequestSha256;fixturePreparationResultPath=$prep.ResultPath;fixturePreparationResultSha256=$prep.ResultSha256;fixturePreparationAttemptId=$prep.AttemptId;fixturePreparationRunId=$prep.RunId;manifestPath=$validatedManifest;manifestSha256=$validatedManifestHash;expiresUtc=$task.mayaTaraAttempt.RequestExpiresUtc};Add-CpvNativeCompanionRequestBinding -Request $requestObject -Preparation $prep;$canonicalJson=ConvertTo-MayaQaCanonicalRequestJson $requestObject;[IO.File]::WriteAllText($request,$canonicalJson,[Text.UTF8Encoding]::new($false));$requestObject['requestSha256']=Get-MayaQaCanonicalRequestSha256 -Request $requestObject
    $null=Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'claimed' -or $x.ClaimId -cne $ClaimId -or [long]$t.revision -ne ([long]$x.TaskRevisionAtClaim+1)){throw 'Launch transition compare-and-swap failed.'};$x.Stage='launching';$x.ExecutionStatus='Launching';$x.LaunchingUtc=Get-RepatoUtc;$x.RequestPath=$request;$x|Add-Member NoteProperty NativeRequestId $requestId -Force;Add-RepatoHistory $t 'maya-tara-native-launching' 'Tara' "claim=$ClaimId; request=$requestId";$x}
    $finalJson=$requestObject|ConvertTo-Json -Compress -Depth 20;[IO.File]::WriteAllText($request,$finalJson,[Text.UTF8Encoding]::new($false))
    try{$started=Invoke-MayaQaProcessLauncher $Executable $Arguments $ProcessLauncher $null $requestObject}catch{$failure=$_.Exception.Message;Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'launching' -or $x.NativeRequestId -cne $requestId -or $x.RequestPath -cne $request){throw 'Ambiguous launch failure compare-and-swap failed.'};$x.Stage='launch-outcome-unknown';$x.ExecutionStatus='LaunchOutcomeUnknown';$x.FailureCode='native-launch-outcome-unknown';$x.FailureDetails=$failure;$x.FailedUtc=Get-RepatoUtc;$x.SideEffectsPerformed=$true;Add-RepatoHistory $t 'maya-tara-native-launch-outcome-unknown' 'Tara' $x.FailureDetails;$x};throw}
    $transition=Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'launching' -or $x.NativeProcessId){throw 'Duplicate native launch rejected.'};$x.NativeProcessId=[int]$started.Pid;$x.LaunchedUtc=$started.StartedUtc;$x.ExecutingUtc=$started.StartedUtc;$x.Stage='executing';$x.ExecutionStatus='Executing';Add-RepatoHistory $t 'maya-tara-native-executing' 'Tara' "pid=$($started.Pid)";$x}
    $currentResult=Read-RepatoTaskStore $StoreRoot;$currentTask=Find-RepatoTask $currentResult $TaskId;$x=$currentTask.mayaTaraExecution
    if($null -eq $Result){return [pscustomobject]@{Stage=$x.Stage;ExecutionStatus=$x.ExecutionStatus;NativeProcessId=$x.NativeProcessId;RequestPath=$x.RequestPath;RequestId=$x.RequestPath;ProcessStarted=$true;ResultAccepted=$false;Completed=$false}}
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','RunId','ClaimId'){if($Result.PSObject.Properties.Name -notcontains $n -or [string]$Result.$n -cne [string]$x.$n){Invoke-MayaQaRevitGracefulShutdownCore -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId ([string]$x.WorkflowId) -FailureOutcomeReported | Out-Null;throw "Result identity mismatch: $n"}}
    if(!$Result.EvidenceAccepted){Invoke-MayaQaRevitGracefulShutdownCore -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId ([string]$x.WorkflowId) -FailureOutcomeReported | Out-Null;throw 'Native evidence was not accepted.'};Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'executing'){throw 'Evidence transition out of order.'};$x.Stage='evidence-collected';$x.ExecutionStatus='EvidenceCollected';$x.ResultPath=$Result.ResultPath;$x.ReportPath=$Result.ReportPath;$x.EvidencePath=$Result.EvidencePath;Add-RepatoHistory $t 'maya-tara-evidence-collected' 'Tara' 'correlated evidence accepted';$x}
    if(!$Result.RollbackProven){Invoke-MayaQaRevitGracefulShutdownCore -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId ([string]$x.WorkflowId) -FailureOutcomeReported | Out-Null;throw 'Rollback proof is required.'};Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'evidence-collected'){throw 'Rollback transition out of order.'};$x.Stage='rollback-verified';$x.ExecutionStatus='RollbackVerified';$x.RollbackStatus='Verified';$x.RollbackVerifiedUtc=Get-RepatoUtc;Add-RepatoHistory $t 'maya-tara-rollback-verified' 'Tara' 'rollback evidence accepted';$x}
    if(!$Result.Verified){Invoke-MayaQaRevitGracefulShutdownCore -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId ([string]$x.WorkflowId) -FailureOutcomeReported | Out-Null;throw 'QA verification failed.'};Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'rollback-verified'){throw 'Verification transition out of order.'};$x.Stage='verified';$x.ExecutionStatus='Verified';$x.VerificationStatus='Verified';$x.VerifiedUtc=Get-RepatoUtc;Add-RepatoHistory $t 'maya-tara-verified' 'Tara' 'QA verification accepted';$x}
    Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'verified'){throw 'Completion transition out of order.'};$x.Stage='completed';$x.ExecutionStatus='Completed';$x.CompletionStatus='Completed';$x.CompletedUtc=Get-RepatoUtc;Add-RepatoHistory $t 'maya-tara-completed' 'Tara' 'canonical execution completed';$x}
    if(!$DryRun){Invoke-MayaQaRevitGracefulShutdownCore -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId ([string]$x.WorkflowId) | Out-Null}
}
function Prepare-MayaQaCanonicalNativeLaunch {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$ClaimId,[Parameter(Mandatory)][string]$ReportDirectory,[string]$RevitInstallDir='E:\revit\Revit 2025',[Parameter(Mandatory)][string]$QaAddinRoot,[ValidateRange(1,86400)][int]$TimeoutSeconds=7200,[switch]$DryRun,[scriptblock]$SessionValidationInvoker,[scriptblock]$PlanPreflightInvoker)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    if(!$task -or $task.PSObject.Properties.Name -notcontains 'mayaTaraExecution'){throw 'Canonical Maya Tara execution is missing.'}
    $r=$task.mayaTaraExecution;$attempt=$task.mayaTaraAttempt
    if($r.Stage -cne 'claimed' -or $r.ExecutionStatus -cne 'Claimed' -or $r.ClaimStatus -cne 'claimed'){throw 'Canonical execution is not claimed.'}
    if($r.ClaimOwner -cne 'Tara' -or $r.ClaimId -cne $ClaimId){throw 'Canonical Tara claim identity mismatch.'}
    if(!$attempt -or $attempt.AttemptId -cne $r.AttemptId -or $attempt.RunId -cne $r.RunId){throw 'Canonical attempt/run is not current.'}
    if([DateTimeOffset]::Parse($attempt.RequestExpiresUtc) -le [DateTimeOffset]::UtcNow){throw 'Canonical Maya Tara attempt is expired.'}
    if([long]$task.revision -ne ([long]$r.TaskRevisionAtClaim+1)){throw 'Claimed execution revision is stale.'}
    if($r.NativeProcessId -or $r.SideEffectsPerformed){throw 'Canonical execution already has native side effects.'}
    foreach($n in 'ArtifactPath','RunnerManifestPath','AuthoritativeFixturePath','DisposableModelPath','IsolationPolicyPath'){$p=[string]$r.$n;if([string]::IsNullOrWhiteSpace($p)){throw "Canonical execution is missing $n."}}
    foreach($pair in @(@('ArtifactPath','ArtifactSha256'),@('RunnerManifestPath','RunnerManifestSha256'),@('AuthoritativeFixturePath','AuthoritativeFixtureSha256'),@('DisposableModelPath','DisposableModelSha256'),@('IsolationPolicyPath','IsolationPolicySha256'))){$p=[string]$r.($pair[0]);$expected=[string]$r.($pair[1]);if(!(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ine $expected){throw "Canonical $($pair[0]) hash validation failed."}}
    if(!$r.IsolationAllowed){throw 'Canonical isolation policy is not allowed.'}
    Import-Module (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -WarningAction SilentlyContinue
    $qaRoot=Get-MayaQaRoot;$def=Get-MayaQaWorkflowDefinition $r.QaWorkflowId
    $context=[pscustomobject]@{QaRoot=$qaRoot;SourceFixturePath=$r.AuthoritativeFixturePath;FixtureId=$def.FixtureId;FixtureSha256=$r.AuthoritativeFixtureSha256;ModelSha256=$r.DisposableModelSha256;FixturePreparationEvidence=$r.FixturePreparationEvidence;TestId=$r.TestId;ArtifactPath=$r.ArtifactPath;ArtifactSha256=$r.ArtifactSha256;ManifestPath=$r.RunnerManifestPath;ManifestSha256=$r.RunnerManifestSha256;TaskId=$r.TaskId;WorkflowId=$r.WorkflowId;QaWorkflowId=$r.QaWorkflowId;HandoffId=$r.HandoffId;AttemptId=$r.AttemptId;RunId=$r.RunId;ClaimId=$r.ClaimId}
    $plan=if($PlanPreflightInvoker){& $PlanPreflightInvoker $StoreRoot $r $ReportDirectory $RevitInstallDir $QaAddinRoot $TimeoutSeconds $context $DryRun}else{New-TaraRevitQaPlan -StoreRoot $StoreRoot -TaskId $r.TaskId -WorkflowId $r.WorkflowId -QaWorkflowId $r.QaWorkflowId -RunId $r.RunId -ModelPath $r.DisposableModelPath -SidecarPath ($r.DisposableModelPath+'.fixture.json') -ReportDirectory $ReportDirectory -RevitInstallDir $RevitInstallDir -QaAddinRoot $QaAddinRoot -TimeoutSeconds $TimeoutSeconds -Context $context -DryRun -SessionValidationInvoker $SessionValidationInvoker}
    $request=[ordered]@{requestId=$plan.RequestId;claimId=$r.ClaimId;testId=$r.TestId;modelPath=$r.DisposableModelPath;TaskId=$r.TaskId;WorkflowId=$r.WorkflowId;QaWorkflowId=$r.QaWorkflowId;HandoffId=$r.HandoffId;AttemptId=$r.AttemptId;RunId=$r.RunId;createdUtc=(Get-RepatoUtc);expiresUtc=$attempt.RequestExpiresUtc;selectedManifestPath=$plan.QaRunnerManifestPath;selectedManifestSha256=$plan.QaRunnerManifestSha256;addinIsolation=$plan.Isolation;fixtureSha256=$r.AuthoritativeFixtureSha256;fixturePreparationRequestPath=$r.FixturePreparationEvidence.RequestPath;fixturePreparationRequestSha256=$r.FixturePreparationEvidence.RequestSha256;fixturePreparationResultPath=$r.FixturePreparationEvidence.ResultPath;fixturePreparationResultSha256=$r.FixturePreparationEvidence.ResultSha256;fixturePreparationAttemptId=$r.FixturePreparationEvidence.AttemptId;fixturePreparationRunId=$r.FixturePreparationEvidence.RunId}
    Add-CpvNativeCompanionRequestBinding -Request $request -Preparation $r.FixturePreparationEvidence
    if($DryRun){return [pscustomobject]@{Mode='DryRun';Stage='claimed';ReadyToLaunch=$true;ProcessStarted=$false;SideEffectsPerformed=$false;TaskId=$r.TaskId;WorkflowId=$r.WorkflowId;QaWorkflowId=$r.QaWorkflowId;HandoffId=$r.HandoffId;AttemptId=$r.AttemptId;RunId=$r.RunId;ClaimId=$r.ClaimId;Request=$request;Plan=$plan}}
    Write-TaraJsonNew $plan.RequestPath ([pscustomobject]$request)
    $started=Get-RepatoUtc
    try{Invoke-RepatoStoreMutation $StoreRoot {param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;if($x.Stage -cne 'claimed' -or $x.ClaimId -cne $ClaimId -or [long]$t.revision -ne ([long]$x.TaskRevisionAtClaim+1) -or $x.NativeProcessId -or $x.SideEffectsPerformed){throw 'Canonical launch compare-and-swap failed.'};$x.Stage='launching';$x.ExecutionStatus='Launching';$x.LaunchingUtc=$started;$x.RequestPath=$plan.RequestPath;$x|Add-Member NoteProperty NativeRequestId $plan.RequestId -Force;Add-RepatoHistory $t 'maya-tara-native-launching' 'Tara' "claim=$ClaimId; request=$($plan.RequestId)";$x}}catch{if(Test-Path -LiteralPath $plan.RequestPath -PathType Leaf){Remove-Item -LiteralPath $plan.RequestPath -Force -ErrorAction SilentlyContinue};throw}
    [pscustomobject]@{Mode='Prepared';Stage='launching';ProcessStarted=$false;SideEffectsPerformed=$true;RequestPath=$plan.RequestPath;Request=$request;Plan=$plan}
}
function Prepare-MayaQaCanonicalLaunchPhase {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$ClaimId)
    $data=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $data $TaskId;$r=$t.mayaTaraExecution
    if(!$r -or $r.Stage -cne 'claimed' -or $r.ExecutionStatus -cne 'Claimed' -or $r.ClaimStatus -cne 'claimed'){throw 'Canonical execution is not claimed.'}
    if($r.ClaimOwner -cne 'Tara' -or $r.ClaimId -cne $ClaimId){throw 'Canonical claim identity mismatch.'}
    if(!$t.mayaTaraAttempt -or $t.mayaTaraAttempt.AttemptId -cne $r.AttemptId -or $t.mayaTaraAttempt.RunId -cne $r.RunId){throw 'Canonical attempt/run is not current.'}
    if([DateTimeOffset]::Parse($t.mayaTaraAttempt.RequestExpiresUtc)-le [DateTimeOffset]::UtcNow){throw 'Attempt expired before native launch.'}
    if([long]$t.revision -ne ([long]$r.TaskRevisionAtClaim+1)){throw 'Claimed execution revision is stale.'}
    [pscustomobject]@{Stage='claimed';TaskId=$r.TaskId;WorkflowId=$r.WorkflowId;QaWorkflowId=$r.QaWorkflowId;TestId=$r.TestId;HandoffId=$r.HandoffId;AttemptId=$r.AttemptId;RunId=$r.RunId;ClaimId=$r.ClaimId;ResultRequired=$false;ProcessStarted=$false}
}
function Start-MayaQaCanonicalProcessPhase {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$ClaimId,[Parameter(Mandatory)][string]$Executable,[string]$Arguments,[scriptblock]$ProcessLauncher)
    $null=Prepare-MayaQaCanonicalLaunchPhase $StoreRoot $TaskId $ClaimId
    Invoke-MayaQaCanonicalNativeCore -StoreRoot $StoreRoot -TaskId $TaskId -ClaimId $ClaimId -Executable $Executable -Arguments $Arguments -ProcessLauncher $ProcessLauncher
}
function Accept-MayaQaCanonicalEvidencePhase { param([Parameter(Mandatory)]$Result) if(!$Result.EvidenceAccepted){throw 'Native evidence was not accepted.'};$Result }
function Verify-MayaQaCanonicalRollbackPhase { param([Parameter(Mandatory)]$Result) if(!$Result.RollbackProven){throw 'Rollback proof is required.'};$Result }
function Verify-MayaQaCanonicalExecutionPhase { param([Parameter(Mandatory)]$Result) if(!$Result.Verified){throw 'QA verification failed.'};$Result }
function Wait-MayaQaCanonicalResultPhase {
    param([Parameter(Mandatory)][object]$Launch,[Parameter(Mandatory)][object]$Identity,[Parameter(Mandatory)][scriptblock]$ResultProvider)
    if(!$Launch.NativeProcessId -or !$Launch.RequestId){throw 'Native launch has no process or request identity.'}
    $result=& $ResultProvider $Launch
    if(!$result){throw 'Native result was not produced.'}
    foreach($n in 'RequestId','TaskId','WorkflowId','QaWorkflowId','AttemptId','RunId','ClaimId'){
        if($result.PSObject.Properties.Name -notcontains $n -or [string]$result.$n -cne [string]$Identity.$n){throw "Native result identity mismatch: $n"}
    }
    if($result.PSObject.Properties.Name -contains 'ExpiresUtc' -and [DateTimeOffset]::Parse($result.ExpiresUtc) -lt [DateTimeOffset]::UtcNow){throw 'Native result is expired.'}
    $result
}
function Complete-MayaQaCanonicalExecutionPhase {
    param([Parameter(Mandatory)][object]$Result)
    $e=Accept-MayaQaCanonicalEvidencePhase $Result;$r=Verify-MayaQaCanonicalRollbackPhase $e;$v=Verify-MayaQaCanonicalExecutionPhase $r
    if(!$v){throw 'Canonical execution verification did not pass.'}
    [pscustomobject]@{Result=$v;Completed=$true;CleanupAllowed=$true}
}
function Invoke-MayaQaIntake {
    param([Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$UserRequest,[switch]$DryRun)
    if ($TaskId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$') { throw 'Invalid task identity.' }
    if ($WorkflowId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$') { throw 'Invalid workflow identity.' }
    $resolved = Resolve-MayaQaRequestWorkflow $UserRequest
    $canonical = Resolve-MayaQaWorkflowId $QaWorkflowId
    if($resolved -cne $canonical){ throw "User request resolves to '$resolved', not '$canonical'." }
    $QaWorkflowId = $canonical
    $def = Get-MayaQaWorkflowDefinition $QaWorkflowId
    $intent = Get-MayaQaRequestIntent $UserRequest
    if ([string]::IsNullOrWhiteSpace($UserRequest)) { throw 'User request is required.' }
    [pscustomobject]@{
        TaskId = $TaskId
        WorkflowId = $WorkflowId
        OriginalUserRequest = $UserRequest
        RequestIntent = $intent
        QaWorkflowId = $QaWorkflowId
        FixtureId = $def.FixtureId
        NativeTestId = Get-MayaQaNativeTestId $def
        PreparationScript = $def.Prep
        RequiredApprovalStage = 'Maya approval after Tara QA passed'
        NextAllowedOperation = 'qa-run-plan'
        SideEffectsPerformed = $false
        DryRun = [bool]$DryRun
    }
}function New-MayaQaBuildRequest {
    param(
        [Parameter(Mandatory)]
        [string]$StoreRoot,

        [Parameter(Mandatory)]
        [string]$TaskId,

        [Parameter(Mandatory)]
        [string]$WorkflowId,

        [Parameter(Mandatory)]
        [string]$QaWorkflowId,

        [string]$UserRequest = '',

        [string]$SourceBranch = 'current',

        [string]$ProjectPath = 'Forma.RevitConnector.csproj',
        [object]$AuthenticatedBuildSource,

        [switch]$DryRun
    )

    if ([string]::IsNullOrWhiteSpace($SourceBranch)) {
        $SourceBranch = 'current'
    }

    if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
        $ProjectPath = 'Forma.RevitConnector.csproj'
    }
    if ($AuthenticatedBuildSource) { $null = Resolve-MayaQaAuthenticatedBuildSource $AuthenticatedBuildSource }

    if ([string]::IsNullOrWhiteSpace($UserRequest)) {
        $UserRequest = "Please run QA workflow $QaWorkflowId"
    }

    $null = Invoke-MayaQaIntake `
        $TaskId `
        $WorkflowId `
        $QaWorkflowId `
        $UserRequest `
        -DryRun:$true
    $QaWorkflowId = Resolve-MayaQaWorkflowId $QaWorkflowId
    $requestIntent = Get-MayaQaRequestIntent $UserRequest

    $requestId = 'build-' + [guid]::NewGuid().ToString('N')
    $requestedArtifact = 'bin\Release\net8.0-windows\Repato.Revit.dll'

    if ($DryRun) {
        return [pscustomobject]@{
            BuildRequestId = $requestId
            TaskId = $TaskId
            WorkflowId = $WorkflowId
            QaWorkflowId = $QaWorkflowId
            BuildStatus = 'requested'
            SourceBranch = $SourceBranch
            ProjectPath = $ProjectPath
            RequestedArtifact = $requestedArtifact
            SideEffectsPerformed = $false
        }
    }

    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId

    if ($workflow.PSObject.Properties.Name -contains 'qaWorkflowId' -and
        $workflow.qaWorkflowId -cne $QaWorkflowId) {
        throw 'Valid QA intake record is missing.'
    }

    if ($workflow.PSObject.Properties.Name -contains 'qaBuildRequestId' -and
        $workflow.qaBuildRequestId) {
        throw 'Build request already exists.'
    }

    $data = Read-RepatoTaskStore $StoreRoot
    $task = Find-RepatoTask $data $TaskId

    $mutation = @(Invoke-RepatoWorkflowMutation `
        $StoreRoot `
        $TaskId `
        $WorkflowId `
        $workflow.workflowRevision `
        $task.revision {

        param($current)

        $current | Add-Member `
            -NotePropertyName qaWorkflowId `
            -NotePropertyValue $QaWorkflowId `
            -Force

        $current | Add-Member `
            -NotePropertyName qaBuildRequestId `
            -NotePropertyValue $requestId `
            -Force

        $current | Add-Member `
            -NotePropertyName qaBuildRequest `
            -NotePropertyValue ([pscustomobject]@{
                BuildRequestId = $requestId
                SourceBranch = $SourceBranch
                ProjectPath = $ProjectPath
                AuthenticatedBuildSource = $AuthenticatedBuildSource
                RequestedArtifact = $requestedArtifact
                BuildStatus = 'requested'
                RequestedUtc = (Get-Date).ToUniversalTime().ToString('O')
            }) `
            -Force
        $current | Add-Member -NotePropertyName qaRequestIntent -NotePropertyValue $requestIntent -Force

        return $current
    })[-1]

    [pscustomobject]@{
        BuildRequestId = $requestId
        TaskId = $TaskId
        WorkflowId = $WorkflowId
        QaWorkflowId = $QaWorkflowId
        BuildStatus = 'requested'
        SourceBranch = $SourceBranch
        ProjectPath = $ProjectPath
        AuthenticatedBuildSource = $AuthenticatedBuildSource
        RequestedArtifact = $requestedArtifact
        WorkflowRevision = $mutation.Workflow.workflowRevision
        TaskRevision = $mutation.TaskRevision
        SideEffectsPerformed = $true
    }
}
function New-MayaQaCandidateReplacementBuildRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [object]$AuthenticatedBuildSource,
        [string]$SourceBranch='current',
        [string]$ProjectPath='Forma.RevitConnector.csproj',
        [string]$Reason='Scoped Create Plan Views fixture-preparation runner change',
        [switch]$PreserveRecoveredPreparation,
        [long]$ExpectedTaskRevision=0,
        [switch]$DryRun
    )
    $QaWorkflowId=Resolve-MayaQaWorkflowId $QaWorkflowId
    $source=Resolve-MayaQaAuthenticatedBuildSource $AuthenticatedBuildSource
    $commit=Get-MayaQaTrustedBuildSourceCommit -RepositoryRoot $source.RepositoryRoot -ProjectPath $source.ProjectPath
    if($source.ExpectedSourceCommit -and $commit -ine $source.ExpectedSourceCommit){throw 'Authenticated replacement source commit mismatch.'}
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $activeAttempt=($task.PSObject.Properties.Name -contains 'mayaTaraAttempt') -and [bool]$task.mayaTaraAttempt
    $activeExecution=($task.PSObject.Properties.Name -contains 'mayaTaraExecution') -and [bool]$task.mayaTaraExecution
    $retirement=if($task.PSObject.Properties['mayaQaCandidateReplacementRetirement']){$task.mayaQaCandidateReplacementRetirement}else{$null}
    $recoveredBinding=$null
    if($PreserveRecoveredPreparation){
        if($ExpectedTaskRevision -lt 1 -or [long]$task.revision -ne $ExpectedTaskRevision -or $task.status -cne 'in-progress' -or $task.workflowStage -cne 'qa' -or $QaWorkflowId -cne 'create-plan-views-v1' -or $activeAttempt -or $activeExecution){throw 'Recovered candidate replacement requires exact QA-ready revision and no native attempt.'}
        if(Test-MayaQaHasActiveCanonicalExecutionApproval -Approvals @($task.approvalRequests)){throw 'Active native authorization prevents recovered candidate replacement.'}
        foreach($name in 'mayaTaraQaPacket','mayaTaraExecutionEvidence'){if($task.PSObject.Properties[$name] -and $task.$name){throw 'Recovered candidate replacement found existing native state.'}}
        $recoveredBinding=New-CpvNativeContinuationBinding -Task $task -Workflow $workflow -ExpectedTaskRevision $ExpectedTaskRevision
    }
    $retirementReady=$false
    if($retirement -and $retirement.PSObject.Properties['RecoveredAttemptId'] -and
        $retirement.PSObject.Properties['RecoveredRunId'] -and $retirement.PSObject.Properties['ConsumedApprovalPreserved'] -and
        $retirement.PSObject.Properties['NativeLaunchAbsent']) {
        $retirementReady=($retirement.WorkflowId -ceq $WorkflowId -and $retirement.FailedAttemptId -and
            $retirement.RecoveredAttemptId -and $retirement.RecoveredRunId -and
            $retirement.ConsumedApprovalPreserved -eq $true -and $retirement.NativeLaunchAbsent -eq $true -and
            $task.status -ceq 'in-progress' -and $task.workflowStage -ceq 'build-checks')
    }
    if($retirement -and $retirement.ReconciledNativeFailure -eq $true -and $retirement.WorkflowId -ceq $WorkflowId -and
        $retirement.FailedAttemptId -and $retirement.FailedRunId -and $retirement.FailedClaimId -and
        $retirement.HistoricalApprovalDisposition -ceq 'expired-unconsumed' -and
        $retirement.ReplacementNativeLaunchAbsent -eq $true -and $task.status -ceq 'in-progress' -and
        $task.workflowStage -ceq 'build-checks') {
        $historicalApproval=@($task.approvalRequests|Where-Object {$_.requestId -ceq $retirement.HistoricalApprovalRequestId -and $_.action -ceq 'qa-run'})
        if($historicalApproval.Count -ne 1 -or $historicalApproval[0].status -cne 'approved' -or
            $historicalApproval[0].consumedUtc -or (Get-MayaQaCanonicalObjectSha256 $historicalApproval[0]) -ine $retirement.HistoricalApprovalSha256) {
            throw 'Reconciled failure retirement no longer preserves the exact expired, unconsumed approval record.'
        }
        $retirementReady=$true
    }
    $legacyPassedReady=($task.status -ceq 'passed' -and $task.workflowStage -ceq 'approval')
    if($workflow.qaWorkflowId -cne $QaWorkflowId -or (!$legacyPassedReady -and !$retirementReady -and !$recoveredBinding) -or $activeAttempt -or $activeExecution){throw 'Candidate replacement build requires a supported approval, retirement, or verified recovered-preparation state, with no active attempt or execution.'}
    if(@(Get-Process -Name Revit -ErrorAction SilentlyContinue).Count){throw 'Revit is running; candidate replacement build request is blocked.'}
    if($workflow.qaBuildStatus -cne 'succeeded' -or !$workflow.qaBuildEvidence -or !$workflow.qaBuildRequest){throw 'Existing authenticated candidate evidence is required before replacement.'}
    if($workflow.qaBuildRequest.PSObject.Properties.Name -contains 'ReplacementSourceCommit' -and $workflow.qaBuildRequest.ReplacementSourceCommit -ceq $commit -and $workflow.qaBuildStatus -eq 'requested'){
        return [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;SourceCommit=$commit;BuildStatus='requested';Reused=$true;SideEffectsPerformed=$false}
    }
    $requestId='build-'+[guid]::NewGuid().ToString('N')
    $replacement=[pscustomobject][ordered]@{BuildRequestId=$requestId;SourceBranch=$SourceBranch;ProjectPath=$ProjectPath;AuthenticatedBuildSource=$AuthenticatedBuildSource;RequestedArtifact='bin\Release\net8.0-windows\Repato.Revit.dll';BuildStatus='requested';RequestedUtc=(Get-Date).ToUniversalTime().ToString('O');ReplacementSourceCommit=$commit;ReplacementReason=$Reason}
    if($DryRun){return [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;BuildRequestId=$requestId;SourceCommit=$commit;BuildStatus='planned';SideEffectsPerformed=$false}}
    $prior=[pscustomobject][ordered]@{BuildRequest=$workflow.qaBuildRequest;BuildEvidence=$workflow.qaBuildEvidence;SupersededByBuildRequestId=$requestId;SupersededUtc=(Get-Date).ToUniversalTime().ToString('O');Reason=$Reason}
    $mutation=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {
        param($current)
        if($current.qaBuildRequest.BuildRequestId -cne $workflow.qaBuildRequest.BuildRequestId -or $current.qaBuildEvidence.ArtifactSha256 -ine $workflow.qaBuildEvidence.ArtifactSha256 -or $current.qaBuildStatus -cne 'succeeded'){throw 'Candidate replacement compare-and-swap failed.'}
        if($recoveredBinding){Assert-CpvNativeContinuationBinding -Task $task -Workflow $current -Binding $recoveredBinding}
        if($current.PSObject.Properties.Name -notcontains 'qaBuildHistory'){$current|Add-Member NoteProperty qaBuildHistory ([object[]]@()) -Force}
        $current.qaBuildHistory=[object[]]@($current.qaBuildHistory)+$prior
        $current.qaBuildRequestId=$requestId
        $current.qaBuildRequest=$replacement
        $current.qaBuildStatus='requested'
        $current.qaBuildEvidence=$null
        return $current
    })[-1]
    [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;BuildRequestId=$requestId;PreviousBuildRequestId=$prior.BuildRequest.BuildRequestId;SourceCommit=$commit;WorkflowRevision=$mutation.Workflow.workflowRevision;TaskRevision=$mutation.TaskRevision;PriorCandidateEvidencePreserved=$true;BuildStatus='requested';SideEffectsPerformed=$true}
}

function Get-MayaQaCanonicalObjectSha256 {
    param([Parameter(Mandatory)][object]$Value)
    $json=ConvertTo-Json -InputObject $Value -Depth 50 -Compress
    $sha=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Recover-MayaQaReconciledDuplicateFloorPlanFailureForCandidateReplacement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][ValidateRange(1,[long]::MaxValue)][long]$ExpectedTaskRevision,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$FailedAttemptId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$FailedRunId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$FailedClaimId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$NativeRequestId,
        [Parameter(Mandatory)][string]$ApprovalRequestId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedResultSha256,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedReportSha256,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedModelSha256,
        [switch]$DryRun
    )

    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    if([long]$task.revision -ne $ExpectedTaskRevision){throw 'Duplicate FloorPlan failure recovery task revision is stale.'}
    $retirement=if($task.PSObject.Properties['mayaQaCandidateReplacementRetirement']){$task.mayaQaCandidateReplacementRetirement}else{$null}
    if($task.status -ceq 'in-progress' -and $task.workflowStage -ceq 'build-checks' -and
        $retirement -and $retirement.ReconciledNativeFailure -eq $true -and
        $retirement.FailedAttemptId -ceq $FailedAttemptId -and $retirement.FailedRunId -ceq $FailedRunId -and
        $retirement.FailedClaimId -ceq $FailedClaimId -and $retirement.NativeRequestId -ceq $NativeRequestId -and
        $retirement.HistoricalApprovalRequestId -ceq $ApprovalRequestId -and
        $retirement.ResultSha256 -ieq $ExpectedResultSha256 -and
        $retirement.ReportSha256 -ieq $ExpectedReportSha256 -and
        $retirement.ModelSha256 -ieq $ExpectedModelSha256) {
        return [pscustomobject]@{Status='AlreadyRecovered';TaskId=$TaskId;FailedAttemptId=$FailedAttemptId;FailedRunId=$FailedRunId;HistoricalApprovalDisposition='expired-unconsumed';FailedEvidencePreserved=$true;NativeLaunchPerformed=$false;SideEffectsPerformed=$false}
    }

    $execution=$task.mayaTaraExecution
    $attempt=$task.mayaTaraAttempt
    if($task.status -cne 'blocked' -or $task.workflowStage -cne 'qa' -or !$execution -or !$attempt -or
        $execution.TaskId -cne $TaskId -or $execution.WorkflowId -cne $WorkflowId -or
        $execution.QaWorkflowId -cne 'create-plan-views-v1' -or $execution.TestId -cne 'create-plan-views-v1' -or
        $execution.Stage -cne 'qa-failed' -or $execution.ExecutionStatus -cne 'QaFailed' -or
        $execution.FailureCode -cne 'duplicate-floor-plan-view-family-type' -or
        $execution.AttemptId -cne $FailedAttemptId -or $execution.RunId -cne $FailedRunId -or
        $attempt.AttemptId -cne $FailedAttemptId -or $attempt.RunId -cne $FailedRunId -or
        $execution.FailedClaimId -cne $FailedClaimId -or $execution.NativeRequestId -cne $NativeRequestId -or
        $execution.ClaimId -or $execution.ClaimOwner -or $execution.ClaimStatus -cne 'released' -or
        $execution.TransactionStatus -cne 'NotStarted' -or $execution.RollbackStatus -cne 'NotRequired' -or
        $execution.VerificationStatus -cne 'Failed' -or $execution.CompletionStatus -cne 'Failed' -or
        $execution.SideEffectsPerformed -ne $false) {
        throw 'Canonical task does not contain the exact terminal, released duplicate-FloorPlan failure.'
    }
    if($execution.ResultSha256 -ine $ExpectedResultSha256 -or $execution.ReportSha256 -ine $ExpectedReportSha256 -or
        $execution.DisposableModelSha256 -ine $ExpectedModelSha256 -or
        !$execution.RequestPath -or $execution.ResultPath -cne ($execution.RequestPath+'.result.json') -or
        $execution.ReceiptPath -cne $execution.ResultPath -or
        !$execution.ReportPath -or !$execution.DisposableModelPath) {
        throw 'Canonical failure evidence or model binding does not match the supplied identities.'
    }
    $cleanup=$execution.CleanupEvidence
    if($execution.CleanupStatus -cne 'Verified' -or !$cleanup -or
        $cleanup.TaskId -cne $TaskId -or $cleanup.AttemptId -cne $FailedAttemptId -or
        $cleanup.RunId -cne $FailedRunId -or $cleanup.ClaimId -cne $FailedClaimId -or
        $cleanup.NativeRequestId -cne $NativeRequestId -or $cleanup.NativeProcessId -ne $execution.NativeProcessId -or
        $cleanup.ProcessExitConfirmed -ne $true -or $cleanup.Forced -ne $false -or
        $cleanup.ModelUnlocked -ne $true -or $cleanup.RetryAuthorized -ne $false -or
        $cleanup.FailureClass -cne 'duplicate-floor-plan-view-family-type' -or
        $cleanup.TransactionStatus -cne 'NotStarted' -or $cleanup.RollbackStatus -cne 'NotRequired' -or
        $cleanup.ModelSha256 -ine $ExpectedModelSha256) {
        throw 'Verified graceful cleanup evidence is missing or does not match the failed execution.'
    }
    foreach($pair in @(
        @($execution.RequestPath,$cleanup.RequestPath,$cleanup.RequestSha256),
        @($execution.ResultPath,$cleanup.ReceiptPath,$cleanup.ReceiptSha256),
        @($execution.ReportPath,$cleanup.ReportPath,$cleanup.ReportSha256),
        @($execution.DisposableModelPath,$execution.DisposableModelPath,$ExpectedModelSha256),
        @($cleanup.JournalPath,$cleanup.JournalPath,$cleanup.JournalSha256)
    )) {
        if(!$pair[0] -or [IO.Path]::GetFullPath([string]$pair[0]) -ine [IO.Path]::GetFullPath([string]$pair[1]) -or
            !(Test-Path -LiteralPath $pair[0] -PathType Leaf) -or
            (Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ine [string]$pair[2]) {
            throw 'Failure request, result, report, model, or journal evidence hash validation failed.'
        }
    }
    if($cleanup.ReceiptSha256 -ine $ExpectedResultSha256 -or $cleanup.ReportSha256 -ine $ExpectedReportSha256 -or
        $cleanup.ExitVerification -cne 'terminal-journal-no-process-model-unlocked' -or
        @(Get-Process -Name Revit -ErrorAction SilentlyContinue).Count) {
        throw 'Failed execution cleanup is not terminal or Revit remains active.'
    }
    try {
        $request=Get-Content -LiteralPath $execution.RequestPath -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
        $receipt=Get-Content -LiteralPath $execution.ResultPath -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
        $report=Get-Content -LiteralPath $execution.ReportPath -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    } catch { throw "Original native failure evidence is malformed: $($_.Exception.Message)" }
    foreach($document in @($request,$receipt,$report)) {
        foreach($name in 'TaskId','WorkflowId','TestId','AttemptId','RunId','ClaimId') {
            $expected=if($name -ceq 'TestId'){$execution.TestId}elseif($name -ceq 'ClaimId'){$FailedClaimId}else{$execution.$name}
            if([string]$document.$name -cne [string]$expected){throw "Original failure evidence identity mismatch: $name"}
        }
        if([string]$document.RequestId -cne $NativeRequestId){throw 'Original failure evidence native request identity mismatch.'}
    }
    if($request.operation -cne 'launch-revit-qa' -or $request.expiresUtc -cne $attempt.RequestExpiresUtc -or
        [IO.Path]::GetFullPath([string]$request.modelPath) -ine [IO.Path]::GetFullPath([string]$execution.DisposableModelPath) -or
        $request.modelSha256 -ine $ExpectedModelSha256 -or
        $receipt.Status -cne 'Failed' -or $receipt.QaWorkflowId -cne 'create-plan-views-v1' -or
        [IO.Path]::GetFullPath([string]$receipt.ReportPath) -ine [IO.Path]::GetFullPath([string]$execution.ReportPath) -or
        $report.Status -cne 'Failed' -or $report.RollbackStatus -cne 'NotStarted' -or
        [IO.Path]::GetFullPath([string]$report.DocumentPath) -ine [IO.Path]::GetFullPath([string]$execution.DisposableModelPath) -or
        $report.AssemblyIdentity.Sha256 -ine $execution.ArtifactSha256 -or
        @($report.Errors).Count -ne 1 -or [string]$report.Errors[0] -notmatch 'Sequence contains more than one matching element' -or
        [string]$report.Errors[0] -notmatch 'CreatePlanViewsQaApplication\.Execute' -or
        @($report.Assertions|Where-Object {$_.Passed -ne $true}).Count -gt 0) {
        throw 'Original native report does not prove the exact duplicate-FloorPlan pre-transaction failure.'
    }
    foreach($pair in @(@($execution.AuthoritativeFixturePath,$execution.AuthoritativeFixtureSha256),
        @($execution.FixturePreparationEvidence.RequestPath,$execution.FixturePreparationEvidence.RequestSha256),
        @($execution.FixturePreparationEvidence.ResultPath,$execution.FixturePreparationEvidence.ResultSha256))) {
        if(!$pair[0] -or !$pair[1] -or !(Test-Path -LiteralPath $pair[0] -PathType Leaf) -or
            (Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ine [string]$pair[1]) {
            throw 'Original fixture or preparation provenance hash validation failed.'
        }
    }
    $approvals=@($task.approvalRequests|Where-Object {$_.requestId -ceq $ApprovalRequestId -and $_.action -ceq 'qa-run'})
    if($approvals.Count -ne 1){throw 'The exact historical QA approval record is missing or ambiguous.'}
    $approval=$approvals[0]
    $consumptionFields=@(@('consumedUtc','ConsumedAttemptId','ConsumedRunId','ConsumedNativeRequestId','ConsumptionEvidencePath'|Where-Object {
        $property=$approval.PSObject.Properties[$_];$property -and $property.Value
    }))
    if($approval.status -cne 'approved' -or $approval.requiredLevel -cne 'user' -or $approval.decidedBy -cne 'user' -or
        $consumptionFields.Count) {
        throw 'Historical approval is not the expected approved-but-unconsumed record.'
    }
    $approvalExpiry=[DateTimeOffset]::MinValue;$approvalDecision=[DateTimeOffset]::MinValue;$launchTime=[DateTimeOffset]::MinValue
    if(![DateTimeOffset]::TryParse([string]$approval.expiresUtc,[ref]$approvalExpiry) -or
        ![DateTimeOffset]::TryParse([string]$approval.decidedUtc,[ref]$approvalDecision)){
        throw 'Historical approval expiry or decision-time binding is invalid.'
    }
    try{$launchTime=Get-MayaQaNormalizedUtc -Value ([string]$execution.LaunchedUtc) -Context 'Historical native launch timestamp'}catch{throw 'Historical approval expiry or decision-time binding is invalid.'}
    if($approvalExpiry -gt [DateTimeOffset]::UtcNow -or $approvalDecision -gt $approvalExpiry -or $launchTime -gt $approvalExpiry) {
        throw 'Historical approval expiry or decision-time binding is invalid.'
    }
    $approvalBinding=if($approval.PSObject.Properties['executionBinding']){$approval.executionBinding}else{$approval.recoveryBinding}
    if(!$approvalBinding -or (Get-MayaQaCanonicalObjectSha256 $approvalBinding) -ine $approval.bindingHash) {
        throw 'Historical approval binding hash is invalid.'
    }
    $boundAttemptId=if($approvalBinding.PSObject.Properties['AttemptId']){$approvalBinding.AttemptId}elseif($approvalBinding.NativeContinuation){$approvalBinding.NativeContinuation.AttemptId}else{$null}
    $boundRunId=if($approvalBinding.PSObject.Properties['RunId']){$approvalBinding.RunId}elseif($approvalBinding.NativeContinuation){$approvalBinding.NativeContinuation.RunId}else{$null}
    if([string]$boundAttemptId -cne $FailedAttemptId -or [string]$boundRunId -cne $FailedRunId){throw 'Historical approval attempt/run binding mismatch.'}
    foreach($pair in @(@('TaskId',$TaskId),@('WorkflowId',$WorkflowId),@('CandidateSha256',$execution.ArtifactSha256),
        @('ModelPath',$execution.DisposableModelPath),@('ModelSha256',$ExpectedModelSha256))) {
        if([string]$approvalBinding.($pair[0]) -ine [string]$pair[1]){throw "Historical approval binding mismatch: $($pair[0])"}
    }
    $approvalHash=Get-MayaQaCanonicalObjectSha256 $approval
    if($task.PSObject.Properties['mayaTaraExecutionHistory'] -and @($task.mayaTaraExecutionHistory|Where-Object {$_.AttemptId -ceq $FailedAttemptId}).Count){throw 'Failed attempt is already archived without a matching recovery record.'}
    if($DryRun){return [pscustomobject]@{Status='DryRun';TaskId=$TaskId;FailedAttemptId=$FailedAttemptId;FailedRunId=$FailedRunId;HistoricalApprovalDisposition='expired-unconsumed';FailedEvidencePreserved=$true;ModelUnchanged=$true;RevitAbsent=$true;NativeLaunchPerformed=$false;SideEffectsPerformed=$false}}

    Invoke-RepatoStoreMutation $StoreRoot {
        param($current,$preview)
        $t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution
        $currentApproval=@($t.approvalRequests|Where-Object {$_.requestId -ceq $ApprovalRequestId})
        if([long]$t.revision -ne $ExpectedTaskRevision -or $t.status -cne 'blocked' -or $t.workflowStage -cne 'qa' -or
            !$x -or $x.AttemptId -cne $FailedAttemptId -or $x.RunId -cne $FailedRunId -or
            $x.FailedClaimId -cne $FailedClaimId -or $x.NativeRequestId -cne $NativeRequestId -or
            $x.ResultSha256 -ine $ExpectedResultSha256 -or $x.ReportSha256 -ine $ExpectedReportSha256 -or
            $x.DisposableModelSha256 -ine $ExpectedModelSha256 -or $currentApproval.Count -ne 1 -or
            (Get-MayaQaCanonicalObjectSha256 $currentApproval[0]) -ine $approvalHash) {
            throw 'Duplicate FloorPlan failure recovery compare-and-swap failed.'
        }
        $archive=[pscustomobject]$x
        $archive|Add-Member NoteProperty CandidateReplacementArchivedUtc (Get-RepatoUtc) -Force
        $archive|Add-Member NoteProperty HistoricalApprovalRequestId $ApprovalRequestId -Force
        $archive|Add-Member NoteProperty HistoricalApprovalDisposition 'expired-unconsumed' -Force
        if($t.PSObject.Properties.Name -notcontains 'mayaTaraExecutionHistory'){$t|Add-Member NoteProperty mayaTaraExecutionHistory ([object[]]@()) -Force}
        $t.mayaTaraExecutionHistory=[object[]]@($t.mayaTaraExecutionHistory)+$archive
        if($t.PSObject.Properties.Name -notcontains 'mayaTaraAttemptHistory'){$t|Add-Member NoteProperty mayaTaraAttemptHistory ([object[]]@()) -Force}
        $archivedAttempt=[pscustomobject]$t.mayaTaraAttempt
        $archivedAttempt|Add-Member NoteProperty CandidateReplacementArchivedUtc (Get-RepatoUtc) -Force
        $t.mayaTaraAttemptHistory=[object[]]@($t.mayaTaraAttemptHistory)+$archivedAttempt
        if($t.mayaTaraQaPacket){
            if($t.PSObject.Properties.Name -notcontains 'mayaTaraQaPacketHistory'){$t|Add-Member NoteProperty mayaTaraQaPacketHistory ([object[]]@()) -Force}
            $t.mayaTaraQaPacketHistory=[object[]]@($t.mayaTaraQaPacketHistory)+[pscustomobject]$t.mayaTaraQaPacket
        }
        $t.mayaTaraAttempt=$null;$t.mayaTaraExecution=$null;$t.mayaTaraQaPacket=$null
        if($t.PSObject.Properties.Name -contains 'mayaTaraExecutionEvidence'){$t.mayaTaraExecutionEvidence=$null}
        $replacementRetirement=[pscustomobject][ordered]@{
            WorkflowId=$WorkflowId;FailedAttemptId=$FailedAttemptId;FailedRunId=$FailedRunId;FailedClaimId=$FailedClaimId
            NativeRequestId=$NativeRequestId;HistoricalApprovalRequestId=$ApprovalRequestId
            HistoricalApprovalDisposition='expired-unconsumed';HistoricalApprovalSha256=$approvalHash
            ReconciledNativeFailure=$true;ReplacementNativeLaunchAbsent=$true
            ResultSha256=$ExpectedResultSha256;ReportSha256=$ExpectedReportSha256;ModelSha256=$ExpectedModelSha256
            RetiredUtc=Get-RepatoUtc
        }
        if($t.PSObject.Properties['mayaQaCandidateReplacementRetirement']){$t.mayaQaCandidateReplacementRetirement=$replacementRetirement}
        else{$t|Add-Member NoteProperty mayaQaCandidateReplacementRetirement $replacementRetirement -Force}
        $t.status='in-progress';$t.workflowStage='build-checks';$t.errorDetails=$null
        Add-RepatoHistory $t 'maya-tara-reconciled-duplicate-floor-plan-failure-archived' 'Maya' "attempt=$FailedAttemptId; run=$FailedRunId; claim=$FailedClaimId; request=$NativeRequestId; approval=$ApprovalRequestId preserved expired and unconsumed; failure evidence retained; no retry or native launch"
        [pscustomobject]@{Status='Recovered';TaskId=$TaskId;WorkflowId=$WorkflowId;FailedAttemptId=$FailedAttemptId;FailedRunId=$FailedRunId;FailedClaimId=$FailedClaimId;HistoricalApprovalDisposition='expired-unconsumed';ApprovalRecordPreserved=$true;FailedEvidencePreserved=$true;TaskStage='build-checks';NativeLaunchPerformed=$false}
    }
}

function Reset-MayaQaReconciledDuplicateFloorPlanWorkflowPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][ValidateRange(1,[long]::MaxValue)][long]$ExpectedTaskRevision,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$FailedAttemptId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$FailedRunId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$FailedClaimId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$NativeRequestId,
        [Parameter(Mandatory)][string]$ApprovalRequestId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedResultSha256,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedReportSha256,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedModelSha256,
        [switch]$DryRun
    )
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    if(!$task -or [long]$task.revision -ne $ExpectedTaskRevision){throw 'Reconciled workflow-plan reset task revision is stale.'}
    $workflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId)
    if($workflows.Count -ne 1 -or [string]$workflows[0].taskId -cne $TaskId){throw 'Reconciled workflow-plan reset task/workflow identity is invalid.'}
    $workflow=$workflows[0]
    $retirement=if($task.PSObject.Properties['mayaQaCandidateReplacementRetirement']){$task.mayaQaCandidateReplacementRetirement}else{$null}
    $executionRecords=@()
    if($task.PSObject.Properties['mayaTaraExecutionHistory']){$executionRecords=@($task.mayaTaraExecutionHistory|Where-Object {$_.AttemptId -ceq $FailedAttemptId -and $_.RunId -ceq $FailedRunId})}
    $attemptRecords=@()
    if($task.PSObject.Properties['mayaTaraAttemptHistory']){$attemptRecords=@($task.mayaTaraAttemptHistory|Where-Object {$_.AttemptId -ceq $FailedAttemptId -and $_.RunId -ceq $FailedRunId})}
    $approvalRecords=@($task.approvalRequests|Where-Object {$_.requestId -ceq $ApprovalRequestId -and $_.action -ceq 'qa-run'})
    if($task.status -cne 'in-progress' -or $task.workflowStage -cne 'build-checks' -or
        !$retirement -or $retirement.ReconciledNativeFailure -ne $true -or
        $retirement.WorkflowId -cne $WorkflowId -or $retirement.FailedAttemptId -cne $FailedAttemptId -or
        $retirement.FailedRunId -cne $FailedRunId -or $retirement.FailedClaimId -cne $FailedClaimId -or
        $retirement.NativeRequestId -cne $NativeRequestId -or
        $retirement.HistoricalApprovalRequestId -cne $ApprovalRequestId -or
        $retirement.HistoricalApprovalDisposition -cne 'expired-unconsumed' -or
        $retirement.ResultSha256 -ine $ExpectedResultSha256 -or $retirement.ReportSha256 -ine $ExpectedReportSha256 -or
        $retirement.ModelSha256 -ine $ExpectedModelSha256 -or $executionRecords.Count -ne 1 -or
        $attemptRecords.Count -ne 1 -or $approvalRecords.Count -ne 1) {
        throw 'Reconciled workflow-plan reset is not bound to the exact archived native failure.'
    }
    $execution=$executionRecords[0]
    $attempt=$attemptRecords[0]
    $approval=$approvalRecords[0]
    if($execution.FailedClaimId -cne $FailedClaimId -or $execution.NativeRequestId -cne $NativeRequestId -or
        $execution.ResultSha256 -ine $ExpectedResultSha256 -or $execution.ReportSha256 -ine $ExpectedReportSha256 -or
        $execution.DisposableModelSha256 -ine $ExpectedModelSha256 -or
        $execution.TransactionStatus -cne 'NotStarted' -or $execution.RollbackStatus -cne 'NotRequired' -or
        $execution.ClaimStatus -cne 'released' -or $attempt.AttemptId -cne $FailedAttemptId -or
        $attempt.RunId -cne $FailedRunId -or $approval.status -cne 'approved' -or $approval.consumedUtc) {
        throw 'Archived failure, attempt, or historical approval disposition is inconsistent.'
    }
    if((Get-MayaQaCanonicalObjectSha256 $approval) -ine [string]$retirement.HistoricalApprovalSha256){throw 'Historical approval record changed after failure reconciliation.'}
    $approvalExpiry=[DateTimeOffset]::MinValue
    if(![DateTimeOffset]::TryParse([string]$approval.expiresUtc,[ref]$approvalExpiry) -or $approvalExpiry -gt [DateTimeOffset]::UtcNow){
        throw 'Historical approval is not verifiably expired.'
    }
    if(@(Get-Process -Name Revit -ErrorAction SilentlyContinue).Count){throw 'Revit is active; reconciled workflow-plan reset is blocked.'}
    $alreadyArchived=@()
    if($workflow.PSObject.Properties['qaRunHistory']){$alreadyArchived=@($workflow.qaRunHistory|Where-Object {$_.RunId -ceq $FailedRunId})}
    if([string]::IsNullOrWhiteSpace([string]$workflow.qaRunId)){
        if($alreadyArchived.Count -ne 1 -or $workflow.qaModelPath -or $workflow.qaSidecarPath -or
            $workflow.qaFixturePreparationEvidence -or $workflow.qaHandoff -or $workflow.qaApprovalId) {
            throw 'Workflow plan is partially reset or has ambiguous archive history.'
        }
        return [pscustomobject]@{Status='AlreadyArchived';TaskId=$TaskId;WorkflowId=$WorkflowId;FailedRunId=$FailedRunId;FailureEvidencePreserved=$true;HistoricalApprovalPreserved=$true;NativeLaunchPerformed=$false;SideEffectsPerformed=$false}
    }
    if([string]$workflow.qaWorkflowId -cne 'create-plan-views-v1' -or
        [string]$workflow.qaRunId -cne $FailedRunId -or
        [IO.Path]::GetFullPath([string]$workflow.qaModelPath) -ine [IO.Path]::GetFullPath([string]$execution.DisposableModelPath) -or
        [string]$workflow.qaDisposableModelSha256 -ine $ExpectedModelSha256 -or
        [string]$workflow.qaFixturePreparationEvidence.RunId -cne $FailedRunId -or
        [string]$workflow.qaFixturePreparationEvidence.AttemptId -cne $FailedAttemptId -or
        [string]$workflow.qaFixturePreparationEvidence.PreparedModelSha256 -ine $ExpectedModelSha256 -or
        [string]$workflow.qaApprovalId -cne $ApprovalRequestId -or [string]$workflow.qaApprovalStatus -cne 'approved' -or
        $alreadyArchived.Count) {
        throw 'Current workflow plan does not match the exact reconciled failure or already has an archive.'
    }
    $modelPath=[IO.Path]::GetFullPath([string]$workflow.qaModelPath)
    $sidecarPath=[IO.Path]::GetFullPath([string]$workflow.qaSidecarPath)
    if(!(Test-Path -LiteralPath $modelPath -PathType Leaf) -or
        (Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash -ine $ExpectedModelSha256 -or
        !(Test-Path -LiteralPath $sidecarPath -PathType Leaf)) {
        throw 'Reconciled workflow model or sidecar is missing or changed.'
    }
    $sidecar=Get-Content -LiteralPath $sidecarPath -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
    if([string]$sidecar.fixtureId -cne [string]$workflow.qaFixtureId -or
        [string]$sidecar.sourceSha256 -ine [string]$workflow.qaFixtureSha256) {
        throw 'Reconciled workflow sidecar provenance does not match the prior plan.'
    }
    $preparation=$workflow.qaFixturePreparationEvidence
    foreach($pair in @(@($preparation.RequestPath,$preparation.RequestSha256),@($preparation.ResultPath,$preparation.ResultSha256))) {
        if(!$pair[0] -or $pair[1] -notmatch '^[A-Fa-f0-9]{64}$' -or
            !(Test-Path -LiteralPath $pair[0] -PathType Leaf) -or
            (Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ine [string]$pair[1]) {
            throw 'Prior fixture-preparation evidence is missing or changed.'
        }
    }
    $handoff=$workflow.qaHandoff
    if($handoff -and
        ($handoff.HandoffId -cne $workflow.qaHandoffId -or
         [IO.Path]::GetFullPath([string]$handoff.ModelPath) -ine $modelPath -or
         [IO.Path]::GetFullPath([string]$handoff.SidecarPath) -ine $sidecarPath)) {
        throw 'Prior workflow handoff identity or model binding changed.'
    }
    if($DryRun){return [pscustomobject]@{Status='DryRun';TaskId=$TaskId;WorkflowId=$WorkflowId;FailedRunId=$FailedRunId;FailureEvidencePreserved=$true;HistoricalApprovalPreserved=$true;ModelUnchanged=$true;NativeLaunchPerformed=$false;SideEffectsPerformed=$false}}
    $archive=[pscustomobject][ordered]@{
        ArchivedUtc=Get-RepatoUtc;TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=[string]$workflow.qaWorkflowId
        RunId=[string]$workflow.qaRunId;ModelPath=$modelPath;SidecarPath=$sidecarPath
        FixtureId=[string]$workflow.qaFixtureId;FixtureSha256=[string]$workflow.qaFixtureSha256
        FixtureSpecSha256=[string]$workflow.qaFixtureSpecSha256;TestId=[string]$workflow.qaTestId
        DisposableModelSha256=[string]$workflow.qaDisposableModelSha256
        FixturePreparationEvidence=$preparation;ReportPath=$workflow.qaReportPath;ReportSha256=$workflow.qaReportSha256
        Evidence=$workflow.qaEvidence;VerificationStatus=$workflow.qaVerificationStatus
        CompletionStatus=$workflow.qaCompletionStatus;CompletedUtc=$workflow.qaCompletedUtc
        HandoffId=$workflow.qaHandoffId;Handoff=$handoff;ApprovalId=$workflow.qaApprovalId
        ApprovalStatus=$workflow.qaApprovalStatus;FailedAttemptId=$FailedAttemptId;FailedClaimId=$FailedClaimId
        NativeRequestId=$NativeRequestId;FailedResultSha256=$ExpectedResultSha256
        FailedReportSha256=$ExpectedReportSha256;FailedCandidateSha256=[string]$execution.ArtifactSha256
        HistoricalApprovalSha256=(Get-MayaQaCanonicalObjectSha256 $approval)
    }
    $mutation=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId ([long]$workflow.workflowRevision) $ExpectedTaskRevision {
        param($current)
        if([string]$current.qaRunId -cne $FailedRunId -or
            [string]$current.qaDisposableModelSha256 -ine $ExpectedModelSha256 -or
            [string]$current.qaApprovalId -cne $ApprovalRequestId) {
            throw 'Reconciled workflow-plan reset compare-and-swap failed.'
        }
        if($current.PSObject.Properties.Name -notcontains 'qaRunHistory'){$current|Add-Member NoteProperty qaRunHistory ([object[]]@()) -Force}
        $current.qaRunHistory=[object[]]@($current.qaRunHistory)+$archive
        foreach($name in @('qaRunId','qaModelPath','qaSidecarPath','qaFixtureId','qaFixtureSha256','qaFixtureSpecSha256',
            'qaTestId','qaDisposableModelSha256','qaFixturePreparationEvidence','qaReportPath','qaReportSha256','qaEvidence',
            'qaVerificationStatus','qaCompletionStatus','qaCompletedUtc','qaHandoffId','qaHandoff','qaApprovalId','qaApprovalStatus')) {
            $current|Add-Member -NotePropertyName $name -NotePropertyValue $null -Force
        }
        return $current
    })[-1]
    [pscustomobject]@{Status='Archived';TaskId=$TaskId;WorkflowId=$WorkflowId;FailedRunId=$FailedRunId;TaskRevision=$mutation.TaskRevision;WorkflowRevision=$mutation.Workflow.workflowRevision;FailureEvidencePreserved=$true;HistoricalApprovalPreserved=$true;NativeLaunchPerformed=$false;SideEffectsPerformed=$true}
}

function Resolve-MayaQaRequestWorkflow {
    param([Parameter(Mandatory)][string]$Request)
    $text=$Request.Trim().ToLowerInvariant()
    if (($text -match 'create[- ]levels' -or $text -match 'create\s+(?:one|two|three|four|five|six|seven|eight|nine|ten|\d+)\s+levels') -and $text -match 'grid[- ]resequence|resequence') { throw 'User request is ambiguous.' }
    $map=@{
        'welcome-smoke'='welcome-supervised-dialog-v1';
        'create-grids-world-axis-v1'='create-grids-world-axis-v1';'create grids'='create-grids-world-axis-v1';'create grids world axis'='create-grids-world-axis-v1';
        'create-levels-elevations-v1'='create-levels-elevations-v1';'create-levels'='create-levels-elevations-v1';'create levels'='create-levels-elevations-v1';'create-plan-views-v1'='create-plan-views-v1';
        'grid-bubble-visibility-v1'='grid-bubble-visibility-v1';'grid bubble visibility'='grid-bubble-visibility-v1';
        'grid-bubble-offset-v1'='grid-bubble-offset-v1';'grid bubble offset'='grid-bubble-offset-v1';
        'grid-resequence-v1'='grid-resequence-v1';'grid-resequence-all-directions-v1'='grid-resequence-v1';'grid resequence'='grid-resequence-v1'
    }
    if($map.ContainsKey($text)){return $map[$text]}
    if($text -match 'eight grids|create grids|world axis'){return 'create-grids-world-axis-v1'}
    if($text -match 'create[- ]levels' -or $text -match 'create\s+(?:one|two|three|four|five|six|seven|eight|nine|ten|\d+)\s+levels'){return 'create-levels-elevations-v1'}
    if($text -match 'bubble visibility' -or ($text -match '(show|display|hide|turn)\b' -and $text -match 'bubbles?' -and $text -match 'selected\s+grids?')){return 'grid-bubble-visibility-v1'}
    if($text -match 'bubble offset' -or ($text -match '(offset|move|shift)' -and $text -match 'bubbles?' -and $text -match '\b(?:-?\d+(?:\.\d+)?)\s*mm\b')){return 'grid-bubble-offset-v1'}
    if($text -match 'plan\s+views?|floor\s+plan|ceiling\s+plan'){
        return 'create-plan-views-v1'
    }
    if($text -match 'resequence'){
        if($text -notmatch '\bgrids?\b'){throw 'User request does not identify a supported QA workflow.'}
        return 'grid-resequence-v1'
    }
    throw 'User request does not identify a supported QA workflow.'
}
function New-MayaQaRequestFoundation {
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$UserRequest,
        [string]$SourceBranch='main',
        [string]$ProjectPath,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [object]$AuthenticatedBuildSource
    )
    $qaId=Resolve-MayaQaRequestWorkflow $UserRequest
    if($qaId -cne (Resolve-MayaQaWorkflowId $QaWorkflowId)){throw 'QA workflow identity mismatch.'}
    $def=Get-MayaQaWorkflowDefinition $qaId
    $taskId='task-'+[guid]::NewGuid().ToString('N');$workflowId='workflow-'+[guid]::NewGuid().ToString('N')
    if([string]::IsNullOrWhiteSpace($ProjectPath)){$ProjectPath='Forma.RevitConnector.csproj'}
    $null=Initialize-RepatoTaskStore $StoreRoot
    New-RepatoTask $StoreRoot $taskId 'Maya QA request' $UserRequest 'qa/maya-qa-workflow' 'maya'|Out-Null
    $taskNow=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $taskId
    if($taskNow.workflowStage -eq 'queued'){Claim-RepatoTask $StoreRoot $taskId 'Neil'|Out-Null;Update-RepatoTask $StoreRoot $taskId 'in-progress' 'implementation' 'Neil' $null $null|Out-Null;Update-RepatoTask $StoreRoot $taskId 'in-progress' 'build-checks' 'Neil' $null $null|Out-Null}
    $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$plan=New-DeployPlan $StoreRoot $taskId (Join-Path $root 'bin\Release\net8.0-windows\Repato.Revit.dll') (Join-Path $root 'Repato.addin');$workflow=New-DeployWorkflow $StoreRoot $plan
    $intake=Invoke-MayaQaIntake $taskId $workflow.workflowId $qaId $UserRequest
    $buildRequest=New-MayaQaBuildRequest -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflow.workflowId -QaWorkflowId $qaId -UserRequest $UserRequest -SourceBranch $SourceBranch -ProjectPath $ProjectPath -AuthenticatedBuildSource $AuthenticatedBuildSource
    [pscustomobject]@{TaskId=$taskId;WorkflowId=$workflow.workflowId;QaWorkflowId=$qaId;NativeTestId=(Get-MayaQaNativeTestId $def);Intake=$intake;BuildRequest=$buildRequest}
}
function New-MayaQaDeploymentValidationOperation {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][long]$ExpectedTaskRevision,[Parameter(Mandatory)][string]$BuildRequestId,[Parameter(Mandatory)][string]$CandidateSourceCommit,[Parameter(Mandatory)][string]$CandidateSha256,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$TestId,[ValidateSet('CanonicalAfterStaging','IndependentAfterAmbiguousStaging','RecoveredQaCurrentDeployment')][string]$ValidationPurpose='CanonicalAfterStaging',[string]$RequestId,[object]$ValidationRequest)
    $id=[guid]::NewGuid().ToString('N');if([string]::IsNullOrWhiteSpace($RequestId)){$requestId=[guid]::NewGuid().ToString('N')}else{$parsed=[guid]::Empty;if(![guid]::TryParse($RequestId,[ref]$parsed)){throw 'Deployment-validation request identity is invalid.'};$requestId=$RequestId};$now=Get-RepatoUtc
    if($ValidationRequest){foreach($pair in @(@('requestId',$requestId),@('taskId',$TaskId),@('workflowId',$WorkflowId),@('candidateCommit',$CandidateSourceCommit),@('expectedCandidateSha256',$CandidateSha256),@('qaWorkflowId',$QaWorkflowId),@('testId',$TestId))){if([string]$ValidationRequest.($pair[0]) -cne [string]$pair[1]){throw "Deployment-validation request payload binding mismatch: $($pair[0])."}}}
    $requestJson=if($ValidationRequest){ConvertTo-Json -InputObject $ValidationRequest -Compress -Depth 32}else{$null};$requestHash=$null;if($requestJson){$sha=[Security.Cryptography.SHA256]::Create();try{$requestHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($requestJson)))).Replace('-','')}finally{$sha.Dispose()}}
    $op=[pscustomobject][ordered]@{SchemaVersion=1;OperationId=$id;RequestId=$requestId;TaskId=$TaskId;WorkflowId=$WorkflowId;ExpectedTaskRevision=([long]$ExpectedTaskRevision+1);BuildRequestId=$BuildRequestId;CandidateSourceCommit=$CandidateSourceCommit;CandidateSha256=$CandidateSha256;QaWorkflowId=$QaWorkflowId;TestId=$TestId;ValidationPurpose=$ValidationPurpose;ValidationRequest=$ValidationRequest;ValidationRequestSha256=$requestHash;RequestDisposition='confirmed-unsent';CreatedUtc=$now;TransmittingTaskRevision=$null;Response=$null}
    $null=Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)$t=Find-RepatoTask $d $TaskId;if(!$t){throw 'Continuation task was not found.'};if([long]$t.revision -ne $ExpectedTaskRevision){throw 'Cannot create deployment-validation operation for a stale task revision.'};$w=@($t.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId);if($w.Count -ne 1 -or $w[0].taskId -cne $TaskId){throw 'Cannot create deployment-validation operation for an unbound workflow.'};if($t.PSObject.Properties.Name -notcontains 'deploymentValidationOperations'){$t|Add-Member NoteProperty deploymentValidationOperations ([object[]]@()) -Force};if(@($t.deploymentValidationOperations|Where-Object {$_.RequestDisposition -in @('confirmed-unsent','transmitting','unknown')}).Count){throw 'An unresolved deployment-validation operation already exists.'};if(@($t.deploymentValidationOperations|Where-Object OperationId -ceq $id).Count){throw 'Deployment-validation operation already exists.'};Add-RepatoHistory $t 'deployment-validation-operation-created' 'Maya' "operation=$id; request=$requestId; disposition=confirmed-unsent";$t.deploymentValidationOperations=[object[]]@($t.deploymentValidationOperations)+$op;$t}
    $stored=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId;@($stored.deploymentValidationOperations|Where-Object OperationId -ceq $id)[0]
}
function Continue-MayaQaDeploymentValidation {
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$OperationId,
        [Parameter(Mandatory)][long]$ExpectedTaskRevision,
        [Parameter(Mandatory)][string]$ExpectedBuildRequestId,
        [Parameter(Mandatory)][string]$ExpectedCandidateSourceCommit,
        [Parameter(Mandatory)][string]$ExpectedCandidateSha256,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$TestId,
        [scriptblock]$DispositionResolver,
        [scriptblock]$RequestInvoker
    )
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    if(!$task){throw 'Continuation task was not found.'}
    $workflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId)
    if($workflows.Count -ne 1 -or $workflows[0].taskId -cne $TaskId){throw 'Continuation task/workflow identity mismatch.'}
    $op=$null;if($task.PSObject.Properties.Name -contains 'deploymentValidationOperations'){$op=@($task.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId)[0]}
    if(!$op){throw 'Deployment-validation operation was not found.'}
    foreach($pair in @(@('TaskId',$TaskId),@('WorkflowId',$WorkflowId),@('BuildRequestId',$ExpectedBuildRequestId),@('CandidateSourceCommit',$ExpectedCandidateSourceCommit),@('CandidateSha256',$ExpectedCandidateSha256),@('QaWorkflowId',$QaWorkflowId),@('TestId',$TestId))){if([string]$op.($pair[0]) -cne [string]$pair[1]){throw "Deployment-validation operation binding mismatch: $($pair[0])."}}
    if([long]$op.ExpectedTaskRevision -ne $ExpectedTaskRevision){throw 'Deployment-validation operation revision binding mismatch.'}
    if($op.RequestDisposition -ceq 'completed') {[pscustomobject]@{Status='Completed';OperationId=$OperationId;RequestId=$op.RequestId;RequestDisposition='completed';CompletedTaskRevision=$op.CompletedTaskRevision;Validation=$op.Response;RevitLaunched=$false;ApprovalBoundaryPreserved=$true};return}
    if($op.RequestDisposition -ceq 'completed-failed'){throw "Deployment validation previously failed: $($op.FailureReason)"}
    $requiredCurrentRevision=if($op.RequestDisposition -in @('unknown','transmitting')){[long]$op.TransmittingTaskRevision}else{$ExpectedTaskRevision}
    if($null -eq $requiredCurrentRevision -or [long]$task.revision -ne [long]$requiredCurrentRevision){throw 'Continuation task revision changed.'}
    if($op.RequestDisposition -in @('unknown','transmitting')){
        if(!$DispositionResolver){throw 'Ambiguous deployment-validation transmission is not retryable without authoritative completion evidence.'}
        if($null -eq $op.TransmittingTaskRevision){throw 'Ambiguous deployment-validation operation has no durable transmission revision.'}
        $resolved=& $DispositionResolver $op
        if(!$resolved -or [string]$resolved.OperationId -cne $OperationId -or [string]$resolved.Disposition -cne 'completed'){throw 'Authoritative deployment-validation disposition did not confirm completion.'}
        if(!$resolved.Response){throw 'Authoritative deployment-validation disposition did not include a response.'}
        $responseRequestId=if($op.PSObject.Properties.Name -contains 'RequestId'){[string]$op.RequestId}else{$null}
        $op.Response=Assert-MayaQaDeploymentValidationResponseEnvelope -Response $resolved.Response -ExpectedRequestId $responseRequestId;$op.RequestDisposition='response-received'
    } elseif($op.RequestDisposition -ne 'confirmed-unsent'){throw 'Legacy or incompatible deployment-validation operation state is not retryable.'}
    if($op.RequestDisposition -ceq 'response-received'){$response=$op.Response}else{
        if(!$RequestInvoker){throw 'A request invoker is required for confirmed-unsent continuation.'}
        $null=Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)$t=Find-RepatoTask $d $TaskId;if([long]$t.revision -ne $ExpectedTaskRevision){throw 'Deployment-validation operation revision changed before transmission.'};$x=@($t.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId)[0];if(!$x -or $x.RequestDisposition -cne 'confirmed-unsent' -or [string]$x.BuildRequestId -cne $ExpectedBuildRequestId -or [string]$x.CandidateSourceCommit -cne $ExpectedCandidateSourceCommit -or [string]$x.CandidateSha256 -cne $ExpectedCandidateSha256){throw 'Deployment-validation operation changed before transmission.'};$x.RequestDisposition='transmitting';Add-RepatoHistory $t 'deployment-validation-transmitting' 'Maya' "operation=$OperationId";$x.TransmittingTaskRevision=[long]$t.revision;$t}
        $response=$null;try{$response=& $RequestInvoker $op}catch{throw 'Deployment-validation transmission is ambiguous; retry is blocked.'}
        if(!$response){throw 'Deployment-validation response was not received; retry is blocked.'}
        $responseRequestId=if($op.PSObject.Properties.Name -contains 'RequestId'){[string]$op.RequestId}else{$null}
        $response=Assert-MayaQaDeploymentValidationResponseEnvelope -Response $response -ExpectedRequestId $responseRequestId
    }
    try{$result=Normalize-MayaQaDeploymentValidationResponse -Response $response -CandidateCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256 -QaWorkflowId $QaWorkflowId -TestId $TestId -ExpectedRequestId $responseRequestId}catch{
        $failureReason=$_.Exception.Message
        $null=Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)$t=Find-RepatoTask $d $TaskId;$x=@($t.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId)[0];if(!$x -or $x.RequestDisposition -notin @('transmitting','unknown')){throw 'Deployment-validation failed completion state changed.'};if([long]$t.revision -ne [long]$x.TransmittingTaskRevision -or [string]$x.RequestId -cne $responseRequestId){throw 'Deployment-validation failed completion binding changed.'};$x.RequestDisposition='completed-failed';$x.Response=$response;$x|Add-Member NoteProperty ValidationStatus 'failed' -Force;$x|Add-Member NoteProperty FailureReason $failureReason -Force;$x|Add-Member NoteProperty CompletedUtc (Get-RepatoUtc) -Force;Add-RepatoHistory $t 'deployment-validation-failed' 'Maya' "operation=$OperationId; request=$responseRequestId; reason=$failureReason";$t}
        throw $failureReason
    }
    $op.Response=$result
    $null=Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)$t=Find-RepatoTask $d $TaskId;$x=@($t.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId)[0];if(!$x -or $x.RequestDisposition -notin @('transmitting','unknown','completed')){throw 'Deployment-validation operation disappeared or is not completing.'};if($x.RequestDisposition -in @('transmitting','unknown') -and [long]$t.revision -ne [long]$x.TransmittingTaskRevision){throw 'Deployment-validation completion revision changed.'};if([string]$x.TaskId -cne $TaskId -or [string]$x.WorkflowId -cne $WorkflowId -or [string]$x.BuildRequestId -cne $ExpectedBuildRequestId -or [string]$x.CandidateSourceCommit -cne $ExpectedCandidateSourceCommit -or [string]$x.CandidateSha256 -cne $ExpectedCandidateSha256){throw 'Deployment-validation completion binding changed.'};$x.RequestDisposition='completed';$x.Response=$op.Response;Add-RepatoHistory $t 'deployment-validation-completed' 'Maya' "operation=$OperationId";$x|Add-Member NoteProperty CompletedTaskRevision ([long]$t.revision) -Force;$t}
    [pscustomobject]@{Status='Completed';OperationId=$OperationId;RequestId=$op.RequestId;RequestDisposition='completed';Validation=$result;RevitLaunched=$false;ApprovalBoundaryPreserved=$true}
}
function Invoke-MayaQaIndependentDeploymentValidationRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][long]$ExpectedTaskRevision,[Parameter(Mandatory)][string]$ExpectedBuildRequestId,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{40}$')][string]$ExpectedCandidateSourceCommit,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedCandidateSha256,
        [Parameter(Mandatory)][string]$ExpectedRunnerManifestPath,[Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedRunnerManifestSha256,
        [scriptblock]$HealthInvoker,[scriptblock]$PreflightInvoker,[scriptblock]$DeploymentValidationInvoker,
        [scriptblock]$RevitProcessProvider,[switch]$DryRun
    )
    $qaId='create-plan-views-v1';$testId=$qaId
    $trustedManifest=[IO.Path]::GetFullPath((Join-Path (Join-Path $PSScriptRoot '..\QA') 'Repato.CreatePlanViews.TestRunner.addin'))
    $expectedInstalledManifest=[IO.Path]::GetFullPath('C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin')
    if([IO.Path]::GetFullPath($ExpectedRunnerManifestPath) -ine $expectedInstalledManifest){throw 'Independent validation runner manifest path is not the approved RepatoQA path.'}
    $manifestHash=(Get-FileHash -LiteralPath $trustedManifest -Algorithm SHA256).Hash
    if($manifestHash -ine $ExpectedRunnerManifestSha256){throw 'Trusted source runner manifest hash mismatch.'}

    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    $workflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId)
    if($workflows.Count -ne 1 -or [string]$workflows[0].taskId -cne $TaskId){throw 'Independent validation canonical task/workflow identity mismatch.'}
    $workflow=$workflows[0];$e=$workflow.qaBuildEvidence
    $recoveredQa=$task.workflowStage -ceq 'qa'
    $validationPurpose='IndependentAfterAmbiguousStaging'
    if($recoveredQa){
        $null=Assert-CpvRecoveredQaDeploymentBindingState -Task $task -Workflow $workflow -ExpectedTaskRevision $ExpectedTaskRevision -TaskId $TaskId -WorkflowId $WorkflowId -BuildRequestId $ExpectedBuildRequestId -CandidateSourceCommit $ExpectedCandidateSourceCommit -CandidateSha256 $ExpectedCandidateSha256
        $validationPurpose='RecoveredQaCurrentDeployment'
    }elseif($task.status -cne 'in-progress' -or $task.workflowStage -cne 'build-checks'){throw 'Independent validation requires build-checks or verified recovered QA.'}
    if(@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and ($_.status -ceq 'pending' -or ($_.status -ceq 'approved' -and [string]::IsNullOrWhiteSpace([string]$_.consumedUtc)))}).Count){throw 'Independent validation is blocked by an active approval.'}
    foreach($n in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){if($task.PSObject.Properties.Name -contains $n -and $task.$n){throw 'Independent validation is blocked by existing Tara state.'}}
    if(!$e -or $workflow.qaBuildStatus -cne 'succeeded' -or [string]$e.BuildRequestId -cne $ExpectedBuildRequestId -or [string]$e.SourceCommit -ine $ExpectedCandidateSourceCommit -or [string]$e.CandidateSourceCommit -ine $ExpectedCandidateSourceCommit -or [string]$e.ArtifactSha256 -ine $ExpectedCandidateSha256 -or [string]$e.EvidenceSource -cne 'FrozenCandidate' -or [string]$e.RunnerManifestSha256 -ine $ExpectedRunnerManifestSha256){throw 'Independent validation canonical build or candidate evidence mismatch.'}
    if($e.DeploymentValidation -or ($e.PSObject.Properties.Name -contains 'IndependentDeploymentValidation' -and $e.IndependentDeploymentValidation)){throw 'Independent deployment-validation evidence is already recorded.'}
    $revit=if($RevitProcessProvider){@(& $RevitProcessProvider)}else{@(Get-Process Revit -ErrorAction SilentlyContinue)}
    if(@($revit).Count){throw 'Independent deployment validation requires Revit to be stopped.'}

    $health=if($HealthInvoker){& $HealthInvoker}else{Invoke-MayaQaLaunchAgentHealth}
    if(!$health.Ready -or $health.User -ine 'RAMSAI\RepatoQA' -or $health.SID -cne 'S-1-5-21-1031246752-3872016183-2454652381-1015' -or [int]$health.SessionId -le 0 -or !$health.UserInteractive){throw 'Independent validation Launch Agent identity/health contract failed.'}
    $candidate=New-MayaQaPersistedCandidateEvidence -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $qaId -TestId $testId
    $preflight=if($PreflightInvoker){& $PreflightInvoker}elseif($recoveredQa){Invoke-MayaQaLaunchAgentPreflightReadonly -CandidateEvidence $candidate -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $qaId -TestId $testId -CandidateCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256}else{Invoke-MayaQaLaunchAgentPreflightReadonly}
    $postStageCandidateMismatch=Test-MayaQaPostStageCandidateHashMismatch -Preflight $preflight -ExpectedCandidateSha256 $ExpectedCandidateSha256
    if(($recoveredQa -and !$preflight.Succeeded) -or (!$preflight.Succeeded -and !$postStageCandidateMismatch) -or $preflight.ExecutionIdentity -ine 'RAMSAI\RepatoQA' -or [IO.Path]::GetFullPath($preflight.RunnerManifestPath) -ine $expectedInstalledManifest -or $preflight.ExpectedRunnerManifestSha256 -ine $ExpectedRunnerManifestSha256){throw 'Independent validation requires a pinned runner manifest and valid candidate preflight.'}

    $candidate=New-MayaQaPersistedCandidateEvidence -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $qaId -TestId $testId
    if($candidate.CandidateSourceCommit -ine $ExpectedCandidateSourceCommit -or $candidate.CandidateDllSha256 -ine $ExpectedCandidateSha256 -or $candidate.RunnerManifestSha256 -ine $ExpectedRunnerManifestSha256){throw 'Independent validation candidate provenance does not match the approved pins.'}
    $existingValidationOps=if($task.PSObject.Properties.Name -contains 'deploymentValidationOperations'){@($task.deploymentValidationOperations)}else{@()}
    $allBoundOps=@($existingValidationOps|Where-Object {$_.TaskId -ceq $TaskId -and $_.WorkflowId -ceq $WorkflowId -and $_.BuildRequestId -ceq $ExpectedBuildRequestId -and $_.CandidateSourceCommit -ieq $ExpectedCandidateSourceCommit -and $_.CandidateSha256 -ieq $ExpectedCandidateSha256})
    if(@($allBoundOps|Where-Object ValidationPurpose -cne $validationPurpose).Count){throw 'A different validation lifecycle already exists for this candidate; do not create an independent duplicate.'}
    $ops=@($allBoundOps|Where-Object ValidationPurpose -ceq $validationPurpose)
    if($ops.Count -gt 1){throw 'Multiple independent deployment-validation operations exist; manual reconciliation is required.'}
    if($ops.Count -eq 0){
        if([long]$task.revision -ne $ExpectedTaskRevision){throw 'Independent validation task revision is stale.'}
        if($DryRun){return [pscustomobject]@{Status='DryRun';TaskId=$TaskId;WorkflowId=$WorkflowId;BuildRequestId=$ExpectedBuildRequestId;CandidateSourceCommit=$ExpectedCandidateSourceCommit;CandidateSha256=$ExpectedCandidateSha256;StageRequestResent=$false;StagingSuccessClaimed=$false;SideEffectsPerformed=$false}}
        $requestId=[guid]::NewGuid().ToString('N')
        $validationRequest=[ordered]@{schemaVersion=1;operation='validate-qa-deployment';requestId=$requestId;candidateCommit=$ExpectedCandidateSourceCommit;expectedCandidateSha256=$ExpectedCandidateSha256;taskId=$TaskId;workflowId=$WorkflowId;qaWorkflowId=$qaId;testId=$testId;candidateEvidence=$candidate}
        $created=New-MayaQaDeploymentValidationOperation -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -ExpectedTaskRevision $ExpectedTaskRevision -BuildRequestId $ExpectedBuildRequestId -CandidateSourceCommit $ExpectedCandidateSourceCommit -CandidateSha256 $ExpectedCandidateSha256 -QaWorkflowId $qaId -TestId $testId -ValidationPurpose $validationPurpose -RequestId $requestId -ValidationRequest $validationRequest
        $op=$created;$data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    } else { $op=$ops[0] }

    foreach($pair in @(@('TaskId',$TaskId),@('WorkflowId',$WorkflowId),@('BuildRequestId',$ExpectedBuildRequestId),@('CandidateSourceCommit',$ExpectedCandidateSourceCommit),@('CandidateSha256',$ExpectedCandidateSha256),@('QaWorkflowId',$qaId),@('TestId',$testId))){if([string]$op.($pair[0]) -cne [string]$pair[1]){throw "Independent validation operation binding mismatch: $($pair[0])."}}
    if(!$op.ValidationRequest -or [string]$op.ValidationRequest.requestId -cne [string]$op.RequestId -or [string]$op.ValidationRequest.candidateEvidence.CandidateSourceCommit -ine $ExpectedCandidateSourceCommit -or [string]$op.ValidationRequest.candidateEvidence.CandidateDllSha256 -ine $ExpectedCandidateSha256 -or [string]$op.ValidationRequest.candidateEvidence.RunnerManifestSha256 -ine $ExpectedRunnerManifestSha256){throw 'Independent validation request payload is missing or mismatched.'}
    $requestJson=ConvertTo-Json -InputObject $op.ValidationRequest -Compress -Depth 32;$sha=[Security.Cryptography.SHA256]::Create();try{$requestHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($requestJson)))).Replace('-','')}finally{$sha.Dispose()}
    if($requestHash -ine $op.ValidationRequestSha256){throw 'Independent validation request payload hash mismatch.'}
    switch([string]$op.RequestDisposition){
        'confirmed-unsent' {if([long]$task.revision -ne [long]$op.ExpectedTaskRevision){throw 'Confirmed-unsent independent validation operation revision is stale.'}}
        'completed' {
            $last=@($task.history)[-1]
            if($null -eq $op.TransmittingTaskRevision -or [long]$task.revision -ne ([long]$op.TransmittingTaskRevision+1) -or $last.event -cne 'deployment-validation-completed' -or [string]$last.details -cnotmatch [regex]::Escape([string]$op.OperationId)){throw 'Completed independent validation operation is stale or has subsequent task mutations.'}
        }
        {$_ -in @('transmitting','unknown','response-received')} {throw 'Independent validation request is ambiguous; automatic resend or uncorrelated completion is prohibited.'}
        default {throw "Independent validation operation is not safely continuable: $($op.RequestDisposition)"}
    }
    if($DryRun){return [pscustomobject]@{Status='DryRun';TaskId=$TaskId;WorkflowId=$WorkflowId;OperationId=$op.OperationId;RequestId=$op.RequestId;RequestDisposition=$op.RequestDisposition;StageRequestResent=$false;StagingSuccessClaimed=$false;SideEffectsPerformed=$false}}

    $requestInvoker={param($pending)
        if($DeploymentValidationInvoker){& $DeploymentValidationInvoker $candidate $pending}
        else{Invoke-MayaQaLaunchAgentDeploymentValidation -CandidateCommit $pending.ValidationRequest.candidateCommit -ExpectedCandidateSha256 $pending.ValidationRequest.expectedCandidateSha256 -QaWorkflowId $pending.ValidationRequest.qaWorkflowId -TestId $pending.ValidationRequest.testId -CandidateEvidence $pending.ValidationRequest.candidateEvidence -TaskId $pending.ValidationRequest.taskId -WorkflowId $pending.ValidationRequest.workflowId -RequestId $pending.RequestId}
    }.GetNewClosure()
    $continued=Continue-MayaQaDeploymentValidation -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -OperationId $op.OperationId -ExpectedTaskRevision $op.ExpectedTaskRevision -ExpectedBuildRequestId $ExpectedBuildRequestId -ExpectedCandidateSourceCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256 -QaWorkflowId $qaId -TestId $testId -RequestInvoker $requestInvoker
    if($continued.Status -cne 'Completed' -or !$continued.Validation.succeeded){throw 'Independent deployment validation did not complete successfully.'}
    $after=Read-RepatoTaskStore $StoreRoot;$afterTask=Find-RepatoTask $after $TaskId
    $afterRevit=if($RevitProcessProvider){@(& $RevitProcessProvider)}else{@(Get-Process Revit -ErrorAction SilentlyContinue)}
    if(@($afterRevit).Count){throw 'Revit started during independent deployment validation.'}
    $completedOps=@($afterTask.deploymentValidationOperations|Where-Object OperationId -ceq $op.OperationId)
    if($completedOps.Count -ne 1 -or $completedOps[0].RequestDisposition -cne 'completed'){throw 'Independent deployment-validation operation was not durably completed.'}
    $persist=Invoke-MayaQaFrozenCandidateEvidence -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $qaId -CandidateDirectory $e.CandidateDirectory -CandidateDllPath $e.ArtifactPath -ExpectedSha256 $ExpectedCandidateSha256 -ExpectedSourceCommit $ExpectedCandidateSourceCommit -DeploymentEvidence $continued.Validation -DeploymentValidationOperation $completedOps[0] -BindDeploymentEvidenceOnly:$recoveredQa
    [pscustomobject]@{Status='IndependentDeploymentValidated';TaskId=$TaskId;WorkflowId=$WorkflowId;BuildRequestId=$ExpectedBuildRequestId;OperationId=$op.OperationId;RequestId=$op.RequestId;CandidateSourceCommit=$ExpectedCandidateSourceCommit;CandidateSha256=$ExpectedCandidateSha256;DeploymentValidationRecorded=$true;StagingDisposition=$(if($recoveredQa){'existing-verified-deployment'}else{'ambiguous-unresolved'});StagingSuccessClaimed=$false;StageRequestResent=$false;RevitLaunched=$false;ApprovalRequested=$false;Evidence=$persist}
}

function Abandon-MayaQaUnresolvedDeploymentValidation {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$OperationId,
        [Parameter(Mandatory)][long]$ExpectedTaskRevision,[Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)][switch]$ConfirmReadOnlyValidationPath,[scriptblock]$RevitProcessProvider,[switch]$DryRun
    )
    if([string]::IsNullOrWhiteSpace($Reason)){throw 'Deployment-validation abandonment reason is required.'}
    if(!$ConfirmReadOnlyValidationPath){throw 'Explicit confirmation of the audited read-only validation path is required.'}
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    if(!$task){throw 'Deployment-validation abandonment task was not found.'}
    if([long]$task.revision -ne $ExpectedTaskRevision){throw 'Deployment-validation abandonment task revision changed.'}
    $workflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId)
    if($workflows.Count -ne 1 -or [string]$workflows[0].taskId -cne $TaskId){throw 'Deployment-validation abandonment workflow identity mismatch.'}
    $ops=@($task.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId);if($ops.Count -ne 1){throw 'Deployment-validation abandonment operation identity is not unique.'};$op=$ops[0]
    if([string]$op.TaskId -cne $TaskId -or [string]$op.WorkflowId -cne $WorkflowId){throw 'Deployment-validation abandonment binding mismatch.'}
    if([string]$op.RequestDisposition -notin @('transmitting','unknown') -or $op.Response){throw 'Only an unresolved ambiguous deployment-validation operation can be abandoned.'}
    if([long]$op.TransmittingTaskRevision -ne $ExpectedTaskRevision){throw 'Deployment-validation abandonment transmission revision mismatch.'}
    if($op.PSObject.Properties.Name -contains 'RequestId' -and ![string]::IsNullOrWhiteSpace([string]$op.RequestId)){throw 'Request-bound deployment validation must use authoritative reconciliation, not legacy abandonment.'}
    foreach($n in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){if($task.PSObject.Properties.Name -contains $n -and $task.$n){throw 'Deployment-validation abandonment found Tara execution state.'}}
    $revit=if($RevitProcessProvider){@(& $RevitProcessProvider)}else{@(Get-Process Revit -ErrorAction SilentlyContinue)};if(@($revit).Count){throw 'Deployment-validation abandonment requires Revit to be stopped.'}
    $workflow=$workflows[0];$e=$workflow.qaBuildEvidence
    if(!$e -or [string]$e.BuildRequestId -cne [string]$op.BuildRequestId -or [string]$e.CandidateSourceCommit -cne [string]$op.CandidateSourceCommit -or [string]$e.ArtifactSha256 -ine [string]$op.CandidateSha256){throw 'Deployment-validation abandonment candidate evidence mismatch.'}
    $sourceFiles=@('QaLaunchAgent\NamedPipeServer.cs','QaLaunchAgent\LaunchCoordinator.cs','QaLaunchAgent\StagingAdapter.cs','AgentOrchestration\Invoke-RepatoQaDeploymentValidation.ps1','AgentOrchestration\Repato.QaAddinDeployment.psm1');$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$sourceHashes=[ordered]@{};foreach($relative in $sourceFiles){$path=[IO.Path]::GetFullPath((Join-Path $repo $relative));if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Audited validation source is missing: $relative"};$sourceHashes[$relative]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
    $audit=[pscustomobject][ordered]@{SchemaVersion=1;Outcome='AbandonedUnresolved';SuccessClaimed=$false;OriginalDisposition=[string]$op.RequestDisposition;LegacyRequestIdMissing=$true;ResponsePresent=$false;ValidationPathReadOnlyConfirmed=$true;DeploymentMutationPerformed=$false;RevitLaunched=$false;Reason=$Reason;SourceSha256=$sourceHashes;RecordedUtc=Get-RepatoUtc}
    if($DryRun -or !$PSCmdlet.ShouldProcess("$TaskId/$OperationId",'Terminally abandon unresolved read-only deployment validation')){return [pscustomobject]@{Status='DryRun';TaskId=$TaskId;WorkflowId=$WorkflowId;OperationId=$OperationId;ExpectedTaskRevision=$ExpectedTaskRevision;NewDisposition='abandoned';Audit=$audit;FreshValidationPermittedAfterApply=$false;SideEffectsPerformed=$false}}
    $result=Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)$t=Find-RepatoTask $d $TaskId;if([long]$t.revision -ne $ExpectedTaskRevision){throw 'Deployment-validation abandonment compare-and-swap revision changed.'};$x=@($t.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId);if($x.Count -ne 1 -or [string]$x[0].RequestDisposition -notin @('transmitting','unknown') -or $x[0].Response -or [long]$x[0].TransmittingTaskRevision -ne $ExpectedTaskRevision -or ($x[0].PSObject.Properties.Name -contains 'RequestId' -and ![string]::IsNullOrWhiteSpace([string]$x[0].RequestId))){throw 'Deployment-validation abandonment compare-and-swap failed.'};$x[0].RequestDisposition='abandoned';$x[0]|Add-Member NoteProperty TerminalStatus 'AbandonedUnresolved' -Force;$x[0]|Add-Member NoteProperty AbandonmentEvidence $audit -Force;$x[0]|Add-Member NoteProperty AbandonedUtc (Get-RepatoUtc) -Force;Add-RepatoHistory $t 'deployment-validation-abandoned' 'Maya' "operation=$OperationId; outcome=AbandonedUnresolved; success=false";$x[0]}
    [pscustomobject]@{Status='AbandonedUnresolved';TaskId=$TaskId;WorkflowId=$WorkflowId;OperationId=$OperationId;PreviousDisposition=$audit.OriginalDisposition;NewDisposition=$result.RequestDisposition;TaskRevision=([long]$ExpectedTaskRevision+1);SuccessClaimed=$false;EvidenceRetained=$true;FreshValidationPermittedAfterApply=$true;RevitLaunched=$false;SideEffectsPerformed=$true}
}
function Set-MayaQaDeploymentValidationOutcomeUnknown {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$OperationId,
        [Parameter(Mandatory)][string]$RequestId,[Parameter(Mandatory)][long]$ExpectedTaskRevision,
        [Parameter(Mandatory)][string]$ReplayLedgerPath,[Parameter(Mandatory)][int]$AgentProcessId,
        [Parameter(Mandatory)][DateTime]$AgentProcessStartTime,[Parameter(Mandatory)][object]$HealthResponse,
        [Parameter(Mandatory)][DateTimeOffset]$HealthObservedUtc,[scriptblock]$AgentProcessProvider,[scriptblock]$RevitProcessProvider,[switch]$DryRun
    )
    $parsed=[guid]::Empty;if(![guid]::TryParse($RequestId,[ref]$parsed)){throw 'Outcome-unknown request identity is invalid.'}
    if(!$HealthResponse -or $HealthResponse.Operation -cne 'health' -or !$HealthResponse.Ready -or !$HealthResponse.UserInteractive -or $HealthResponse.User -ine 'RAMSAI\RepatoQA' -or $HealthResponse.Sid -ine 'S-1-5-21-1031246752-3872016183-2454652381-1015'){throw 'Fresh correlated Launch Agent health evidence is required.'}
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    if(!$task -or [long]$task.revision -ne $ExpectedTaskRevision){throw 'Outcome-unknown task revision changed.'}
    $workflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId);if($workflows.Count -ne 1 -or [string]$workflows[0].taskId -cne $TaskId){throw 'Outcome-unknown workflow binding mismatch.'}
    $ops=@($task.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId);if($ops.Count -ne 1){throw 'Outcome-unknown operation is not unique.'};$op=$ops[0]
    $lastHistory=@($task.history|Sort-Object timestampUtc)[-1];$transmitEvent=($lastHistory.event -ceq 'deployment-validation-transmitting' -and [string]$lastHistory.details -match [regex]::Escape([string]$op.OperationId));$workflowEvent=($lastHistory.event -ceq 'deployment-workflow-mutated' -and [string]$lastHistory.details -ceq $WorkflowId)
    if([string]$op.RequestId -cne $RequestId -or [string]$op.RequestDisposition -notin @('transmitting','unknown') -or $op.Response -or (($transmitEvent -and [long]$op.TransmittingTaskRevision -ne $ExpectedTaskRevision) -or ($workflowEvent -and [long]$op.TransmittingTaskRevision -ne ($ExpectedTaskRevision-1)) -or (!$transmitEvent -and !$workflowEvent))){throw 'Only the exact transmitted response-missing request can become outcome-unknown.'}
    if([DateTimeOffset]::Parse($lastHistory.timestampUtc) -lt [DateTimeOffset]::Parse($op.CreatedUtc)){throw 'Task changed after transmission outside the bound validation or workflow.'}
    if($HealthObservedUtc -lt [DateTimeOffset]::Parse($op.CreatedUtc)){throw 'Health observation predates the ambiguous request.'}
    foreach($n in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){if($task.PSObject.Properties.Name -contains $n -and $task.$n){throw 'Outcome-unknown recovery found Tara execution state.'}}
    $e=$workflows[0].qaBuildEvidence;if(!$e -or [string]$e.BuildRequestId -cne [string]$op.BuildRequestId -or [string]$e.CandidateSourceCommit -cne [string]$op.CandidateSourceCommit -or [string]$e.ArtifactSha256 -ine [string]$op.CandidateSha256 -or $e.DeploymentValidation){throw 'Outcome-unknown candidate binding mismatch.'}
    $revit=if($RevitProcessProvider){@(& $RevitProcessProvider)}else{@(Get-Process Revit -ErrorAction SilentlyContinue)};if(@($revit).Count){throw 'Outcome-unknown recovery requires Revit to be stopped.'}
    $agent=@();if($AgentProcessProvider){$agent=@(& $AgentProcessProvider $AgentProcessId)}else{$agent=@(Get-Process -Id $AgentProcessId -ErrorAction Stop)};if(@($agent).Count -ne 1 -or $agent[0].ProcessName -cne 'Repato.QaLaunchAgent' -or $agent[0].Id -ne $AgentProcessId -or $agent[0].StartTime -ne $AgentProcessStartTime){throw 'Launch Agent process identity changed since health probe.'}
    $ledgerFull=[IO.Path]::GetFullPath($ReplayLedgerPath);if(!(Test-Path -LiteralPath $ledgerFull -PathType Leaf)){throw 'Launch Agent replay ledger is missing.'};$raw=Get-Content -LiteralPath $ledgerFull -Raw;$ledger=$raw|ConvertFrom-Json
    if(@($ledger|Where-Object {[string]$_.RequestId -ceq $RequestId}).Count){throw 'Request now has a replay receipt; use bound response reconciliation.'}
    $audit=[pscustomobject][ordered]@{SchemaVersion=1;Outcome='OutcomeUnknown';SuccessClaimed=$false;RequestId=$RequestId;OperationId=$OperationId;ReplayLedgerPath=$ledgerFull;ReplayLedgerSha256=(Get-FileHash -LiteralPath $ledgerFull -Algorithm SHA256).Hash;MatchingReceiptCount=0;HealthResponse=$HealthResponse;HealthObservedUtc=$HealthObservedUtc.ToString('O');AgentProcessId=$AgentProcessId;AgentProcessStartTime=$AgentProcessStartTime.ToString('O');ObservedUtc=(Get-Date).ToUniversalTime().ToString('O');AutomaticRetryPermitted=$false;RevitLaunched=$false}
    if($DryRun -or !$PSCmdlet.ShouldProcess("$TaskId/$OperationId",'Terminally record deployment-validation outcome unknown')){return [pscustomobject]@{Status='DryRun';Audit=$audit;SideEffectsPerformed=$false}}
    $result=Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)$t=Find-RepatoTask $d $TaskId;if([long]$t.revision -ne $ExpectedTaskRevision){throw 'Outcome-unknown compare-and-swap revision changed.'};$x=@($t.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId);if($x.Count -ne 1 -or [string]$x[0].RequestId -cne $RequestId -or [string]$x[0].RequestDisposition -notin @('transmitting','unknown') -or $x[0].Response){throw 'Outcome-unknown compare-and-swap binding changed.'};$x[0].RequestDisposition='outcome-unknown';$x[0]|Add-Member NoteProperty TerminalStatus 'OutcomeUnknown' -Force;$x[0]|Add-Member NoteProperty OutcomeUnknownEvidence $audit -Force;$x[0]|Add-Member NoteProperty CompletedUtc (Get-RepatoUtc) -Force;Add-RepatoHistory $t 'deployment-validation-outcome-unknown' 'Maya' "operation=$OperationId; request=$RequestId; success=false; retry=false";$x[0]}
    [pscustomobject]@{Status='OutcomeUnknown';OperationId=$OperationId;RequestId=$RequestId;EvidenceRetained=$true;SuccessClaimed=$false;OldRequestReusePermitted=$false;SideEffectsPerformed=$true}
}
function Fail-MayaQaBoundDeploymentValidationWithoutResponse {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$OperationId,
        [Parameter(Mandatory)][string]$RequestId,[Parameter(Mandatory)][long]$ExpectedTaskRevision,
        [Parameter(Mandatory)][string]$ObservedFailure,[Parameter(Mandatory)][string]$ReplayLedgerPath,
        [scriptblock]$RevitProcessProvider,[switch]$DryRun
    )
    if([string]::IsNullOrWhiteSpace($ObservedFailure)){throw 'Observed deployment-validation failure is required.'}
    $parsed=[guid]::Empty;if(![guid]::TryParse($RequestId,[ref]$parsed)){throw 'Bound deployment-validation request identity is invalid.'}
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;if(!$task){throw 'Bound deployment-validation task was not found.'}
    if([long]$task.revision -ne $ExpectedTaskRevision){throw 'Bound deployment-validation task revision changed.'}
    $workflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId);if($workflows.Count -ne 1 -or [string]$workflows[0].taskId -cne $TaskId){throw 'Bound deployment-validation workflow identity mismatch.'}
    $ops=@($task.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId);if($ops.Count -ne 1){throw 'Bound deployment-validation operation identity is not unique.'};$op=$ops[0]
    if([string]$op.TaskId -cne $TaskId -or [string]$op.WorkflowId -cne $WorkflowId -or [string]$op.RequestId -cne $RequestId){throw 'Bound deployment-validation operation binding mismatch.'}
    if([string]$op.RequestDisposition -notin @('transmitting','unknown') -or $op.Response -or [long]$op.TransmittingTaskRevision -ne $ExpectedTaskRevision){throw 'Only a response-missing transmitted deployment validation can be terminally failed.'}
    foreach($n in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){if($task.PSObject.Properties.Name -contains $n -and $task.$n){throw 'Bound deployment-validation failure recovery found Tara execution state.'}}
    $e=$workflows[0].qaBuildEvidence;if(!$e -or [string]$e.BuildRequestId -cne [string]$op.BuildRequestId -or [string]$e.CandidateSourceCommit -cne [string]$op.CandidateSourceCommit -or [string]$e.ArtifactSha256 -ine [string]$op.CandidateSha256 -or $e.DeploymentValidation){throw 'Bound deployment-validation failure candidate evidence mismatch.'}
    $revit=if($RevitProcessProvider){@(& $RevitProcessProvider)}else{@(Get-Process Revit -ErrorAction SilentlyContinue)};if(@($revit).Count){throw 'Bound deployment-validation failure recovery requires Revit to be stopped.'}
    $ledgerFull=[IO.Path]::GetFullPath($ReplayLedgerPath);if(!(Test-Path -LiteralPath $ledgerFull -PathType Leaf)){throw 'Launch Agent replay ledger is missing.'}
    $ledgerRaw=Get-Content -LiteralPath $ledgerFull -Raw;$ledger=$ledgerRaw|ConvertFrom-Json;$receipts=@($ledger|Where-Object {[string]$_.RequestId -ceq $RequestId});if($receipts.Count -ne 1){throw 'Launch Agent replay ledger does not contain exactly one bound receipt.'}
    $receipt=$receipts[0];if([string]$receipt.RunId -cne $RequestId -or [string]$receipt.PayloadHash -notmatch '^[A-Fa-f0-9]{64}$' -or [string]::IsNullOrWhiteSpace([string]$receipt.SeenUtc)){throw 'Launch Agent replay ledger receipt is structurally invalid.'}
    $audit=[pscustomobject][ordered]@{SchemaVersion=1;Outcome='FailedResponseUnavailable';SuccessClaimed=$false;RequestId=$RequestId;LedgerReceipt=$receipt;ReplayLedgerPath=$ledgerFull;ReplayLedgerSha256=(Get-FileHash -LiteralPath $ledgerFull -Algorithm SHA256).Hash;ObservedFailure=$ObservedFailure;ResponsePresent=$false;AutomaticRetryPermitted=$false;DeploymentValidationPassed=$false;RevitLaunched=$false;RecordedUtc=Get-RepatoUtc}
    if($DryRun -or !$PSCmdlet.ShouldProcess("$TaskId/$OperationId",'Terminally fail request-bound deployment validation without a persisted response')){return [pscustomobject]@{Status='DryRun';TaskId=$TaskId;OperationId=$OperationId;RequestId=$RequestId;ExpectedTaskRevision=$ExpectedTaskRevision;NewDisposition='completed-failed';Audit=$audit;SideEffectsPerformed=$false}}
    $result=Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)$t=Find-RepatoTask $d $TaskId;if([long]$t.revision -ne $ExpectedTaskRevision){throw 'Bound deployment-validation failure compare-and-swap revision changed.'};$x=@($t.deploymentValidationOperations|Where-Object OperationId -ceq $OperationId);if($x.Count -ne 1 -or [string]$x[0].RequestId -cne $RequestId -or [string]$x[0].RequestDisposition -notin @('transmitting','unknown') -or $x[0].Response -or [long]$x[0].TransmittingTaskRevision -ne $ExpectedTaskRevision){throw 'Bound deployment-validation failure compare-and-swap failed.'};$x[0].RequestDisposition='completed-failed';$x[0]|Add-Member NoteProperty TerminalStatus 'FailedResponseUnavailable' -Force;$x[0]|Add-Member NoteProperty ValidationStatus 'failed' -Force;$x[0]|Add-Member NoteProperty FailureReason $ObservedFailure -Force;$x[0]|Add-Member NoteProperty FailureEvidence $audit -Force;$x[0]|Add-Member NoteProperty CompletedUtc (Get-RepatoUtc) -Force;Add-RepatoHistory $t 'deployment-validation-failed-response-unavailable' 'Maya' "operation=$OperationId; request=$RequestId; success=false; retry=false";$x[0]}
    [pscustomobject]@{Status='FailedResponseUnavailable';TaskId=$TaskId;WorkflowId=$WorkflowId;OperationId=$OperationId;RequestId=$RequestId;NewDisposition=$result.RequestDisposition;TaskRevision=([long]$ExpectedTaskRevision+1);SuccessClaimed=$false;EvidenceRetained=$true;AutomaticRetryPermitted=$false;RevitLaunched=$false;SideEffectsPerformed=$true}
}
function Invoke-MayaQaCanonicalFrozenCandidateStagingValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$TestId,
        [Parameter(Mandatory)][string]$ExpectedBuildRequestId,
        [Parameter(Mandatory)][string]$ExpectedCandidateSourceCommit,
        [Parameter(Mandatory)][string]$ExpectedCandidateSha256,
        [Parameter(Mandatory)][string]$ExpectedRunnerManifestPath,
        [Parameter(Mandatory)][string]$ExpectedRunnerManifestSha256,
        [switch]$FreshApprovalAfterDeployment,
        [scriptblock]$HealthInvoker,
        [scriptblock]$PreflightInvoker,
        [scriptblock]$StagingInvoker,
        [scriptblock]$DeploymentValidationInvoker,
        [scriptblock]$PersistenceInvoker,
        [scriptblock]$RevitProcessProvider
    )
    $state={
        $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
        if(!$task){throw 'Canonical task was not found.'}
        $workflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId)
        if($workflows.Count -ne 1 -or $workflows[0].taskId -cne $TaskId){throw 'Canonical task/workflow identity mismatch.'}
        [pscustomobject]@{Task=$task;Workflow=$workflows[0]}
    }
    $s=& $state;$w=$s.Workflow;$e=$w.qaBuildEvidence
    if($w.qaBuildStatus -cne 'succeeded'){throw 'Authenticated build status is not succeeded.'}
    if(!$e -or $e.BuildRequestId -cne $ExpectedBuildRequestId -or $e.SourceCommit -cne $ExpectedCandidateSourceCommit -or $e.CandidateSourceCommit -cne $ExpectedCandidateSourceCommit){throw 'Authenticated build evidence identity is invalid.'}
    if($e.EvidenceSource -cne 'FrozenCandidate' -or [string]::IsNullOrWhiteSpace([string]$e.CandidateProvenancePath)){throw 'Frozen candidate evidence is missing or not adopted.'}
    if($e.ArtifactSha256 -ine $ExpectedCandidateSha256){throw 'Frozen candidate hash is invalid.'}
    if($e.PSObject.Properties.Name -contains 'DeploymentValidation' -and $e.DeploymentValidation){throw 'Historical deployment validation evidence is already present.'}
    $approval=@($s.Task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})
    if($FreshApprovalAfterDeployment){if($approval.Count){throw 'Fresh candidate staging cannot reuse an existing QA approval.'}}elseif($approval.Count -ne 1){throw 'QA approval is not exactly pending.'}
    if(Test-MayaQaTaskHasTaraExecutionState -Task $s.Task){throw 'Tara state already exists.'}
    $revit=if($RevitProcessProvider){@(& $RevitProcessProvider)}else{@(Get-Process Revit -ErrorAction SilentlyContinue)}
    if(@($revit).Count){throw 'Revit is running.'}
    $null=Resolve-MayaQaSourceRunnerManifestEvidence -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $QaWorkflowId -TestId $TestId
    $candidate=New-MayaQaPersistedCandidateEvidence -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $QaWorkflowId -TestId $TestId
    if($candidate.RunnerManifestSha256 -ine $ExpectedRunnerManifestSha256){throw 'Authenticated runner source evidence is invalid.'}
    $health=if($HealthInvoker){& $HealthInvoker}else{Invoke-MayaQaLaunchAgentHealth}
    if(!$health.Ready -or $health.User -ine 'RAMSAI\RepatoQA' -or $health.SID -cne 'S-1-5-21-1031246752-3872016183-2454652381-1015' -or [int]$health.SessionId -le 0 -or !$health.UserInteractive){throw 'Launch Agent health contract failed.'}
    $pre=if($PreflightInvoker){
        & $PreflightInvoker $candidate $TaskId $WorkflowId $QaWorkflowId $TestId $ExpectedCandidateSourceCommit $ExpectedCandidateSha256
    }else{
        Invoke-MayaQaLaunchAgentPreflightReadonly -CandidateEvidence $candidate -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $QaWorkflowId -TestId $TestId -CandidateCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256
    }
    if($pre.ExecutionIdentity -ine 'RAMSAI\RepatoQA' -or [IO.Path]::GetFullPath($pre.RunnerManifestPath) -ine [IO.Path]::GetFullPath($ExpectedRunnerManifestPath) -or $pre.ExpectedRunnerManifestSha256 -ine $ExpectedRunnerManifestSha256){throw 'Launch Agent preflight contract failed.'}
    if(!$pre.Succeeded){
        $failed=@($pre.Checks|Where-Object {!$_.passed})
        if($failed.Count -ne 1 -or $failed[0].name -cne 'deployed-candidate-dll-integrity' -or ([string]$failed[0].detail -notmatch ('expected='+[regex]::Escape($ExpectedCandidateSha256)))){throw 'Launch Agent preflight contract failed.'}
    }
    $stage=if($StagingInvoker){& $StagingInvoker $candidate}else{Invoke-MayaQaLaunchAgentFrozenCandidateStaging -CandidateCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256 -QaWorkflowId $QaWorkflowId -TestId $TestId -CandidateEvidence $candidate -TaskId $TaskId -WorkflowId $WorkflowId}
    if(!$stage.succeeded -or $stage.candidateCommit -cne $ExpectedCandidateSourceCommit -or $stage.candidateSha256 -ine $ExpectedCandidateSha256 -or $stage.qaWorkflowId -cne $QaWorkflowId -or $stage.testId -cne $TestId -or !$stage.isolationPassed -or ($stage.PSObject.Properties.Name -contains 'taskId' -and $stage.taskId -cne $TaskId) -or ($stage.PSObject.Properties.Name -contains 'workflowId' -and $stage.workflowId -cne $WorkflowId)){throw 'Fresh staging response failed canonical validation.'}
    $post=if($PreflightInvoker){
        & $PreflightInvoker $candidate $TaskId $WorkflowId $QaWorkflowId $TestId $ExpectedCandidateSourceCommit $ExpectedCandidateSha256
    }else{
        Invoke-MayaQaLaunchAgentPreflightReadonly -CandidateEvidence $candidate -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $QaWorkflowId -TestId $TestId -CandidateCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256
    }
    $postCandidateMismatch=Test-MayaQaPostStageCandidateHashMismatch -Preflight $post -ExpectedCandidateSha256 $ExpectedCandidateSha256
    if((!$post.Succeeded -and !$postCandidateMismatch) -or $post.ExecutionIdentity -ine 'RAMSAI\RepatoQA' -or [IO.Path]::GetFullPath($post.RunnerManifestPath) -ine [IO.Path]::GetFullPath($ExpectedRunnerManifestPath) -or $post.ExpectedRunnerManifestSha256 -ine $ExpectedRunnerManifestSha256){throw 'Post-staging Launch Agent preflight contract failed.'}
    $currentTask=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    $operation=New-MayaQaDeploymentValidationOperation -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -ExpectedTaskRevision ([long]$currentTask.revision) -BuildRequestId $ExpectedBuildRequestId -CandidateSourceCommit $ExpectedCandidateSourceCommit -CandidateSha256 $ExpectedCandidateSha256 -QaWorkflowId $QaWorkflowId -TestId $TestId
    $requestInvoker={param($pendingOperation)if($DeploymentValidationInvoker){& $DeploymentValidationInvoker $candidate $pendingOperation}else{Invoke-MayaQaLaunchAgentDeploymentValidation -CandidateCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256 -QaWorkflowId $QaWorkflowId -TestId $TestId -CandidateEvidence $candidate -TaskId $TaskId -WorkflowId $WorkflowId -RequestId $pendingOperation.RequestId}}.GetNewClosure()
    $validation=(Continue-MayaQaDeploymentValidation -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -OperationId $operation.OperationId -ExpectedTaskRevision ([long]$operation.ExpectedTaskRevision) -ExpectedBuildRequestId $ExpectedBuildRequestId -ExpectedCandidateSourceCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256 -QaWorkflowId $QaWorkflowId -TestId $TestId -RequestInvoker $requestInvoker).Validation
    if(!$validation.succeeded -or $validation.qaWorkflowId -cne $QaWorkflowId -or $validation.testId -cne $TestId -or $validation.candidateSha256 -ine $ExpectedCandidateSha256 -or !$validation.isolationPassed -or ($validation.PSObject.Properties.Name -contains 'taskId' -and $validation.taskId -cne $TaskId) -or ($validation.PSObject.Properties.Name -contains 'workflowId' -and $validation.workflowId -cne $WorkflowId) -or ($validation.PSObject.Properties.Name -contains 'runnerManifestPath' -and [IO.Path]::GetFullPath($validation.runnerManifestPath) -ine [IO.Path]::GetFullPath($ExpectedRunnerManifestPath)) -or ($validation.PSObject.Properties.Name -contains 'runnerManifestSha256' -and $validation.runnerManifestSha256 -ine $ExpectedRunnerManifestSha256)){throw 'Deployment validation response failed canonical validation.'}
    $persisted=if($PersistenceInvoker){& $PersistenceInvoker $validation $candidate}else{Invoke-MayaQaFrozenCandidateEvidence -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $QaWorkflowId -CandidateDirectory $e.CandidateDirectory -CandidateDllPath $e.ArtifactPath -ExpectedSha256 $ExpectedCandidateSha256 -ExpectedSourceCommit $ExpectedCandidateSourceCommit -DeploymentEvidence $validation}
    $after=& $state;$afterE=$after.Workflow.qaBuildEvidence
    $pendingAfter=@($after.Task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'}).Count
    if($afterE.BuildRequestId -cne $ExpectedBuildRequestId -or $afterE.CandidateSourceCommit -cne $ExpectedCandidateSourceCommit -or $afterE.ArtifactSha256 -ine $ExpectedCandidateSha256 -or !$afterE.DeploymentValidation -or ($FreshApprovalAfterDeployment -and $pendingAfter -ne 0) -or (!$FreshApprovalAfterDeployment -and $pendingAfter -ne 1)){throw 'Persisted deployment evidence failed canonical verification.'}
    $revitAfter=if($RevitProcessProvider){@(& $RevitProcessProvider)}else{@(Get-Process Revit -ErrorAction SilentlyContinue)};if(@($revitAfter).Count){throw 'Revit started during boundary.'}
    [pscustomobject]@{Succeeded=$true;TaskId=$TaskId;WorkflowId=$WorkflowId;BuildRequestId=$ExpectedBuildRequestId;QaWorkflowId=$QaWorkflowId;TestId=$TestId;CandidateSourceCommit=$ExpectedCandidateSourceCommit;CandidateSha256=$ExpectedCandidateSha256;RunnerManifestPath=$ExpectedRunnerManifestPath;RunnerManifestSha256=$ExpectedRunnerManifestSha256;Staging=$stage;DeploymentValidation=$validation;PersistedEvidence=$persisted;Approval=$(if($FreshApprovalAfterDeployment){'not-requested'}else{'pending'});TaraState='absent';RevitLaunched=$false;StoppedBeforeApproval=$true;StoppedBeforeTara=$true;StoppedBeforeRevit=$true}
}

function New-MayaQaPersistentPreBuildRequest {
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$UserRequest,
        [string]$SourceBranch='main',
        [string]$ProjectPath='Forma.RevitConnector.csproj',
        [Parameter(Mandatory)][object]$AuthenticatedBuildSource
    )
    $foundation=New-MayaQaRequestFoundation -StoreRoot $StoreRoot -UserRequest $UserRequest -SourceBranch $SourceBranch -ProjectPath $ProjectPath -QaWorkflowId (Resolve-MayaQaRequestWorkflow $UserRequest) -AuthenticatedBuildSource $AuthenticatedBuildSource
    $taskData=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $taskData $foundation.TaskId
    Update-RepatoTask $StoreRoot $foundation.TaskId 'in-progress' 'qa' 'Tara' $null $null|Out-Null
    Update-RepatoTask $StoreRoot $foundation.TaskId 'passed' 'qa' 'Tara' $null $null|Out-Null
    Request-RepatoTaskApproval $StoreRoot $foundation.TaskId 'qa-run' 'maya'|Out-Null
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $foundation.TaskId
    $approval=@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})[-1]
    if(!$approval){throw 'Persisted qa-run approval request is missing requestId.'}
    [pscustomobject]@{Success=$false;Mode='Real';TaskId=$foundation.TaskId;WorkflowId=$foundation.WorkflowId;QaWorkflowId=$foundation.QaWorkflowId;NativeTestId=$foundation.NativeTestId;Stage='approval-required';NextOperation='Resolve-RepatoTaskApproval';QaApprovalId=$approval.requestId;QaApprovalStatus=$approval.status;BuildRequest=$foundation.BuildRequest;Intake=$foundation.Intake;SideEffectsPerformed=$true;Error=$null}
}

function Invoke-MayaQaRequest {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$UserRequest,[string]$SourceBranch='main',[string]$ProjectPath,
        [ValidateSet('Build','FrozenCandidate')][string]$ArtifactMode='Build',[string]$CandidateDirectory,[string]$CandidateDllPath,[string]$RuntimeRoot,[string]$FixturePreparationResultPath,
        [string]$ExpectedCandidateSha256,[string]$ExpectedCandidateSourceCommit,[object]$AuthenticatedBuildSource,[switch]$StageFrozenCandidateForQa,[switch]$ValidateExistingDeployment,[scriptblock]$QaStagingInvoker,[scriptblock]$DeploymentValidationInvoker,[scriptblock]$HealthInvoker,[scriptblock]$PreflightInvoker,[scriptblock]$RevitProcessProvider,[switch]$DryRun)
    $qaId=Resolve-MayaQaRequestWorkflow $UserRequest
    $def=Get-MayaQaWorkflowDefinition $qaId
    $qaStaging=$null
    if($ArtifactMode -ceq 'FrozenCandidate'){
        foreach($required in @(@('CandidateDirectory',$CandidateDirectory),@('ExpectedCandidateSha256',$ExpectedCandidateSha256),@('ExpectedCandidateSourceCommit',$ExpectedCandidateSourceCommit))){if([string]::IsNullOrWhiteSpace([string]$required[1])){throw "FrozenCandidate mode requires $($required[0])."}}
        $null=Test-MayaQaFrozenCandidate -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedSha256 $ExpectedCandidateSha256 -ExpectedSourceCommit $ExpectedCandidateSourceCommit -QaWorkflowId $qaId
    }
    $taskId='task-'+[guid]::NewGuid().ToString('N');$workflowId='workflow-'+[guid]::NewGuid().ToString('N');$runId=[guid]::NewGuid().ToString('N')
    if($DryRun){return [pscustomobject]@{Success=$true;Mode='DryRun';TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId=$qaId;RunId=$runId;FixtureId=$def.FixtureId;NativeTestId=(Get-MayaQaNativeTestId $def);QaStaging=$qaStaging;Stages=@('frozen-candidate-validation','qa-only-staging','isolation','intake','build-request','build-execute','handoff','tara-execute','report-verify','complete','receipt','dashboard');SideEffectsPerformed=$false;Error=$null}}
    $foundation=New-MayaQaRequestFoundation -StoreRoot $StoreRoot -UserRequest $UserRequest -SourceBranch $SourceBranch -ProjectPath $ProjectPath -QaWorkflowId $qaId -AuthenticatedBuildSource $AuthenticatedBuildSource
    $taskId=$foundation.TaskId;$workflowId=$foundation.WorkflowId;$intake=$foundation.Intake;$buildRequest=$foundation.BuildRequest
    $deploymentEvidence=$null
    if($ArtifactMode -ceq 'FrozenCandidate'){
        $null=Bind-MayaQaFrozenCandidateBuildEvidence -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedSha256 $ExpectedCandidateSha256 -ExpectedSourceCommit $ExpectedCandidateSourceCommit
        $null=Resolve-MayaQaSourceRunnerManifestEvidence -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -TestId (Get-MayaQaNativeTestId $def)
        $build=Invoke-MayaQaFrozenCandidateEvidence -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedSha256 $ExpectedCandidateSha256 -ExpectedSourceCommit $ExpectedCandidateSourceCommit -DeploymentEvidence $deploymentEvidence
    }else{
        $build=Invoke-MayaQaBuildExecute -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -SourceBranch $SourceBranch -ProjectPath $ProjectPath
    }
    if($build.BuildStatus -cne 'succeeded' -or [string]::IsNullOrWhiteSpace($build.ArtifactPath) -or [string]::IsNullOrWhiteSpace($build.ArtifactSha256) -or !(Test-Path -LiteralPath $build.ArtifactPath -PathType Leaf)){throw 'Neil build did not produce a verified artifact.'}
    if((Get-FileHash -LiteralPath $build.ArtifactPath -Algorithm SHA256).Hash -ine $build.ArtifactSha256){throw 'Neil artifact SHA-256 verification failed.'}
    if([string]::IsNullOrWhiteSpace($build.ManifestPath) -or (Get-FileHash -LiteralPath $build.ManifestPath -Algorithm SHA256).Hash -ine $build.ManifestSha256){throw 'Neil artifact manifest SHA-256 verification failed.'}
    if($ArtifactMode -ceq 'FrozenCandidate' -and ($StageFrozenCandidateForQa -or $ValidateExistingDeployment)){
        if(!$DryRun -and ($StageFrozenCandidateForQa -or $ValidateExistingDeployment)){
            $null=Resolve-MayaQaSourceRunnerManifestEvidence -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -TestId (Get-MayaQaNativeTestId $def)
            $candidateEvidence=New-MayaQaPersistedCandidateEvidence -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -TestId (Get-MayaQaNativeTestId $def)
            $nativeTestId=Get-MayaQaNativeTestId $def
            $runnerSource=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\QA\Repato.CreatePlanViews.TestRunner.addin'));$runnerHash=(Get-FileHash -LiteralPath $runnerSource -Algorithm SHA256).Hash;$runnerPath='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin'
            $stageInvoker={param($candidate)if($QaStagingInvoker){$x=& $QaStagingInvoker $CandidateDirectory $ExpectedCandidateSha256 $ExpectedCandidateSourceCommit $qaId $nativeTestId $false $taskId $workflowId $build;[pscustomobject]@{succeeded=[bool]$x.Success;candidateCommit=$x.CandidateSourceCommit;candidateSha256=$x.CandidateSha256;qaWorkflowId=$qaId;testId=$nativeTestId;isolationPassed=[bool]$x.Isolation.Allowed;taskId=$taskId;workflowId=$workflowId}}else{Invoke-MayaQaLaunchAgentFrozenCandidateStaging -CandidateCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256 -QaWorkflowId $qaId -TestId $nativeTestId -CandidateEvidence $candidate -TaskId $taskId -WorkflowId $workflowId}}
            $validationCallback={param($validationCandidate,$pendingOperation)if($DeploymentValidationInvoker){& $DeploymentValidationInvoker $ExpectedCandidateSourceCommit $ExpectedCandidateSha256 $qaId $nativeTestId $taskId $workflowId $build $validationCandidate $pendingOperation}else{Invoke-MayaQaLaunchAgentDeploymentValidation -CandidateCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256 -QaWorkflowId $qaId -TestId $nativeTestId -CandidateEvidence $validationCandidate -TaskId $taskId -WorkflowId $workflowId -RequestId $pendingOperation.RequestId}}.GetNewClosure()
            $canonical=Invoke-MayaQaCanonicalFrozenCandidateStagingValidation -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -TestId $nativeTestId -ExpectedBuildRequestId $buildRequest.BuildRequestId -ExpectedCandidateSourceCommit $ExpectedCandidateSourceCommit -ExpectedCandidateSha256 $ExpectedCandidateSha256 -ExpectedRunnerManifestPath $runnerPath -ExpectedRunnerManifestSha256 $runnerHash -FreshApprovalAfterDeployment -HealthInvoker $HealthInvoker -PreflightInvoker $PreflightInvoker -StagingInvoker $stageInvoker -DeploymentValidationInvoker $validationCallback -RevitProcessProvider $(if($RevitProcessProvider){$RevitProcessProvider}else{{ @() }})
            $deploymentEvidence=$canonical.DeploymentValidation
        }
    }
    $runTask=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $taskId
    $run=New-MayaQaRun -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId -RunId $runId -RuntimeRoot $RuntimeRoot -FixturePreparationResultPath $FixturePreparationResultPath -ExpectedTaskRevision ([long]$runTask.revision)
    $current=Get-DeployWorkflow $StoreRoot $taskId $workflowId; $taskData=Read-RepatoTaskStore $StoreRoot; $taskNow=Find-RepatoTask $taskData $taskId
    if(@($taskNow.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved'}).Count -eq 0){
        if(@($taskNow.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'}).Count -eq 0){
            $qaStage=Update-RepatoTask $StoreRoot $taskId 'in-progress' 'qa' 'Maya' $null $null -ExpectedTaskRevision ([long]$run.TaskRevision) -ExpectedWorkflowId $workflowId -ExpectedWorkflowRevision ([long]$run.WorkflowRevision) -ExpectedQaWorkflowId $qaId
            if($ArtifactMode -ceq 'FrozenCandidate' -and $deploymentEvidence){$approval=Request-MayaQaCanonicalExecutionApproval -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -BuildRequestId $buildRequest.BuildRequestId -ExpectedTaskRevision ([long]$qaStage.revision) -CandidateSourceCommit $ExpectedCandidateSourceCommit -CandidateSha256 $ExpectedCandidateSha256}
            else{Update-RepatoTask $StoreRoot $taskId 'passed' 'qa' 'Tara' $null $null|Out-Null;$null=Request-RepatoTaskApproval $StoreRoot $taskId 'qa-run' 'maya';$approval=@((Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $taskId).approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})[-1]}
        } else {throw 'Existing pending QA approval cannot be reused after candidate staging.'}
        if($null -eq $approval -or [string]::IsNullOrWhiteSpace([string]$approval.requestId)){throw 'Persisted qa-run approval request is missing requestId.'}
        return [pscustomobject]@{Success=$false;Mode='Real';TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId=$qaId;RunId=$runId;Stage='approval-required';NextOperation='Resolve-RepatoTaskApproval';QaApprovalId=$approval.requestId;QaApprovalStatus=$approval.status;QaStaging=$qaStaging;SideEffectsPerformed=$true;Error=$null}
    }
    $canonical=New-MayaQaCanonicalPreparation -StoreRoot $StoreRoot -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId $qaId
    $handoff=$canonical.Handoff
    $handoffPath=Join-Path (Join-Path $StoreRoot 'handoffs') ($handoff.HandoffId+'.json'); New-Item -ItemType Directory -Path (Split-Path $handoffPath -Parent) -Force | Out-Null
    $approvedTask=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $taskId;$approved=@($approvedTask.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved'})[-1]
    [ordered]@{StoreRoot=$StoreRoot;TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId=$qaId;RunId=$runId;HandoffId=$handoff.HandoffId;QaApprovalId=$approved.requestId;QaApprovalStatus=$approved.status;ModelPath=$handoff.ModelPath;SidecarPath=$handoff.SidecarPath;ArtifactPath=$handoff.ArtifactPath;ArtifactSha256=$handoff.ArtifactSha256;ManifestPath=$handoff.ManifestPath;ManifestSha256=$handoff.ManifestSha256} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $handoffPath -Encoding UTF8
    [pscustomobject]@{Success=$true;Mode='Real';TaskId=$taskId;WorkflowId=$workflowId;QaWorkflowId=$qaId;RunId=$runId;AttemptId=$canonical.Attempt.AttemptId;HandoffPath=$handoffPath;Stage='handoff-ready';Intake=$intake;BuildRequest=$buildRequest;Build=$build;Run=$run;Handoff=$handoff;CanonicalPreparation=$canonical;QaStaging=$qaStaging;SideEffectsPerformed=$true;Error=$null}
}

function Invoke-MayaQaCanonicalTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$UserRequest,
        [string]$SourceBranch = 'current',
        [string]$ProjectPath = 'Forma.RevitConnector.csproj',
        [ValidateSet('Build','FrozenCandidate')][string]$ArtifactMode='Build',
        [string]$CandidateDirectory,[string]$CandidateDllPath,[string]$ExpectedCandidateSha256,[string]$ExpectedCandidateSourceCommit,[object]$AuthenticatedBuildSource,[string]$FixturePreparationResultPath,
        [switch]$StageFrozenCandidateForQa,
        [scriptblock]$RequestInvoker,
        [scriptblock]$ExecutionRecordInvoker,
        [scriptblock]$ClaimInvoker,
        [scriptblock]$NativeCoreInvoker
    )

    # These delegates are test seams only. In production the existing Maya,
    # canonical preparation, claim, and native-core implementations remain
    # the defaults and retain ownership of their validation/state transitions.
    if ($RequestInvoker) {
        $request = & $RequestInvoker $StoreRoot $UserRequest $SourceBranch $ProjectPath
    } else {
        $request = Invoke-MayaQaRequest -StoreRoot $StoreRoot -UserRequest $UserRequest -SourceBranch $SourceBranch -ProjectPath $ProjectPath -ArtifactMode $ArtifactMode -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedCandidateSha256 $ExpectedCandidateSha256 -ExpectedCandidateSourceCommit $ExpectedCandidateSourceCommit -AuthenticatedBuildSource $AuthenticatedBuildSource -FixturePreparationResultPath $FixturePreparationResultPath -StageFrozenCandidateForQa:$StageFrozenCandidateForQa
    }
    if (!$request -or $request.Stage -notin @('handoff-ready','execution-ready')) {
        throw 'Canonical transaction requires an approved Tara handoff.'
    }

    $handoff = if ($request.PSObject.Properties.Name -contains 'Handoff') { $request.Handoff } else { $request }
    $taskData=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $taskData $request.TaskId
    if($task.PSObject.Properties.Name -notcontains 'mayaTaraAttempt' -or !$task.mayaTaraAttempt){throw 'Canonical persisted attempt is missing.'}
    $authoritativeAttempt=$task.mayaTaraAttempt
    foreach($n in 'TaskId','WorkflowId','QaWorkflowId','RunId'){if($authoritativeAttempt.PSObject.Properties.Name -notcontains $n){throw "Canonical persisted attempt is missing $n."};$actual=$authoritativeAttempt.$n;$expected=if($n -eq 'TaskId'){$request.TaskId}elseif($n -eq 'WorkflowId'){$request.WorkflowId}elseif($n -eq 'QaWorkflowId'){$request.QaWorkflowId}else{$request.RunId};if([string]$actual -cne [string]$expected){throw "Canonical persisted identity mismatch: $n"}}
    if([string]::IsNullOrWhiteSpace([string]$authoritativeAttempt.AttemptId) -or [string]$authoritativeAttempt.RunId -cne [string]$request.RunId){throw 'Canonical persisted attempt identity is missing or stale.'}
    if($handoff.PSObject.Properties.Name -contains 'AttemptId' -and ![string]::IsNullOrWhiteSpace([string]$handoff.AttemptId) -and [string]$handoff.AttemptId -cne [string]$authoritativeAttempt.AttemptId){throw 'Handoff AttemptId does not match the persisted canonical attempt.'}
    $workflow=Get-DeployWorkflow $StoreRoot $request.TaskId $request.WorkflowId
    $packet=if($task.PSObject.Properties.Name -contains 'mayaTaraQaPacket'){$task.mayaTaraQaPacket}else{$null}
    $evidence=if($workflow.PSObject.Properties.Name -contains 'qaBuildEvidence'){$workflow.qaBuildEvidence}else{$null}
    $fixturePath=if($packet -and $packet.PSObject.Properties.Name -contains 'FixturePath'){$packet.FixturePath}else{$null}
    $fixtureSha=if($packet -and $packet.PSObject.Properties.Name -contains 'FixtureSha256'){$packet.FixtureSha256}else{$workflow.qaFixtureSha256}
    $modelPath=if($packet -and $packet.PSObject.Properties.Name -contains 'ModelPath'){$packet.ModelPath}else{$workflow.qaModelPath}
    $modelSha=$null;if($modelPath -and (Test-Path -LiteralPath $modelPath -PathType Leaf)){$modelSha=(Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash}
    $runnerPath=if($evidence -and $evidence.PSObject.Properties.Name -contains 'RunnerManifestPath'){$evidence.RunnerManifestPath}elseif($handoff.PSObject.Properties.Name -contains 'RunnerManifestPath'){$handoff.RunnerManifestPath}elseif($packet -and $packet.PSObject.Properties.Name -contains 'RunnerManifestPath'){$packet.RunnerManifestPath}else{$null}
    $runnerSha=if($evidence -and $evidence.PSObject.Properties.Name -contains 'RunnerManifestSha256'){$evidence.RunnerManifestSha256}elseif($handoff.PSObject.Properties.Name -contains 'RunnerManifestSha256'){$handoff.RunnerManifestSha256}elseif($packet -and $packet.PSObject.Properties.Name -contains 'RunnerManifestSha256'){$packet.RunnerManifestSha256}else{$null}
    $validatedPath=if($evidence -and $evidence.PSObject.Properties.Name -contains 'ValidatedRunnerManifestPath'){$evidence.ValidatedRunnerManifestPath}elseif($handoff.PSObject.Properties.Name -contains 'ValidatedRunnerManifestPath'){$handoff.ValidatedRunnerManifestPath}else{$runnerPath}
    $isolation=if($evidence -and $evidence.PSObject.Properties.Name -contains 'Isolation'){$evidence.Isolation}elseif($handoff.PSObject.Properties.Name -contains 'Isolation'){$handoff.Isolation}else{$null}
    $preflight=[pscustomobject]@{TaskId=$request.TaskId;WorkflowId=$request.WorkflowId;QaWorkflowId=$request.QaWorkflowId;TestId=$(if($handoff.PSObject.Properties.Name -contains 'NativeTestId'){$handoff.NativeTestId}else{$packet.TestId});HandoffId=$handoff.HandoffId;AttemptId=$authoritativeAttempt.AttemptId;RunId=$request.RunId;ArtifactPath=$evidence.ArtifactPath;ArtifactSha256=$evidence.ArtifactSha256;CandidateDirectory=$evidence.CandidateDirectory;CandidateDllPath=$evidence.ArtifactPath;CandidateSha256=$evidence.ArtifactSha256;CandidateSourceCommit=$evidence.CandidateSourceCommit;FixturePath=$fixturePath;FixtureSha256=$fixtureSha;DisposableFixturePath=$modelPath;DisposableFixtureSha256=$modelSha;RunnerManifest=$runnerPath;RunnerManifestSha256=$runnerSha;ValidatedRunnerManifestPath=$validatedPath;ValidatedRunnerManifestSha256=$runnerSha;QaAddinRoot=$(if($evidence.PSObject.Properties.Name -contains 'QaAddinRoot'){$evidence.QaAddinRoot}else{$handoff.QaAddinRoot});Isolation=$isolation;RuntimeRoot=$authoritativeAttempt.RuntimeRoot;RequestExpiresUtc=$authoritativeAttempt.RequestExpiresUtc}
    $preparation=$packet.FixturePreparationEvidence;$preflight|Add-Member NoteProperty FixturePreparationEvidence $preparation -Force
    $missing=[Collections.Generic.List[string]]::new();foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','RunId','ArtifactPath','ArtifactSha256','CandidateDirectory','CandidateDllPath','CandidateSha256','CandidateSourceCommit','FixturePath','FixtureSha256','DisposableFixturePath','DisposableFixtureSha256','RunnerManifest','RunnerManifestSha256','ValidatedRunnerManifestPath','QaAddinRoot','RuntimeRoot','RequestExpiresUtc'){if([string]::IsNullOrWhiteSpace([string]$preflight.$n)){$missing.Add($n)}};if(!$preflight.Isolation){$missing.Add('Isolation')}else{foreach($n in 'PolicyPath','PolicySha256'){if([string]::IsNullOrWhiteSpace([string]$preflight.Isolation.$n)){$missing.Add("Isolation.$n")}};if(!$preflight.Isolation.Allowed){$missing.Add('Isolation.Allowed')}};if($missing.Count){throw ('Canonical transaction preflight contract invalid; missing or invalid: '+($missing -join ', '))};if(!(Test-Path -LiteralPath $preflight.FixturePath -PathType Leaf) -or (Get-FileHash -LiteralPath $preflight.FixturePath -Algorithm SHA256).Hash -ine $preflight.FixtureSha256 -or !(Test-Path -LiteralPath $preflight.DisposableFixturePath -PathType Leaf) -or (Get-FileHash -LiteralPath $preflight.DisposableFixturePath -Algorithm SHA256).Hash -ine $preflight.DisposableFixtureSha256){throw 'Canonical source fixture or disposable model hash contract invalid.'};if(!$preparation -and $preflight.DisposableFixtureSha256 -ine $preflight.FixtureSha256){throw 'Canonical fixture/model hash contract invalid without preparation evidence.'};if($preparation){foreach($pair in @(@('RequestPath','RequestSha256'),@('ResultPath','ResultSha256'))){$p=[string]$preparation.($pair[0]);$h=[string]$preparation.($pair[1]);if(!$p -or !$h -or !(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ine $h){throw "Canonical fixture preparation $($pair[0]) hash mismatch."}};if($preparation.AttemptId -cnotmatch '^[A-Fa-f0-9]{32}$' -or $preparation.RunId -cnotmatch '^[A-Fa-f0-9]{32}$' -or $preparation.PreparedModelSha256 -ine $preflight.DisposableFixtureSha256){throw 'Canonical fixture preparation identity/model hash mismatch.'}};$expectedValidatedManifest=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath([string]$preflight.QaAddinRoot))) 'Repato.CreatePlanViews.TestRunner.addin'));$actualValidatedManifest=[IO.Path]::GetFullPath([string]$preflight.ValidatedRunnerManifestPath);if($actualValidatedManifest -ine $expectedValidatedManifest){throw 'Canonical deployed runner-manifest path contract mismatch before execution.'};if([string]$preflight.ValidatedRunnerManifestSha256 -ine [string]$preflight.RunnerManifestSha256 -or !(Test-Path -LiteralPath $actualValidatedManifest -PathType Leaf) -or (Get-FileHash -LiteralPath $actualValidatedManifest -Algorithm SHA256).Hash -ine [string]$preflight.ValidatedRunnerManifestSha256){throw 'Canonical runner-manifest hash contract mismatch before execution.'}
    if ($ExecutionRecordInvoker) {
        $execution = & $ExecutionRecordInvoker $StoreRoot $request.TaskId $preflight
    } else {
        $execution = New-MayaQaExecutionRecord -StoreRoot $StoreRoot -TaskId $request.TaskId -Preflight $preflight
    }
    if (!$execution) { throw 'Canonical execution preparation returned no execution record.' }

    if ($ClaimInvoker) {
        $claimed = & $ClaimInvoker $StoreRoot $request.TaskId 'Tara' $execution
    } else {
        $claimed = Claim-MayaQaExecutionRecord -StoreRoot $StoreRoot -TaskId $request.TaskId -ClaimOwner 'Tara' -Preflight $execution
    }
    if (!$claimed -or [string]::IsNullOrWhiteSpace([string]$claimed.ClaimId)) {
        throw 'Canonical execution claim was not established.'
    }

    if ($NativeCoreInvoker) {
        $result = & $NativeCoreInvoker $StoreRoot $request.TaskId $claimed.ClaimId
    } else {
        $result = Invoke-MayaQaCanonicalNativeCore -StoreRoot $StoreRoot -TaskId $request.TaskId -ClaimId $claimed.ClaimId -Executable (Join-Path 'E:\revit\Revit 2025' 'Revit.exe') -Arguments ''
    }
    [pscustomobject]@{TaskId=$request.TaskId;WorkflowId=$request.WorkflowId;QaWorkflowId=$request.QaWorkflowId;Execution=$execution;Claim=$claimed;Result=$result}
}

function Invoke-MayaQaSingleCanonicalAttempt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$UserRequest,
        [ValidateSet('approve','reject')][string]$ApprovalDecision = 'reject',
        [string]$ApprovalReason = 'Explicit single-attempt QA authorization',
        [string]$SourceBranch = 'current',
        [string]$ProjectPath = 'Forma.RevitConnector.csproj',
        [ValidateSet('Build','FrozenCandidate')][string]$ArtifactMode = 'Build',
        [string]$CandidateDirectory,[string]$CandidateDllPath,
        [string]$ExpectedCandidateSha256,[string]$ExpectedCandidateSourceCommit,[object]$AuthenticatedBuildSource,[string]$FixturePreparationResultPath,
        [switch]$StageFrozenCandidateForQa,
        [scriptblock]$DeploymentValidationInvoker,
        [scriptblock]$RequestInvoker,[scriptblock]$ApprovalInvoker,
        [scriptblock]$PreparationInvoker,[scriptblock]$TransactionInvoker,
        [switch]$DryRun
    )
    if($ApprovalDecision -eq 'approve' -and [string]::IsNullOrWhiteSpace($ApprovalReason)){throw 'Approval reason is required.'}
    $request = if($RequestInvoker){& $RequestInvoker $StoreRoot $UserRequest $SourceBranch $ProjectPath}else{
        Invoke-MayaQaRequest -StoreRoot $StoreRoot -UserRequest $UserRequest -SourceBranch $SourceBranch -ProjectPath $ProjectPath -ArtifactMode $ArtifactMode -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedCandidateSha256 $ExpectedCandidateSha256 -ExpectedCandidateSourceCommit $ExpectedCandidateSourceCommit -AuthenticatedBuildSource $AuthenticatedBuildSource -FixturePreparationResultPath $FixturePreparationResultPath -StageFrozenCandidateForQa:$StageFrozenCandidateForQa -ValidateExistingDeployment:($ArtifactMode -ceq 'FrozenCandidate') -DeploymentValidationInvoker $DeploymentValidationInvoker -DryRun:$DryRun
    }
    if(!$request){throw 'Canonical request returned no result.'}
    if($request.Stage -eq 'handoff-ready' -or $request.Stage -eq 'execution-ready'){throw 'Single-attempt wrapper received an already-prepared request; refusing to risk reuse.'}
    if($request.Stage -ne 'approval-required'){throw "Expected approval-required state, received '$($request.Stage)' without creating a continuation."}
    if($ApprovalDecision -ne 'approve'){return [pscustomobject]@{Success=$false;Stage='approval-required';TaskId=$request.TaskId;WorkflowId=$request.WorkflowId;RunId=$request.RunId;QaWorkflowId=$request.QaWorkflowId;QaApprovalId=$request.QaApprovalId;AttemptId=$null;NativeRequestCount=0;ReplacementAttemptCreated=$false;Error=$null}}
    $approval = if($ApprovalInvoker){& $ApprovalInvoker $StoreRoot $request.TaskId 'approve' 'user' $ApprovalReason}else{Resolve-RepatoTaskApproval $StoreRoot $request.TaskId 'approve' 'user' $ApprovalReason}
    if(!$approval){throw 'Approval resolution returned no result.'}
    $canonical = if($PreparationInvoker){& $PreparationInvoker $StoreRoot $request.TaskId $request.WorkflowId $request.QaWorkflowId}else{New-MayaQaCanonicalPreparation -StoreRoot $StoreRoot -TaskId $request.TaskId -WorkflowId $request.WorkflowId -QaWorkflowId $request.QaWorkflowId}
    if(!$canonical -or !$canonical.Attempt){throw 'Canonical preparation returned no attempt.'}
    $preparedRequest=[pscustomobject]@{Stage='handoff-ready';TaskId=$request.TaskId;WorkflowId=$request.WorkflowId;QaWorkflowId=$request.QaWorkflowId;RunId=$request.RunId;Handoff=$canonical.Handoff}
    $tx = if($TransactionInvoker){& $TransactionInvoker $preparedRequest $StoreRoot}else{
        Invoke-MayaQaCanonicalTransaction -StoreRoot $StoreRoot -UserRequest $UserRequest -RequestInvoker { param($s,$u,$b,$p) $preparedRequest }
    }
    if(!$tx){throw 'Canonical transaction returned no result.'}
    [pscustomobject]@{Success=$true;Stage='native-started';TaskId=$request.TaskId;WorkflowId=$request.WorkflowId;QaWorkflowId=$request.QaWorkflowId;RunId=$request.RunId;AttemptId=$canonical.Attempt.AttemptId;ClaimId=$tx.Claim.ClaimId;Approval=$approval;Preparation=$canonical;Transaction=$tx;NativeRequestCount=1;ReplacementAttemptCreated=$false;Error=$null}
}
function Invoke-MayaQaBuildExecute {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[string]$SourceBranch='current',[string]$ProjectPath='Forma.RevitConnector.csproj',[object]$AuthenticatedBuildSource,[scriptblock]$BuildProcessRunner,[switch]$DryRun)
    $QaWorkflowId = Resolve-MayaQaWorkflowId $QaWorkflowId
    if ([string]::IsNullOrWhiteSpace($SourceBranch)) { $SourceBranch = 'current' }
    if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = 'Forma.RevitConnector.csproj' }
    $def = Get-MayaQaWorkflowDefinition $QaWorkflowId
    if ($DryRun) { return [pscustomobject]@{BuildRequestId=('build-' + [guid]::NewGuid().ToString('N'));TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;BuildStatus='planned';SideEffectsPerformed=$false} }
    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if ($workflow.PSObject.Properties.Name -notcontains 'qaBuildRequest' -or !$workflow.qaBuildRequest) { throw 'Persisted Neil build request is missing.' }
    if ($workflow.PSObject.Properties.Name -contains 'qaWorkflowId' -and $workflow.qaWorkflowId -cne $QaWorkflowId) { throw 'QA workflow identity mismatch.' }
    $normalize = {
        param([string]$Value,[string]$Base)
        if([string]::IsNullOrWhiteSpace($Value)){throw 'Persisted build path is empty.'}
        $clean=$Value.Trim().Trim('"') -replace '\\\\','\'
        if([IO.Path]::IsPathRooted($clean)){[IO.Path]::GetFullPath($clean)}else{[IO.Path]::GetFullPath((Join-Path $Base $clean))}
    }
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    if ($workflow.qaBuildRequest.PSObject.Properties.Name -contains 'AuthenticatedBuildSource' -and $workflow.qaBuildRequest.AuthenticatedBuildSource) { $AuthenticatedBuildSource = $workflow.qaBuildRequest.AuthenticatedBuildSource }
    $sourceBoundary = Resolve-MayaQaAuthenticatedBuildSource $AuthenticatedBuildSource
    $root = $sourceBoundary.RepositoryRoot
    $persistedProject = & $normalize ([string]$workflow.qaBuildRequest.ProjectPath) $root
    $requestedProjectInput = & $normalize $ProjectPath $root
    if ($workflow.qaBuildRequest.SourceBranch -cne $SourceBranch -or $persistedProject -ine $requestedProjectInput) { throw 'Build request parameters do not match the persisted request.' }
    $project = $sourceBoundary.ProjectPath
    if ($persistedProject -ine $project -or !(Test-Path -LiteralPath $persistedProject -PathType Leaf)) { throw 'Normalized project path is missing or outside the approved workspace.' }
    $artifact = [IO.Path]::GetFullPath((Join-Path $root 'bin\Release\net8.0-windows\Repato.Revit.dll'))
    $artifactManifest = [IO.Path]::GetFullPath((Join-Path $root 'Repato.addin'))
    $requestedArtifact = if($workflow.qaBuildRequest.PSObject.Properties.Name -contains 'RequestedArtifact') { & $normalize ([string]$workflow.qaBuildRequest.RequestedArtifact) $root } else { $artifact }
    if($requestedArtifact -ine $artifact){throw 'Normalized requested artifact is outside the approved Release artifact path.'}
    $sourceCommit=Get-MayaQaTrustedBuildSourceCommit -RepositoryRoot $root -ProjectPath $persistedProject
    $command = 'dotnet build "' + $project + '" -c Release -p:RevitInstallDir="E:\revit\Revit 2025"'
    if ($DryRun) { return [pscustomobject]@{BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;BuildStatus='planned';Command=$command;Configuration='Release';ArtifactPath=$artifact;SideEffectsPerformed=$false} }
    $started = (Get-Date).ToUniversalTime().ToString('O')
    if($BuildProcessRunner){$processResult=& $BuildProcessRunner $project $root}else{Push-Location $root;try{$processResult=[pscustomobject]@{Lines=@(& dotnet build $project -c Release '-p:RevitInstallDir=E:\revit\Revit 2025' 2>&1);ExitCode=$LASTEXITCODE}}finally{Pop-Location}}
    if(!$processResult -or $processResult.PSObject.Properties.Name -notcontains 'Lines' -or $processResult.PSObject.Properties.Name -notcontains 'ExitCode'){throw 'Build process runner returned an invalid result.'}
    $lines=@($processResult.Lines);$exit=[int]$processResult.ExitCode
    $finished = (Get-Date).ToUniversalTime().ToString('O')
    # Count compiler/MSBuild diagnostics only. Summary text such as "0 Error(s)" is not an error diagnostic.
    $warningLines = @($lines | Where-Object { [string]$_ -match '(?i):\s*warning\s+[A-Z]+\d+\b' })
    $errorLines = @($lines | Where-Object { [string]$_ -match '(?i):\s*error\s+[A-Z]+\d+\b' })
    $warningCount = $warningLines.Count
    $errorCount = $errorLines.Count
    $manifestValid=$false
    if(Test-Path -LiteralPath $artifactManifest -PathType Leaf){try{$manifestValid=([xml](Get-Content -LiteralPath $artifactManifest -Raw)).DocumentElement.Name -ceq 'RevitAddIns'}catch{$manifestValid=$false}}
    if ($exit -ne 0 -or $errorCount -gt 0 -or !(Test-Path -LiteralPath $artifact -PathType Leaf) -or !$manifestValid) { $status='failed' } else { $status='succeeded' }
    $data = Read-RepatoTaskStore $StoreRoot; $task = Find-RepatoTask $data $TaskId
    $mutation = @(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {
        param($current)
        $current | Add-Member -NotePropertyName qaBuildStatus -NotePropertyValue $status -Force
        $current | Add-Member -NotePropertyName qaBuildEvidence -NotePropertyValue ([pscustomobject]@{BuildRequestId=$current.qaBuildRequest.BuildRequestId;StartedUtc=$started;FinishedUtc=$finished;Command=$command;Configuration='Release';SourceCommit=$sourceCommit;ExitCode=$exit;ArtifactPath=$artifact;ArtifactSha256=$(if(Test-Path $artifact){(Get-FileHash $artifact -Algorithm SHA256).Hash}else{$null});ManifestPath=$artifactManifest;ManifestSha256=$(if(Test-Path $artifactManifest){(Get-FileHash $artifactManifest -Algorithm SHA256).Hash}else{$null});BuildStatus=$status;WarningCount=$warningCount;ErrorCount=$errorCount;ErrorLines=$errorLines}) -Force
        return $current
    })[-1]
    if ($status -ne 'succeeded') { throw "Release build failed with exit code $exit." }
    [pscustomobject]@{BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;BuildStatus=$status;Command=$command;Configuration='Release';SourceCommit=$mutation.Workflow.qaBuildEvidence.SourceCommit;ExitCode=$exit;ArtifactPath=$artifact;ArtifactSha256=$mutation.Workflow.qaBuildEvidence.ArtifactSha256;ArtifactManifestPath=$artifactManifest;ArtifactManifestSha256=$mutation.Workflow.qaBuildEvidence.ManifestSha256;ManifestPath=$artifactManifest;ManifestSha256=$mutation.Workflow.qaBuildEvidence.ManifestSha256;WarningCount=$warningCount;ErrorCount=$errorCount;WorkflowRevision=$mutation.Workflow.workflowRevision;TaskRevision=$mutation.TaskRevision;SideEffectsPerformed=$true}
}

function Get-MayaQaTrustedBuildSourceCommit {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$ProjectPath)
    $root=[IO.Path]::GetFullPath($RepositoryRoot);$project=[IO.Path]::GetFullPath($ProjectPath)
    $commit=(& git -C $root rev-parse HEAD 2>$null).Trim();if($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-fA-F]{40}$'){throw 'Trusted build source commit could not be resolved.'}
    $excluded=@('\QaLaunchAgent\','\QaLaunchAgent.ProtocolInteropTests\','\bin\','\obj\')
    $oldErrorAction=$ErrorActionPreference;$ErrorActionPreference='Continue';try{$statusOutput=@(& git -C $root status --porcelain --untracked-files=all 2>&1);$statusExit=$LASTEXITCODE}finally{$ErrorActionPreference=$oldErrorAction};if($statusExit -ne 0){throw 'Build input cleanliness could not be established.'}
    $diagnostics=@($statusOutput|Where-Object {[string]$_ -notmatch '^[ MADRCU?!]{2}\s'});foreach($diagnostic in $diagnostics){if([string]$diagnostic -notmatch '(?i)warning:\s+could not open directory .*QA[/\\]Quarantine[/\\].*Permission denied'){throw 'Build input cleanliness could not be established.'}}
    $dirty=@($statusOutput|Where-Object {[string]$_ -match '^[ MADRCU?!]{2}\s'})
    $inputs=@($dirty|ForEach-Object { $line=[string]$_;if($line.Length -lt 4){return};$path=$line.Substring(3).Trim('"');if($path -match ' -> '){$path=($path -split ' -> ')[-1]};$full=[IO.Path]::GetFullPath((Join-Path $root $path));$isExcluded=$false;foreach($x in $excluded){if($full -match [regex]::Escape($x)){$isExcluded=$true;break}};if(!$isExcluded -and $full -match '(?i)\.(cs|csproj|props|targets|resx)$|(?i)(^|\\)Directory\.Build\.(props|targets)$'){$full}})
    if($inputs.Count){throw ('Dirty build inputs prevent source-commit binding: '+($inputs -join '; '))}
    $commit
}

function Resolve-MayaQaAuthenticatedBuildSource {
    param([object]$AuthenticatedBuildSource,[switch]$AllowHistoricalCommit)
    $commonGitDirectory=(& git -C $PSScriptRoot rev-parse --path-format=absolute --git-common-dir 2>$null).Trim()
    if($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commonGitDirectory)){throw 'Primary repository identity could not be resolved for authenticated build-source validation.'}
    $primary=[IO.Path]::GetFullPath((Split-Path -Parent $commonGitDirectory))
    if($null -eq $AuthenticatedBuildSource){return [pscustomobject]@{RepositoryRoot=$primary;PrimaryRepositoryRoot=$primary;ProjectPath=[IO.Path]::GetFullPath((Join-Path $primary 'Forma.RevitConnector.csproj'));ExpectedSourceCommit=$null;Isolated=$false}}
    foreach($n in 'RepositoryRoot','ExpectedSourceCommit','ProjectRelativePath'){
        if($AuthenticatedBuildSource.PSObject.Properties.Name -notcontains $n -or [string]::IsNullOrWhiteSpace([string]$AuthenticatedBuildSource.$n)){throw "AuthenticatedBuildSource is missing $n."}
    }
    $root=[IO.Path]::GetFullPath([string]$AuthenticatedBuildSource.RepositoryRoot);$approved=[IO.Path]::GetFullPath('C:\Repato-Autonomous\Worktrees').TrimEnd('\')+'\'
    if(!$root.StartsWith($approved,[StringComparison]::OrdinalIgnoreCase)){throw 'Authenticated build source is outside the approved worktree root.'}
    if([string]$AuthenticatedBuildSource.ExpectedSourceCommit -notmatch '^[0-9a-fA-F]{40}$'){throw 'Authenticated build source commit must be a 40-character SHA.'}
    if(!(Test-Path -LiteralPath $root -PathType Container)){throw 'Authenticated build source worktree is missing.'}
    $cursor=$root;while($cursor -and $cursor -ne [IO.Path]::GetPathRoot($cursor).TrimEnd('\')){if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Authenticated build source contains a reparse point.'};$cursor=[IO.Path]::GetDirectoryName($cursor)}
    $top=(& git -C $root rev-parse --show-toplevel 2>$null).Trim();if($LASTEXITCODE -ne 0 -or [IO.Path]::GetFullPath($top) -ine $root){throw 'Authenticated build source is not a Git worktree.'}
    $common=(& git -C $root rev-parse --path-format=absolute --git-common-dir 2>$null).Trim();$primaryGit=[IO.Path]::GetFullPath((Join-Path $primary '.git'));if($LASTEXITCODE -ne 0 -or [IO.Path]::GetFullPath($common) -ine $primaryGit){throw 'Authenticated build source belongs to another repository.'}
    if($AllowHistoricalCommit){& git -C $root cat-file -e "$($AuthenticatedBuildSource.ExpectedSourceCommit)^{commit}" 2>$null;if($LASTEXITCODE -ne 0){throw 'Authenticated build source commit is not present in the repository.'}}
    else{$head=(& git -C $root rev-parse HEAD 2>$null).Trim();if($LASTEXITCODE -ne 0 -or $head -ine [string]$AuthenticatedBuildSource.ExpectedSourceCommit){throw 'Authenticated build source HEAD does not match the requested commit.'}}
    $projectRel=([string]$AuthenticatedBuildSource.ProjectRelativePath).TrimStart('\','/');if([IO.Path]::IsPathRooted($projectRel) -or $projectRel -match '(^|[\\/])\.\.([\\/]|$)'){throw 'Authenticated project path must remain relative to the worktree.'}
    $project=[IO.Path]::GetFullPath((Join-Path $root $projectRel));$prefix=$root.TrimEnd('\')+'\';if(!$project.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $project -PathType Leaf)){throw 'Authenticated project path is outside or missing from the worktree.'}
    if((Get-Item -LiteralPath $project -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Authenticated project path is a reparse point.'}
    [pscustomobject]@{RepositoryRoot=$root;PrimaryRepositoryRoot=$primary;ProjectPath=$project;ExpectedSourceCommit=[string]$AuthenticatedBuildSource.ExpectedSourceCommit;Isolated=$true}
}

function Get-MayaQaActiveCanonicalExecutionApprovals {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Approvals)
    $active=@()
    foreach($approval in $Approvals) {
        if($approval.action -cne 'qa-run' -or
            ($approval.status -cne 'pending' -and !($approval.status -ceq 'approved' -and !$approval.consumedUtc))) { continue }
        $expiry=[DateTimeOffset]::MinValue
        if(![DateTimeOffset]::TryParse([string]$approval.expiresUtc,[ref]$expiry)){throw 'An active QA approval has an invalid expiry and cannot be safely superseded.'}
        if($expiry -gt [DateTimeOffset]::UtcNow){$active+=,$approval}
    }
    $active
}
function Test-MayaQaHasActiveCanonicalExecutionApproval {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Approvals)
    $active=@(Get-MayaQaActiveCanonicalExecutionApprovals -Approvals $Approvals)
    $active.Count -gt 0
}
function Get-MayaQaExpiredApprovedCanonicalRequestForRefresh {
    param([Parameter(Mandatory)][object]$Task,[Parameter(Mandatory)][object]$Workflow)
    if($Task.status -cne 'in-progress' -or $Task.workflowStage -cne 'approval' -or
        [string]$Workflow.qaWorkflowId -cne 'create-plan-views-v1' -or
        [string]$Task.taskId -cne [string]$Workflow.taskId){return $null}
    $matches=@()
    foreach($candidateRequest in $Task.approvalRequests){
        if(!$candidateRequest -or $candidateRequest.action -cne 'qa-run' -or $candidateRequest.status -cne 'approved' -or
            $candidateRequest.PSObject.Properties.Name -notcontains 'executionBinding' -or !$candidateRequest.executionBinding){continue}
        $candidateBinding=$candidateRequest.executionBinding
        if($candidateBinding.PSObject.Properties.Name -notcontains 'WorkflowId' -or
            $candidateBinding.PSObject.Properties.Name -notcontains 'RunId'){continue}
        if($candidateBinding.WorkflowId -ceq [string]$Workflow.workflowId -and
            $candidateBinding.RunId -ceq [string]$Workflow.qaRunId){$matches+=,$candidateRequest}
    }
    if(!$matches.Count){return $null}
    if($matches.Count -ne 1){throw 'Expired canonical approval refresh is ambiguous.'}
    $request=$matches[0];$binding=$request.executionBinding
    $expiry=[DateTimeOffset]::MinValue;$expiryValid=$true
    if($request.expiresUtc -is [DateTimeOffset]){$expiry=$request.expiresUtc}
    elseif($request.expiresUtc -is [DateTime]){$expiry=[DateTimeOffset]$request.expiresUtc}
    else{$expiryValid=[DateTimeOffset]::TryParse([string]$request.expiresUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$expiry)}
    $json=ConvertTo-Json -InputObject $binding -Depth 25 -Compress
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$bindingHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}
    finally{$sha.Dispose()}
    $invalid=@()
    if($request.requiredLevel -cne 'user'){$invalid+='requiredLevel'}
    if($request.decidedBy -cne 'user'){$invalid+='decidedBy'}
    if($request.consumedUtc){$invalid+='consumedUtc'}
    if(!$expiryValid -or $expiry -gt [DateTimeOffset]::UtcNow){$invalid+='expiry'}
    if([long]$request.approvedRevision -ne [long]$Task.revision){$invalid+='approvedRevision'}
    if([long]$request.requestedRevision -ge [long]$request.approvedRevision){$invalid+='requestedRevision'}
    if($request.bindingHash -ine $bindingHash){$invalid+='bindingHash'}
    if($binding.TaskId -cne [string]$Task.taskId){$invalid+='taskId'}
    if($binding.WorkflowId -cne [string]$Workflow.workflowId){$invalid+='workflowId'}
    if($binding.QaWorkflowId -cne [string]$Workflow.qaWorkflowId){$invalid+='qaWorkflowId'}
    if($binding.BuildRequestId -cne [string]$Workflow.qaBuildEvidence.BuildRequestId){$invalid+='buildRequestId'}
    if($binding.CandidateSourceCommit -cne [string]$Workflow.qaBuildEvidence.CandidateSourceCommit){$invalid+='candidateCommit'}
    if($binding.CandidateSha256 -ine [string]$Workflow.qaBuildEvidence.ArtifactSha256){$invalid+='candidateSha256'}
    if($binding.RunId -cne [string]$Workflow.qaRunId){$invalid+='runId'}
    if($binding.ModelPath -ine [string]$Workflow.qaModelPath){$invalid+='modelPath'}
    if($binding.ModelSha256 -ine [string]$Workflow.qaDisposableModelSha256){$invalid+='modelSha256'}
    if($binding.SidecarPath -ine [string]$Workflow.qaSidecarPath){$invalid+='sidecarPath'}
    if($binding.RunnerManifestPath -ine [string]$Workflow.qaBuildEvidence.RunnerManifestPath){$invalid+='runnerManifestPath'}
    if($binding.RunnerManifestSha256 -ine [string]$Workflow.qaBuildEvidence.RunnerManifestSha256){$invalid+='runnerManifestSha256'}
    if($invalid.Count){throw "Expired approved QA request is not a current, intact canonical candidate binding: $($invalid -join ', ')."}
    $request
}

function Test-MayaQaTaskHasTaraExecutionState {
    param([Parameter(Mandatory)][object]$Task)
    foreach($name in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence') {
        $property=$Task.PSObject.Properties[$name]
        if($property -and $null -ne $property.Value){return $true}
    }
    $false
}

function Test-MayaQaFrozenCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CandidateDirectory,
        [string]$CandidateDllPath,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedSha256,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{7,40}$')][string]$ExpectedSourceCommit,
        [Parameter(Mandatory)][string]$QaWorkflowId
    )
    $directory=[IO.Path]::GetFullPath($CandidateDirectory)
    if(!(Test-Path -LiteralPath $directory -PathType Container)){throw 'Frozen candidate directory is missing.'}
    $dll=if([string]::IsNullOrWhiteSpace($CandidateDllPath)){Join-Path $directory 'Repato.Revit.dll'}else{[IO.Path]::GetFullPath($CandidateDllPath)}
    $prefix=$directory.TrimEnd('\')+'\'
    if(!$dll.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Frozen candidate DLL must be inside the candidate directory.'}
    if(!(Test-Path -LiteralPath $dll -PathType Leaf)){throw 'Frozen candidate DLL is missing.'}
    $actual=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
    if($actual -ine $ExpectedSha256){throw 'Frozen candidate DLL SHA-256 mismatch.'}
    $provenancePath=Join-Path $directory 'release-manifest.json'
    if(!(Test-Path -LiteralPath $provenancePath -PathType Leaf)){throw 'Frozen candidate provenance is missing.'}
    try{$provenance=Get-Content -LiteralPath $provenancePath -Raw|ConvertFrom-Json}catch{throw 'Frozen candidate provenance is invalid JSON.'}
    foreach($name in 'SourceCommit','FrozenArtifactSha256'){
        if($provenance.PSObject.Properties.Name -notcontains $name -or [string]::IsNullOrWhiteSpace([string]$provenance.$name)){throw "Frozen candidate provenance is missing $name."}
    }
    $source=[string]$provenance.SourceCommit
    if(!$source.StartsWith($ExpectedSourceCommit,[StringComparison]::OrdinalIgnoreCase) -or
       ($ExpectedSourceCommit.Length -eq 40 -and $source -ine $ExpectedSourceCommit)){throw 'Frozen candidate source commit mismatch.'}
    if([string]$provenance.FrozenArtifactSha256 -ine $actual){throw 'Frozen candidate provenance artifact hash mismatch.'}
    if($provenance.PSObject.Properties.Name -notcontains 'SupportedQaWorkflows' -or
       @($provenance.SupportedQaWorkflows|Where-Object{[string]$_ -ceq $QaWorkflowId}).Count -ne 1){throw 'Frozen candidate is not compatible with the requested QA workflow.'}
    $manifestPath=Join-Path $directory 'Repato.addin'
    if(!(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw 'Frozen candidate add-in manifest is missing.'}
    try{$manifestXml=[xml](Get-Content -LiteralPath $manifestPath -Raw)}catch{throw 'Frozen candidate add-in manifest is invalid XML.'}
    if($manifestXml.DocumentElement.Name -cne 'RevitAddIns'){throw 'Frozen candidate add-in manifest is invalid.'}
    [pscustomobject]@{CandidateDirectory=$directory;ArtifactPath=$dll;ArtifactSha256=$actual;ManifestPath=$manifestPath;ManifestSha256=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash;ProvenancePath=$provenancePath;ProvenanceSha256=(Get-FileHash -LiteralPath $provenancePath -Algorithm SHA256).Hash;SourceCommit=$source;QaWorkflowId=$QaWorkflowId}
}

function Invoke-MayaQaFrozenCandidateEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$CandidateDirectory,[string]$CandidateDllPath,
        [Parameter(Mandatory)][string]$ExpectedSha256,[Parameter(Mandatory)][string]$ExpectedSourceCommit,[object]$DeploymentEvidence,
        [object]$DeploymentValidationOperation,
        [switch]$BindDeploymentEvidenceOnly,
        [switch]$DryRun
    )
    $verified=Test-MayaQaFrozenCandidate -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedSha256 $ExpectedSha256 -ExpectedSourceCommit $ExpectedSourceCommit -QaWorkflowId $QaWorkflowId
    if($DryRun){return $verified}
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if($workflow.PSObject.Properties.Name -notcontains 'qaBuildRequest' -or !$workflow.qaBuildRequest){throw 'Persisted Neil build request is missing.'}
    if($workflow.qaWorkflowId -cne $QaWorkflowId){throw 'QA workflow identity mismatch.'}
    if($workflow.PSObject.Properties.Name -notcontains 'qaBuildEvidence' -or $workflow.qaBuildEvidence.PSObject.Properties.Name -notcontains 'SourceCommit' -or [string]::IsNullOrWhiteSpace([string]$workflow.qaBuildEvidence.SourceCommit)){throw 'Source-bound Neil build evidence is required.'}
    $oldBuildEvidence=$workflow.qaBuildEvidence;$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$sourceBoundary=$null
    if($workflow.qaBuildRequest.AuthenticatedBuildSource){$sourceBoundary=Resolve-MayaQaAuthenticatedBuildSource $workflow.qaBuildRequest.AuthenticatedBuildSource
        if($sourceBoundary.RepositoryRoot -ine $repoRoot -or ($sourceBoundary.ExpectedSourceCommit -and $sourceBoundary.ExpectedSourceCommit -ine [string]$oldBuildEvidence.SourceCommit)){throw 'Frozen candidate adoption is not bound to the authenticated build worktree.'}}
    $candidateRepositoryRoot=if($sourceBoundary){$sourceBoundary.PrimaryRepositoryRoot}else{$repoRoot};$candidateRoot=[IO.Path]::GetFullPath((Join-Path $candidateRepositoryRoot 'DeploymentCandidates\AgentBuilds')).TrimEnd('\')+'\';$candidateDirectory=[IO.Path]::GetFullPath($verified.CandidateDirectory)
    if($BindDeploymentEvidenceOnly -and (!$DeploymentValidationOperation -or !$DeploymentEvidence -or $oldBuildEvidence.EvidenceSource -cne 'FrozenCandidate' -or $oldBuildEvidence.ArtifactPath -ine $verified.ArtifactPath -or $oldBuildEvidence.CandidateSourceCommit -cne $verified.SourceCommit -or $oldBuildEvidence.BuildRequestId -cne $workflow.qaBuildRequest.BuildRequestId)){throw 'Deployment-only binding requires the already adopted candidate and completed independent proof.'}
    if(!$candidateDirectory.StartsWith($candidateRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Frozen candidate is outside the active repository DeploymentCandidates\\AgentBuilds root.'}
    if([string]$verified.SourceCommit -cne [string]$oldBuildEvidence.SourceCommit){throw 'Frozen candidate source commit does not match Neil build evidence.'}
    if($oldBuildEvidence.PSObject.Properties.Name -notcontains 'ArtifactPath' -or $oldBuildEvidence.PSObject.Properties.Name -notcontains 'ArtifactSha256' -or [string]$oldBuildEvidence.ArtifactSha256 -ine [string]$verified.ArtifactSha256){throw 'Frozen candidate artifact does not match the authenticated Neil ReleaseBuild output.'}
    $buildArtifactPath=[string]$oldBuildEvidence.ArtifactPath;if(![IO.Path]::IsPathRooted($buildArtifactPath)){$buildArtifactPath=Join-Path $repoRoot $buildArtifactPath};$buildArtifactPath=[IO.Path]::GetFullPath($buildArtifactPath)
    if(!(Test-Path -LiteralPath $buildArtifactPath -PathType Leaf) -or (Get-FileHash -LiteralPath $buildArtifactPath -Algorithm SHA256).Hash -ine [string]$oldBuildEvidence.ArtifactSha256){throw 'Authenticated Neil ReleaseBuild artifact path/hash is missing or changed.'}
    if($oldBuildEvidence.PSObject.Properties.Name -notcontains 'ManifestPath' -or $oldBuildEvidence.PSObject.Properties.Name -notcontains 'ManifestSha256' -or [string]$oldBuildEvidence.ManifestSha256 -ine [string]$verified.ManifestSha256){throw 'Frozen candidate manifest does not match the authenticated Neil ReleaseBuild manifest.'}
    $buildManifestPath=[string]$oldBuildEvidence.ManifestPath;if(![IO.Path]::IsPathRooted($buildManifestPath)){$buildManifestPath=Join-Path $repoRoot $buildManifestPath};$buildManifestPath=[IO.Path]::GetFullPath($buildManifestPath)
    if(!(Test-Path -LiteralPath $buildManifestPath -PathType Leaf) -or (Get-FileHash -LiteralPath $buildManifestPath -Algorithm SHA256).Hash -ine [string]$oldBuildEvidence.ManifestSha256){throw 'Authenticated Neil ReleaseBuild manifest path/hash is missing or changed.'}
    $runnerNames=@{'create-plan-views-v1'='Repato.CreatePlanViews.TestRunner.addin';'create-levels-elevations-v1'='Repato.CreateLevels.TestRunner.addin';'create-grids-world-axis-v1'='Repato.CreateGrids.TestRunner.addin';'grid-bubble-visibility-v1'='Repato.GridBubbleVisibility.TestRunner.addin';'grid-bubble-offset-v1'='Repato.GridBubbleOffset.TestRunner.addin';'grid-resequence-v1'='Repato.GridResequence.TestRunner.addin'}
    if(!$runnerNames.ContainsKey($QaWorkflowId)){throw 'Trusted source runner manifest identity is unsupported.'}
    $trustedRunnerRoot=[IO.Path]::GetFullPath((Join-Path $(if($sourceBoundary){$sourceBoundary.PrimaryRepositoryRoot}else{$repoRoot}) 'QA'));$trustedRunnerManifestPath=[IO.Path]::GetFullPath((Join-Path $trustedRunnerRoot $runnerNames[$QaWorkflowId]));$worktreeRunnerManifestPath=[IO.Path]::GetFullPath((Join-Path (Join-Path $repoRoot 'QA') $runnerNames[$QaWorkflowId]));if(!(Test-Path -LiteralPath $trustedRunnerManifestPath -PathType Leaf) -or !(Test-Path -LiteralPath $worktreeRunnerManifestPath -PathType Leaf)){throw 'Trusted source runner manifest is missing.'}
    try{$runnerXml=[xml](Get-Content -LiteralPath $trustedRunnerManifestPath -Raw -ErrorAction Stop)}catch{throw 'Trusted source runner manifest is malformed.'};if($runnerXml.DocumentElement.Name -cne 'RevitAddIns' -or @($runnerXml.RevitAddIns.AddIn|Where-Object Type -eq 'Application').Count -ne 1){throw 'Trusted source runner manifest application contract is invalid.'}
    $trustedRunnerManifestSha256=(Get-FileHash -LiteralPath $trustedRunnerManifestPath -Algorithm SHA256).Hash
    if((Get-FileHash -LiteralPath $worktreeRunnerManifestPath -Algorithm SHA256).Hash -ine $trustedRunnerManifestSha256){throw 'Authenticated build runner manifest differs from trusted source QA.'}
    if($oldBuildEvidence.PSObject.Properties.Name -contains 'RunnerManifestPath' -and $oldBuildEvidence.RunnerManifestPath){$persistedRunnerPath=[IO.Path]::GetFullPath([string]$oldBuildEvidence.RunnerManifestPath);if($persistedRunnerPath -notin @($trustedRunnerManifestPath,$worktreeRunnerManifestPath) -or [string]$oldBuildEvidence.RunnerManifestSha256 -ine $trustedRunnerManifestSha256){throw 'Persisted runner manifest evidence differs from trusted source QA.'}}
    if($DeploymentEvidence -and $DeploymentEvidence.PSObject.Properties.Name -contains 'runnerManifestSha256' -and [string]$DeploymentEvidence.runnerManifestSha256 -ine $trustedRunnerManifestSha256){throw 'Deployment validation runner manifest hash differs from trusted source QA.'}
    $independentValidation=$null
    if($DeploymentValidationOperation){
        $storeState=Read-RepatoTaskStore $StoreRoot;$storeTask=Find-RepatoTask $storeState $TaskId;$storedOps=@($storeTask.deploymentValidationOperations|Where-Object OperationId -ceq $DeploymentValidationOperation.OperationId)
        if($storedOps.Count -ne 1){throw 'Independent deployment-validation operation is not uniquely persisted.'};$storedOp=$storedOps[0]
        foreach($pair in @(@('TaskId',$TaskId),@('WorkflowId',$WorkflowId),@('BuildRequestId',[string]$workflow.qaBuildRequest.BuildRequestId),@('CandidateSourceCommit',$verified.SourceCommit),@('CandidateSha256',$verified.ArtifactSha256),@('QaWorkflowId',$QaWorkflowId),@('TestId',$QaWorkflowId))){if([string]$storedOp.($pair[0]) -cne [string]$pair[1]){throw "Independent validation operation binding mismatch: $($pair[0])."}}
        $recoveredBinding=$storedOp.ValidationPurpose -ceq 'RecoveredQaCurrentDeployment'
        if($storedOp.ValidationPurpose -cnotin @('IndependentAfterAmbiguousStaging','RecoveredQaCurrentDeployment') -or $storedOp.RequestDisposition -cne 'completed' -or !$storedOp.Response -or !$storedOp.ValidationRequest -or [long]$storeTask.revision -ne ([long]$storedOp.TransmittingTaskRevision+1)){throw 'Independent validation operation is incomplete, ambiguous, or stale.'}
        if($recoveredBinding){
            if(!$BindDeploymentEvidenceOnly){throw 'Recovered QA proof requires deployment-only persistence.'}
            $null=Assert-CpvRecoveredQaDeploymentBindingState -Task $storeTask -Workflow $workflow -ExpectedTaskRevision $storeTask.revision -TaskId $TaskId -WorkflowId $WorkflowId -BuildRequestId $workflow.qaBuildRequest.BuildRequestId -CandidateSourceCommit $verified.SourceCommit -CandidateSha256 $verified.ArtifactSha256
        }elseif($BindDeploymentEvidenceOnly){throw 'Recovered QA binding requires its exact validation purpose.'}
        $requestJson=ConvertTo-Json -InputObject $storedOp.ValidationRequest -Compress -Depth 32;$sha=[Security.Cryptography.SHA256]::Create();try{$requestHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($requestJson)))).Replace('-','')}finally{$sha.Dispose()};if($requestHash -ine $storedOp.ValidationRequestSha256){throw 'Persisted independent validation request hash mismatch.'}
        $last=@($storeTask.history)[-1];if($last.event -cne 'deployment-validation-completed' -or [string]$last.details -cnotmatch [regex]::Escape([string]$storedOp.OperationId)){throw 'Task history changed after independent validation completed.'}
        if([string]$storedOp.RequestId -cne [string]$storedOp.Response.requestId -or [string]$storedOp.Response.candidateCommit -ine $verified.SourceCommit -or [string]$storedOp.Response.candidateSha256 -ine $verified.ArtifactSha256 -or [string]$storedOp.Response.runnerManifestSha256 -ine $trustedRunnerManifestSha256 -or [IO.Path]::GetFullPath([string]$storedOp.Response.runnerManifestPath) -ine [IO.Path]::GetFullPath([string]$DeploymentEvidence.runnerManifestPath)){throw 'Independent deployment-validation response is not bound to the persisted candidate.'}
        if([string]$DeploymentEvidence.requestId -cne [string]$storedOp.RequestId -or [string]$DeploymentEvidence.candidateCommit -ine $verified.SourceCommit -or [string]$DeploymentEvidence.candidateSha256 -ine $verified.ArtifactSha256 -or !$DeploymentEvidence.succeeded -or !$DeploymentEvidence.isolationPassed -or !$DeploymentEvidence.manifestIntegrityPassed){throw 'Independent deployment-validation result is invalid.'}
        $activeApprovals=Get-MayaQaActiveCanonicalExecutionApprovals -Approvals @($storeTask.approvalRequests)
        if($storeTask.status -cne 'in-progress' -or (!$recoveredBinding -and $storeTask.workflowStage -cne 'build-checks') -or $activeApprovals.Count){throw 'Task state or approval state changed before independent evidence persistence.'}
        foreach($n in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){if($storeTask.PSObject.Properties.Name -contains $n -and $storeTask.$n){throw 'Tara state appeared before independent evidence persistence.'}}
        if([long]$storeTask.revision -ne ([long]$storedOp.TransmittingTaskRevision+1)){throw 'Independent validation evidence compare-and-swap revision is stale.'}
        $independentValidation=[pscustomobject][ordered]@{Purpose='independent-current-deployment-validation';OperationId=$storedOp.OperationId;RequestId=$storedOp.RequestId;ValidationRequest=$storedOp.ValidationRequest;ValidationRequestSha256=$storedOp.ValidationRequestSha256;TaskId=$TaskId;WorkflowId=$WorkflowId;BuildRequestId=$storedOp.BuildRequestId;CandidateSourceCommit=$storedOp.CandidateSourceCommit;CandidateDllSha256=$storedOp.CandidateSha256;RunnerManifestPath=$DeploymentEvidence.runnerManifestPath;RunnerManifestSha256=$DeploymentEvidence.runnerManifestSha256;Response=$storedOp.Response;StagingDisposition='ambiguous-unresolved';StagingSuccessClaimed=$false}
        if($recoveredBinding){$independentValidation.StagingDisposition='existing-verified-deployment'}
    }
    $now=(Get-Date).ToUniversalTime().ToString('O');$deploymentRunnerManifestPath=if($DeploymentEvidence){$DeploymentEvidence.runnerManifestPath}else{$null};$deploymentRunnerManifestSha256=if($DeploymentEvidence){$DeploymentEvidence.runnerManifestSha256}else{$null};$deploymentValidation=if($DeploymentEvidence){[bool]$DeploymentEvidence.succeeded}else{$false};$deploymentManifestIntegrity=if($DeploymentEvidence -and $DeploymentEvidence.PSObject.Properties.Name -contains 'manifestIntegrityPassed'){[bool]$DeploymentEvidence.manifestIntegrityPassed}elseif($DeploymentEvidence -and $DeploymentEvidence.PSObject.Properties.Name -contains 'manifestIntegrityEvidenceAvailable' -and $DeploymentEvidence.manifestIntegrityEvidenceAvailable){[bool]$DeploymentEvidence.manifestIntegrityPassed}else{$false};$deploymentIsolation=$null;if($DeploymentEvidence){if($DeploymentEvidence.PSObject.Properties.Name -contains 'Isolation'){$deploymentIsolation=$DeploymentEvidence.Isolation}elseif($DeploymentEvidence.PSObject.Properties.Name -contains 'isolationPassed'){$policy=[IO.Path]::GetFullPath((Join-Path (Join-Path $PSScriptRoot '..\QA') 'MachineWideAddins.allowlist.json'));if(!(Test-Path -LiteralPath $policy -PathType Leaf)){throw 'Canonical QA isolation policy is missing.'};$deploymentIsolation=[pscustomobject]@{PolicyPath=$policy;PolicySha256=(Get-FileHash -LiteralPath $policy -Algorithm SHA256).Hash;Allowed=[bool]$DeploymentEvidence.isolationPassed}}else{throw 'Deployment validation isolation evidence is missing.'};if(!$deploymentIsolation -or $deploymentIsolation.PSObject.Properties.Name -notcontains 'Allowed' -or [string]::IsNullOrWhiteSpace([string]$deploymentIsolation.PolicyPath) -or [string]$deploymentIsolation.PolicySha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Deployment validation isolation evidence is malformed.'};if(!(Test-Path -LiteralPath $deploymentIsolation.PolicyPath -PathType Leaf) -or (Get-FileHash -LiteralPath $deploymentIsolation.PolicyPath -Algorithm SHA256).Hash -ine [string]$deploymentIsolation.PolicySha256){throw 'Deployment validation isolation policy identity is invalid.'};if(!$deploymentIsolation.Allowed){throw 'Deployment validation isolation failed.'}};$deploymentQaIsolation=if($deploymentIsolation){[bool]$deploymentIsolation.Allowed}else{$false};$data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    $mutation=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {
        param($current)
        if($BindDeploymentEvidenceOnly){
            if([long]$task.revision -ne [long]$storeTask.revision){throw 'Deployment proof became stale before binding compare-and-swap.'}
            if($current.qaBuildEvidence.BuildRequestId -cne $oldBuildEvidence.BuildRequestId -or $current.qaBuildEvidence.CandidateSourceCommit -cne $verified.SourceCommit -or $current.qaBuildEvidence.ArtifactSha256 -ine $verified.ArtifactSha256 -or !$independentValidation -or !$deploymentValidation -or !$deploymentManifestIntegrity -or !$deploymentQaIsolation){throw 'Deployment-only binding compare-and-swap or proof failed.'}
            foreach($pair in @(@('DeploymentValidation',$deploymentValidation),@('ManifestIntegrityValidation',$deploymentManifestIntegrity),@('QaIsolation',$deploymentQaIsolation),@('DeployedRunnerManifestPath',$deploymentRunnerManifestPath),@('DeployedRunnerManifestSha256',$deploymentRunnerManifestSha256),@('QaAddinRoot',$DeploymentEvidence.qaAddinRoot),@('Isolation',$deploymentIsolation),@('IndependentDeploymentValidation',$independentValidation))){$current.qaBuildEvidence|Add-Member NoteProperty $pair[0] $pair[1] -Force}
            return $current
        }
        $e=[pscustomobject]@{BuildRequestId=$current.qaBuildRequest.BuildRequestId;StartedUtc=$now;FinishedUtc=$now;Command='FrozenCandidate integrity and provenance validation (no compilation)';Configuration='Release';SourceCommit=$current.qaBuildEvidence.SourceCommit;ExitCode=0;ArtifactPath=$verified.ArtifactPath;ArtifactSha256=$verified.ArtifactSha256;ManifestPath=$verified.ManifestPath;ManifestSha256=$verified.ManifestSha256;BuildStatus='succeeded';WarningCount=0;ErrorCount=0;ErrorLines=@();EvidenceSource='FrozenCandidate';CandidateDirectory=$verified.CandidateDirectory;CandidateProvenancePath=$verified.ProvenancePath;CandidateProvenanceSha256=$verified.ProvenanceSha256;CandidateSourceCommit=$verified.SourceCommit;QaWorkflowId=$verified.QaWorkflowId;RunnerManifestPath=$trustedRunnerManifestPath;RunnerManifestSha256=$trustedRunnerManifestSha256;RunnerManifestQaWorkflowId=$QaWorkflowId;RunnerManifestTestId=$QaWorkflowId;RunnerManifestEvidenceStatus='authenticated-source';DeployedRunnerManifestPath=$deploymentRunnerManifestPath;DeployedRunnerManifestSha256=$deploymentRunnerManifestSha256;DeploymentValidation=$deploymentValidation;ManifestIntegrityValidation=$deploymentManifestIntegrity;QaIsolation=$deploymentQaIsolation;QaAddinRoot=$(if($DeploymentEvidence){$DeploymentEvidence.qaAddinRoot}else{$null});Isolation=$deploymentIsolation}
        if($independentValidation){$e|Add-Member NoteProperty IndependentDeploymentValidation $independentValidation -Force}
        foreach($property in $current.qaBuildEvidence.PSObject.Properties){if($e.PSObject.Properties.Name -notcontains $property.Name){$e|Add-Member NoteProperty $property.Name $property.Value -Force}}
        $current|Add-Member NoteProperty qaBuildStatus 'succeeded' -Force
        $current|Add-Member NoteProperty qaBuildEvidence $e -Force
        return $current
    })[-1]
    [pscustomobject]@{BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;BuildStatus='succeeded';Command='FrozenCandidate integrity and provenance validation (no compilation)';Configuration='Release';ExitCode=0;ArtifactPath=$verified.ArtifactPath;ArtifactSha256=$verified.ArtifactSha256;ArtifactManifestPath=$verified.ManifestPath;ArtifactManifestSha256=$verified.ManifestSha256;ManifestPath=$verified.ManifestPath;ManifestSha256=$verified.ManifestSha256;WarningCount=0;ErrorCount=0;EvidenceSource='FrozenCandidate';CandidateProvenancePath=$verified.ProvenancePath;CandidateProvenanceSha256=$verified.ProvenanceSha256;CandidateSourceCommit=$verified.SourceCommit;WorkflowRevision=$mutation.Workflow.workflowRevision;TaskRevision=$mutation.TaskRevision;SideEffectsPerformed=$true}
}

function Bind-MayaQaFrozenCandidateBuildEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$CandidateDirectory,
        [string]$CandidateDllPath,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedSha256,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{7,40}$')][string]$ExpectedSourceCommit
    )
    $verified=Test-MayaQaFrozenCandidate -CandidateDirectory $CandidateDirectory -CandidateDllPath $CandidateDllPath -ExpectedSha256 $ExpectedSha256 -ExpectedSourceCommit $ExpectedSourceCommit -QaWorkflowId $QaWorkflowId
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if($workflow.qaWorkflowId -cne $QaWorkflowId){throw 'QA workflow identity mismatch.'}
    if($workflow.PSObject.Properties.Name -notcontains 'qaBuildRequest' -or !$workflow.qaBuildRequest.BuildRequestId){throw 'Persisted Neil build request is missing.'}
    $existing=if($workflow.PSObject.Properties.Name -contains 'qaBuildEvidence'){$workflow.qaBuildEvidence}else{$null}
    if($existing){
        foreach($n in 'BuildRequestId','SourceCommit','ArtifactPath','ArtifactSha256','ManifestPath','ManifestSha256'){
            if([string]$existing.$n -cne [string]$(if($n -eq 'BuildRequestId'){$workflow.qaBuildRequest.BuildRequestId}elseif($n -eq 'SourceCommit'){$verified.SourceCommit}elseif($n -eq 'ArtifactPath'){$verified.ArtifactPath}elseif($n -eq 'ArtifactSha256'){$verified.ArtifactSha256}elseif($n -eq 'ManifestPath'){$verified.ManifestPath}else{$verified.ManifestSha256})){throw "Frozen candidate evidence conflict: $n"}
        }
        return $existing
    }
    $now=(Get-Date).ToUniversalTime().ToString('O');$bound=[pscustomobject]@{BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;StartedUtc=$now;FinishedUtc=$now;Command='FrozenCandidate integrity and provenance validation (no compilation)';Configuration='Release';SourceCommit=$verified.SourceCommit;ExitCode=0;ArtifactPath=$verified.ArtifactPath;ArtifactSha256=$verified.ArtifactSha256;ManifestPath=$verified.ManifestPath;ManifestSha256=$verified.ManifestSha256;BuildStatus='succeeded';WarningCount=0;ErrorCount=0;ErrorLines=@();EvidenceSource='FrozenCandidate';CandidateDirectory=$verified.CandidateDirectory;CandidateProvenancePath=$verified.ProvenancePath;CandidateProvenanceSha256=$verified.ProvenanceSha256;CandidateSourceCommit=$verified.SourceCommit;QaWorkflowId=$verified.QaWorkflowId}
    $mutation=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {param($current)$current|Add-Member NoteProperty qaBuildStatus 'succeeded' -Force;$current|Add-Member NoteProperty qaBuildEvidence $bound -Force;return $current})[-1]
    $mutation.Workflow.qaBuildEvidence
}

function New-MayaQaCanonicalCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$TestId
    )
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if($workflow.PSObject.Properties.Name -contains 'qaWorkflowId' -and [string]$workflow.qaWorkflowId -cne $QaWorkflowId){throw 'QA workflow identity mismatch.'}
    if($TestId -cne $QaWorkflowId){throw 'QA test identity mismatch.'}
    if($workflow.PSObject.Properties.Name -notcontains 'qaBuildEvidence' -or $workflow.PSObject.Properties.Name -notcontains 'qaBuildStatus' -or $workflow.qaBuildStatus -cne 'succeeded'){throw 'Successful authenticated Neil build evidence is required.'}
    $e=$workflow.qaBuildEvidence
    foreach($n in 'BuildRequestId','SourceCommit','ArtifactPath','ArtifactSha256','ManifestPath','ManifestSha256'){if($e.PSObject.Properties.Name -notcontains $n -or [string]::IsNullOrWhiteSpace([string]$e.$n)){throw "Authenticated build evidence is missing $n."}}
    if([string]$e.SourceCommit -notmatch '^[A-Fa-f0-9]{40}$' -or [string]$e.ArtifactSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [string]$e.ManifestSha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Authenticated build evidence identity or hash is invalid.'}
    $repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$sourceBoundary=$null
    if($workflow.qaBuildRequest.AuthenticatedBuildSource){$sourceBoundary=Resolve-MayaQaAuthenticatedBuildSource $workflow.qaBuildRequest.AuthenticatedBuildSource
        if($sourceBoundary.RepositoryRoot -ine $repo -or ($sourceBoundary.ExpectedSourceCommit -and $sourceBoundary.ExpectedSourceCommit -ine [string]$e.SourceCommit)){throw 'Frozen candidate source is not bound to the authenticated build worktree.'}}
    $artifact=[IO.Path]::GetFullPath([string]$e.ArtifactPath);$expected=[IO.Path]::GetFullPath((Join-Path $repo 'bin\Release\net8.0-windows\Repato.Revit.dll'))
    if($artifact -ine $expected -or [IO.Path]::GetFileName($artifact) -cne 'Repato.Revit.dll'){throw 'Authenticated artifact is not the approved Release Repato.Revit.dll.'}
    if(!(Test-Path -LiteralPath $artifact -PathType Leaf)){throw 'Authenticated Neil artifact is missing.'}
    $actual=(Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash;if($actual -ine [string]$e.ArtifactSha256){throw 'Authenticated Neil artifact hash mismatch.'}
    $manifest=[IO.Path]::GetFullPath([string]$e.ManifestPath);$expectedManifest=[IO.Path]::GetFullPath((Join-Path $repo 'Repato.addin'))
    if($manifest -ine $expectedManifest -or !(Test-Path -LiteralPath $manifest -PathType Leaf) -or (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash -ine [string]$e.ManifestSha256){throw 'Authenticated add-in manifest hash mismatch.'}
    $candidateRepositoryRoot=if($sourceBoundary){$sourceBoundary.PrimaryRepositoryRoot}else{$repo};$root=[IO.Path]::GetFullPath((Join-Path $candidateRepositoryRoot 'DeploymentCandidates\AgentBuilds'));$name='ReleaseCandidate-'+([string]$e.SourceCommit).Substring(0,12);$dir=[IO.Path]::GetFullPath((Join-Path $root $name));$prefix=$root.TrimEnd('\')+'\'
    if(!$dir.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($dir) -ne $name){throw 'Canonical candidate path escaped the approved root.'}
    $dll=Join-Path $dir 'Repato.Revit.dll';$addin=Join-Path $dir 'Repato.addin';$prov=Join-Path $dir 'release-manifest.json'
    if(Test-Path -LiteralPath $dir){
        if(!(Test-Path -LiteralPath $dll -PathType Leaf) -or !(Test-Path -LiteralPath $addin -PathType Leaf) -or !(Test-Path -LiteralPath $prov -PathType Leaf)){throw 'Conflicting canonical candidate is incomplete.'}
        $p=try{Get-Content -LiteralPath $prov -Raw|ConvertFrom-Json -ErrorAction Stop}catch{throw 'Conflicting canonical candidate provenance is invalid.'}
        if((Get-FileHash $dll -Algorithm SHA256).Hash -ine [string]$e.ArtifactSha256 -or (Get-FileHash $addin -Algorithm SHA256).Hash -ine [string]$e.ManifestSha256 -or [string]$p.SourceCommit -cne [string]$e.SourceCommit -or [string]$p.FrozenArtifactSha256 -ine [string]$e.ArtifactSha256 -or [string]$p.ManifestSha256 -ine [string]$e.ManifestSha256 -or [string]$p.TaskId -cne $TaskId -or [string]$p.WorkflowId -cne $WorkflowId -or [string]$p.QaWorkflowId -cne $QaWorkflowId -or [string]$p.TestId -cne $TestId -or [string]$p.BuildRequestId -cne [string]$e.BuildRequestId){throw 'Conflicting canonical candidate identity or provenance.'}
        return [pscustomobject]@{CandidateDirectory=$dir;CandidateDllPath=$dll;CandidateProvenancePath=$prov;CandidateSourceCommit=$e.SourceCommit;NeilArtifactSha256=$e.ArtifactSha256;CandidateSha256=(Get-FileHash $dll -Algorithm SHA256).Hash;Reused=$true;SideEffectsPerformed=$false}
    }
    $tmp=$dir+'.tmp-'+[guid]::NewGuid().ToString('N');New-Item -ItemType Directory -Path $tmp -Force|Out-Null
    try { Copy-Item -LiteralPath $artifact -Destination (Join-Path $tmp 'Repato.Revit.dll');Copy-Item -LiteralPath $manifest -Destination (Join-Path $tmp 'Repato.addin');$p=[ordered]@{SchemaVersion=1;CandidateType='SyntheticReleaseCandidate';TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;TestId=$TestId;BuildRequestId=$e.BuildRequestId;SourceCommit=$e.SourceCommit;NeilArtifactSha256=$e.ArtifactSha256;ManifestSha256=$e.ManifestSha256;FrozenArtifactSha256=(Get-FileHash (Join-Path $tmp 'Repato.Revit.dll') -Algorithm SHA256).Hash;CandidateDllSha256=(Get-FileHash (Join-Path $tmp 'Repato.Revit.dll') -Algorithm SHA256).Hash;CandidateDirectory=$dir;CandidateDllPath=$dll;SupportedQaWorkflows=@($QaWorkflowId)};$p|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $tmp 'release-manifest.json') -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $dir
    } catch {Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue;throw}
    $candidateHash=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash;if($candidateHash -ine [string]$e.ArtifactSha256){throw 'Created candidate hash mismatch.'}
    [pscustomobject]@{CandidateDirectory=$dir;CandidateDllPath=$dll;CandidateProvenancePath=$prov;CandidateSourceCommit=$e.SourceCommit;NeilArtifactSha256=$e.ArtifactSha256;CandidateSha256=$candidateHash;Reused=$false;SideEffectsPerformed=$true}
}
function Resolve-MayaQaSourceRunnerManifestEvidence {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$TestId)
    $names=@{'create-plan-views-v1'='Repato.CreatePlanViews.TestRunner.addin';'create-levels-elevations-v1'='Repato.CreateLevels.TestRunner.addin';'create-grids-world-axis-v1'='Repato.CreateGrids.TestRunner.addin';'grid-bubble-visibility-v1'='Repato.GridBubbleVisibility.TestRunner.addin';'grid-bubble-offset-v1'='Repato.GridBubbleOffset.TestRunner.addin';'grid-resequence-v1'='Repato.GridResequence.TestRunner.addin'}
    if(!$names.ContainsKey($QaWorkflowId)-or $TestId -cne $QaWorkflowId){throw 'Source runner manifest identity is not compatible with the QA workflow.'}
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;$e=$workflow.qaBuildEvidence
    foreach($n in 'EvidenceSource','CandidateDirectory','CandidateSourceCommit','ArtifactSha256','CandidateProvenancePath'){if(!$e -or $e.PSObject.Properties.Name -notcontains $n -or [string]::IsNullOrWhiteSpace([string]$e.$n)){throw "Frozen candidate evidence is missing $n."}}
    if([string]$e.EvidenceSource -cne 'FrozenCandidate' -or $workflow.qaBuildStatus -cne 'succeeded'){throw 'Authenticated frozen-candidate evidence is required before source manifest attestation.'}
    $candidate=Test-MayaQaFrozenCandidate -CandidateDirectory $e.CandidateDirectory -ExpectedSha256 $e.ArtifactSha256 -ExpectedSourceCommit $e.CandidateSourceCommit -QaWorkflowId $QaWorkflowId
    if([string]$candidate.SourceCommit -cne [string]$e.CandidateSourceCommit -or [string]$candidate.ArtifactSha256 -ine [string]$e.ArtifactSha256){throw 'Source manifest candidate binding failed.'}
    $worktreeRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$worktreeQaRoot=[IO.Path]::GetFullPath((Join-Path $worktreeRoot 'QA'));$worktreeManifest=[IO.Path]::GetFullPath((Join-Path $worktreeQaRoot $names[$QaWorkflowId]));$activeRepositoryRoot=$worktreeRoot
    if($workflow.qaBuildRequest.AuthenticatedBuildSource){$sourceBoundary=Resolve-MayaQaAuthenticatedBuildSource $workflow.qaBuildRequest.AuthenticatedBuildSource
        if($sourceBoundary.RepositoryRoot -ine $worktreeRoot -or ($sourceBoundary.ExpectedSourceCommit -and $sourceBoundary.ExpectedSourceCommit -ine [string]$e.CandidateSourceCommit)){throw 'Source runner manifest is not bound to the authenticated build worktree.'}
        $activeRepositoryRoot=$sourceBoundary.PrimaryRepositoryRoot}
    $qaRoot=[IO.Path]::GetFullPath((Join-Path $activeRepositoryRoot 'QA'));$manifest=[IO.Path]::GetFullPath((Join-Path $qaRoot $names[$QaWorkflowId]));$root=$qaRoot.TrimEnd('\')+'\'
    if(!$manifest.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Source runner manifest escaped the approved QA root.'};if(!(Test-Path -LiteralPath $manifest -PathType Leaf) -or !(Test-Path -LiteralPath $worktreeManifest -PathType Leaf)){throw 'Trusted source runner manifest is missing.'}
    try{$xml=[xml](Get-Content -LiteralPath $manifest -Raw -ErrorAction Stop)}catch{throw 'Trusted source runner manifest is malformed.'}
    if(@($xml.RevitAddIns.AddIn|Where-Object Type -eq 'Application').Count -ne 1){throw 'Trusted source runner manifest application contract is invalid.'}
    $hash=(Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash;if((Get-FileHash -LiteralPath $worktreeManifest -Algorithm SHA256).Hash -ine $hash){throw 'Authenticated build runner manifest differs from the Launch Agent-approved source manifest.'};$data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId
    $oldEvidence=$workflow.qaBuildEvidence
    if($oldEvidence.PSObject.Properties.Name -contains 'RunnerManifestPath' -and $oldEvidence.RunnerManifestPath){
        $oldPath=[IO.Path]::GetFullPath([string]$oldEvidence.RunnerManifestPath);$legacyPath=[IO.Path]::GetFullPath((Join-Path 'C:\Repato-Autonomous\Worktrees\create-plan-views-buildfix-4f2cbba22ba9\QA' $names[$QaWorkflowId]))
        if($oldPath -ine $manifest -and $oldPath -ine $worktreeManifest -and $oldPath -ine $legacyPath){throw 'Persisted runner manifest is outside the authenticated source and approved candidate-worktree locations.'}
        if([string]$oldEvidence.RunnerManifestSha256 -ine $hash -or (Get-FileHash -LiteralPath $oldPath -Algorithm SHA256).Hash -ine $hash){throw 'Persisted runner manifest copy does not match trusted Source\QA content.'}
        if($oldPath -ieq $manifest -and $oldEvidence.PSObject.Properties.Name -contains 'RunnerManifestQaWorkflowId' -and [string]$oldEvidence.RunnerManifestQaWorkflowId -ceq $QaWorkflowId -and $oldEvidence.PSObject.Properties.Name -contains 'RunnerManifestTestId' -and [string]$oldEvidence.RunnerManifestTestId -ceq $TestId){return $oldEvidence}
    }
    $mutation=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {param($current)
        $old=$current.qaBuildEvidence;$previousPath=if($old.PSObject.Properties.Name -contains 'RunnerManifestPath'){[string]$old.RunnerManifestPath}else{$null};if($previousPath -and [IO.Path]::GetFullPath($previousPath) -ine $manifest){$old|Add-Member NoteProperty OriginalRunnerManifestPath $previousPath -Force}
        foreach($pair in @(@('RunnerManifestPath',$manifest),@('RunnerManifestSha256',$hash),@('RunnerManifestQaWorkflowId',$QaWorkflowId),@('RunnerManifestTestId',$TestId),@('RunnerManifestEvidenceStatus','authenticated-source'))){$old|Add-Member NoteProperty $pair[0] $pair[1] -Force}
        if($old.PSObject.Properties.Name -notcontains 'DeploymentValidation'){$old|Add-Member NoteProperty DeploymentValidation $false -Force};$current.qaBuildEvidence=$old;return $current
    })[-1]
    $mutation.Workflow.qaBuildEvidence
}
function New-MayaQaPersistedCandidateEvidence {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$TestId)
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;$e=$w.qaBuildEvidence
    foreach($n in 'CandidateSourceCommit','SourceCommit','CandidateDirectory','ArtifactPath','ArtifactSha256','RunnerManifestPath','RunnerManifestSha256','CandidateProvenancePath'){if(!$e -or $e.PSObject.Properties.Name -notcontains $n -or [string]::IsNullOrWhiteSpace([string]$e.$n)){throw "Authenticated candidate evidence is missing $n."}}
    $manifestNames=@{'create-plan-views-v1'='Repato.CreatePlanViews.TestRunner.addin';'create-levels-elevations-v1'='Repato.CreateLevels.TestRunner.addin';'create-grids-world-axis-v1'='Repato.CreateGrids.TestRunner.addin';'grid-bubble-visibility-v1'='Repato.GridBubbleVisibility.TestRunner.addin';'grid-bubble-offset-v1'='Repato.GridBubbleOffset.TestRunner.addin';'grid-resequence-v1'='Repato.GridResequence.TestRunner.addin'}
    if(!$manifestNames.ContainsKey($QaWorkflowId) -or $TestId -cne $QaWorkflowId -or $w.qaBuildStatus -cne 'succeeded' -or [string]$e.EvidenceSource -cne 'FrozenCandidate' -or [string]$e.SourceCommit -cne [string]$e.CandidateSourceCommit){throw 'Persisted candidate evidence identity or status is invalid.'}
    foreach($n in 'RunnerManifestQaWorkflowId','RunnerManifestTestId'){if($e.PSObject.Properties.Name -contains $n -and [string]$e.$n -cne $(if($n -eq 'RunnerManifestQaWorkflowId'){$QaWorkflowId}else{$TestId})){throw "Persisted candidate evidence identity is invalid: $n."}}
    $worktreeRunnerRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\QA'))
    $activeRepositoryRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    if($w.qaBuildRequest.AuthenticatedBuildSource){$sourceBoundary=Resolve-MayaQaAuthenticatedBuildSource $w.qaBuildRequest.AuthenticatedBuildSource -AllowHistoricalCommit
        if($sourceBoundary.RepositoryRoot -ine $activeRepositoryRoot -or ($sourceBoundary.ExpectedSourceCommit -and $sourceBoundary.ExpectedSourceCommit -ine [string]$e.SourceCommit)){throw 'Persisted candidate is not bound to the authenticated build worktree.'}
        $activeRepositoryRoot=$sourceBoundary.PrimaryRepositoryRoot}
    $runnerRoot=[IO.Path]::GetFullPath((Join-Path $activeRepositoryRoot 'QA'));$runnerPath=[IO.Path]::GetFullPath((Join-Path $runnerRoot $manifestNames[$QaWorkflowId]));$worktreeRunnerPath=[IO.Path]::GetFullPath((Join-Path $worktreeRunnerRoot $manifestNames[$QaWorkflowId]));$installedPath=[IO.Path]::GetFullPath((Join-Path 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025' $manifestNames[$QaWorkflowId]));$externalRunnerPath=[IO.Path]::GetFullPath((Join-Path 'C:\Repato-Autonomous\Worktrees\create-plan-views-buildfix-4f2cbba22ba9\QA' $manifestNames[$QaWorkflowId]))
    $sourceRunnerHash=if(Test-Path -LiteralPath $worktreeRunnerPath -PathType Leaf){(Get-FileHash -LiteralPath $worktreeRunnerPath -Algorithm SHA256).Hash}else{$null}
    if(!$sourceRunnerHash -or $sourceRunnerHash -ine $e.RunnerManifestSha256 -or !(Test-Path -LiteralPath $runnerPath -PathType Leaf) -or (Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash -ine $sourceRunnerHash -or [IO.Path]::GetFullPath($e.RunnerManifestPath) -notin @($runnerPath,$worktreeRunnerPath,$installedPath,$externalRunnerPath)){throw 'Persisted candidate runner manifest does not match trusted source evidence.'}
    if([IO.Path]::GetFullPath($e.RunnerManifestPath) -ine $runnerPath -and (!(Test-Path -LiteralPath $e.RunnerManifestPath -PathType Leaf) -or (Get-FileHash -LiteralPath $e.RunnerManifestPath -Algorithm SHA256).Hash -ine $sourceRunnerHash)){throw 'Persisted candidate runner manifest copy differs from trusted source evidence.'}
    $candidate=New-RepatoCandidateEvidence -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $QaWorkflowId -TestId $TestId -CandidateSourceCommit $e.CandidateSourceCommit -CandidateDirectory $e.CandidateDirectory -CandidateDllPath $e.ArtifactPath -CandidateDllSha256 $e.ArtifactSha256 -NeilBuildArtifactSha256 $e.ArtifactSha256 -RunnerManifestPath $runnerPath -RunnerManifestSha256 $e.RunnerManifestSha256 -CandidateProvenancePath $e.CandidateProvenancePath
    $root=[IO.Path]::GetFullPath((Join-Path $activeRepositoryRoot 'DeploymentCandidates\AgentBuilds'))
    $null=Resolve-RepatoCandidateEvidence -Evidence $candidate -AuthenticatedEvidence $candidate -ApprovedCandidateRoot $root -ApprovedRunnerManifestRoot $runnerRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $QaWorkflowId -TestId $TestId
    $candidate
}
function New-MayaQaHandoff {
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [switch]$DryRun
    )

    $QaWorkflowId = Resolve-MayaQaWorkflowId $QaWorkflowId
    $definition = Get-MayaQaWorkflowDefinition $QaWorkflowId
    if ($DryRun) {
        return [pscustomobject]@{
            HandoffId = 'handoff-' + [guid]::NewGuid().ToString('N')
            TaskId = $TaskId
            WorkflowId = $WorkflowId
            QaWorkflowId = $QaWorkflowId
            NativeTestId = Get-MayaQaNativeTestId $definition
            HandoffStatus = 'planned'
            SideEffectsPerformed = $false
        }
    }

    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $properties = @($workflow.PSObject.Properties.Name)
    if ($properties -notcontains 'qaBuildRequest' -or $null -eq $workflow.qaBuildRequest) {
        throw 'Completed Neil build request is missing.'
    }
    if ($properties -notcontains 'qaBuildEvidence' -or $properties -notcontains 'qaBuildStatus' -or $workflow.qaBuildStatus -ne 'succeeded' -or $workflow.qaBuildEvidence.PSObject.Properties.Name -notcontains 'SourceCommit' -or [string]::IsNullOrWhiteSpace([string]$workflow.qaBuildEvidence.SourceCommit)) {
        throw 'Successful Neil build execution is required.'
    }
    if ($properties -contains 'qaHandoffId' -and $workflow.qaHandoffId) {
        throw 'Tara QA handoff already exists.'
    }

    $evidence = $workflow.qaBuildEvidence
    if($evidence.PSObject.Properties.Name -contains 'EvidenceSource' -and $evidence.EvidenceSource -ceq 'FrozenCandidate'){
        if([string]::IsNullOrWhiteSpace([string]$evidence.CandidateDirectory) -or [string]::IsNullOrWhiteSpace([string]$evidence.CandidateSourceCommit)){throw 'Frozen candidate handoff evidence is incomplete.'}
        $provenancePath=Join-Path $evidence.CandidateDirectory 'release-manifest.json'
        if(!(Test-Path -LiteralPath $provenancePath -PathType Leaf)){throw 'Frozen candidate handoff provenance is missing.'}
        $provenance=Get-Content -LiteralPath $provenancePath -Raw|ConvertFrom-Json
        $candidate=Test-MayaQaFrozenCandidate -CandidateDirectory $evidence.CandidateDirectory -ExpectedSha256 ([string]$provenance.FrozenArtifactSha256) -ExpectedSourceCommit $evidence.CandidateSourceCommit -QaWorkflowId $QaWorkflowId
        if($candidate.SourceCommit -ine [string]$evidence.CandidateSourceCommit){throw 'Frozen candidate handoff provenance mismatch.'}
        if($evidence.PSObject.Properties.Name -contains 'DeploymentValidation'){
            if([string]::IsNullOrWhiteSpace([string]$evidence.RunnerManifestPath) -or [string]$evidence.RunnerManifestPath -notmatch '\\Repato\.CreatePlanViews\.TestRunner\.addin$' -or [string]$evidence.RunnerManifestSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [string]::IsNullOrWhiteSpace([string]$evidence.DeployedRunnerManifestPath) -or [string]$evidence.DeployedRunnerManifestPath -notmatch '\\Repato\.CreatePlanViews\.TestRunner\.addin$' -or [string]$evidence.DeployedRunnerManifestSha256 -ine [string]$evidence.RunnerManifestSha256 -or !$evidence.DeploymentValidation -or !$evidence.ManifestIntegrityValidation -or !$evidence.QaIsolation){throw 'Validated RepatoQA runner manifest evidence is missing or invalid.'}
            $evidence=[pscustomobject]@{ArtifactPath=$candidate.ArtifactPath;ArtifactSha256=$candidate.ArtifactSha256;ManifestPath=$candidate.ManifestPath;ManifestSha256=$candidate.ManifestSha256;CandidateDirectory=$candidate.CandidateDirectory;CandidateProvenancePath=$candidate.ProvenancePath;CandidateSourceCommit=$candidate.SourceCommit;EvidenceSource='FrozenCandidate';RunnerManifestPath=$evidence.RunnerManifestPath;RunnerManifestSha256=$evidence.RunnerManifestSha256;DeployedRunnerManifestPath=$evidence.DeployedRunnerManifestPath;DeployedRunnerManifestSha256=$evidence.DeployedRunnerManifestSha256;DeploymentValidation=$evidence.DeploymentValidation;ManifestIntegrityValidation=$evidence.ManifestIntegrityValidation;QaIsolation=$evidence.QaIsolation;QaAddinRoot=$evidence.QaAddinRoot;Isolation=$evidence.Isolation}
        }
    }
    $taskData=Read-RepatoTaskStore $StoreRoot; $task=Find-RepatoTask $taskData $TaskId
    $approvedApproval=@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved'})[-1]
    if($null -eq $approvedApproval){throw 'Approved qa-run approval is required before Tara handoff.'}
    foreach ($item in @(
        @('artifact', $evidence.ArtifactPath, $evidence.ArtifactSha256),
        @('manifest', $evidence.ManifestPath, $evidence.ManifestSha256)
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$item[1]) -or !(Test-Path -LiteralPath $item[1] -PathType Leaf)) {
            throw "Built $($item[0]) is missing."
        }
        $actualHash = (Get-FileHash -LiteralPath $item[1] -Algorithm SHA256).Hash
        if ($actualHash -ine [string]$item[2]) {
            throw "Built $($item[0]) hash mismatch."
        }
    }
    $artifactHash = (Get-FileHash -LiteralPath $evidence.ArtifactPath -Algorithm SHA256).Hash
    $manifestHash = (Get-FileHash -LiteralPath $evidence.ManifestPath -Algorithm SHA256).Hash
    $handoffId = 'handoff-' + [guid]::NewGuid().ToString('N')
    if($properties -notcontains 'qaRunId' -or [string]::IsNullOrWhiteSpace([string]$workflow.qaRunId)){throw 'Canonical workflow qaRunId is required before Tara handoff.'}
    $coordinatorRunId = [string]$workflow.qaRunId
    $data = Read-RepatoTaskStore $StoreRoot
    $mutation = @(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {
        param($current)
        $handoff = [pscustomobject]@{
            HandoffId = $handoffId
            TaskId = $TaskId
            BuildRequestId = $current.qaBuildRequest.BuildRequestId
            ArtifactPath = $evidence.ArtifactPath
            ArtifactSha256 = $artifactHash
            ManifestPath = $evidence.ManifestPath
            ManifestSha256 = $manifestHash
            RunnerManifestPath = $evidence.RunnerManifestPath
            ValidatedRunnerManifestPath = $evidence.DeployedRunnerManifestPath
            ValidatedRunnerManifestSha256 = $evidence.DeployedRunnerManifestSha256
            RunnerManifestSha256 = $evidence.RunnerManifestSha256
            QaAddinRoot = $evidence.QaAddinRoot
            Isolation = $evidence.Isolation
            QaWorkflowId = $QaWorkflowId
            FixtureId = $definition.FixtureId
            NativeTestId = Get-MayaQaNativeTestId $definition
            PreparationScript = $definition.Prep
            ModelPath = $(if($current.PSObject.Properties.Name -contains 'qaModelPath'){$current.qaModelPath}else{$null})
            SidecarPath = $(if($current.PSObject.Properties.Name -contains 'qaSidecarPath'){$current.qaSidecarPath}else{$null})
            CoordinatorRunId = $coordinatorRunId
            HandoffStatus = 'ready'
            QaApprovalId = $approvedApproval.requestId
            QaApprovalStatus = 'approved'
            RequestIntent = $(if($current.PSObject.Properties.Name -contains 'qaRequestIntent'){$current.qaRequestIntent}else{$null})
            CreatedUtc = (Get-Date).ToUniversalTime().ToString('O')
        }
        $current | Add-Member -NotePropertyName qaHandoffId -NotePropertyValue $handoffId -Force
        $current | Add-Member -NotePropertyName qaHandoff -NotePropertyValue $handoff -Force
        $current | Add-Member -NotePropertyName qaApprovalId -NotePropertyValue $approvedApproval.requestId -Force
        $current | Add-Member -NotePropertyName qaApprovalStatus -NotePropertyValue 'approved' -Force
        return $current
    })[-1]
    $handoffPath=Join-Path (Join-Path $StoreRoot 'handoffs') ($handoffId+'.json');New-Item -ItemType Directory -Path (Split-Path $handoffPath -Parent) -Force|Out-Null
    [ordered]@{StoreRoot=$StoreRoot;TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;RunId=$workflow.qaRunId;HandoffId=$handoffId;NativeTestId=(Get-MayaQaNativeTestId $definition);QaApprovalId=$approvedApproval.requestId;QaApprovalStatus='approved';ModelPath=$workflow.qaModelPath;SidecarPath=$workflow.qaSidecarPath;ArtifactPath=$evidence.ArtifactPath;ArtifactSha256=$artifactHash;ManifestPath=$evidence.ManifestPath;ManifestSha256=$manifestHash}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $handoffPath -Encoding UTF8
    [pscustomobject]@{
        HandoffId = $handoffId
        TaskId = $TaskId
        WorkflowId = $WorkflowId
        BuildRequestId = $workflow.qaBuildRequest.BuildRequestId
        ArtifactPath = $evidence.ArtifactPath
        ArtifactSha256 = $artifactHash
        ManifestPath = $evidence.ManifestPath
        ManifestSha256 = $manifestHash
        RunnerManifestPath = $evidence.RunnerManifestPath
        ValidatedRunnerManifestPath = $evidence.DeployedRunnerManifestPath
        ValidatedRunnerManifestSha256 = $evidence.DeployedRunnerManifestSha256
        RunnerManifestSha256 = $evidence.RunnerManifestSha256
        QaAddinRoot = $evidence.QaAddinRoot
        Isolation = $evidence.Isolation
        QaWorkflowId = $QaWorkflowId
        FixtureId = $definition.FixtureId
        NativeTestId = Get-MayaQaNativeTestId $definition
        PreparationScript = $definition.Prep
        ModelPath = $(if($properties -contains 'qaModelPath'){$workflow.qaModelPath}else{$null})
        SidecarPath = $(if($properties -contains 'qaSidecarPath'){$workflow.qaSidecarPath}else{$null})
        CoordinatorRunId = $coordinatorRunId
        HandoffStatus = 'ready'
        HandoffPath = $handoffPath
        QaApprovalId = $approvedApproval.requestId
        QaApprovalStatus = 'approved'
        RequestIntent = $(if($properties -contains 'qaRequestIntent'){$workflow.qaRequestIntent}else{$null})
        WorkflowRevision = $mutation.Workflow.workflowRevision
        TaskRevision = $mutation.TaskRevision
        SideEffectsPerformed = $true
    }
}

function Reconcile-MayaQaDuplicatePendingApprovals {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$BuildRequestId,[Parameter(Mandatory)][string]$CandidateSourceCommit,[Parameter(Mandatory)][string]$CandidateSha256,[ValidateRange(1,240)][int]$ExpiryMinutes=30)
    if($CandidateSourceCommit -notmatch '^[A-Fa-f0-9]{40}$' -or $CandidateSha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Approval reconciliation candidate identity is invalid.'}
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$workflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId)
    if(!$task -or $workflows.Count -ne 1 -or [string]$workflows[0].qaBuildEvidence.BuildRequestId -cne $BuildRequestId -or [string]$workflows[0].qaBuildEvidence.CandidateSourceCommit -cne $CandidateSourceCommit -or [string]$workflows[0].qaBuildEvidence.ArtifactSha256 -ine $CandidateSha256){throw 'Approval reconciliation candidate binding mismatch.'}
    if($task.status -cne 'awaiting-approval' -or $task.workflowStage -cne 'approval'){throw 'Approval reconciliation requires an awaiting-approval task.'}
    foreach($n in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){if($task.PSObject.Properties.Name -contains $n -and $task.$n){throw 'Approval reconciliation found active QA state.'}}
    if(($task.PSObject.Properties.Name -contains 'taraRuns') -and @($task.taraRuns|Where-Object {$_ -and $_.status -in @('running','passed','completed')}).Count){throw 'Approval reconciliation found a launched QA run.'}
    $pending=@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})
    if($pending.Count -lt 2 -or @($task.approvalRequests|Where-Object {$_.status -ceq 'pending' -and $_.action -cne 'qa-run'}).Count){throw 'Only duplicate pending QA approvals may be reconciled.'}
    if(@($pending|Where-Object {[string]::IsNullOrWhiteSpace([string]$_.requestId) -or [DateTimeOffset]::Parse($_.expiresUtc) -gt [DateTimeOffset]::UtcNow}).Count){throw 'Only expired duplicate QA approvals may be superseded.'}
    $requestIds=@($pending|ForEach-Object {[string]$_.requestId});$expectedRevision=[long]$task.revision
    Invoke-RepatoStoreMutation $StoreRoot {param($d,$preview)
        $t=Find-RepatoTask $d $TaskId
        if([long]$t.revision -ne $expectedRevision -or $t.status -cne 'awaiting-approval' -or $t.workflowStage -cne 'approval'){throw 'Approval state changed during reconciliation.'}
        foreach($n in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){if($t.PSObject.Properties.Name -contains $n -and $t.$n){throw 'QA state appeared during approval reconciliation.'}}
        if(($t.PSObject.Properties.Name -contains 'taraRuns') -and @($t.taraRuns|Where-Object {$_ -and $_.status -in @('running','passed','completed')}).Count){throw 'A QA run appeared during approval reconciliation.'}
        $ws=@($t.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId);if($ws.Count -ne 1 -or [string]$ws[0].qaBuildEvidence.BuildRequestId -cne $BuildRequestId -or [string]$ws[0].qaBuildEvidence.CandidateSourceCommit -cne $CandidateSourceCommit -or [string]$ws[0].qaBuildEvidence.ArtifactSha256 -ine $CandidateSha256){throw 'Candidate binding changed during approval reconciliation.'}
        $all=@($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'});$ids=@($all|ForEach-Object {[string]$_.requestId})
        if($all.Count -ne $requestIds.Count -or (@(Compare-Object -ReferenceObject $requestIds -DifferenceObject $ids).Count -ne 0)){throw 'Pending QA approvals changed during reconciliation.'}
        if(@($all|Where-Object {[DateTimeOffset]::Parse($_.expiresUtc) -gt [DateTimeOffset]::UtcNow}).Count){throw 'A QA approval was renewed during reconciliation.'}
        foreach($q in $all){$q.status='superseded';$q.reason='Expired request superseded by guarded duplicate-approval recovery.'}
        $q=[pscustomobject]@{requestId=[guid]::NewGuid().ToString('N');action='qa-run';requiredLevel='user';status='pending';bindingHash='';previousStatus='passed';requestedRevision=[long]0;approvedRevision=$null;requestedUtc=Get-RepatoUtc;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes($ExpiryMinutes).ToString('O');decidedUtc=$null;decidedBy=$null;reason=$null;consumedUtc=$null}
        $t.approvalRequests=[object[]]@($t.approvalRequests)+$q;$t.status='awaiting-approval';$t.workflowStage='approval'
        Add-RepatoHistory $t 'expired-qa-approvals-reconciled' 'Maya' ("superseded="+($requestIds -join ',')+"; new="+$q.requestId+"; build="+$BuildRequestId)
        $q.requestedRevision=[long]$t.revision;$t
    }
}

function Request-MayaQaCanonicalApprovalRefresh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$BuildRequestId,[ValidateSet('maya','user')][string]$ApprovalLevel='maya',[ValidateRange(1,240)][int]$ExpiryMinutes=30
    )
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if([string]$workflow.qaWorkflowId -cne $QaWorkflowId -or [string]$workflow.qaBuildRequest.BuildRequestId -cne $BuildRequestId){throw 'Canonical QA identity mismatch.'}
    $e=$workflow.qaBuildEvidence
    if([string]$workflow.qaBuildStatus -cne 'succeeded' -or !$e -or [string]$e.BuildRequestId -cne $BuildRequestId -or [string]$e.BuildStatus -cne 'succeeded' -or [string]$e.EvidenceSource -cne 'FrozenCandidate'){throw 'Canonical build evidence is invalid.'}
    foreach($n in 'SourceCommit','CandidateSourceCommit','ArtifactSha256','CandidateProvenancePath','RunnerManifestPath','RunnerManifestSha256'){if($e.PSObject.Properties.Name -notcontains $n -or [string]::IsNullOrWhiteSpace([string]$e.$n)){throw "Canonical candidate evidence is missing $n."}}
    if([string]$e.SourceCommit -cne [string]$e.CandidateSourceCommit -or [string]$e.CandidateSourceCommit -notmatch '^[A-Fa-f0-9]{40}$' -or [string]$e.ArtifactSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [string]$e.RunnerManifestSha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Canonical candidate evidence identity or hash is invalid.'}
    if(!$e.DeploymentValidation -or !$e.ManifestIntegrityValidation -or !$e.QaIsolation){throw 'Canonical deployment evidence is missing or failed.'}
    $d=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $d $TaskId
    if($task.status -cne 'awaiting-approval' -or $task.workflowStage -cne 'approval'){throw 'Canonical task is not awaiting approval.'}
    if($task.PSObject.Properties.Name -contains 'mayaTaraExecution' -and $task.mayaTaraExecution){throw 'Tara execution has begun.'}
    if($task.PSObject.Properties.Name -contains 'mayaTaraAttempt' -and $task.mayaTaraAttempt){throw 'Tara attempt already exists.'}
    if($task.PSObject.Properties.Name -contains 'taraRuns' -and @($task.taraRuns|Where-Object {$_ -and $_.status -in @('running','passed','completed')}).Count){throw 'Native QA has already begun.'}
    $pending=@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})
    if($pending.Count -ne 1){throw 'Exactly one pending QA approval is required.'}
    $old=$pending[0];$expired=[DateTimeOffset]::Parse($old.expiresUtc) -le [DateTimeOffset]::UtcNow;$stale=[long]$old.requestedRevision -ne [long]$task.revision
    if(!$expired -and !$stale){throw 'Current QA approval request is still valid.'}
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)
        $t=Find-RepatoTask $data $TaskId;$current=@($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})
        if($current.Count -ne 1){throw 'Approval changed during refresh.'};$current[0].status='superseded';$current[0].reason='Replaced by canonical approval refresh.'
        $q=[pscustomobject]@{requestId=[guid]::NewGuid().ToString('N');action='qa-run';requiredLevel=$ApprovalLevel;status='pending';bindingHash='';previousStatus='passed';requestedRevision=[long]0;approvedRevision=$null;requestedUtc=Get-RepatoUtc;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes($ExpiryMinutes).ToString('O');decidedUtc=$null;decidedBy=$null;reason=$null;consumedUtc=$null}
        $t.approvalRequests=[object[]]@($t.approvalRequests)+$q;$t.status='awaiting-approval';$t.workflowStage='approval';Add-RepatoHistory $t 'approval-refreshed' 'Maya' 'qa-run';$q.requestedRevision=[long]$t.revision;$t
    }
}

function Request-MayaQaCanonicalExecutionApproval {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$BuildRequestId,[Parameter(Mandatory)][long]$ExpectedTaskRevision,[Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{40}$')][string]$CandidateSourceCommit,[Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$CandidateSha256,[ValidateRange(1,240)][int]$ExpiryMinutes=30)
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;$task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId;$e=$workflow.qaBuildEvidence
    if(!$task -or [long]$task.revision -ne $ExpectedTaskRevision -or [string]$workflow.taskId -cne $TaskId -or [string]$workflow.qaWorkflowId -cne 'create-plan-views-v1'){throw 'Canonical approval task/workflow revision or QA identity is stale.'}
    if(!$task -or $workflow.qaBuildStatus -cne 'succeeded' -or !$e -or $e.BuildRequestId -cne $BuildRequestId -or $e.BuildStatus -cne 'succeeded' -or $e.EvidenceSource -cne 'FrozenCandidate' -or $e.SourceCommit -cne $CandidateSourceCommit -or $e.CandidateSourceCommit -cne $CandidateSourceCommit -or $e.ArtifactSha256 -ine $CandidateSha256){throw 'Canonical approval candidate identity is invalid.'}
    if($e.DeploymentValidation -ne $true -or $e.ManifestIntegrityValidation -ne $true -or $e.QaIsolation -ne $true){throw 'Candidate deployment validation, manifest integrity, and isolation must pass before approval.'}
    $expiredApprovalRefresh=$null
    if($task.status -cne 'in-progress'){throw 'Canonical execution approval requires an in-progress task.'}
    if($task.workflowStage -ceq 'approval'){
        $expiredApprovalRefresh=Get-MayaQaExpiredApprovedCanonicalRequestForRefresh -Task $task -Workflow $workflow
        if(!$expiredApprovalRefresh){throw 'Approval-stage refresh requires one expired, unconsumed human approval bound to the unchanged canonical run.'}
    }elseif($task.workflowStage -cne 'qa'){throw 'Canonical execution approval requires the validated QA-ready state.'}
    $activeQaApprovals=@(Get-MayaQaActiveCanonicalExecutionApprovals -Approvals @($task.approvalRequests))
    if($activeQaApprovals.Count){throw 'An active or previously approved QA request prevents fresh approval creation.'}
    foreach($n in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){if($task.PSObject.Properties.Name -contains $n -and $task.$n){throw 'Canonical execution approval found existing Tara execution state.'}}
    if($task.PSObject.Properties.Name -contains 'taraRuns' -and @($task.taraRuns|Where-Object {$_ -and $_.status -in @('running','passed','completed')}).Count){throw 'Canonical execution approval found existing native QA execution.'}
    if(@(Get-Process Revit -ErrorAction SilentlyContinue).Count){throw 'Canonical execution approval requires Revit to be stopped.'}
    if($workflow.qaRunId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$' -or !$workflow.qaModelPath -or !$workflow.qaSidecarPath -or !$workflow.qaFixtureSha256){throw 'Canonical execution plan is incomplete.'}
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\';$storePath=[IO.Path]::GetFullPath($StoreRoot);$runtime=[IO.Path]::GetFullPath($(if($storePath.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)){$env:TEMP}else{Get-MayaQaRuntimeRoot}));$model=[IO.Path]::GetFullPath([string]$workflow.qaModelPath);$sidecar=[IO.Path]::GetFullPath([string]$workflow.qaSidecarPath)
    if(!$model.StartsWith($runtime.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or !$sidecar.StartsWith($runtime.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $model -PathType Leaf) -or !(Test-Path -LiteralPath $sidecar -PathType Leaf)){throw 'Canonical disposable model is missing or outside the approved QA runtime.'}
    $modelHash=(Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash;$definition=Get-MayaQaWorkflowDefinition $workflow.qaWorkflowId
    $expectedRecoveredHash=if($workflow.qaFixturePreparationEvidence -and $workflow.qaFixturePreparationEvidence.PSObject.Properties['RecoveredProvenanceSha256']){[string]$workflow.qaFixturePreparationEvidence.RecoveredProvenanceSha256}else{''}
    $sidecarData=Read-CpvFixtureProvenance -SidecarPath $sidecar -ExpectedRecoveredProvenanceSha256 $expectedRecoveredHash
    if($workflow.qaWorkflowId -cne 'create-plan-views-v1' -or $workflow.qaTestId -cne $workflow.qaWorkflowId -or $workflow.qaFixtureId -cne $definition.FixtureId -or $sidecarData.fixtureId -cne $workflow.qaFixtureId -or $sidecarData.sourceSha256 -ine $workflow.qaFixtureSha256 -or $modelHash -ine $workflow.qaDisposableModelSha256){throw 'Canonical execution plan fixture or model identity is invalid.'}
    $candidate=New-MayaQaPersistedCandidateEvidence -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $workflow.qaWorkflowId -TestId $workflow.qaWorkflowId
    $deploymentBinding=Get-RepatoCanonicalQaDeploymentApprovalEvidence -Task $task -Workflow $workflow -BuildRequestId $BuildRequestId -CandidateSourceCommit $CandidateSourceCommit -CandidateSha256 $CandidateSha256 -RunnerManifestPath $candidate.RunnerManifestPath -RunnerManifestSha256 $candidate.RunnerManifestSha256
    $plan=[pscustomobject][ordered]@{TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$workflow.qaWorkflowId;Stage='qa-prepared';ActiveAgent='Maya';NextAgent='Tara';NextOperation='canonical-execution-record';SideEffectsPerformed=$false}
    $binding=[ordered]@{SchemaVersion='maya-qa-canonical-execution-approval-v1';TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$workflow.qaWorkflowId;BuildRequestId=$BuildRequestId;CandidateSourceCommit=$CandidateSourceCommit;CandidateSha256=$CandidateSha256;CandidateProvenancePath=$e.CandidateProvenancePath;CandidateProvenanceSha256=(Get-FileHash -LiteralPath $e.CandidateProvenancePath -Algorithm SHA256).Hash;RunnerManifestPath=$candidate.RunnerManifestPath;RunnerManifestSha256=$candidate.RunnerManifestSha256;DeploymentValidation=$true;ManifestIntegrityValidation=$true;QaIsolation=$true;DeploymentValidationEvidence=$deploymentBinding;ExecutionPlan=$plan;RunId=$workflow.qaRunId;ModelPath=$model;ModelSha256=$modelHash;SidecarPath=$sidecar;SidecarSha256=(Get-FileHash -LiteralPath $sidecar -Algorithm SHA256).Hash;FixtureId=$workflow.qaFixtureId;FixtureSha256=$workflow.qaFixtureSha256;FixturePreparationEvidence=$(if($workflow.PSObject.Properties['qaFixturePreparationEvidence']){$workflow.qaFixturePreparationEvidence}else{$null});RequiredExecutor='Tara';RevitVersion='2025'}
    if($expectedRecoveredHash){$binding['NativeContinuation']=New-CpvNativeContinuationBinding -Task $task -Workflow $workflow -ExpectedTaskRevision $ExpectedTaskRevision}
    $json=ConvertTo-Json -InputObject $binding -Depth 20 -Compress;$sha=[Security.Cryptography.SHA256]::Create();try{$bindingHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}finally{$sha.Dispose()}
    $expectedRevision=[long]$ExpectedTaskRevision;$expectedStage=[string]$task.workflowStage
    $updated=Invoke-RepatoStoreMutation $StoreRoot {
        param($data,$preview)
        $current=Find-RepatoTask $data $TaskId
        if([long]$current.revision -ne $expectedRevision -or $current.status -cne 'in-progress' -or $current.workflowStage -cne $expectedStage){throw 'Canonical approval compare-and-swap state changed.'}
        if($expectedStage -ceq 'approval'){
            $latest=Get-MayaQaExpiredApprovedCanonicalRequestForRefresh -Task $current -Workflow (Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId)
            if(!$latest -or $latest.requestId -cne $expiredApprovalRefresh.requestId){throw 'Expired approval refresh source changed during request creation.'}
        }
        if(Test-MayaQaHasActiveCanonicalExecutionApproval -Approvals @($current.approvalRequests)){throw 'An active QA approval appeared during request creation.'}
        $ws=@($current.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId)
        if($ws.Count -ne 1 -or $ws[0].qaBuildEvidence.ArtifactSha256 -ine $CandidateSha256 -or $ws[0].qaBuildEvidence.CandidateSourceCommit -cne $CandidateSourceCommit -or $ws[0].qaBuildEvidence.RunnerManifestSha256 -ine $binding.RunnerManifestSha256){throw 'Candidate or manifest changed during approval creation.'}
        $latestProof=Get-RepatoCanonicalQaDeploymentApprovalEvidence -Task $current -Workflow $ws[0] -BuildRequestId $BuildRequestId -CandidateSourceCommit $CandidateSourceCommit -CandidateSha256 $CandidateSha256 -RunnerManifestPath $binding.RunnerManifestPath -RunnerManifestSha256 $binding.RunnerManifestSha256
        if((ConvertTo-Json -InputObject $latestProof -Depth 20 -Compress) -cne (ConvertTo-Json -InputObject $binding.DeploymentValidationEvidence -Depth 20 -Compress)){throw 'Deployment-validation evidence changed during approval creation.'}
        if($binding.Contains('NativeContinuation')){Assert-CpvNativeContinuationBinding -Task $current -Workflow $ws[0] -Binding $binding.NativeContinuation}
        $q=[pscustomobject][ordered]@{requestId=[guid]::NewGuid().ToString('N');action='qa-run';requiredLevel='user';status='pending';bindingHash=$bindingHash;executionBinding=$binding;previousStatus='in-progress';refreshedRequestId=$(if($expiredApprovalRefresh){$expiredApprovalRefresh.requestId}else{$null});requestedRevision=[long]0;approvedRevision=$null;requestedUtc=Get-RepatoUtc;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes($ExpiryMinutes).ToString('O');decidedUtc=$null;decidedBy=$null;reason=$null;consumedUtc=$null}
        $current.approvalRequests=[object[]]@($current.approvalRequests)+$q
        $current.status='awaiting-approval'
        $current.workflowStage='approval'
        Add-RepatoHistory $current 'approval-requested' 'Maya' 'qa-run bound to validated candidate, deployment evidence, manifest, isolation, and execution plan'
        $q.requestedRevision=[long]$current.revision
        $current
    }
    @($updated.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})[-1]
}

function Request-MayaQaValidatedCandidateApproval {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][long]$ExpectedTaskRevision,[ValidateSet('maya','user')][string]$ApprovalLevel='user',[ValidateRange(1,240)][int]$ExpiryMinutes=30)
    $updated=Invoke-RepatoStoreMutation $StoreRoot {
        param($data,$preview)
        $task=Find-RepatoTask $data $TaskId
        if([long]$task.revision -ne $ExpectedTaskRevision){throw 'QA approval task revision changed.'}
        if($task.status -cne 'passed' -or $task.workflowStage -cne 'qa'){throw 'Validated candidate approval requires a passed QA-stage task.'}
        $workflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId)
        if($workflows.Count -ne 1 -or [string]$workflows[0].taskId -cne $TaskId){throw 'Validated candidate approval task/workflow binding is invalid.'}
        $workflow=$workflows[0];$e=$workflow.qaBuildEvidence
        if($workflow.qaBuildStatus -cne 'succeeded' -or !$e -or $e.BuildStatus -cne 'succeeded' -or $e.EvidenceSource -cne 'FrozenCandidate' -or
           [string]$e.SourceCommit -cne [string]$e.CandidateSourceCommit -or [string]$e.CandidateSourceCommit -notmatch '^[A-Fa-f0-9]{40}$' -or
           [string]$e.ArtifactSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [string]$e.RunnerManifestSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
           $e.DeploymentValidation -ne $true -or $e.ManifestIntegrityValidation -ne $true -or $e.QaIsolation -ne $true){throw 'Deployment, manifest integrity, and QA isolation validations must all pass before approval.'}
        if(@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'}).Count){throw 'A pending QA approval already exists.'}
        $request=[pscustomobject]@{requestId=[guid]::NewGuid().ToString('N');action='qa-run';requiredLevel=$ApprovalLevel;status='pending';bindingHash='';previousStatus='passed';requestedRevision=[long]0;approvedRevision=$null;requestedUtc=Get-RepatoUtc;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes($ExpiryMinutes).ToString('O');decidedUtc=$null;decidedBy=$null;reason=$null;consumedUtc=$null}
        $task.approvalRequests=[object[]]@($task.approvalRequests)+$request;$task.status='awaiting-approval';$task.workflowStage='approval';Add-RepatoHistory $task 'approval-requested' 'Maya' 'qa-run after validated frozen candidate adoption';$request.requestedRevision=[long]$task.revision;$task
    }
    @($updated.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})[-1]
}

function Request-MayaQaRecoveredNativeFailureApproval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$FailedAttemptId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$RecoveredAttemptId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$RecoveredRunId,
        [Parameter(Mandatory)][long]$ExpectedTaskRevision,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$ExpectedCandidateSourceCommit,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedCandidateSha256,
        [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+\+[a-fA-F0-9]+$')][string]$LaunchAgentRuntimeVersion,
        [ValidateRange(1,240)][int]$ExpiryMinutes=30
    )
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    if([long]$task.revision -ne $ExpectedTaskRevision){throw 'Recovered task revision is stale.'}
    if($task.status -cne 'in-progress' -or $task.workflowStage -cne 'approval'){throw 'Recovered task is not in the canonical in-progress approval state.'}
    $archives=@($task.mayaTaraExecutionHistory|Where-Object {$_.AttemptId -ceq $FailedAttemptId -and $_.FailureCode -ceq 'native-qa-failed' -and $_.ReplacementAttemptId -ceq $RecoveredAttemptId -and $_.ReplacementRunId -ceq $RecoveredRunId})
    if($archives.Count -ne 1 -or $archives[0].ExecutionStatus -cne 'QaFailed' -or $archives[0].Stage -cne 'qa-failed'){throw 'Exact archived native-qa-failed recovery identity is required.'}
    $failed=$archives[0]
    foreach($pair in @(@($failed.ResultPath,$failed.ResultSha256),@($failed.ReportPath,$failed.ReportSha256))){if(!$pair[0] -or !$pair[1] -or !(Test-Path -LiteralPath $pair[0] -PathType Leaf) -or (Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ine $pair[1]){throw 'Archived failed result/report evidence is missing or changed.'}}
    $attempt=$task.mayaTaraAttempt;$execution=$task.mayaTaraExecution
    if(!$attempt -or !$execution -or $attempt.AttemptId -cne $RecoveredAttemptId -or $attempt.RunId -cne $RecoveredRunId -or $execution.AttemptId -cne $RecoveredAttemptId -or $execution.RunId -cne $RecoveredRunId -or $execution.Stage -cne 'prepared' -or $execution.ExecutionStatus -cne 'Prepared' -or $execution.ClaimId -or $execution.NativeProcessId -or $execution.RequestPath -or $execution.ResultPath -or $execution.ReportPath -or $execution.ReceiptPath -or $execution.SideEffectsPerformed){throw 'Exact unlaunched recovered attempt/run is required.'}
    if($execution.TaskId -cne $TaskId -or $execution.WorkflowId -cne $WorkflowId -or $execution.QaWorkflowId -cne 'create-plan-views-v1'){throw 'Recovered execution canonical identity mismatch.'}
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;$e=$workflow.qaBuildEvidence
    if($workflow.qaWorkflowId -cne 'create-plan-views-v1' -or $workflow.qaBuildStatus -cne 'succeeded' -or !$e -or $e.BuildStatus -cne 'succeeded' -or $e.EvidenceSource -cne 'FrozenCandidate' -or $e.SourceCommit -cne $ExpectedCandidateSourceCommit -or $e.CandidateSourceCommit -cne $ExpectedCandidateSourceCommit -or $e.ArtifactSha256 -ine $ExpectedCandidateSha256 -or $execution.ArtifactSha256 -ine $ExpectedCandidateSha256 -or !$e.DeploymentValidation -or !$e.ManifestIntegrityValidation -or !$e.QaIsolation){throw 'Recovered attempt candidate evidence does not match the expected QA product candidate.'}
    $pending=@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})
    if($pending.Count){throw 'A pending qa-run approval already exists.'}
    foreach($q in @($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved' -and !$_.consumedUtc})){try{$expiry=[DateTimeOffset]::Parse([string]$q.expiresUtc)}catch{throw 'Existing qa-run approval has an invalid expiry.'};if($expiry -gt [DateTimeOffset]::UtcNow){throw 'An existing unconsumed qa-run approval has not expired.'}}
    $binding=[ordered]@{SchemaVersion='maya-qa-recovered-native-failure-approval-v1';TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId='create-plan-views-v1';BuildRequestId=[string]$e.BuildRequestId;CandidateSourceCommit=$ExpectedCandidateSourceCommit;CandidateSha256=$ExpectedCandidateSha256;AttemptId=$RecoveredAttemptId;RunId=$RecoveredRunId}
    $bindingJson=ConvertTo-Json -InputObject $binding -Depth 5 -Compress;$sha=[Security.Cryptography.SHA256]::Create();try{$bindingHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($bindingJson)))).Replace('-','')}finally{$sha.Dispose()}
    $runtime=[ordered]@{Name='Repato.QaLaunchAgent';Version=$LaunchAgentRuntimeVersion}
    $request=[pscustomobject][ordered]@{requestId=[guid]::NewGuid().ToString('N');action='qa-run';requiredLevel='user';status='pending';bindingHash=$bindingHash;candidate=[pscustomobject]@{BuildRequestId=[string]$e.BuildRequestId;SourceCommit=$ExpectedCandidateSourceCommit;ArtifactSha256=$ExpectedCandidateSha256};attemptId=$RecoveredAttemptId;runId=$RecoveredRunId;runtime=[pscustomobject]$runtime;previousStatus='in-progress';requestedRevision=[long]0;approvedRevision=$null;requestedUtc=Get-RepatoUtc;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes($ExpiryMinutes).ToString('O');decidedUtc=$null;decidedBy=$null;reason='Fresh user approval for the existing recovered native-qa-failed attempt.';consumedUtc=$null}
    Invoke-RepatoStoreMutation $StoreRoot {
        param($data,$preview)
        $t=Find-RepatoTask $data $TaskId
        if([long]$t.revision -ne $ExpectedTaskRevision -or $t.status -cne 'in-progress' -or $t.workflowStage -cne 'approval' -or $t.mayaTaraAttempt.AttemptId -cne $RecoveredAttemptId -or $t.mayaTaraAttempt.RunId -cne $RecoveredRunId -or $t.mayaTaraExecution.AttemptId -cne $RecoveredAttemptId -or $t.mayaTaraExecution.RunId -cne $RecoveredRunId){throw 'Recovered approval compare-and-swap failed.'}
        $current=@($t.mayaTaraExecutionHistory|Where-Object {$_.AttemptId -ceq $FailedAttemptId -and $_.FailureCode -ceq 'native-qa-failed' -and $_.ReplacementAttemptId -ceq $RecoveredAttemptId -and $_.ReplacementRunId -ceq $RecoveredRunId})
        $w=@($t.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId)
        if($current.Count -ne 1 -or $w.Count -ne 1 -or [string]$w[0].qaBuildEvidence.CandidateSourceCommit -cne $ExpectedCandidateSourceCommit -or [string]$w[0].qaBuildEvidence.ArtifactSha256 -ine $ExpectedCandidateSha256){throw 'Recovered approval identity or candidate changed during compare-and-swap.'}
        if(@($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'}).Count){throw 'A pending qa-run approval appeared during compare-and-swap.'}
        foreach($q in @($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved' -and !$_.consumedUtc})){$expiry=[DateTimeOffset]::Parse([string]$q.expiresUtc);if($expiry -gt [DateTimeOffset]::UtcNow){throw 'An unconsumed qa-run approval became active during recovery compare-and-swap.'};$q.status='superseded';$q.reason='Expired approval superseded for the recovered native-failure attempt.'}
        $t.approvalRequests=[object[]]@($t.approvalRequests)+$request;$t.status='awaiting-approval';$t.workflowStage='approval'
        Add-RepatoHistory $t 'maya-tara-native-failure-approval-requested' 'Maya' "request=$($request.requestId); attempt=$RecoveredAttemptId; run=$RecoveredRunId; candidate=$ExpectedCandidateSourceCommit; runtime=$LaunchAgentRuntimeVersion"
        $request.requestedRevision=[long]$t.revision
        [pscustomobject]@{Task=$t;Request=$request;Binding=$binding}
    }
}

function Request-MayaQaRecoveredLaunchFailureApproval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$FailedAttemptId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$RecoveredAttemptId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$RecoveredRunId,
        [Parameter(Mandatory)][long]$ExpectedTaskRevision,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$ExpectedCandidateSourceCommit,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedCandidateSha256,
        [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+\+[a-fA-F0-9]+$')][string]$LaunchAgentRuntimeVersion,
        [ValidateRange(1,240)][int]$ExpiryMinutes=30
    )
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    if([long]$task.revision -ne $ExpectedTaskRevision -or $task.status -cne 'in-progress' -or $task.workflowStage -cne 'approval'){throw 'Recovered launch-failure task is not in the canonical pre-approval state.'}
    $archives=@($task.mayaTaraExecutionHistory|Where-Object {$_.AttemptId -ceq $FailedAttemptId -and $_.Stage -ceq 'launch-failed' -and $_.ExecutionStatus -ceq 'LaunchFailed' -and $_.FailureCode -ceq 'native-process-start-failed' -and $_.ReplacementAttemptId -ceq $RecoveredAttemptId -and $_.ReplacementRunId -ceq $RecoveredRunId})
    if($archives.Count -ne 1 -or $archives[0].NativeProcessId -or $archives[0].SideEffectsPerformed){throw 'Exact side-effect-free archived launch failure is required.'}
    $attempt=$task.mayaTaraAttempt;$execution=$task.mayaTaraExecution
    if(!$attempt -or !$execution -or $attempt.AttemptId -cne $RecoveredAttemptId -or $attempt.RunId -cne $RecoveredRunId -or $execution.AttemptId -cne $RecoveredAttemptId -or $execution.RunId -cne $RecoveredRunId -or $execution.Stage -cne 'prepared' -or $execution.ExecutionStatus -cne 'Prepared' -or $execution.ClaimId -or $execution.NativeProcessId -or $execution.RequestPath -or $execution.SideEffectsPerformed){throw 'Exact unlaunched recovered launch-failure attempt/run is required.'}
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;$e=$workflow.qaBuildEvidence
    if($workflow.qaWorkflowId -cne 'create-plan-views-v1' -or $e.CandidateSourceCommit -cne $ExpectedCandidateSourceCommit -or $e.ArtifactSha256 -ine $ExpectedCandidateSha256 -or $execution.ArtifactSha256 -ine $ExpectedCandidateSha256 -or !$e.DeploymentValidation -or !$e.ManifestIntegrityValidation -or !$e.QaIsolation -or [IO.Path]::GetFullPath([string]$execution.ValidatedRunnerManifestPath) -ine [IO.Path]::GetFullPath([string]$e.DeployedRunnerManifestPath) -or [string]$execution.ValidatedRunnerManifestSha256 -ine [string]$e.DeployedRunnerManifestSha256 -or [string]$execution.RunnerManifestPath -cne [string]$e.RunnerManifestPath -or [string]$execution.RunnerManifestSha256 -ine [string]$e.RunnerManifestSha256){throw 'Recovered launch-failure candidate or deployed manifest binding is invalid.'}
    if(@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'}).Count){throw 'A pending qa-run approval already exists.'}
    $binding=[ordered]@{SchemaVersion='maya-qa-recovered-launch-failure-approval-v1';TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId='create-plan-views-v1';BuildRequestId=[string]$e.BuildRequestId;CandidateSourceCommit=$ExpectedCandidateSourceCommit;CandidateSha256=$ExpectedCandidateSha256;SourceRunnerManifestPath=[string]$e.RunnerManifestPath;SourceRunnerManifestSha256=[string]$e.RunnerManifestSha256;DeployedRunnerManifestPath=[string]$e.DeployedRunnerManifestPath;DeployedRunnerManifestSha256=[string]$e.DeployedRunnerManifestSha256;FailedAttemptId=$FailedAttemptId;AttemptId=$RecoveredAttemptId;RunId=$RecoveredRunId;LaunchAgentRuntimeVersion=$LaunchAgentRuntimeVersion}
    $json=$binding|ConvertTo-Json -Compress -Depth 8;$sha=[Security.Cryptography.SHA256]::Create();try{$bindingHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}finally{$sha.Dispose()}
    $request=[pscustomobject][ordered]@{requestId=[guid]::NewGuid().ToString('N');action='qa-run';requiredLevel='user';status='pending';bindingHash=$bindingHash;recoveryBinding=[pscustomobject]$binding;candidate=[pscustomobject]@{BuildRequestId=[string]$e.BuildRequestId;SourceCommit=$ExpectedCandidateSourceCommit;ArtifactSha256=$ExpectedCandidateSha256};attemptId=$RecoveredAttemptId;runId=$RecoveredRunId;runtime=[pscustomobject]@{Name='Repato.QaLaunchAgent';Version=$LaunchAgentRuntimeVersion};previousStatus='in-progress';requestedRevision=[long]0;approvedRevision=$null;requestedUtc=Get-RepatoUtc;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes($ExpiryMinutes).ToString('O');decidedUtc=$null;decidedBy=$null;reason='Fresh user approval for one recovered side-effect-free launch failure attempt.';consumedUtc=$null}
    $updated=Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$t=Find-RepatoTask $data $TaskId;if([long]$t.revision -ne $ExpectedTaskRevision -or $t.status -cne 'in-progress' -or $t.workflowStage -cne 'approval' -or $t.mayaTaraExecution.AttemptId -cne $RecoveredAttemptId -or $t.mayaTaraExecution.RunId -cne $RecoveredRunId){throw 'Recovered launch-failure approval compare-and-swap failed.'};$current=@($t.mayaTaraExecutionHistory|Where-Object {$_.AttemptId -ceq $FailedAttemptId -and $_.FailureCode -ceq 'native-process-start-failed' -and $_.ReplacementAttemptId -ceq $RecoveredAttemptId -and $_.ReplacementRunId -ceq $RecoveredRunId});$w=@($t.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId);if($current.Count -ne 1 -or $w.Count -ne 1 -or [string]$w[0].qaBuildEvidence.DeployedRunnerManifestPath -cne [string]$binding.DeployedRunnerManifestPath -or [string]$w[0].qaBuildEvidence.DeployedRunnerManifestSha256 -ine [string]$binding.DeployedRunnerManifestSha256){throw 'Recovered launch-failure binding changed during compare-and-swap.'};if(@($t.approvalRequests|Where-Object {$_.status -ceq 'pending'}).Count){throw 'A pending approval appeared during compare-and-swap.'};foreach($q in @($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved' -and !$_.consumedUtc})){$q.status='superseded';$q.reason='Superseded after side-effect-free launch failure recovery.'};$t.approvalRequests=[object[]]@($t.approvalRequests)+$request;$t.status='awaiting-approval';Add-RepatoHistory $t 'maya-tara-launch-failure-approval-requested' 'Maya' "failedAttempt=$FailedAttemptId; request=$($request.requestId); attempt=$RecoveredAttemptId; run=$RecoveredRunId";$request.requestedRevision=[long]$t.revision;$t.mayaTaraExecution.TaskRevisionAtPrepare=[long]$t.revision;$t}
    @($updated.approvalRequests|Where-Object {$_.requestId -ceq $request.requestId})[0]
}

function Repair-MayaQaRecoveredLaunchApprovalRevision {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$RequestId,[Parameter(Mandatory)][long]$ExpectedTaskRevision)
    Invoke-RepatoStoreMutation $StoreRoot {
        param($data,$preview)
        $t=Find-RepatoTask $data $TaskId
        $pending=@($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})
        if([long]$t.revision -ne $ExpectedTaskRevision -or $t.status -cne 'awaiting-approval' -or $t.workflowStage -cne 'approval' -or $pending.Count -ne 1 -or $pending[0].requestId -cne $RequestId){throw 'Recovered launch approval repair state is stale.'}
        $q=$pending[0];$b=$q.recoveryBinding;$x=$t.mayaTaraExecution;$a=$t.mayaTaraAttempt
        $json=ConvertTo-Json $b -Depth 20 -Compress;$sha=[Security.Cryptography.SHA256]::Create();try{$hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}finally{$sha.Dispose()}
        if($q.bindingHash -cne $hash -or $b.SchemaVersion -cne 'maya-qa-recovered-launch-failure-approval-v1' -or $b.TaskId -cne $TaskId -or $b.AttemptId -cne $x.AttemptId -or $b.RunId -cne $x.RunId -or $a.AttemptId -cne $x.AttemptId -or $a.RunId -cne $x.RunId -or $q.requiredLevel -cne 'user' -or $q.decidedBy -or $q.decidedUtc -or $x.Stage -cne 'prepared' -or $x.ExecutionStatus -cne 'Prepared' -or $x.ClaimStatus -cne 'unclaimed' -or $x.ClaimId -or $x.NativeProcessId -or $x.RequestPath -or $x.SideEffectsPerformed -or [long]$q.requestedRevision -ne [long]$t.revision -or [long]$x.TaskRevisionAtPrepare -ge [long]$t.revision -or [DateTimeOffset]::Parse($q.expiresUtc) -le [DateTimeOffset]::UtcNow -or [DateTimeOffset]::Parse($a.RequestExpiresUtc) -le [DateTimeOffset]::UtcNow){throw 'Exact valid pending launch recovery approval with stale preparation revision is required.'}
        Add-RepatoHistory $t 'maya-tara-launch-approval-preparation-revision-repaired' 'Maya' "request=$RequestId; attempt=$($x.AttemptId); authorization remains pending; expiry unchanged"
        $x.TaskRevisionAtPrepare=[long]$t.revision;$q.requestedRevision=[long]$t.revision
        $t
    }
}

function Request-MayaQaRecoveredExpiredAttemptApproval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$ExpiredApprovalRequestId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$ExpiredAttemptId,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$')][string]$ExpiredRunId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$RecoveredAttemptId,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{32}$')][string]$RecoveredRunId,
        [Parameter(Mandatory)][long]$ExpectedTaskRevision,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{40}$')][string]$ExpectedCandidateSourceCommit,
        [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedCandidateSha256,
        [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+\+[a-fA-F0-9]+$')][string]$LaunchAgentRuntimeVersion,
        [ValidateRange(1,240)][int]$ExpiryMinutes=30
    )
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    if([long]$task.revision -ne $ExpectedTaskRevision){throw 'Expired attempt task revision is stale.'}
    if($task.status -cne 'in-progress' -or $task.workflowStage -cne 'approval'){throw 'Expired attempt task is not in the canonical pre-approval state.'}
    # Follow the persisted replacement edges backwards. Every hop must have its
    # attempt record and at least one intact packet snapshot; this permits a
    # historical approval to remain bound to an earlier attempt in the chain.
    $history=@($task.mayaTaraExecutionHistory);$attemptHistory=@($task.mayaTaraAttemptHistory);$packetHistory=@($task.mayaTaraQaPacketHistory)
    $seen=@{};$cursorAttempt=$RecoveredAttemptId;$cursorRun=$RecoveredRunId;$lineage=@()
    while($cursorAttempt -cne $ExpiredAttemptId -or $cursorRun -cne $ExpiredRunId){
        if($seen.ContainsKey($cursorAttempt)){throw 'Expired attempt recovery lineage contains a cycle.'};$seen[$cursorAttempt]=$true
        $edges=@($history|Where-Object {$_.ReplacementAttemptId -ceq $cursorAttempt -and $_.ReplacementRunId -ceq $cursorRun -and $_.FailureCode -ceq 'attempt-expired' -and $_.Stage -ceq 'expired' -and $_.ExecutionStatus -ceq 'Expired'})
        if($edges.Count -ne 1){throw 'Expired attempt recovery lineage is missing or ambiguous.'};$edge=$edges[0]
        if($edge.TaskId -cne $TaskId -or $edge.WorkflowId -cne $WorkflowId -or $edge.QaWorkflowId -cne 'create-plan-views-v1' -or !$edge.AttemptId -or !$edge.RunId){throw 'Expired attempt recovery lineage identity mismatch.'}
        $prior=@($attemptHistory|Where-Object {$_.AttemptId -ceq $edge.AttemptId -and $_.RunId -ceq $edge.RunId -and $_.TaskId -ceq $TaskId -and $_.WorkflowId -ceq $WorkflowId})
        if($prior.Count -ne 1){throw 'Expired attempt recovery lineage has no unique persisted attempt record.'}
        $packets=@($packetHistory|Where-Object {$_.AttemptId -ceq $edge.AttemptId -and $_.RunId -ceq $edge.RunId -and $_.Packet -and $_.Packet.AttemptId -ceq $edge.AttemptId -and $_.Packet.RunId -ceq $edge.RunId -and $_.Packet.TaskId -ceq $TaskId -and $_.Packet.WorkflowId -ceq $WorkflowId -and $_.Packet.QaWorkflowId -ceq 'create-plan-views-v1' -and $_.Packet.ArtifactSha256 -ieq $ExpectedCandidateSha256})
        if(!$packets.Count -or @($packets|Where-Object {$_.Packet.RunnerManifestSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or $_.Packet.ArtifactSha256 -notmatch '^[A-Fa-f0-9]{64}$'}).Count){throw 'Expired attempt recovery lineage packet evidence is missing or altered.'}
        $lineage+=,$edge;$cursorAttempt=[string]$edge.AttemptId;$cursorRun=[string]$edge.RunId
        if(!$cursorAttempt -or !$cursorRun -or $lineage.Count -gt $history.Count){throw 'Expired attempt recovery lineage is broken.'}
    }
    if(!$lineage.Count){throw 'Exact expired prepared attempt recovery identity is required.'}
    $archives=@($lineage|Where-Object {$_.AttemptId -ceq $ExpiredAttemptId -and $_.RunId -ceq $ExpiredRunId})
    if($archives.Count -ne 1){throw 'Historical approved attempt is not in the recovered lineage.'}
    $lineageKeys=@($lineage|ForEach-Object {"$($_.AttemptId)/$($_.RunId)>$($_.ReplacementAttemptId)/$($_.ReplacementRunId)"})
    $attempt=$task.mayaTaraAttempt;$execution=$task.mayaTaraExecution
    if(!$attempt -or !$execution -or $attempt.AttemptId -cne $RecoveredAttemptId -or $attempt.RunId -cne $RecoveredRunId -or $execution.AttemptId -cne $RecoveredAttemptId -or $execution.RunId -cne $RecoveredRunId -or $execution.Stage -cne 'prepared' -or $execution.ExecutionStatus -cne 'Prepared' -or $execution.ClaimStatus -cne 'unclaimed' -or $execution.ClaimId -or $execution.NativeProcessId -or $execution.RequestPath -or $execution.ResultPath -or $execution.ReportPath -or $execution.ReceiptPath -or $execution.SideEffectsPerformed){throw 'Exact unlaunched recovered attempt/run is required.'}
    if([DateTimeOffset]::Parse([string]$attempt.RequestExpiresUtc) -le [DateTimeOffset]::UtcNow){throw 'Recovered attempt launch window is expired.'}
    if($execution.TaskId -cne $TaskId -or $execution.WorkflowId -cne $WorkflowId -or $execution.QaWorkflowId -cne 'create-plan-views-v1'){throw 'Recovered execution canonical identity mismatch.'}
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;$e=$workflow.qaBuildEvidence
    if($workflow.qaWorkflowId -cne 'create-plan-views-v1' -or $workflow.qaBuildStatus -cne 'succeeded' -or !$e -or $e.BuildStatus -cne 'succeeded' -or $e.EvidenceSource -cne 'FrozenCandidate' -or $e.SourceCommit -cne $ExpectedCandidateSourceCommit -or $e.CandidateSourceCommit -cne $ExpectedCandidateSourceCommit -or $e.ArtifactSha256 -ine $ExpectedCandidateSha256 -or $execution.ArtifactSha256 -ine $ExpectedCandidateSha256 -or !$e.DeploymentValidation -or !$e.ManifestIntegrityValidation -or !$e.QaIsolation){throw 'Recovered attempt candidate evidence does not match the expected QA product candidate.'}
    foreach($edge in $lineage){$matching=@($packetHistory|Where-Object {$_.AttemptId -ceq $edge.AttemptId -and $_.RunId -ceq $edge.RunId});foreach($entry in $matching){$p=$entry.Packet;if($p.AttemptId -cne $edge.AttemptId -or $p.RunId -cne $edge.RunId -or $p.TaskId -cne $TaskId -or $p.WorkflowId -cne $WorkflowId -or $p.QaWorkflowId -cne 'create-plan-views-v1' -or $p.ArtifactSha256 -ine $ExpectedCandidateSha256 -or $p.ManifestSha256 -inotmatch '^[A-Fa-f0-9]{64}$' -or $p.RunnerManifestSha256 -ine [string]$e.RunnerManifestSha256 -or $p.ManifestSha256 -ine [string]$e.ManifestSha256){throw 'Expired attempt recovery lineage packet hashes do not match the frozen candidate.'}}}
    $old=@($task.approvalRequests|Where-Object {$_.requestId -ceq $ExpiredApprovalRequestId -and $_.action -ceq 'qa-run' -and $_.status -ceq 'approved'})
    $oldBound=$false
    if($old.Count -eq 1 -and $old[0].requiredLevel -ceq 'user'){
        $legacyBinding=if($old[0].PSObject.Properties.Name -contains 'executionBinding'){$old[0].executionBinding}else{$null}
        if($legacyBinding){
            $bindingJson=ConvertTo-Json -InputObject $legacyBinding -Depth 20 -Compress;$sha=[Security.Cryptography.SHA256]::Create();try{$legacyBindingHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($bindingJson)))).Replace('-','')}finally{$sha.Dispose()}
            $oldBound=($old[0].bindingHash -ceq $legacyBindingHash -and $legacyBinding.SchemaVersion -ceq 'maya-qa-canonical-execution-approval-v1' -and $legacyBinding.TaskId -ceq $TaskId -and $legacyBinding.WorkflowId -ceq $WorkflowId -and $legacyBinding.QaWorkflowId -ceq 'create-plan-views-v1' -and $legacyBinding.BuildRequestId -ceq [string]$e.BuildRequestId -and $legacyBinding.CandidateSourceCommit -ceq $ExpectedCandidateSourceCommit -and $legacyBinding.CandidateSha256 -ieq $ExpectedCandidateSha256 -and $legacyBinding.RunId -ceq $ExpiredRunId -and $legacyBinding.ModelPath -ceq [string]$archives[0].DisposableModelPath -and $legacyBinding.ModelSha256 -ieq [string]$archives[0].DisposableModelSha256 -and $legacyBinding.CandidateProvenancePath -ceq [string]$e.CandidateProvenancePath -and $legacyBinding.CandidateProvenanceSha256 -ieq [string]$e.CandidateProvenanceSha256 -and $legacyBinding.RunnerManifestPath -ceq [string]$e.RunnerManifestPath -and $legacyBinding.RunnerManifestSha256 -ieq [string]$e.RunnerManifestSha256 -and $legacyBinding.DeploymentValidation -eq $true -and $legacyBinding.ManifestIntegrityValidation -eq $true -and $legacyBinding.QaIsolation -eq $true -and $legacyBinding.RevitVersion -ceq '2025')
        }else{
            $oldBound=($old[0].attemptId -ceq $ExpiredAttemptId -and $old[0].runId -ceq $ExpiredRunId -and $old[0].candidate.BuildRequestId -ceq [string]$e.BuildRequestId -and $old[0].candidate.SourceCommit -ceq $ExpectedCandidateSourceCommit -and $old[0].candidate.ArtifactSha256 -ieq $ExpectedCandidateSha256 -and $old[0].runtime.Version -ceq $LaunchAgentRuntimeVersion)
        }
    }
    if(!$oldBound){throw 'Exact expired user approval identity is required.'}
    try{if([DateTimeOffset]::Parse([string]$old[0].expiresUtc) -gt [DateTimeOffset]::UtcNow){throw 'Historical user approval is still valid.'}}catch{if($_.Exception.Message -eq 'Historical user approval is still valid.'){throw};throw 'Historical user approval expiry is invalid.'}
    if(@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved' -and $_.requestId -cne $ExpiredApprovalRequestId}).Count){throw 'An unrelated approved qa-run request prevents expired-attempt recovery.'}
    if(@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'}).Count){throw 'A pending qa-run approval already exists.'}
    $binding=[ordered]@{SchemaVersion='maya-qa-expired-prepared-attempt-approval-v1';TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId='create-plan-views-v1';BuildRequestId=[string]$e.BuildRequestId;CandidateSourceCommit=$ExpectedCandidateSourceCommit;CandidateSha256=$ExpectedCandidateSha256;AttemptId=$RecoveredAttemptId;RunId=$RecoveredRunId}
    $bindingJson=ConvertTo-Json -InputObject $binding -Depth 5 -Compress;$sha=[Security.Cryptography.SHA256]::Create();try{$bindingHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($bindingJson)))).Replace('-','')}finally{$sha.Dispose()}
    $runtime=[ordered]@{Name='Repato.QaLaunchAgent';Version=$LaunchAgentRuntimeVersion}
    $request=[pscustomobject][ordered]@{requestId=[guid]::NewGuid().ToString('N');action='qa-run';requiredLevel='user';status='pending';bindingHash=$bindingHash;candidate=[pscustomobject]@{BuildRequestId=[string]$e.BuildRequestId;SourceCommit=$ExpectedCandidateSourceCommit;ArtifactSha256=$ExpectedCandidateSha256};attemptId=$RecoveredAttemptId;runId=$RecoveredRunId;runtime=[pscustomobject]$runtime;previousStatus='in-progress';requestedRevision=[long]0;approvedRevision=$null;requestedUtc=Get-RepatoUtc;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes($ExpiryMinutes).ToString('O');decidedUtc=$null;decidedBy=$null;reason='Fresh user approval for the replacement of an expired prepared attempt.';consumedUtc=$null}
    Invoke-RepatoStoreMutation $StoreRoot {
        param($data,$preview)
        $t=Find-RepatoTask $data $TaskId
        if([long]$t.revision -ne $ExpectedTaskRevision -or $t.status -cne 'in-progress' -or $t.workflowStage -cne 'approval' -or $t.mayaTaraAttempt.AttemptId -cne $RecoveredAttemptId -or $t.mayaTaraAttempt.RunId -cne $RecoveredRunId -or $t.mayaTaraExecution.AttemptId -cne $RecoveredAttemptId -or $t.mayaTaraExecution.RunId -cne $RecoveredRunId){throw 'Expired attempt approval compare-and-swap failed.'}
        $currentLineage=@($t.mayaTaraExecutionHistory|Where-Object {$_.FailureCode -ceq 'attempt-expired' -and $_.Stage -ceq 'expired' -and $_.ExecutionStatus -ceq 'Expired'}|ForEach-Object {"$($_.AttemptId)/$($_.RunId)>$($_.ReplacementAttemptId)/$($_.ReplacementRunId)"}|Where-Object {$lineageKeys -contains $_})
        $a=@($currentLineage|Where-Object {$lineageKeys -contains $_})
        $prior=@($t.approvalRequests|Where-Object {$_.requestId -ceq $ExpiredApprovalRequestId -and $_.status -ceq 'approved'})
        if($a.Count -ne $lineageKeys.Count -or $prior.Count -ne 1 -or @($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'}).Count){throw 'Expired attempt approval state changed during compare-and-swap.'}
        $t.approvalRequests=[object[]]@($t.approvalRequests)+$request;$t.status='awaiting-approval';$t.workflowStage='approval'
        Add-RepatoHistory $t 'maya-tara-expired-attempt-approval-requested' 'Maya' "expiredApproval=$ExpiredApprovalRequestId; request=$($request.requestId); attempt=$RecoveredAttemptId; run=$RecoveredRunId; candidate=$ExpectedCandidateSourceCommit; runtime=$LaunchAgentRuntimeVersion"
        $t.mayaTaraExecution.TaskRevisionAtPrepare=[long]$t.revision
        $request.requestedRevision=[long]$t.revision
        [pscustomobject]@{Task=$t;Request=$request;Binding=$binding}
    }
}

function Repair-MayaQaExpiredPreparedApprovalHistory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$ExpiredRequestId,[Parameter(Mandatory)][string]$ExpiredAttemptId,[Parameter(Mandatory)][string]$ExpiredRunId,[Parameter(Mandatory)][string]$CurrentAttemptId,[Parameter(Mandatory)][string]$CurrentRunId,[Parameter(Mandatory)][long]$ExpectedTaskRevision)
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    if([long]$task.revision -ne $ExpectedTaskRevision -or $task.status -cne 'awaiting-approval' -or $task.workflowStage -cne 'approval'){throw 'Expired approval history repair task state is stale.'}
    $old=@($task.approvalRequests|Where-Object {$_.requestId -ceq $ExpiredRequestId -and $_.action -ceq 'qa-run' -and $_.status -ceq 'expired' -and $_.attemptId -ceq $ExpiredAttemptId -and $_.runId -ceq $ExpiredRunId})
    $pending=@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending' -and $_.attemptId -ceq $CurrentAttemptId -and $_.runId -ceq $CurrentRunId})
    $archive=@($task.mayaTaraExecutionHistory|Where-Object {$_.AttemptId -ceq $ExpiredAttemptId -and $_.RunId -ceq $ExpiredRunId -and $_.FailureCode -ceq 'attempt-expired' -and $_.ReplacementAttemptId -ceq $CurrentAttemptId -and $_.ReplacementRunId -ceq $CurrentRunId})
    if($old.Count -ne 1 -or $old[0].decidedBy -cne 'user' -or $old[0].reason -cne "Approval expired with its prepared attempt before native launch." -or $pending.Count -ne 1 -or $archive.Count -ne 1 -or $task.mayaTaraAttempt.AttemptId -cne $CurrentAttemptId -or $task.mayaTaraAttempt.RunId -cne $CurrentRunId -or [DateTimeOffset]::Parse([string]$pending[0].expiresUtc) -le [DateTimeOffset]::UtcNow){throw 'Exact expired approval and replacement request are required.'}
    $decisionReason="User explicitly approved request $ExpiredRequestId."
    Invoke-RepatoStoreMutation $StoreRoot {
        param($data,$preview)
        $t=Find-RepatoTask $data $TaskId;$prior=@($t.approvalRequests|Where-Object {$_.requestId -ceq $ExpiredRequestId -and $_.status -ceq 'expired'});$fresh=@($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending' -and $_.attemptId -ceq $CurrentAttemptId -and $_.runId -ceq $CurrentRunId})
        if([long]$t.revision -ne $ExpectedTaskRevision -or $prior.Count -ne 1 -or $prior[0].reason -cne 'Approval expired with its prepared attempt before native launch.' -or $fresh.Count -ne 1 -or $t.mayaTaraAttempt.AttemptId -cne $CurrentAttemptId -or $t.mayaTaraAttempt.RunId -cne $CurrentRunId){throw 'Expired approval history repair compare-and-swap failed.'}
        $prior[0].reason=$decisionReason;$prior[0]|Add-Member NoteProperty expiredReason 'Approval expired with its prepared attempt before native launch.' -Force
        Add-RepatoHistory $t 'maya-tara-expired-approval-history-preserved' 'Maya' "request=$ExpiredRequestId; attempt=$ExpiredAttemptId; run=$ExpiredRunId"
        $fresh[0].requestedRevision=[long]$t.revision;$t.mayaTaraExecution.TaskRevisionAtPrepare=[long]$t.revision
        $fresh[0]
    }
}

function Repair-MayaQaCanonicalRunIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$ExpectedBuildRequestId,[string]$RuntimeRoot,[string]$FixturePreparationResultPath
    )
    $qaId=Resolve-MayaQaWorkflowId $QaWorkflowId;$w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if([string]$w.qaWorkflowId -cne $qaId -or [string]$w.qaBuildRequest.BuildRequestId -cne $ExpectedBuildRequestId){throw 'Canonical QA identity mismatch.'}
    if([string]$w.qaBuildStatus -cne 'succeeded' -or !$w.qaBuildEvidence -or [string]$w.qaBuildEvidence.BuildRequestId -cne $ExpectedBuildRequestId -or [string]$w.qaBuildEvidence.BuildStatus -cne 'succeeded' -or [string]$w.qaBuildEvidence.EvidenceSource -cne 'FrozenCandidate'){throw 'Canonical build evidence is invalid.'}
    $e=$w.qaBuildEvidence;foreach($n in 'SourceCommit','CandidateSourceCommit','ArtifactPath','ArtifactSha256','CandidateProvenancePath','RunnerManifestPath','RunnerManifestSha256'){if($e.PSObject.Properties.Name -notcontains $n -or [string]::IsNullOrWhiteSpace([string]$e.$n)){throw "Canonical evidence is missing $n."}}
    if([string]$e.SourceCommit -cne [string]$e.CandidateSourceCommit -or [string]$e.CandidateSourceCommit -notmatch '^[A-Fa-f0-9]{40}$' -or [string]$e.ArtifactSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [string]$e.RunnerManifestSha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Canonical evidence identity or hash is invalid.'}
    $legacyUnavailable=[string]$e.ManifestIntegrityValidation -ceq 'Unavailable'
    if(!$e.DeploymentValidation -or !$e.QaIsolation -or (!$legacyUnavailable -and $e.ManifestIntegrityValidation -ne $true)){throw 'Canonical staging or deployment evidence is missing or failed.'}
    if($legacyUnavailable){
        if(!(Test-Path -LiteralPath $e.ManifestPath -PathType Leaf) -or (Get-FileHash -LiteralPath $e.ManifestPath -Algorithm SHA256).Hash -ine [string]$e.ManifestSha256){throw 'Legacy manifest integrity evidence is invalid.'}
        if(!(Test-Path -LiteralPath $e.CandidateProvenancePath -PathType Leaf)){throw 'Legacy candidate provenance is missing.'}
        $provenance=Get-Content -LiteralPath $e.CandidateProvenancePath -Raw|ConvertFrom-Json
        $supportedQa=@(if($provenance.PSObject.Properties.Name -contains 'SupportedQaWorkflows'){$provenance.SupportedQaWorkflows})
        $eQa=if($e.PSObject.Properties.Name -contains 'QaWorkflowId'){[string]$e.QaWorkflowId}else{$qaId}
        if([string]$provenance.SourceCommit -cne [string]$e.SourceCommit -or [string]$provenance.FrozenArtifactSha256 -ine [string]$e.ArtifactSha256 -or ($supportedQa.Count -and $eQa -notin $supportedQa)){throw 'Legacy candidate provenance binding is invalid.'}
    }
    $d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId
    if($t.status -cne 'passed' -or $t.workflowStage -cne 'approval'){throw 'Canonical task is not approved for QA run recovery.'}
    $approved=@($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved'})
    if($approved.Count -ne 1){throw 'Canonical QA approval is missing or stale.'}
    $approvalRevisionValid=([long]$approved[0].approvedRevision -eq [long]$t.revision)
    $failedPreparationContinuity=([long]$approved[0].approvedRevision -eq ([long]$t.revision-1) -and @($t.history)[-1].event -ceq 'deployment-workflow-mutated' -and @($t.history)[-1].actor -ceq 'Maya')
    if(!$approvalRevisionValid -and !$failedPreparationContinuity){throw 'Canonical QA approval is missing or stale.'}
    if($w.PSObject.Properties.Name -contains 'qaRunId' -and -not [string]::IsNullOrWhiteSpace([string]$w.qaRunId)){throw 'Canonical qaRunId already exists.'}
    if($w.PSObject.Properties.Name -notcontains 'qaHandoff' -or !$w.qaHandoff -or [string]$w.qaHandoffId -cne [string]$w.qaHandoff.HandoffId -or [string]$w.qaHandoff.TaskId -cne $TaskId -or [string]$w.qaHandoff.QaWorkflowId -cne $qaId){throw 'Canonical partial handoff is missing or inconsistent.'}
    if($w.qaHandoff.PSObject.Properties.Name -contains 'WorkflowId'){if([string]::IsNullOrWhiteSpace([string]$w.qaHandoff.WorkflowId) -or [string]$w.qaHandoff.WorkflowId -cne $WorkflowId){throw 'Canonical partial handoff WorkflowId is inconsistent.'}}
    if($w.qaHandoff.PSObject.Properties.Name -contains 'BuildRequestId' -and [string]$w.qaHandoff.BuildRequestId -cne [string]$ExpectedBuildRequestId){throw 'Canonical partial handoff BuildRequestId is inconsistent.'}
    if([string]$w.qaHandoff.ArtifactSha256 -ine [string]$e.ArtifactSha256 -or [string]$w.qaHandoff.ManifestSha256 -ine [string]$e.ManifestSha256 -or [string]$w.qaHandoff.RunnerManifestSha256 -ine [string]$e.RunnerManifestSha256){throw 'Canonical partial handoff evidence is inconsistent.'}
    if([string]$w.qaApprovalId -cne [string]$approved[0].requestId -or [string]$w.qaApprovalStatus -cne 'approved' -or [string]$w.qaHandoff.QaApprovalId -cne [string]$approved[0].requestId){throw 'Canonical partial approval is missing or inconsistent.'}
    if($t.PSObject.Properties.Name -contains 'mayaTaraQaPacket' -or $t.PSObject.Properties.Name -contains 'mayaTaraAttempt' -or $t.PSObject.Properties.Name -contains 'mayaTaraExecution'){throw 'Tara preparation has already begun.'}
    if($t.PSObject.Properties.Name -contains 'nativeAttemptCount' -and [int]$t.nativeAttemptCount -gt 0){throw 'Native QA has already begun.'}
    if($t.PSObject.Properties.Name -contains 'taraRuns' -and @($t.taraRuns|Where-Object {$_ -and $_.status -in @('running','passed','completed')}).Count){throw 'Native QA has already begun.'}
    if($t.PSObject.Properties.Name -contains 'finishedUtc' -and $t.finishedUtc){throw 'Canonical task is terminal.'}
    $runId='MAYA-'+[guid]::NewGuid().ToString('N');New-MayaQaRun -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $qaId -RunId $runId -RuntimeRoot $RuntimeRoot -FixturePreparationResultPath $FixturePreparationResultPath -ExpectedTaskRevision ([long]$t.revision)
}

function New-MayaQaCanonicalPreparation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [switch]$DryRun
    )
    $QaWorkflowId=Resolve-MayaQaWorkflowId $QaWorkflowId
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if($workflow.PSObject.Properties['qaFixturePreparationEvidence'] -and $workflow.qaFixturePreparationEvidence -and $workflow.qaFixturePreparationEvidence.PSObject.Properties['RecoveredProvenanceSha256']){
        $beforeHandoffTask=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
        $beforeHandoffApprovals=@($beforeHandoffTask.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved' -and !$_.consumedUtc -and $_.PSObject.Properties['executionBinding'] -and $_.executionBinding.WorkflowId -ceq $WorkflowId})
        if($beforeHandoffApprovals.Count -ne 1){throw 'Recovered preparation requires exact fresh native authorization before handoff creation.'}
        $null=Resolve-CpvNativeContinuationExpiry -Task $beforeHandoffTask -Workflow $workflow -Approval $beforeHandoffApprovals[0] -AttemptDurationMinutes (Get-MayaQaAttemptDurationMinutes)
    }
    $handoff=if($workflow.PSObject.Properties.Name -contains 'qaHandoff' -and $workflow.qaHandoff){$workflow.qaHandoff}else{New-MayaQaHandoff -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $QaWorkflowId -DryRun:$DryRun}
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $taskState=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    $existingPlan=if($taskState.PSObject.Properties.Name -contains 'mayaPlan'){$taskState.mayaPlan}else{$null}
    if($existingPlan){
        if([string]$existingPlan.TaskId -cne $TaskId -or [string]$existingPlan.WorkflowId -cne $WorkflowId -or [string]$existingPlan.QaWorkflowId -cne $QaWorkflowId -or [string]$existingPlan.Stage -cne 'qa-prepared' -or [string]$existingPlan.NextAgent -cne 'Tara' -or [string]$existingPlan.NextOperation -cne 'canonical-execution-record' -or $existingPlan.SideEffectsPerformed -ne $false){throw 'Persisted canonical plan is not eligible for execution-record continuation.'}
    }
    $runId=[string]$workflow.qaRunId
    if([string]::IsNullOrWhiteSpace($runId)){throw 'Canonical QA run identity is missing.'}
    $preparationEvidence=if($workflow.PSObject.Properties['qaFixturePreparationEvidence']){$workflow.qaFixturePreparationEvidence}else{$null}
    $attemptId=if($preparationEvidence -and $preparationEvidence.AttemptId){[string]$preparationEvidence.AttemptId}else{[guid]::NewGuid().ToString('N')}
    if($QaWorkflowId -ceq 'create-plan-views-v1' -and (!$preparationEvidence -or $attemptId -notmatch '^[a-fA-F0-9]{32}$' -or [string]$preparationEvidence.RunId -cne $runId)){throw 'Create Plan Views canonical attempt must preserve the authenticated fixture-preparation AttemptId and RunId.'}
    $runtimeRoot=[IO.Path]::GetDirectoryName([string]$workflow.qaModelPath)
    $attemptExpiry=[DateTimeOffset]::UtcNow.AddMinutes((Get-MayaQaAttemptDurationMinutes))
    $nativeContinuation=$null
    if($preparationEvidence -and $preparationEvidence.PSObject.Properties['RecoveredProvenanceSha256']){
        $nativeApprovals=@($taskState.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved' -and !$_.consumedUtc -and $_.requestId -ceq $handoff.QaApprovalId})
        if($nativeApprovals.Count -ne 1){throw 'Recovered canonical preparation requires one exact fresh native approval.'}
        $attemptExpiry=Resolve-CpvNativeContinuationExpiry -Task $taskState -Workflow $workflow -Approval $nativeApprovals[0] -AttemptDurationMinutes (Get-MayaQaAttemptDurationMinutes)
        $nativeContinuation=$nativeApprovals[0].executionBinding.NativeContinuation
    }elseif($preparationEvidence -and $preparationEvidence.PSObject.Properties['ExpiresUtc'] -and $preparationEvidence.ExpiresUtc){try{$preparationExpiry=[DateTimeOffset]::Parse([string]$preparationEvidence.ExpiresUtc);if($preparationExpiry -lt $attemptExpiry){$attemptExpiry=$preparationExpiry}}catch{throw 'Canonical fixture-preparation expiry is invalid.'}}
    if($attemptExpiry -le [DateTimeOffset]::UtcNow){throw 'Canonical fixture-preparation attempt is expired.'}
    $attempt=[pscustomobject][ordered]@{SchemaVersion='maya-tara-execution-request-v1';AttemptId=$attemptId;TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;RunId=$runId;RuntimeRoot=$runtimeRoot;RequestExpiresUtc=$attemptExpiry.ToString('O');Stage='prepared';Success=$false;RequestPath=$null}
    $plan=[pscustomobject][ordered]@{TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;Stage='qa-prepared';ActiveAgent='Maya';NextAgent='Tara';NextOperation='canonical-execution-record';SideEffectsPerformed=$false}
    $packet=[pscustomobject][ordered]@{SchemaVersion='maya-tara-qa-packet-v3';HandoffId=$handoff.HandoffId;TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;TestId=$handoff.NativeTestId;RunId=$runId;AttemptId=$attemptId;ArtifactPath=$handoff.ArtifactPath;ArtifactSha256=$handoff.ArtifactSha256;ManifestPath=$handoff.ManifestPath;ManifestSha256=$handoff.ManifestSha256;RunnerManifestPath=$handoff.RunnerManifestPath;RunnerManifestSha256=$handoff.RunnerManifestSha256;ModelPath=$workflow.qaModelPath;SidecarPath=$workflow.qaSidecarPath;FixturePath=(Join-Path (Join-Path (Get-MayaQaRoot) 'Fixtures') (Get-MayaQaWorkflowDefinition $QaWorkflowId).Source);FixtureSha256=$workflow.qaFixtureSha256;DisposableModelSha256=$(if($workflow.PSObject.Properties.Name -contains 'qaDisposableModelSha256'){$workflow.qaDisposableModelSha256}else{$workflow.qaFixtureSha256});FixturePreparationEvidence=$(if($workflow.PSObject.Properties.Name -contains 'qaFixturePreparationEvidence'){$workflow.qaFixturePreparationEvidence}else{$null});RequestExpiresUtc=$attempt.RequestExpiresUtc;Stage='prepared';SideEffectsPerformed=$false;StoreRoot=$StoreRoot}
    if($DryRun){return [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;Handoff=$handoff;Attempt=$attempt;Plan=$plan;Packet=$packet;SideEffectsPerformed=$false}}
    $result=Invoke-RepatoStoreMutation $StoreRoot {
        param($data,$preview)
        $task=Find-RepatoTask $data $TaskId
        if($nativeContinuation){
            $currentWorkflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId)
            $currentApprovals=@($task.approvalRequests|Where-Object requestId -ceq $nativeApprovals[0].requestId)
            if($currentWorkflows.Count -ne 1 -or $currentApprovals.Count -ne 1 -or [long]$task.revision -ne [long]$taskState.revision){throw 'Recovered native preparation compare-and-swap changed.'}
            $null=Resolve-CpvNativeContinuationExpiry -Task $task -Workflow $currentWorkflows[0] -Approval $currentApprovals[0] -AttemptDurationMinutes (Get-MayaQaAttemptDurationMinutes)
        }
        foreach($name in 'mayaTaraQaPacket','mayaTaraAttempt','mayaTaraExecution'){if($task.PSObject.Properties.Name -contains $name -and $task.$name){throw "Canonical preparation already contains $name."}}
        if($task.PSObject.Properties.Name -contains 'mayaPlan' -and $task.mayaPlan){$p=$task.mayaPlan;if([string]$p.TaskId -cne $TaskId -or [string]$p.WorkflowId -cne $WorkflowId -or [string]$p.QaWorkflowId -cne $QaWorkflowId -or [string]$p.Stage -cne 'qa-prepared' -or [string]$p.NextOperation -cne 'canonical-execution-record' -or $p.SideEffectsPerformed -ne $false){throw 'Persisted canonical plan changed or no longer matches this continuation.'}}else{$task|Add-Member NoteProperty mayaPlan $plan -Force}
        $task|Add-Member NoteProperty mayaTaraQaPacket $packet -Force
        $task|Add-Member NoteProperty mayaTaraAttempt $attempt -Force
        Add-RepatoHistory $task 'maya-tara-canonical-prepared' 'Maya' "workflow=$WorkflowId; handoff=$($handoff.HandoffId); attempt=$attemptId; run=$runId"
        [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;Handoff=$handoff;Attempt=$attempt;Plan=$plan;Packet=$packet;SideEffectsPerformed=$true}
    }
    $result
}
function Get-MayaQaWorkflowStatus { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId)
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId; $qaId=if($w.PSObject.Properties.Name -contains 'qaWorkflowId'){$w.qaWorkflowId}else{$null}; $def=if($qaId){Get-MayaQaWorkflowDefinition $qaId}else{$null}
    [pscustomobject]@{WorkflowId=$WorkflowId;TaskId=$TaskId;QaWorkflowId=$qaId;Stage=$w.stage;DeploymentStatus=$w.status;QaRunId=$(if($w.PSObject.Properties.Name -contains 'qaRunId'){$w.qaRunId}else{$null});QaVerificationStatus=$(if($w.PSObject.Properties.Name -contains 'qaVerificationStatus'){$w.qaVerificationStatus}else{$null});QaCompletionStatus=$(if($w.PSObject.Properties.Name -contains 'qaCompletionStatus'){$w.qaCompletionStatus}else{$null});Capabilities=$(if($def){@($def.Capabilities)}else{@()});SupervisedExecutionRequired=$true;RevitLaunchByCoordinator=$false;RealDeploymentByCoordinator=$false;DryRunSupported=$true}
}
function Get-MayaQaRoot {
    if($script:MayaQaRootOverrideForTests){$override=[IO.Path]::GetFullPath([string]$script:MayaQaRootOverrideForTests);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\';if(!$override.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){throw 'Synthetic QA root override must remain under the operating-system temporary directory.'};return $override}
    $primaryRepositoryRoot=(Resolve-MayaQaAuthenticatedBuildSource $null).PrimaryRepositoryRoot
    [IO.Path]::GetFullPath((Join-Path $primaryRepositoryRoot 'QA'))
}
function Get-MayaQaRuntimeRoot {
    if($script:MayaQaRootOverrideForTests){return [IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) 'TestRuns'))}
    [IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) 'TestRuns'))
}
function New-MayaQaBootstrap { param([Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$RunId,[string]$StoreRoot,[string]$TaskId,[switch]$DryRun)
    $QaWorkflowId = Resolve-MayaQaWorkflowId $QaWorkflowId
    $def=Get-MayaQaWorkflowDefinition $QaWorkflowId
    if($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'){throw 'Invalid QA run ID.'}
    if(!$StoreRoot){$StoreRoot=Join-Path $env:TEMP ('maya-qa-store-'+[guid]::NewGuid().ToString('N'))}
    $store=[IO.Path]::GetFullPath($StoreRoot);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(!$store.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){throw 'Bootstrap store must be temporary.'}
    if(!$TaskId){$TaskId='maya-qa-'+[guid]::NewGuid().ToString('N').Substring(0,16)}
    if($DryRun){return [pscustomobject]@{StoreRoot=$store;TaskId=$TaskId;WorkflowId=([guid]::NewGuid().ToString('N'));QaWorkflowId=$QaWorkflowId;RunId=$RunId;SideEffectsPerformed=$false}}
    New-RepatoTask $store $TaskId 'Maya QA fixture workflow' "QA workflow $QaWorkflowId" 'qa/maya-qa-workflow' 'maya'|Out-Null
    Claim-RepatoTask $store $TaskId 'Neil'|Out-Null
    Update-RepatoTask $store $TaskId 'in-progress' 'implementation' 'Neil' $null $null|Out-Null
    Update-RepatoTask $store $TaskId 'in-progress' 'build-checks' 'Neil' $null $null|Out-Null
    Update-RepatoTask $store $TaskId 'passed' 'qa' 'Tara' $null $null|Out-Null
    $null=Request-RepatoTaskApproval $store $TaskId 'qa-run' 'maya';$null=Resolve-RepatoTaskApproval $store $TaskId approve 'Maya' 'Tara QA passed; Maya authorized supervised QA run';$qaData=Read-RepatoTaskStore $store;$qaTask=Find-RepatoTask $qaData $TaskId;$qaApproval=@($qaTask.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved'})[-1];if(!$qaApproval){throw 'QA approval was not persisted.'}
    $target=Join-Path $store 'TargetRoot';New-Item -ItemType Directory -Path $target -Force|Out-Null;$artifact=Join-Path $target 'artifact.bin';$manifest=Join-Path $target 'manifest.addin';Set-Content $artifact 'fixture artifact';Set-Content $manifest 'fixture manifest'
    $nativeTestId=Get-MayaQaNativeTestId $def;$plan=New-DeployPlan $store $TaskId $artifact $manifest -TargetRoot $target;$w=New-DeployWorkflow $store $plan;$d=Read-RepatoTaskStore $store;$t=Find-RepatoTask $d $TaskId;$w=@(Invoke-RepatoWorkflowMutation $store $TaskId $w.workflowId $w.workflowRevision $t.revision {param($x)$x|Add-Member -NotePropertyName qaWorkflowId -NotePropertyValue $QaWorkflowId -Force;$x|Add-Member -NotePropertyName qaNativeTestId -NotePropertyValue $nativeTestId -Force;$x|Add-Member -NotePropertyName qaRunId -NotePropertyValue $RunId -Force;$x|Add-Member -NotePropertyName qaApprovalId -NotePropertyValue $qaApproval.requestId -Force;$x|Add-Member -NotePropertyName qaApprovalStatus -NotePropertyValue 'approved' -Force;return $x})[-1];$w=$w.Workflow
    [pscustomobject]@{StoreRoot=$store;TaskId=$TaskId;WorkflowId=$w.workflowId;QaWorkflowId=$QaWorkflowId;NativeTestId=(Get-MayaQaNativeTestId $def);RunId=$RunId;Stage=$w.stage;PlanId=$plan.planId;PlanHash=(Get-DeployPlanHash $plan);SideEffectsPerformed=$true}
}
function Assert-MayaQaPath { param([string]$Path,[string]$Root)
    $p=[IO.Path]::GetFullPath($Path); $r=([IO.Path]::GetFullPath($Root)).TrimEnd('\')+'\'
    if (-not $p.StartsWith($r,[StringComparison]::OrdinalIgnoreCase)) { throw "Path is outside approved QA root: $Path" }; $p
}
function New-MayaQaRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$RunId,
        [string]$RuntimeRoot,
        [string]$FixturePreparationResultPath,
        [long]$ExpectedTaskRevision = 0,
        [switch]$DryRun
    )
    $QaWorkflowId = Resolve-MayaQaWorkflowId $QaWorkflowId
    $def=Get-MayaQaWorkflowDefinition $QaWorkflowId
    if ($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'){throw 'Invalid QA run ID.'}

    $data=Read-RepatoTaskStore $StoreRoot
    $task=Find-RepatoTask $data $TaskId
    $workflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId)
    if($workflows.Count -ne 1 -or [string]$workflows[0].taskId -cne $TaskId){throw 'QA run task/workflow identity is invalid.'}
    $w=$workflows[0]
    $hasExpectedRevision=$PSBoundParameters.ContainsKey('ExpectedTaskRevision')
    if($hasExpectedRevision -and $ExpectedTaskRevision -lt 1){throw 'ExpectedTaskRevision must be a positive task revision.'}
    $expectedRevision=if($hasExpectedRevision){[long]$ExpectedTaskRevision}else{[long]$task.revision}
    if([long]$task.revision -ne $expectedRevision){throw 'QA run task revision is stale.'}
    if($DryRun){return [pscustomobject]@{WorkflowId=$WorkflowId;RunId=$RunId;Stage=$w.stage;SideEffectsPerformed=$false}}
    if($QaWorkflowId -ceq 'create-plan-views-v1'){
        if([string]$w.stage -cnotin @('planned','validated')){throw 'Create Plan Views QA workflow stage is incompatible with plan preparation.'}
        $freshPlan=($task.status -ceq 'in-progress' -and $task.workflowStage -ceq 'build-checks')
        $recoveryPlan=$false
        if($task.status -ceq 'passed' -and $task.workflowStage -ceq 'approval'){
            $workflowApprovalId=if($w.PSObject.Properties.Name -contains 'qaApprovalId'){[string]$w.qaApprovalId}else{''}
            $workflowApprovalStatus=if($w.PSObject.Properties.Name -contains 'qaApprovalStatus'){[string]$w.qaApprovalStatus}else{''}
            $approved=@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved' -and $_.requestId -ceq $workflowApprovalId})
            $pending=@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})
            $handoff=if($w.PSObject.Properties.Name -contains 'qaHandoff'){$w.qaHandoff}else{$null}
            $binding=if($approved.Count -eq 1 -and $approved[0].PSObject.Properties.Name -contains 'executionBinding'){$approved[0].executionBinding}else{$null}
            $buildEvidence=if($w.PSObject.Properties.Name -contains 'qaBuildEvidence'){$w.qaBuildEvidence}else{$null}
            $evidenceBuildId=if($buildEvidence -and $buildEvidence.PSObject.Properties.Name -contains 'BuildRequestId'){[string]$buildEvidence.BuildRequestId}else{''}
            $evidenceCommit=if($buildEvidence -and $buildEvidence.PSObject.Properties.Name -contains 'CandidateSourceCommit'){[string]$buildEvidence.CandidateSourceCommit}else{''}
            $evidenceHash=if($buildEvidence -and $buildEvidence.PSObject.Properties.Name -contains 'ArtifactSha256'){[string]$buildEvidence.ArtifactSha256}else{''}
            $recoveryPlan=($approved.Count -eq 1 -and $pending.Count -eq 0 -and $workflowApprovalStatus -ceq 'approved' -and $handoff -and $binding -and
                [string]$handoff.HandoffId -ceq [string]$w.qaHandoffId -and [string]$handoff.TaskId -ceq $TaskId -and
                [string]$handoff.WorkflowId -ceq $WorkflowId -and [string]$handoff.QaWorkflowId -ceq $QaWorkflowId -and
                [string]$binding.TaskId -ceq $TaskId -and [string]$binding.WorkflowId -ceq $WorkflowId -and
                [string]$binding.BuildRequestId -ceq $evidenceBuildId -and
                [string]$binding.CandidateSourceCommit -ceq $evidenceCommit -and
                [string]$binding.CandidateSha256 -ieq $evidenceHash)
        }
        if(!$freshPlan -and !$recoveryPlan){throw 'Create Plan Views QA planning requires build-checks or a supported approved-run recovery state.'}
        if($freshPlan -and (Test-MayaQaHasActiveCanonicalExecutionApproval -Approvals @($task.approvalRequests))){throw 'An active QA approval prevents new plan preparation.'}
        if($w.PSObject.Properties.Name -contains 'qaRunId' -and ![string]::IsNullOrWhiteSpace([string]$w.qaRunId)){throw 'Create Plan Views QA run already exists.'}
        if($freshPlan){foreach($n in 'qaModelPath','qaSidecarPath','qaFixturePreparationEvidence'){if($w.PSObject.Properties.Name -contains $n -and $null -ne $w.$n -and ![string]::IsNullOrWhiteSpace([string]$w.$n)){throw 'Create Plan Views QA plan is partially prepared.'}}}
        foreach($n in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){if($task.PSObject.Properties.Name -contains $n -and $task.$n){throw 'Existing Tara execution state prevents new plan preparation.'}}
    }
    if($w.PSObject.Properties.Name -contains 'qaRunId' -and ![string]::IsNullOrWhiteSpace([string]$w.qaRunId)){throw 'QA run already exists for this workflow.'}
    if($w.PSObject.Properties.Name -contains 'qaBuildEvidence' -and $w.PSObject.Properties.Name -contains 'qaBuildStatus' -and $w.qaBuildStatus -cne 'succeeded'){throw 'Valid Neil build evidence is required before QA run planning.'}
    if ($w.PSObject.Properties.Name -notcontains 'qaBuildEvidence' -or $w.PSObject.Properties.Name -notcontains 'qaBuildStatus' -or $w.qaBuildStatus -ne 'succeeded') { throw 'Valid Neil build evidence is required before QA run planning.' }
    foreach($pair in @(@($w.qaBuildEvidence.ArtifactPath,$w.qaBuildEvidence.ArtifactSha256),@($w.qaBuildEvidence.ManifestPath,$w.qaBuildEvidence.ManifestSha256))){if(!(Test-Path -LiteralPath $pair[0] -PathType Leaf) -or (Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ine $pair[1]){throw 'Neil build evidence hash validation failed.'}}

    $qa=Get-MayaQaRoot
    $runs=if([string]::IsNullOrWhiteSpace($RuntimeRoot)){Get-MayaQaRuntimeRoot}else{[IO.Path]::GetFullPath($RuntimeRoot)}
    $run=[IO.Path]::GetFullPath((Join-Path $runs ($WorkflowId+'-'+$RunId)))
    $runsPrefix=([IO.Path]::GetFullPath($runs)).TrimEnd('\')+'\'
    if(!$run.StartsWith($runsPrefix,[StringComparison]::OrdinalIgnoreCase)){throw "Run path escaped QA runtime root: $run"}
    if(Test-Path -LiteralPath $run){throw 'QA run directory already exists.'}
    $source=Join-Path (Join-Path $qa 'Fixtures') $def.Source
    if(!(Test-Path -LiteralPath $source -PathType Leaf)){throw "Approved fixture missing: $source"}
    $fixtureHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $preparation=$null
    if($QaWorkflowId -ceq 'create-plan-views-v1' -and [string]::IsNullOrWhiteSpace($FixturePreparationResultPath)){
        throw 'Create Plan Views QA run requires correlated fixture-preparation evidence before approval or execution preparation.'
    }
    if($FixturePreparationResultPath){
        if($QaWorkflowId -cne 'create-plan-views-v1'){throw 'Prepared-fixture provenance is supported only for Create Plan Views.'}
        $prepResultPath=Assert-MayaQaPath $FixturePreparationResultPath (Join-Path $qa 'TestRuns')
        if(!(Test-Path -LiteralPath $prepResultPath -PathType Leaf)){throw 'Fixture preparation result is missing.'}
        if(!$prepResultPath.EndsWith('.request.json.preparation.json',[StringComparison]::OrdinalIgnoreCase)){throw 'Fixture preparation result path is not a supported canonical result name.'}
        $prepRequestPath=$prepResultPath.Substring(0,$prepResultPath.Length-('.preparation.json'.Length))
        if(!(Test-Path -LiteralPath $prepRequestPath -PathType Leaf)){throw 'Correlated fixture preparation request is missing.'}
        $prepRequest=Get-Content -LiteralPath $prepRequestPath -Raw|ConvertFrom-Json
        $prepResult=Get-Content -LiteralPath $prepResultPath -Raw|ConvertFrom-Json
        $prepRequestHash=(Get-FileHash -LiteralPath $prepRequestPath -Algorithm SHA256).Hash
        $prepResultHash=(Get-FileHash -LiteralPath $prepResultPath -Algorithm SHA256).Hash
        foreach($pair in @(@('operation','prepare-disposable-create-plan-views-fixture'),@('taskId',$TaskId),@('workflowId',$WorkflowId))){if([string]$prepRequest.($pair[0]) -cne [string]$pair[1]){throw "Fixture preparation request identity mismatch: $($pair[0])."}}
        if([string]$prepResult.Status -cne 'Passed' -or [string]$prepResult.Operation -cne 'prepare-disposable-create-plan-views-fixture' -or [string]$prepResult.TaskId -cne $TaskId -or [string]$prepResult.WorkflowId -cne $WorkflowId -or [string]$prepResult.AttemptId -cne [string]$prepRequest.AttemptId -or [string]$prepResult.RunId -cne [string]$prepRequest.RunId -or [IO.Path]::GetFullPath([string]$prepResult.ModelPath) -ine [IO.Path]::GetFullPath([string]$prepRequest.modelPath)){throw 'Fixture preparation result identity does not correlate to its request.'}
        if([string]$prepRequest.modelSha256 -ine $fixtureHash -or [string]$prepResult.SourceModelSha256 -ine $fixtureHash -or [string]$prepResult.PreparedModelSha256 -notmatch '^[a-fA-F0-9]{64}$' -or !(Test-Path -LiteralPath $prepRequest.modelPath -PathType Leaf) -or (Get-FileHash -LiteralPath $prepRequest.modelPath -Algorithm SHA256).Hash -ine [string]$prepResult.PreparedModelSha256){throw 'Fixture preparation source/prepared model hash validation failed.'}
        if([IO.Path]::GetFullPath([string]$prepRequest.outputPath) -ine $prepResultPath -or [string]$prepRequest.attemptId -notmatch '^[a-fA-F0-9]{32}$' -or [string]$prepRequest.runId -notmatch '^[a-fA-F0-9]{32}$'){throw 'Fixture preparation request/result path or identity binding failed.'}
        $preparation=[pscustomobject]@{RequestPath=$prepRequestPath;RequestSha256=$prepRequestHash;ResultPath=$prepResultPath;ResultSha256=$prepResultHash;AttemptId=[string]$prepRequest.attemptId;RunId=[string]$prepRequest.runId;SourceSha256=$fixtureHash;PreparedModelPath=[IO.Path]::GetFullPath([string]$prepRequest.modelPath);PreparedModelSha256=[string]$prepResult.PreparedModelSha256}
    }

    $model=Join-Path $run 'model.rvt'
    $sidecar=Join-Path $run 'model.rvt.fixture.json'
    $created=[pscustomobject]@{Run=$false;RunsRoot=$false;ModelHash=$null}
    $transform={
        param($current)
        if(Test-Path -LiteralPath $run){throw 'QA run directory already exists.'}
        if(!(Test-Path -LiteralPath $runs -PathType Container)){New-Item -ItemType Directory -Path $runs -Force|Out-Null;$created.RunsRoot=$true}
        New-Item -ItemType Directory -Path $run -ErrorAction Stop|Out-Null
        $created.Run=$true
        if($preparation){Copy-Item -LiteralPath $preparation.PreparedModelPath -Destination $model -ErrorAction Stop}else{Copy-Item -LiteralPath $source -Destination $model -ErrorAction Stop}
        $created.ModelHash=(Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash
        if($preparation -and $created.ModelHash -ine $preparation.PreparedModelSha256){throw 'Canonical disposable model does not match the prepared-model result hash.'}
        $side=[ordered]@{fixtureId=$def.FixtureId;sourceSha256=$fixtureHash}
        if($preparation){$side.preparedModelSha256=$preparation.PreparedModelSha256;$side.fixturePreparationRequestPath=$preparation.RequestPath;$side.fixturePreparationRequestSha256=$preparation.RequestSha256;$side.fixturePreparationResultPath=$preparation.ResultPath;$side.fixturePreparationResultSha256=$preparation.ResultSha256;$side.fixturePreparationAttemptId=$preparation.AttemptId;$side.fixturePreparationRunId=$preparation.RunId}
        if($QaWorkflowId -eq 'grid-bubble-visibility-v1' -or $QaWorkflowId -eq 'grid-bubble-offset-v1'){$side.requiredGridNames=@('A','B','C','D','1','2','3','4')}
        if($QaWorkflowId -eq 'grid-resequence-v1'){$side.requiredGridNames=@('1','2','3','3.2','4','A','A.1','B','C')}
        $side|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $sidecar -Encoding UTF8
        if($WorkflowId -eq 'grid-bubble-visibility-v1'){$check=Get-Content -LiteralPath $sidecar -Raw|ConvertFrom-Json;$expected=@('A','B','C','D','1','2','3','4');if($check.fixtureId -cne 'GridBubbleVisibilityEmpty' -or $check.sourceSha256 -ine $fixtureHash -or (@($check.requiredGridNames)-join '|') -cne ($expected -join '|')){throw 'Grid Bubble Visibility sidecar identity is invalid.'}}
        foreach($v in @(@('qaWorkflowId',$QaWorkflowId),@('qaRunId',$RunId),@('qaModelPath',$model),@('qaSidecarPath',$sidecar),@('qaFixtureId',$def.FixtureId),@('qaFixtureSha256',$fixtureHash),@('qaFixturePreparationEvidence',$preparation),@('qaDisposableModelSha256',$created.ModelHash),@('qaTestId',(Get-MayaQaNativeTestId $def)),@('qaReportPath',$null),@('qaReportSha256',$null),@('qaEvidence',$null),@('qaVerificationStatus',$null),@('qaCompletionStatus',$null),@('qaCompletedUtc',$null))){$current|Add-Member -NotePropertyName $v[0] -NotePropertyValue $v[1] -Force}
        if($current.PSObject.Properties.Name -contains 'qaHandoff'){
            if($current.qaHandoff){$current.qaHandoff|Add-Member -NotePropertyName ModelPath -NotePropertyValue $model -Force;$current.qaHandoff|Add-Member -NotePropertyName SidecarPath -NotePropertyValue $sidecar -Force}
        }
        return $current
    }.GetNewClosure()
    try{
        $m=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $w.workflowRevision $expectedRevision $transform)[-1]
    }catch{
        if($created.Run -and (Test-Path -LiteralPath $run -PathType Container)){Remove-Item -LiteralPath $run -Recurse -Force -ErrorAction SilentlyContinue}
        if($created.RunsRoot -and (Test-Path -LiteralPath $runs -PathType Container) -and @((Get-ChildItem -LiteralPath $runs -Force -ErrorAction SilentlyContinue)).Count -eq 0){Remove-Item -LiteralPath $runs -Force -ErrorAction SilentlyContinue}
        throw
    }
    [pscustomobject]@{WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;RunId=$RunId;ModelPath=$model;SidecarPath=$sidecar;FixtureId=$def.FixtureId;FixtureSha256=$fixtureHash;ModelSha256=$created.ModelHash;FixturePreparation=$preparation;Stage=$m.Workflow.stage;WorkflowRevision=$m.Workflow.workflowRevision;TaskRevision=$m.TaskRevision;SideEffectsPerformed=$true}
}
function Register-MayaQaReport { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$ReportPath,[string]$ReportRoot,[switch]$DryRun)
    $def=Get-MayaQaWorkflowDefinition $QaWorkflowId; $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if($DryRun){return [pscustomobject]@{WorkflowId=$WorkflowId;Valid=$false;SideEffectsPerformed=$false}}
    if([string]::IsNullOrWhiteSpace($ReportRoot)){$ReportRoot=Join-Path (Get-MayaQaRuntimeRoot) 'Reports'}else{$ReportRoot=[IO.Path]::GetFullPath($ReportRoot)}
    $report=Assert-MayaQaPath $ReportPath $ReportRoot; if(!(Test-Path -LiteralPath $report -PathType Leaf)){throw 'QA report does not exist.'}
    $j=Get-Content -LiteralPath $report -Raw|ConvertFrom-Json
    if($j.TestId -cne (Get-MayaQaNativeTestId $def) -or $j.Status -cne 'Passed' -or $j.RollbackStatus -cne 'RolledBack'){throw 'QA report identity/status failed.'}
    if(!$j.Assertions -or @($j.Assertions|Where-Object {$_.Passed -ne $true}).Count){throw 'QA report contains failed assertions.'}
    if([string]::IsNullOrWhiteSpace([string]$j.DocumentPath) -or ([IO.Path]::GetFullPath($j.DocumentPath) -ine [IO.Path]::GetFullPath($w.qaModelPath))){throw 'QA report model identity failed.'}
    if($j.FixtureId -cne $w.qaFixtureId -or $j.FixtureSha256 -ine $w.qaFixtureSha256){throw 'QA report fixture identity failed.'}
    if([string]::IsNullOrWhiteSpace([string]$j.FinishedUtc)){throw 'QA report timestamp is missing.'};try { $finishedUtc=if($j.FinishedUtc -is [datetime]){$finishedDate=[datetime]$j.FinishedUtc;[DateTimeOffset]::new($finishedDate,[TimeZoneInfo]::Local.GetUtcOffset($finishedDate))}else{Get-MayaQaNormalizedUtc -Value ([string]$j.FinishedUtc) -Context 'QA report finish'};if($finishedUtc -lt (Get-MayaQaNormalizedUtc -Value ([string]$w.startedUtc) -Context 'QA workflow start')){throw 'QA report is stale.'} } catch { if($_.Exception.Message -eq 'QA report is stale.'){throw}; throw 'QA report timestamp is invalid.' }
    $side=Get-Content -LiteralPath $w.qaSidecarPath -Raw|ConvertFrom-Json; if($side.sourceSha256 -ine $w.qaFixtureSha256){throw 'Fixture sidecar hash mismatch.'}
    $rh=(Get-FileHash -LiteralPath $report -Algorithm SHA256).Hash; $d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId
    $m=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $w.workflowRevision $t.revision {param($x)$tara=if($x.PSObject.Properties.Name -contains 'qaTaraExecutionEvidence'){$x.qaTaraExecutionEvidence}else{$null};$e=[pscustomobject]@{CoordinatorRunId=$x.qaRunId;NativeRunId=$j.RunId;TestId=$j.TestId;Status=$j.Status;RollbackStatus=$j.RollbackStatus;Assertions=@($j.Assertions).Count;DocumentPath=[IO.Path]::GetFullPath($j.DocumentPath);FixtureId=$j.FixtureId;FixtureSha256=$j.FixtureSha256;RequestIntent=$(if($x.PSObject.Properties.Name -contains 'qaRequestIntent'){$x.qaRequestIntent}else{$null});PromptDetected=$(if($tara){$tara.PromptDetected}else{$null});PromptAction=$(if($tara){$tara.PromptAction}else{$null});ApprovedManifest=$(if($tara){$tara.ApprovedManifest}else{$null});PromptFree=$(if($tara){$tara.PromptFree}else{$null});VerifiedUtc=(Get-Date).ToUniversalTime().ToString('O')};$x|Add-Member -NotePropertyName qaReportPath -NotePropertyValue $report -Force;$x|Add-Member -NotePropertyName qaReportSha256 -NotePropertyValue $rh -Force;$x|Add-Member -NotePropertyName qaEvidence -NotePropertyValue $e -Force;$x|Add-Member -NotePropertyName qaVerificationStatus -NotePropertyValue 'verified' -Force;return $x})[-1]
    [pscustomobject]@{WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;ReportPath=$report;ReportSha256=$rh;Valid=$true;WorkflowRevision=$m.Workflow.workflowRevision;TaskRevision=$m.TaskRevision;SideEffectsPerformed=$true}
}
function Submit-MayaQaReport {
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$HandoffId,
        [Parameter(Mandatory)][string]$ReportPath,
        [string]$ReportRoot,
        [switch]$DryRun
    )
    $definition = Get-MayaQaWorkflowDefinition $QaWorkflowId
    if ($DryRun) {
        return [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;HandoffId=$HandoffId;ReportPath=$ReportPath;Valid=$false;SubmissionStatus='planned';SideEffectsPerformed=$false}
    }
    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $properties = @($workflow.PSObject.Properties.Name)
    if ($properties -notcontains 'qaHandoff' -or $properties -notcontains 'qaHandoffId' -or $workflow.qaHandoffId -cne $HandoffId) {
        throw 'Tara QA handoff identity is invalid.'
    }
    if ($workflow.qaHandoff.HandoffStatus -cne 'ready' -or $workflow.qaHandoff.QaWorkflowId -cne $QaWorkflowId -or $workflow.qaHandoff.TaskId -cne $TaskId) {
        throw 'Tara QA handoff is not valid for this workflow.'
    }
    foreach ($item in @(
        @('artifact', $workflow.qaHandoff.ArtifactPath, $workflow.qaHandoff.ArtifactSha256),
        @('manifest', $workflow.qaHandoff.ManifestPath, $workflow.qaHandoff.ManifestSha256)
    )) {
        if (!(Test-Path -LiteralPath $item[1] -PathType Leaf)) { throw "Handoff $($item[0]) is missing." }
        if ((Get-FileHash -LiteralPath $item[1] -Algorithm SHA256).Hash -ine [string]$item[2]) { throw "Handoff $($item[0]) hash mismatch." }
    }
    if ($properties -contains 'qaReportPath' -and $workflow.qaReportPath) {
        throw 'QA report has already been submitted.'
    }
    if([string]::IsNullOrWhiteSpace($ReportRoot)){$ReportRoot=Join-Path (Get-MayaQaRuntimeRoot) 'Reports'}else{$ReportRoot=[IO.Path]::GetFullPath($ReportRoot)}
    $reportsRoot = $ReportRoot.TrimEnd('\') + '\'
    $resolvedReport = [IO.Path]::GetFullPath($ReportPath)
    if (!$resolvedReport.StartsWith($reportsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Path is outside approved QA root: $ReportPath" }
    if (!(Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { throw 'QA report does not exist.' }
    $result = Register-MayaQaReport $StoreRoot $TaskId $WorkflowId $QaWorkflowId $resolvedReport -ReportRoot $ReportRoot
    [pscustomobject]@{
        TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;HandoffId=$HandoffId
        ReportPath=$result.ReportPath;ReportSha256=$result.ReportSha256;NativeRunId=$workflow.qaRunId
        Valid=$result.Valid;SubmissionStatus='submitted';WorkflowRevision=$result.WorkflowRevision
        TaskRevision=$result.TaskRevision;SideEffectsPerformed=$true
    }
}
function Complete-MayaQaApprovedRunAuthorization {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[switch]$DryRun)
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if($w.PSObject.Properties.Name -notcontains 'qaApprovalId' -or [string]::IsNullOrWhiteSpace([string]$w.qaApprovalId)){throw 'Approved run authorization reconciliation requires the canonical QA approval identity.'}
    if($w.PSObject.Properties.Name -notcontains 'qaEvidence' -or !$w.qaEvidence){throw 'Approved run authorization reconciliation requires registered passed QA evidence.'}
    $e=$w.qaEvidence
    if($w.qaVerificationStatus -cne 'verified' -or [string]$e.Status -cne 'Passed' -or [string]$e.RollbackStatus -cne 'RolledBack'){throw 'Approved run authorization reconciliation requires verified passed QA evidence with rollback proof.'}
    $nativeRunId=[string]$e.NativeRunId
    if($nativeRunId.Length -lt 8 -or $nativeRunId -cne [string]$w.qaRunId){throw 'Approved run authorization reconciliation requires the registered native run identity.'}
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    if(!$task -or $task.status -cne 'in-progress' -or $task.workflowStage -cne 'approval'){throw 'Approved run authorization reconciliation requires the in-progress approval stage.'}
    foreach($n in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket'){if($task.PSObject.Properties.Name -notcontains $n -or !$task.$n -or [string]$task.$n.RunId -cne $nativeRunId){throw "Approved run authorization reconciliation requires the completed native run for $n."}}
    $execution=$task.mayaTaraExecution
    if([string]$execution.CompletionStatus -cne 'Completed' -or [string]$execution.VerificationStatus -cne 'Verified' -or [string]$execution.RollbackStatus -cne 'Verified'){throw 'Approved run authorization reconciliation requires a completed verified native execution.'}
    if([string]::IsNullOrWhiteSpace([string]$execution.LaunchedUtc)){throw 'Approved run authorization reconciliation requires the recorded native launch timestamp.'}
    try{$launchedUtc=Get-MayaQaNormalizedUtc -Value ([string]$execution.LaunchedUtc) -Context 'Native launch'}catch{throw 'Native launch timestamp is invalid.'}
    $approvals=@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved' -and $_.requestId -ceq [string]$w.qaApprovalId})
    if($approvals.Count -ne 1){throw 'Approved run authorization reconciliation requires exactly one approved human QA request for the canonical run.'}
    $approval=$approvals[0]
    if($approval.PSObject.Properties.Name -notcontains 'executionBinding' -or !$approval.executionBinding){throw 'Approved run authorization reconciliation requires the canonical execution binding.'}
    $binding=[string]$approval.bindingHash
    if([string]::IsNullOrWhiteSpace($binding)){throw 'Approved run authorization reconciliation requires the approval binding hash.'}
    $json=ConvertTo-Json -InputObject $approval.executionBinding -Depth 20 -Compress
    $sha=[Security.Cryptography.SHA256]::Create();try{$actualBindingHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}finally{$sha.Dispose()}
    if($actualBindingHash -ine $binding){throw 'Approved run authorization binding hash mismatch.'}
    if([string]$approval.decidedBy -cne 'user' -or !$approval.approvedRevision){throw 'Approved run authorization reconciliation requires the recorded human decision.'}
    foreach($n in 'expiresUtc','requestedUtc','decidedUtc'){try{Get-MayaQaNormalizedUtc -Value ([string]$approval.$n) -Context 'Approval' | Out-Null}catch{throw 'Approval timestamp is invalid.'}}
    $expiresUtc=Get-MayaQaNormalizedUtc -Value ([string]$approval.expiresUtc) -Context 'Approval expiry'
    if($launchedUtc -ge $expiresUtc){throw 'Recorded native launch occurred after the human authorization expired.'}
    if((Get-MayaQaNormalizedUtc -Value ([string]$approval.requestedUtc) -Context 'Approval request') -gt $launchedUtc -or (Get-MayaQaNormalizedUtc -Value ([string]$approval.decidedUtc) -Context 'Approval decision') -gt $launchedUtc){throw 'Approval request or decision postdates the native launch it authorizes.'}
    $runIdProp=$approval.PSObject.Properties['runId']
    if($runIdProp -and $runIdProp.Value){if([string]$runIdProp.Value -cne $nativeRunId){throw 'Approved run authorization run identity is already bound to a different native run.'};if($approval.consumedUtc){return [pscustomobject]@{Status='AlreadyReconciled';TaskId=$TaskId;WorkflowId=$WorkflowId;ApprovalId=[string]$approval.requestId;RunId=$nativeRunId;ConsumedUtc=[string]$approval.consumedUtc;TaskRevision=[long]$task.revision;SideEffectsPerformed=$false}}}
    if($DryRun){return [pscustomobject]@{Status='WouldReconcile';TaskId=$TaskId;WorkflowId=$WorkflowId;ApprovalId=[string]$approval.requestId;RunId=$nativeRunId;ConsumedUtc=$null;TaskRevision=[long]$task.revision;SideEffectsPerformed=$false}}
    $expectedRevision=[long]$task.revision
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)
        $t=Find-RepatoTask $data $TaskId
        if([long]$t.revision -ne $expectedRevision -or $t.status -cne 'in-progress' -or $t.workflowStage -cne 'approval'){throw 'Approved run authorization compare-and-swap failed.'}
        $ws=@($t.deploymentWorkflows|Where-Object {$_.workflowId -ceq $WorkflowId -and $_.taskId -ceq $TaskId})
        if($ws.Count -ne 1 -or [string]$ws[0].qaRunId -cne $nativeRunId -or [string]$ws[0].qaApprovalId -cne $w.qaApprovalId -or !$ws[0].qaEvidence -or [string]$ws[0].qaEvidence.NativeRunId -cne $nativeRunId){throw 'QA evidence changed during approved run authorization reconciliation.'}
        foreach($n in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket'){if($t.PSObject.Properties.Name -notcontains $n -or !$t.$n -or [string]$t.$n.RunId -cne $nativeRunId){throw "Native run identity changed during approved run authorization reconciliation: $n"}}
        $current=@($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved' -and $_.requestId -ceq [string]$w.qaApprovalId})
        if($current.Count -ne 1){throw 'Approved QA request changed during run authorization reconciliation.'}
        $ap=$current[0]
        $runIdProp=$ap.PSObject.Properties['runId']
        if($runIdProp -and $runIdProp.Value -and [string]$runIdProp.Value -cne $nativeRunId){throw 'Approved run authorization run identity is already bound to a different native run.'}
        $changed=$false
        if(!$runIdProp -or !$runIdProp.Value){$ap|Add-Member NoteProperty runId ([string]$nativeRunId) -Force;$changed=$true}
        if(!$ap.consumedUtc){$ap.consumedUtc=$launchedUtc.ToString('O');$changed=$true}
        if($changed){Add-RepatoHistory $t 'maya-qa-approved-run-authorization-consumed' 'Maya' "approval=$($ap.requestId); run=$nativeRunId; launchedUtc=$($launchedUtc.ToString('O'))"}
        [pscustomobject]@{Status='Reconciled';TaskId=$TaskId;WorkflowId=$WorkflowId;ApprovalId=[string]$ap.requestId;RunId=$nativeRunId;ConsumedUtc=[string]$ap.consumedUtc;TaskRevision=[long]$t.revision;SideEffectsPerformed=$true}
    }
}
function Invoke-MayaQaRevitGracefulShutdownCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [ValidateRange(1,14400)][int]$GracefulTimeoutSeconds=120,
        [switch]$FailureOutcomeReported,
        [scriptblock]$ProcessProvider
    )
    $storePath=[IO.Path]::GetFullPath($StoreRoot);$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(!$storePath.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and $GracefulTimeoutSeconds -lt 120){throw 'Revit graceful shutdown timeout must be at least 120 seconds outside synthetic test stores.'}
    if(!$ProcessProvider){$ProcessProvider={Get-Process Revit -ErrorAction SilentlyContinue}}
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    if(!$task){throw 'Revit graceful shutdown requires the task.'}
    if($task.PSObject.Properties.Name -notcontains 'mayaTaraExecution' -or !$task.mayaTaraExecution){throw 'Revit graceful shutdown requires the native execution record.'}
    $x=$task.mayaTaraExecution
    if([string]$x.WorkflowId -cne $WorkflowId){throw 'Revit graceful shutdown workflow identity mismatch.'}
    $pidProp=$x.PSObject.Properties['NativeProcessId']
    if(!$pidProp -or !$pidProp.Value){throw 'Revit graceful shutdown requires the recorded native process identity.'}
    $targetPid=[int]$pidProp.Value
    if($targetPid -le 0){throw 'Revit graceful shutdown native process identity is invalid.'}
    $completed=($x.PSObject.Properties['CompletionStatus'] -and [string]$x.CompletionStatus -ceq 'Completed')
    $failed=($x.PSObject.Properties['FailureCode'] -and $x.FailureCode) -and ($x.PSObject.Properties['FailedUtc'] -and $x.FailedUtc)
    if(!$completed -and !$failed -and !$FailureOutcomeReported){throw 'Revit graceful shutdown requires a completed or failed native attempt record without pending Revit operations.'}
    $existing=$x.PSObject.Properties['RevitShutdownStatus']
    if($existing -and $existing.Value){return [pscustomobject]@{Status='AlreadyShutdown';Detail=('previous='+[string]$existing.Value);ProcessId=$targetPid;ModelUnlocked=$null;ModelSha256=$null;ModelShaMatch=$null;TaskRevision=[long]$task.revision;SideEffectsPerformed=$false}}
    if($FailureOutcomeReported){throw 'Failure-outcome shutdown is coordinator-only and cannot be invoked from the module boundary.'}
    $procs=@(& $ProcessProvider)
    $matching=@($procs|Where-Object {try{[int]$_.Id -eq $targetPid}catch{$false}})
    $otherCount=@($procs|Where-Object {try{[int]$_.Id -ne $targetPid -and [string]$_.ProcessName -ieq 'Revit'}catch{$false}}).Count
    $outcome=$null;$detail=$null;$sideEffects=$false
    if($matching.Count -eq 0){
        $outcome='Closed';$detail=('process-already-exited'+$(if($otherCount){'; other-revit-instances-present='+$otherCount}else{''}))
    } else {
        $target=$matching[0]
        if([string]$target.ProcessName -cne 'Revit'){throw "Recorded native process $targetPid is not a Revit process."}
        $closed=$false
        try{
            if($target.HasExited){$closed=$true;$detail='process-already-exited'}
            elseif($target.MainWindowHandle -eq [IntPtr]::Zero){$detail='window-close-unavailable';$closed=$false}
            else{$closed=[bool]$target.CloseMainWindow();if($closed){$detail='window-close-requested'}}
        }catch{$closed=$false;$detail='window-close-refused'}
        if($closed -and $detail -ceq 'window-close-requested'){$sideEffects=$true}
        if(-not $closed){
            if(-not $detail){$detail='window-close-refused'}
            $outcome='Blocked'
        } else {
            $deadline=[DateTimeOffset]::UtcNow.AddSeconds($GracefulTimeoutSeconds)
            $exited=$false
            while([DateTimeOffset]::UtcNow -lt $deadline){
                Start-Sleep -Seconds 1
                $latest=@(& $ProcessProvider)
                if(-not @($latest|Where-Object {try{[int]$_.Id -eq $targetPid}catch{$false}})){$exited=$true;break}
            }
            if($exited){$outcome='Closed';$detail='window-close-requested; process-exited'}
            else{$outcome='Timeout'}
        }
    }
    $modelUnlocked=$null;$modelSha=$null;$modelShaMatch=$null
    if($outcome -ceq 'Closed'){
        $modelPathProp=$x.PSObject.Properties['DisposableModelPath']
        $modelPath=if($modelPathProp){[string]$modelPathProp.Value}else{''}
        if(![string]::IsNullOrWhiteSpace($modelPath) -and (Test-Path -LiteralPath $modelPath -PathType Leaf)){
            for($i=0;$i -lt 5;$i++){
                try{$fs=[IO.File]::Open($modelPath,'Open','Read','Read');$fs.Close();$modelUnlocked=$true;break}catch{$modelUnlocked=$false;Start-Sleep -Seconds 1}
            }
            if($modelUnlocked){
                $modelSha=(Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash
                $expectedShaProp=$x.PSObject.Properties['DisposableModelSha256']
                if($expectedShaProp -and $expectedShaProp.Value){$modelShaMatch=($modelSha -ieq [string]$expectedShaProp.Value)}
            }
        }
    }
    if($modelShaMatch -eq $false){$detail=([string]$detail)+'; model-sha-mismatch'}
    $needsStamp=($sideEffects -or $outcome -in @('Blocked','Timeout'))
    if(-not $needsStamp){
        return [pscustomobject]@{Status=$outcome;Detail=$detail;ProcessId=$targetPid;ModelUnlocked=$modelUnlocked;ModelSha256=$modelSha;ModelShaMatch=$modelShaMatch;TaskRevision=[long]$task.revision;SideEffectsPerformed=$false}
    }
    $expectedRevision=[long]$task.revision
    $stamp=Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)
        $t=Find-RepatoTask $data $TaskId
        if([long]$t.revision -ne $expectedRevision){throw 'Revit graceful shutdown compare-and-swap failed.'}
        $xr=$t.mayaTaraExecution
        if(!$xr -or [string]$xr.RunId -cne [string]$x.RunId -or [string]$xr.AttemptId -cne [string]$x.AttemptId -or ([int]$xr.NativeProcessId) -ne $targetPid){throw 'Native execution record changed during Revit graceful shutdown.'}
        if($xr.PSObject.Properties['RevitShutdownStatus'] -and $xr.RevitShutdownStatus){throw 'Revit graceful shutdown already stamped.'}
        $xr|Add-Member NoteProperty RevitShutdownStatus ([string]$outcome) -Force
        $xr|Add-Member NoteProperty RevitShutdownUtc (Get-RepatoUtc) -Force
        $xr|Add-Member NoteProperty RevitShutdownDetail ([string]$detail) -Force
        $xr|Add-Member NoteProperty RevitShutdownModelUnlocked $modelUnlocked -Force
        $xr|Add-Member NoteProperty RevitShutdownModelSha256 $modelSha -Force
        Add-RepatoHistory $t 'maya-tara-revit-graceful-shutdown' 'Maya' "pid=$targetPid; outcome=$outcome; detail=$detail; modelUnlocked=$modelUnlocked"
        [pscustomobject]@{TaskRevision=[long]$t.revision}}
    [pscustomobject]@{Status=$outcome;Detail=$detail;ProcessId=$targetPid;ModelUnlocked=$modelUnlocked;ModelSha256=$modelSha;ModelShaMatch=$modelShaMatch;TaskRevision=$stamp.TaskRevision;SideEffectsPerformed=$sideEffects}
}
function Invoke-MayaQaRevitGracefulShutdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [ValidateRange(1,14400)][int]$GracefulTimeoutSeconds=120,
        [scriptblock]$ProcessProvider
    )
    Invoke-MayaQaRevitGracefulShutdownCore -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -GracefulTimeoutSeconds $GracefulTimeoutSeconds $ProcessProvider
}
function Complete-MayaQaWorkflow { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[switch]$DryRun)
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $completion = if($w.PSObject.Properties.Name -contains 'qaCompletionStatus'){[string]$w.qaCompletionStatus}else{$null}
    $verification = if($w.PSObject.Properties.Name -contains 'qaVerificationStatus'){[string]$w.qaVerificationStatus}else{$null}
    if($DryRun){return [pscustomobject]@{WorkflowId=$WorkflowId;QaVerificationStatus=$verification;QaCompletionStatus=$completion;SideEffectsPerformed=$false}}
    if($completion -eq 'completed'){throw 'QA workflow is already completed.'}
    if(($verification -and $verification -ne 'verified') -or !$w.qaEvidence -or $w.qaEvidence.Status -ne 'Passed' -or $w.qaEvidence.RollbackStatus -ne 'RolledBack'){throw 'Verified QA evidence is required.'}
    if(!(Test-Path -LiteralPath $w.qaReportPath -PathType Leaf)){throw 'Verified QA report is missing.'}
    if((Get-FileHash -LiteralPath $w.qaReportPath -Algorithm SHA256).Hash -ine $w.qaReportSha256){throw 'Verified QA report hash changed.'}
    $d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId
    $m=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $w.workflowRevision $t.revision {param($x)$x|Add-Member -NotePropertyName qaVerificationStatus -NotePropertyValue 'verified' -Force;$x|Add-Member -NotePropertyName qaCompletionStatus -NotePropertyValue 'completed' -Force;$x|Add-Member -NotePropertyName qaCompletedUtc -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('O')) -Force;return $x})[-1]
    $updated=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    [pscustomobject]@{WorkflowId=$WorkflowId;QaVerificationStatus=$updated.qaVerificationStatus;QaCompletionStatus=$updated.qaCompletionStatus;CoordinatorRunId=$updated.qaEvidence.CoordinatorRunId;NativeRunId=$updated.qaEvidence.NativeRunId;WorkflowRevision=$m.Workflow.workflowRevision;TaskRevision=$m.TaskRevision;SideEffectsPerformed=$true}
}
function Complete-MayaQaTaskClosure {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[switch]$DryRun)
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if($workflow.qaCompletionStatus -cne 'completed' -or $workflow.qaVerificationStatus -cne 'verified'){throw 'Verified completed QA workflow is required before task closure.'}
    $receipt=Get-MayaQaReceiptStatus -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -QaWorkflowId $QaWorkflowId
    if($receipt.ReceiptStatus -cne 'Valid' -or !$receipt.ReceiptHashValid -or @($receipt.ReferencedHashes|Where-Object {!$_.Valid}).Count){throw 'Valid immutable QA receipt evidence is required before task closure.'}
    if($task.status -cne 'in-progress' -or $task.workflowStage -cne 'approval'){throw 'Parent task is not in the verified QA closure state.'}
    $approved=@($task.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved' -and $_.requestId -ceq $workflow.qaApprovalId})
    if($approved.Count -ne 1){throw 'Exact approved QA request is required before task closure.'}
    if($DryRun){return [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;ReceiptSha256=$receipt.ReceiptSha256;WouldComplete=$true;SideEffectsPerformed=$false}}
    $expectedRevision=[long]$task.revision
    $closed=Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$t=Find-RepatoTask $data $TaskId;if([long]$t.revision -ne $expectedRevision -or $t.status -cne 'in-progress' -or $t.workflowStage -cne 'approval'){throw 'QA task closure compare-and-swap failed.'};$w=@($t.deploymentWorkflows|Where-Object {$_.workflowId -ceq $WorkflowId -and $_.taskId -ceq $TaskId});$a=@($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved' -and $_.requestId -ceq $workflow.qaApprovalId -and $_.runId -ceq $workflow.qaEvidence.NativeRunId});if($w.Count -ne 1 -or $w[0].qaCompletionStatus -cne 'completed' -or $w[0].qaVerificationStatus -cne 'verified' -or $w[0].qaApprovalId -cne $workflow.qaApprovalId -or $a.Count -ne 1){throw 'Verified QA task closure evidence changed during compare-and-swap.'};$t.status='completed';$t.workflowStage='completed';$t.finishedUtc=Get-RepatoUtc;Add-RepatoHistory $t 'completed' 'Maya' 'verified QA receipt and approved run closed the task';$t}
    [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;ReceiptSha256=$receipt.ReceiptSha256;Status=$closed.status;WorkflowStage=$closed.workflowStage;SideEffectsPerformed=$true}
}
function New-MayaQaReceipt {
    param(
        [Parameter(Mandatory)]
        [string]$StoreRoot,

        [Parameter(Mandatory)]
        [string]$TaskId,

        [Parameter(Mandatory)]
        [string]$WorkflowId,

        [string]$ReportRoot,

        [switch]$DryRun
    )

    $w = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId

    if($DryRun){
        return [pscustomobject]@{
            WorkflowId = $WorkflowId
            SideEffectsPerformed = $false
        }
    }

    $qaId = if(
        $w.PSObject.Properties.Name -contains 'qaWorkflowId'
    ){
        $w.qaWorkflowId
    }
    else {
        $null
    }

    if(!$qaId){
        throw 'QA workflow identity is missing.'
    }

    $def = Get-MayaQaWorkflowDefinition $qaId

    if(
        $w.PSObject.Properties.Name -notcontains 'qaCompletionStatus' -or
        $w.qaCompletionStatus -ne 'completed' -or
        $w.qaVerificationStatus -ne 'verified'
    ){
        throw 'QA workflow is incomplete.'
    }

    if(
        !$w.qaEvidence -or
        $w.qaEvidence.Status -ne 'Passed' -or
        $w.qaEvidence.RollbackStatus -ne 'RolledBack'
    ){
        throw 'QA evidence is incomplete.'
    }

    $build = $w.qaBuildEvidence

    $tara = if(
        $w.PSObject.Properties.Name -contains 'qaTaraExecutionEvidence'
    ){
        $w.qaTaraExecutionEvidence
    }
    else {
        [pscustomobject]@{
            QaRunnerManifestPath = $null
            QaRunnerManifestSha256 = $null
        }
    }

    $artifactPath = $build.ArtifactPath
    $artifactHash = $build.ArtifactSha256
    $artifactManifestPath = $build.ManifestPath
    $artifactManifestHash = $build.ManifestSha256
    $runnerPath = $tara.QaRunnerManifestPath
    $runnerHash = $tara.QaRunnerManifestSha256

    # Verify immutable evidence before reading values from the native report.
    $immutableEvidencePairs = @(
        ,@($artifactPath, $artifactHash)
        ,@($artifactManifestPath, $artifactManifestHash)
        ,@($w.qaReportPath, $w.qaReportSha256)
    )

    if($runnerPath){
        $immutableEvidencePairs += ,@($runnerPath, $runnerHash)
    }

    foreach($pair in $immutableEvidencePairs){
        if(!(Test-Path -LiteralPath $pair[0] -PathType Leaf)){
            throw "Evidence file is missing: $($pair[0])"
        }

        $actualHash = (
            Get-FileHash `
                -LiteralPath $pair[0] `
                -Algorithm SHA256
        ).Hash

        if($actualHash -ine $pair[1]){
            throw "Evidence hash mismatch: $($pair[0])"
        }
    }

    $nativeReport = Get-Content `
        -LiteralPath $w.qaReportPath `
        -Raw |
        ConvertFrom-Json

    if(
        $nativeReport.Status -cne 'Passed' -or
        $nativeReport.RollbackStatus -cne 'RolledBack' -or
        $nativeReport.FixtureSha256 -ine $w.qaFixtureSha256
    ){
        throw 'Native report status, rollback, or fixture identity mismatch.'
    }

    $runtimeModelHash = if(
        $nativeReport.PSObject.Properties.Name -contains 'RuntimeModelSha256' -and
        $nativeReport.RuntimeModelSha256 -match '^[A-Fa-f0-9]{64}$'
    ){
        $nativeReport.RuntimeModelSha256
    }
    else {
        # Compatibility for older QA reports whose runtime model remained
        # byte-identical to the source fixture.
        $w.qaFixtureSha256
    }

    if(!(Test-Path -LiteralPath $w.qaModelPath -PathType Leaf)){
        throw "Evidence file is missing: $($w.qaModelPath)"
    }

    $actualRuntimeModelHash = (
        Get-FileHash `
            -LiteralPath $w.qaModelPath `
            -Algorithm SHA256
    ).Hash

    if($actualRuntimeModelHash -ine $runtimeModelHash){
        throw "Evidence hash mismatch: $($w.qaModelPath)"
    }

    if([string]::IsNullOrWhiteSpace($ReportRoot)){
        $ReportRoot = Join-Path (Get-MayaQaRuntimeRoot) 'Reports'
    }
    else {
        $ReportRoot = [IO.Path]::GetFullPath($ReportRoot)
    }

    if(!(Test-Path -LiteralPath $ReportRoot)){
        New-Item `
            -ItemType Directory `
            -Path $ReportRoot `
            -Force |
            Out-Null
    }

    $receiptPath = Join-Path `
        $ReportRoot `
        ('maya-qa-receipt-' + $w.qaRunId + '.json')

    $base = [ordered]@{
        SchemaVersion = '1'
        TaskId = $TaskId
        DeploymentWorkflowId = $WorkflowId
        QaWorkflowId = $qaId

        QaApprovalId = if(
            $w.PSObject.Properties.Name -contains 'qaApprovalId'
        ){
            $w.qaApprovalId
        }
        else {
            $null
        }

        QaApprovalStatus = if(
            $w.PSObject.Properties.Name -contains 'qaApprovalStatus'
        ){
            $w.qaApprovalStatus
        }
        else {
            $null
        }

        CoordinatorRunId = $w.qaEvidence.CoordinatorRunId
        NativeRunId = $w.qaEvidence.NativeRunId

        ArtifactPath = $artifactPath
        ArtifactSha256 = $artifactHash
        ArtifactManifestPath = $artifactManifestPath
        ArtifactManifestSha256 = $artifactManifestHash

        QaRunnerManifestPath = $runnerPath
        QaRunnerManifestSha256 = $runnerHash

        ManifestPath = $build.ManifestPath
        ManifestSha256 = $build.ManifestSha256

        QaModelPath = $w.qaModelPath
        FixtureSha256 = $w.qaFixtureSha256
        RuntimeModelSha256 = $runtimeModelHash

        QaReportPath = $w.qaReportPath
        QaReportSha256 = $w.qaReportSha256

        ReportStatus = $w.qaEvidence.Status
        AssertionCount = $w.qaEvidence.Assertions
        RollbackStatus = $w.qaEvidence.RollbackStatus
        QaVerificationStatus = $w.qaVerificationStatus
        QaCompletionStatus = $w.qaCompletionStatus
        CompletionTimestamp = $w.qaCompletedUtc

        RequestIntent = if(
            $w.PSObject.Properties.Name -contains 'qaRequestIntent'
        ){
            $w.qaRequestIntent
        }
        else {
            $null
        }

        PromptDetected = $w.qaEvidence.PromptDetected
        PromptAction = $w.qaEvidence.PromptAction
        ApprovedManifest = $w.qaEvidence.ApprovedManifest
        PromptFree = $w.qaEvidence.PromptFree
    }

    $json = $base | ConvertTo-Json -Compress -Depth 12
    $hasher = [Security.Cryptography.SHA256]::Create()

    try {
        $final = (
            [BitConverter]::ToString(
                $hasher.ComputeHash(
                    [Text.Encoding]::UTF8.GetBytes($json)
                )
            )
        ).Replace('-', '')
    }
    finally {
        $hasher.Dispose()
    }

    $receipt = [ordered]@{}

    $base.GetEnumerator() |
        ForEach-Object {
            $receipt[$_.Key] = $_.Value
        }

    $receipt.FinalReceiptSha256 = $final
    $serialized = $receipt | ConvertTo-Json -Compress -Depth 12

    if(Test-Path -LiteralPath $receiptPath){
        $existing = (
            Get-Content `
                -LiteralPath $receiptPath `
                -Raw
        ).Trim()

        if($existing -ne $serialized){
            throw 'Receipt already exists with different evidence.'
        }

        return [pscustomobject]@{
            ReceiptPath = $receiptPath
            FinalReceiptSha256 = $final
            Duplicate = $true
            SideEffectsPerformed = $false
        }
    }

    $serialized |
        Set-Content `
            -LiteralPath $receiptPath `
            -Encoding UTF8

    $data = Read-RepatoTaskStore $StoreRoot
    $task = Find-RepatoTask $data $TaskId

    $mutation = @(
        Invoke-RepatoWorkflowMutation `
            $StoreRoot `
            $TaskId `
            $WorkflowId `
            $w.workflowRevision `
            $task.revision {

            param($current)

            $current |
                Add-Member `
                    -NotePropertyName qaReceiptPath `
                    -NotePropertyValue $receiptPath `
                    -Force

            $current |
                Add-Member `
                    -NotePropertyName qaReceiptSha256 `
                    -NotePropertyValue $final `
                    -Force

            return $current
        }
    )[-1]

    [pscustomobject]@{
        ReceiptPath = $receiptPath
        FinalReceiptSha256 = $final
        Duplicate = $false
        WorkflowRevision = $mutation.Workflow.workflowRevision
        TaskRevision = $mutation.TaskRevision
        SideEffectsPerformed = $true
    }
}
function Get-MayaQaBuildEvidenceStatus {
    param([object]$Workflow)
    if ($Workflow.PSObject.Properties.Name -notcontains 'qaBuildEvidence' -or $Workflow.PSObject.Properties.Name -notcontains 'qaBuildStatus' -or $Workflow.qaBuildStatus -ne 'succeeded') { throw 'Neil build evidence is missing or failed.' }
    $e = $Workflow.qaBuildEvidence
    $checks = @()
    foreach ($pair in @(@('Artifact',$e.ArtifactPath,$e.ArtifactSha256),@('Manifest',$e.ManifestPath,$e.ManifestSha256))) {
        $valid = Test-Path -LiteralPath $pair[1] -PathType Leaf
        if ($valid) { $valid = (Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash -ieq $pair[2] }
        $checks += [pscustomobject]@{Name=$pair[0];Path=$pair[1];ExpectedSha256=$pair[2];Valid=$valid}
        if (-not $valid) { throw "Neil build evidence hash mismatch: $($pair[0])" }
    }
    [pscustomobject]@{BuildStatus=$Workflow.qaBuildStatus;ArtifactPath=$e.ArtifactPath;ArtifactSha256=$e.ArtifactSha256;ManifestPath=$e.ManifestPath;ManifestSha256=$e.ManifestSha256;SourceBranch=$e.SourceBranch;CommitId=$e.CommitId;HashVerification=$checks}
}function Get-MayaQaReceiptStatus { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[switch]$DryRun)
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;if($DryRun){return [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;SideEffectsPerformed=$false}}
    if($w.PSObject.Properties.Name -notcontains 'qaReceiptPath' -or [string]::IsNullOrWhiteSpace([string]$w.qaReceiptPath)){throw 'QA receipt is missing.'}
    $receiptPath=[IO.Path]::GetFullPath($w.qaReceiptPath);if(!(Test-Path -LiteralPath $receiptPath -PathType Leaf)){throw 'QA receipt is missing.'};$receipt=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
    if($receipt.TaskId -cne $TaskId -or $receipt.DeploymentWorkflowId -cne $WorkflowId -or $receipt.QaWorkflowId -cne $QaWorkflowId){throw 'QA receipt identity mismatch.'}
    $stored=$receipt.FinalReceiptSha256;$copy=[ordered]@{};$receipt.PSObject.Properties|Where-Object Name -ne 'FinalReceiptSha256'|ForEach-Object{$copy[$_.Name]=$_.Value};$json=$copy|ConvertTo-Json -Compress -Depth 12;$h=[Security.Cryptography.SHA256]::Create();try{$computed=([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}finally{$h.Dispose()};if($computed -ine $stored -or ($w.PSObject.Properties.Name -contains 'qaReceiptSha256' -and $w.qaReceiptSha256 -ine $stored)){throw 'QA receipt hash mismatch.'}
    $modelExpectedHash=if($receipt.PSObject.Properties.Name -contains 'RuntimeModelSha256' -and $receipt.RuntimeModelSha256 -match '^[A-Fa-f0-9]{64}$'){$receipt.RuntimeModelSha256}else{$receipt.FixtureSha256}
    $checks=@();foreach($pair in @(@('Artifact',$receipt.ArtifactPath,$receipt.ArtifactSha256),@('Manifest',$receipt.ManifestPath,$receipt.ManifestSha256),@('Model',$receipt.QaModelPath,$modelExpectedHash),@('Report',$receipt.QaReportPath,$receipt.QaReportSha256))){$ok=Test-Path -LiteralPath $pair[1] -PathType Leaf;if($ok){$ok=(Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash -ieq $pair[2]};$checks+=[pscustomobject]@{Name=$pair[0];Path=$pair[1];ExpectedSha256=$pair[2];Valid=$ok};if(!$ok){throw "$($pair[0]) hash verification failed."}}
    [pscustomobject]@{ReceiptStatus='Valid';TaskId=$receipt.TaskId;WorkflowId=$receipt.DeploymentWorkflowId;QaWorkflowId=$receipt.QaWorkflowId;RequestIntent=$receipt.RequestIntent;CoordinatorRunId=$receipt.CoordinatorRunId;NativeRunId=$receipt.NativeRunId;ReportStatus=$receipt.ReportStatus;RollbackStatus=$receipt.RollbackStatus;QaVerificationStatus=$receipt.QaVerificationStatus;QaCompletionStatus=$receipt.QaCompletionStatus;CompletionTimestamp=$receipt.CompletionTimestamp;ReceiptSha256=$stored;ReceiptHashValid=$true;ReferencedHashes=$checks;SideEffectsPerformed=$false}
}
function Get-MayaQaDashboard { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[switch]$DryRun)
    $def=Get-MayaQaWorkflowDefinition $QaWorkflowId;$catalog=Get-MayaQaWorkflowCatalog
    if($DryRun){return [pscustomobject]@{Catalog=$catalog;SelectedWorkflowId=$QaWorkflowId;CapabilityFlags=$def.Capabilities;DeploymentWorkflowStatus='unread';QaApprovalStatus='unread';QaPlanStatus='unread';ReportVerificationStatus='unread';QaCompletionStatus='unread';ReceiptStatus='unread';SideEffectsPerformed=$false}}
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;$plan=Get-DeployWorkflowPlan $StoreRoot $TaskId $WorkflowId;$plan.artifactPath=$w.qaBuildEvidence.ArtifactPath;$plan.artifactSha256=$w.qaBuildEvidence.ArtifactSha256;$plan.manifestPath=$w.qaBuildEvidence.ManifestPath;$plan.manifestSha256=$w.qaBuildEvidence.ManifestSha256
    $hashes=@();foreach($pair in @(@('Artifact',$plan.artifactPath,$plan.artifactSha256),@('Manifest',$plan.manifestPath,$plan.manifestSha256))){$ok=Test-Path -LiteralPath $pair[1] -PathType Leaf;if($ok){$ok=(Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash -ieq $pair[2]};$hashes+=[pscustomobject]@{Name=$pair[0];Path=$pair[1];ExpectedSha256=$pair[2];Valid=$ok};if(!$ok){throw "$($pair[0]) hash verification failed."}}
    $taraEvidence=if($w.PSObject.Properties.Name -contains 'qaTaraExecutionEvidence'){$w.qaTaraExecutionEvidence}else{[pscustomobject]@{QaRunnerManifestPath=$null;QaRunnerManifestSha256=$null}};$runnerOk=$true;if($taraEvidence.QaRunnerManifestPath){$runnerOk=Test-Path -LiteralPath $taraEvidence.QaRunnerManifestPath -PathType Leaf;if($runnerOk){$runnerOk=(Get-FileHash -LiteralPath $taraEvidence.QaRunnerManifestPath -Algorithm SHA256).Hash -ieq $taraEvidence.QaRunnerManifestSha256}};$hashes+=[pscustomobject]@{Name='QaRunnerManifest';Path=$taraEvidence.QaRunnerManifestPath;ExpectedSha256=$taraEvidence.QaRunnerManifestSha256;Valid=$runnerOk};if(!$runnerOk -and $w.qaCompletionStatus -eq 'completed'){throw 'QA runner manifest hash verification failed.'}
    $qaFields=@('qaModelPath','qaFixtureSha256','qaReportPath','qaReportSha256');foreach($n in $qaFields){if($w.PSObject.Properties.Name -notcontains $n){$hashes+=[pscustomobject]@{Name=$n;Valid=$false};continue}}
    if($w.PSObject.Properties.Name -contains 'qaModelPath'){$dashboardModelHash=$w.qaFixtureSha256;if(Test-Path -LiteralPath $w.qaReportPath -PathType Leaf){$dashboardReport=Get-Content -LiteralPath $w.qaReportPath -Raw|ConvertFrom-Json;if($dashboardReport.PSObject.Properties.Name -contains 'RuntimeModelSha256' -and $dashboardReport.RuntimeModelSha256 -match '^[A-Fa-f0-9]{64}$'){$dashboardModelHash=$dashboardReport.RuntimeModelSha256}};$qaPairs=@(@('Model',$w.qaModelPath,$dashboardModelHash),@('Report',$w.qaReportPath,$w.qaReportSha256));foreach($pair in $qaPairs){$ok=Test-Path -LiteralPath $pair[1] -PathType Leaf;if($ok){$ok=(Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash -ieq $pair[2]};$hashes+=[pscustomobject]@{Name=$pair[0];Path=$pair[1];ExpectedSha256=$pair[2];Valid=$ok};if(!$ok -and $w.qaCompletionStatus -eq 'completed'){throw "$($pair[0]) hash verification failed."}}}
    $receiptStatus='Missing';if($w.PSObject.Properties.Name -contains 'qaReceiptPath' -and $w.qaReceiptPath){$receipt=Get-MayaQaReceiptStatus $StoreRoot $TaskId $WorkflowId $QaWorkflowId;$receiptStatus='Valid'}elseif($w.PSObject.Properties.Name -contains 'qaCompletionStatus' -and $w.qaCompletionStatus -eq 'completed'){throw 'Completed QA workflow is missing its receipt.'}
    [pscustomobject]@{Catalog=$catalog;SelectedWorkflowId=$QaWorkflowId;CapabilityFlags=$def.Capabilities;RequestIntent=$(if($w.PSObject.Properties.Name -contains 'qaRequestIntent'){$w.qaRequestIntent}else{$null});DeploymentWorkflowStatus=$w.status;QaApprovalStatus=$(if($w.PSObject.Properties.Name -contains 'qaApprovalStatus'){$w.qaApprovalStatus}else{$null});QaPlanStatus=$w.stage;ReportVerificationStatus=$(if($w.PSObject.Properties.Name -contains 'qaVerificationStatus'){$w.qaVerificationStatus}else{$null});QaCompletionStatus=$(if($w.PSObject.Properties.Name -contains 'qaCompletionStatus'){$w.qaCompletionStatus}else{$null});ReceiptStatus=$receiptStatus;CoordinatorRunId=$(if($w.PSObject.Properties.Name -contains 'qaEvidence'){$w.qaEvidence.CoordinatorRunId}else{$null});NativeRunId=$(if($w.PSObject.Properties.Name -contains 'qaEvidence'){$w.qaEvidence.NativeRunId}else{$null});HashVerification=$hashes;CompletionTimestamp=$(if($w.PSObject.Properties.Name -contains 'qaCompletedUtc'){$w.qaCompletedUtc}else{$null});SideEffectsPerformed=$false}
}
function Invoke-MayaQaOverview { param([Parameter(Mandatory)][ValidateSet('qa-catalog-dry-run','qa-status','qa-receipt-status','qa-dashboard')][string]$Route,[string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$QaWorkflowId,[switch]$DryRun)
    $result=switch($Route){'qa-catalog-dry-run'{Get-MayaQaCatalogDryRun $WorkflowId};'qa-status'{Get-MayaQaWorkflowStatus $StoreRoot $TaskId $WorkflowId};'qa-receipt-status'{Get-MayaQaReceiptStatus $StoreRoot $TaskId $WorkflowId $QaWorkflowId -DryRun:$DryRun};'qa-dashboard'{Get-MayaQaDashboard $StoreRoot $TaskId $WorkflowId $QaWorkflowId -DryRun:$DryRun}}
    [pscustomobject]@{Operation=$Route;TimestampUtc=(Get-Date).ToUniversalTime().ToString('O');WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;ResultStatus='ok';SideEffectsPerformed=$false;Result=$result}
}
Export-ModuleMember -Function Prepare-MayaQaCanonicalLaunchPhase,Start-MayaQaCanonicalProcessPhase,Accept-MayaQaCanonicalEvidencePhase,Verify-MayaQaCanonicalRollbackPhase,Verify-MayaQaCanonicalExecutionPhase
Export-ModuleMember -Function Wait-MayaQaCanonicalResultPhase,Complete-MayaQaCanonicalExecutionPhase
Export-ModuleMember -Function Invoke-MayaQaTaraExecute,Resolve-MayaQaRequestWorkflow,Resolve-MayaQaWorkflowId,Resolve-MayaQaTaskStoreIdentity,New-MayaQaExecutionRecord,Claim-MayaQaExecutionRecord,Prepare-MayaQaCanonicalNativeLaunch,Invoke-MayaQaCanonicalNativeCore,Get-MayaQaAttemptDurationMinutes,Recover-MayaQaExpiredExecutionRecord,Recover-MayaQaTerminalLaunchFailure,Recover-MayaQaAbandonedNativeExecution,Repair-MayaQaPreparedExecutionLifecycle,Get-MayaQaCanonicalNativeResult,Resume-MayaQaCanonicalExecution,Get-MayaQaNativeTestId,Invoke-MayaQaRequest,New-MayaQaPersistentPreBuildRequest,Invoke-MayaQaCanonicalTransaction,Invoke-MayaQaSingleCanonicalAttempt,Get-MayaQaWorkflowDefinition,Get-MayaQaWorkflowCatalog,Get-MayaQaCatalogDryRun,Get-MayaQaWorkflowStatus,Invoke-MayaQaIntake,New-MayaQaBuildRequest,New-MayaQaCandidateReplacementBuildRequest,Invoke-MayaQaBuildExecute,New-MayaQaHandoff,Submit-MayaQaReport,Get-MayaQaDashboard,Invoke-MayaQaOverview,New-MayaQaBootstrap,New-MayaQaRun,Register-MayaQaReport,Complete-MayaQaWorkflow,New-MayaQaReceipt,Get-MayaQaReceiptStatus
Export-ModuleMember -Function Complete-MayaQaTaskClosure
Export-ModuleMember -Function Recover-MayaQaInvalidNativeClaim
Export-ModuleMember -Function Recover-MayaQaCorrelatedNativeFailure
Export-ModuleMember -Function Request-MayaQaRecoveredLaunchFailureApproval
Export-ModuleMember -Function Repair-MayaQaRecoveredLaunchApprovalRevision
Export-ModuleMember -Function Repair-MayaQaRecoveredFixturePreparation,Set-MayaQaRecoveredFixtureReadyState,Read-MayaQaFixturePreparationRecord
Export-ModuleMember -Function Invoke-MayaQaFixtureBlockedRecovery
Export-ModuleMember -Function Prepare-MayaQaAfterExpiredFailureRecovery,Archive-MayaQaRecoveredAttemptForCandidateReplacement
Export-ModuleMember -Function Complete-MayaQaTerminalLaunchFailureCleanup
Export-ModuleMember -Function Complete-MayaQaRunnerStartupFailureReconciliation
Export-ModuleMember -Function Complete-MayaQaPreAttemptOrphanRuntimeCleanup
Export-ModuleMember -Function Complete-MayaQaPreparedAttemptCleanup
Export-ModuleMember -Function Archive-MayaQaUnlaunchedPreparedExecution
Export-ModuleMember -Function Invoke-MayaQaLaunchAgentHealth,Invoke-MayaQaLaunchAgentPreflightReadonly,Invoke-MayaQaLaunchAgentFrozenCandidateStaging,Invoke-MayaQaLaunchAgentDeploymentValidation
Export-ModuleMember -Function New-MayaQaDeploymentValidationOperation,Continue-MayaQaDeploymentValidation,Abandon-MayaQaUnresolvedDeploymentValidation,Fail-MayaQaBoundDeploymentValidationWithoutResponse
Export-ModuleMember -Function Invoke-MayaQaIndependentDeploymentValidationRecovery
Export-ModuleMember -Function Set-MayaQaDeploymentValidationOutcomeUnknown
Export-ModuleMember -Function New-MayaQaPersistedCandidateEvidence
Export-ModuleMember -Function Invoke-MayaQaCanonicalFrozenCandidateStagingValidation
Export-ModuleMember -Function Normalize-MayaQaDeploymentValidationResponse
Export-ModuleMember -Function Test-MayaQaFrozenCandidate,New-MayaQaCanonicalCandidate,Invoke-MayaQaFrozenCandidateEvidence,Get-MayaQaTrustedBuildSourceCommit,Resolve-MayaQaAuthenticatedBuildSource
Export-ModuleMember -Function New-MayaQaCanonicalPreparation
Export-ModuleMember -Function Request-MayaQaCanonicalApprovalRefresh,Request-MayaQaCanonicalExecutionApproval,Request-MayaQaValidatedCandidateApproval
Export-ModuleMember -Function Request-MayaQaRecoveredNativeFailureApproval
Export-ModuleMember -Function Request-MayaQaRecoveredExpiredAttemptApproval
Export-ModuleMember -Function Repair-MayaQaExpiredPreparedApprovalHistory
Export-ModuleMember -Function Repair-MayaQaCanonicalRunIdentity
Export-ModuleMember -Function Recover-MayaQaReconciledDuplicateFloorPlanFailureForCandidateReplacement
Export-ModuleMember -Function Reset-MayaQaReconciledDuplicateFloorPlanWorkflowPlan
Export-ModuleMember -Function Remove-MayaQaExpiredOrphanedPreparation
Export-ModuleMember -Function Complete-MayaQaApprovedRunAuthorization
Export-ModuleMember -Function Invoke-MayaQaRevitGracefulShutdown

function Accept-MayaQaLegacyManifestAttestation {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$ClaimId,[Parameter(Mandatory)][string]$EvidencePath,[Parameter(Mandatory)][string]$EvidenceSha256,[scriptblock]$StoreMutationBoundary)
    $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$r=$task.mayaTaraExecution
    if(!$r -or $r.Stage -cne 'executing' -or $r.ExecutionStatus -cne 'Executing' -or $r.ClaimOwner -cne 'Tara' -or $r.ClaimId -cne $ClaimId){throw 'Legacy attestation execution is not eligible.'}
    if($r.SideEffectsPerformed -or $r.VerificationStatus -ceq 'Verified' -or $r.CompletionStatus -ceq 'Completed' -or $r.VerifiedUtc -or $r.CompletedUtc){throw 'Legacy attestation execution is terminal or has side effects.'}
    $epProp=$r.PSObject.Properties['EvidencePath'];$ehProp=$r.PSObject.Properties['EvidenceSha256'];if(($epProp -and $epProp.Value) -or ($ehProp -and $ehProp.Value)){throw 'Legacy attestation evidence already exists.'}
    if(!(Test-Path -LiteralPath $EvidencePath -PathType Leaf)){throw 'Legacy attestation evidence is missing.'};if((Get-FileHash -LiteralPath $EvidencePath -Algorithm SHA256).Hash -ine $EvidenceSha256){throw 'Legacy attestation evidence hash mismatch.'}
    try{$e=Get-Content -LiteralPath $EvidencePath -Raw|ConvertFrom-Json}catch{throw 'Legacy attestation evidence is malformed.'}
    foreach($n in @('EvidenceVersion','ValidationStatus','TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','CanonicalRunId','ClaimId','NativeRunId','DeployedRunnerManifestPath','DeployedRunnerManifestSha256','IsolationPolicySha256','ValidatedUtc')){if($e.PSObject.Properties.Name -notcontains $n){throw "Legacy attestation evidence is missing: $n"}}
    if([int]$e.EvidenceVersion -ne 1 -or [string]$e.ValidationStatus -cne 'Passed'){throw 'Legacy attestation evidence did not pass validation.'}
    foreach($n in @('TaskId','WorkflowId','QaWorkflowId','TestId','HandoffId','AttemptId','ClaimId')){if([string]$e.$n -cne [string]$r.$n){throw "Legacy attestation identity mismatch: $n"}}
    if([string]$e.CanonicalRunId -cne [string]$r.RunId -or [string]$e.DeployedRunnerManifestPath -cne [string]$r.RunnerManifestPath -or [string]$e.DeployedRunnerManifestSha256 -ine [string]$r.RunnerManifestSha256 -or [string]$e.IsolationPolicySha256 -ine [string]$r.IsolationPolicySha256){throw 'Legacy attestation manifest identity or hash mismatch.'}
    try{$null=[DateTimeOffset]::Parse([string]$e.ValidatedUtc)}catch{throw 'Legacy attestation timestamp is invalid.'}
    $resultPath=$r.RequestPath+'.result.json';if(!(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'Legacy attestation native result is missing.'};try{$receipt=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json}catch{throw 'Legacy attestation native result is malformed.'}
    if([string]$receipt.RequestId -cne [string]$r.RunId -or [string]$receipt.Status -cne 'Failed' -or [string]$receipt.RunId -cne [string]$e.NativeRunId -or [string]::IsNullOrWhiteSpace([string]$receipt.ReportPath)){throw 'Legacy attestation native result correlation failed.'}
    if(!(Test-Path -LiteralPath $receipt.ReportPath -PathType Leaf)){throw 'Legacy attestation native report is missing.'};try{$report=Get-Content -LiteralPath $receipt.ReportPath -Raw|ConvertFrom-Json}catch{throw 'Legacy attestation native report is malformed.'}
    if([string]$report.RunId -cne [string]$e.NativeRunId -or [string]$report.TestId -cne [string]$r.TestId -or [string]$report.Status -cne 'Failed'){throw 'Legacy attestation native report correlation failed.'}
    $oldAttempt=[string]$r.AttemptId;$oldRun=[string]$r.RunId;$oldClaim=[string]$r.ClaimId
    $cas={param($current,$preview)$t=Find-RepatoTask $current $TaskId;$x=$t.mayaTaraExecution;$xEp=$x.PSObject.Properties['EvidencePath'];$xEh=$x.PSObject.Properties['EvidenceSha256'];if($x.Stage -cne 'executing' -or $x.ExecutionStatus -cne 'Executing' -or $x.AttemptId -cne $oldAttempt -or $x.RunId -cne $oldRun -or $x.ClaimId -cne $oldClaim -or ($xEp -and $xEp.Value) -or ($xEh -and $xEh.Value)){throw 'Legacy attestation compare-and-swap failed.'};$x|Add-Member NoteProperty EvidencePath $EvidencePath -Force;$x|Add-Member NoteProperty EvidenceSha256 $EvidenceSha256 -Force;$x}
    if($StoreMutationBoundary){& $StoreMutationBoundary $StoreRoot $cas}else{Invoke-RepatoStoreMutation $StoreRoot $cas}
    [pscustomobject]@{TaskId=$TaskId;ClaimId=$ClaimId;EvidencePath=$EvidencePath;EvidenceSha256=$EvidenceSha256;Accepted=$true}
}
Export-ModuleMember -Function Accept-MayaQaLegacyManifestAttestation
Export-ModuleMember -Function Accept-MayaQaPreparedManifestAttestation
Export-ModuleMember -Function Reconcile-MayaQaDuplicatePendingApprovals
Export-ModuleMember -Function Repair-MayaQaRecoveredFixturePreparation
