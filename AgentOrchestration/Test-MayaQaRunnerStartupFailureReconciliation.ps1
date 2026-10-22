$ErrorActionPreference='Stop'
$here=$PSScriptRoot;$sourceStore=Join-Path (Split-Path $here -Parent) 'QA\MayaRuns';$modulePath=Join-Path $here 'Repato.MayaQaWorkflow.psm1'
Import-Module (Join-Path $here 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module $modulePath -Force -WarningAction SilentlyContinue
$module=Get-Module Repato.MayaQaWorkflow
function New-Context {
    $root=Join-Path ([IO.Path]::GetTempPath()) ('maya-runner-startup-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
    $data=Read-RepatoTaskStore $sourceStore;$original=Find-RepatoTask $data 'task-41cfec12ef3e406990d36c9997cf6591';$task=$original|ConvertTo-Json -Depth 30|ConvertFrom-Json
    $task.taskId='synthetic-runner-startup-task';$task.revision=39;$task.status='blocked';$task.workflowStage='qa';$task.history=@($task.history|Where-Object{$_.event -cne 'maya-tara-runner-startup-failed'})
    $attempt='3adc98af191a46b6bce2bc985137e2c7';$run='96179f6678ab4723a639892f89b7be95';$claim='fe9e5ac63e454cf59c5f89c9d08219e5';$reqId='a63f6e96e52e4c6fb34a1f46778dec3f';$processId=44920;$started=[DateTimeOffset]::Parse('2026-10-10T19:22:34.843Z');$seen=$started.AddMilliseconds(-89)
    $requestPath=Join-Path $root 'maya-tara-96179f6678ab4723a639892f89b7be95.request.json';$journalPath=Join-Path $root 'journal.0103.txt';$ledgerPath=Join-Path $root 'replay.json'
    $request=[ordered]@{schemaVersion=2;operation='launch-revit-qa';requestId=$reqId;taskId=$task.taskId;workflowId=$task.mayaTaraExecution.WorkflowId;qaWorkflowId=$task.mayaTaraExecution.QaWorkflowId;testId=$task.mayaTaraExecution.TestId;attemptId=$attempt;runId=$run;claimId=$claim;requestPath=$requestPath;requestSha256=('0'*64);modelPath='C:\synthetic\model.rvt';modelSha256=('1'*64);manifestPath='C:\synthetic\runner.addin';manifestSha256=('2'*64);expiresUtc='2026-10-10T19:49:05.3443051+00:00'}
    $request.requestSha256=& $module {param($r) Get-MayaQaCanonicalRequestSha256 $r} $request
    [IO.File]::WriteAllText($requestPath,($request|ConvertTo-Json -Compress -Depth 10),[Text.UTF8Encoding]::new($false))
    $payload='4D84F1DD93037A00013270E03C680DB82C4BC6F960F673B8657B36A86161C06E'
    $ledger=@(@{RequestId=$reqId;RunId=$run;PayloadHash=$payload;SeenUtc=$seen.ToString('O')})|ConvertTo-Json -Compress
    [IO.File]::WriteAllText($ledgerPath,$ledger,[Text.UTF8Encoding]::new($false))
    $journal='API_ERROR { Starting External Application: Repato Create Plan Views QA; Repato.Revit.TestRunner.CreatePlanViewsQaApplication'+[Environment]::NewLine+'TaskDialog "Revit cannot run the external application "Repato Create Plan Views QA"'+[Environment]::NewLine+'TaskDialog_Security_Unsigned_File_Loading'+[Environment]::NewLine+'AddInCodeSigningStatus: Unsigned'+[Environment]::NewLine+'AddInLoadFailureMessage: NoError'
    [IO.File]::WriteAllText($journalPath,$journal,[Text.UTF8Encoding]::new($false))
    $x=$task.mayaTaraExecution;$x.TaskId=$task.taskId;$x.AttemptId=$attempt;$x.RunId=$run;$x.ClaimId=$claim;$x.ClaimOwner='Tara';$x.ClaimStatus='claimed';$x.NativeRequestId=$reqId;$x.RequestPath=$requestPath;$x.Stage='launch-failed';$x.ExecutionStatus='LaunchFailed';$x.FailureCode='native-process-start-failed';$x.FailureDetails='IncludeUserName required elevation';$x.SideEffectsPerformed=$false
    foreach($n in 'NativeProcessId','LaunchedUtc','ExecutingUtc','ResultPath','ReportPath','ReceiptPath','EvidencePath','RunnerStartupEvidence'){if($x.PSObject.Properties.Name -contains $n){$x.$n=$null}}
    $task.mayaTaraAttempt.TaskId=$task.taskId;$task.mayaTaraAttempt.AttemptId=$attempt;$task.mayaTaraAttempt.RunId=$run;$task.mayaTaraAttempt.Stage='prepared';$task.mayaTaraAttempt.Success=$false
    $data.tasks=@($task);Write-RepatoJsonAtomic (Join-Path $root 'tasks.json') $data;[IO.File]::WriteAllText((Join-Path $root 'status.json'),'{}');[IO.File]::WriteAllText((Join-Path $root 'store.lock'),'')
    [pscustomobject]@{Root=$root;TaskId=$task.taskId;AttemptId=$attempt;RunId=$run;ClaimId=$claim;RequestId=$reqId;ProcessId=$processId;StartedUtc=$started.ToString('O');RequestPath=$requestPath;RequestSha256=(Get-FileHash $requestPath -Algorithm SHA256).Hash;JournalPath=$journalPath;JournalSha256=(Get-FileHash $journalPath -Algorithm SHA256).Hash;LedgerPath=$ledgerPath;PayloadHash=$payload;Prompt='User confirmed selecting Load Once for the expected Repato QA add-in.'}
}
function Invoke-Recovery($c,[scriptblock]$inspector,[switch]$dry,[string]$requestId,[string]$journalHash,[switch]$ack){
    Complete-MayaQaRunnerStartupFailureReconciliation -StoreRoot $c.Root -TaskId $c.TaskId -AttemptId $c.AttemptId -RunId $c.RunId -ClaimId $c.ClaimId -NativeRequestId $(if($requestId){$requestId}else{$c.RequestId}) -ProcessId $c.ProcessId -ProcessStartedUtc $c.StartedUtc -RequestPath $c.RequestPath -RequestSha256 $c.RequestSha256 -JournalPath $c.JournalPath -JournalSha256 $(if($journalHash){$journalHash}else{$c.JournalSha256}) -AgentLedgerPath $c.LedgerPath -AgentPayloadHash $c.PayloadHash -FailureDetails 'Revit launched; API_ERROR loading CreatePlanViewsQaApplication; no QA result.' -ManualPromptEvidence $c.Prompt -ManualLoadOnceAcknowledged:$ack -ProcessInspector $inspector -DryRun:$dry
}
function Assert-Rejected($name,[scriptblock]$run){$rejected=$false;try{&$run|Out-Null}catch{$rejected=$true};if(!$rejected){throw "Unsafe runner-startup reconciliation accepted: $name"}}
$positive=New-Context
try {
    $before=Read-RepatoTaskStore $positive.Root;$dry=Invoke-Recovery $positive {param($p,$s)$null} -dry -ack
    if($dry.ReplacementAttemptCreated -or (Read-RepatoTaskStore $positive.Root).tasks[0].revision -ne $before.tasks[0].revision){throw 'Dry run mutated the store or created a replacement.'}
    $done=Invoke-Recovery $positive {param($p,$s)$null} -ack;$after=Read-RepatoTaskStore $positive.Root;$task=Find-RepatoTask $after $positive.TaskId;$x=$task.mayaTaraExecution
    if($x.Stage -cne 'runner-startup-failed' -or $x.ExecutionStatus -cne 'RunnerStartupFailed' -or $x.FailureCode -cne 'runner-startup-failed' -or $x.NativeProcessId -ne 44920 -or $x.NativeRequestId -cne $positive.RequestId -or !$x.RunnerStartupEvidence.ManualLoadOnceAcknowledged -or !$x.RunnerStartupEvidence.ResultAbsent -or $task.status -cne 'blocked' -or $task.mayaTaraAttempt.AttemptId -cne $positive.AttemptId){throw 'Terminal runner-startup evidence was not durably retained.'}
    if(@($task.history|Where-Object event -ceq 'maya-tara-runner-startup-failed').Count -ne 1 -or $done.ReplacementAttemptCreated){throw 'Audit event or no-retry guarantee failed.'}
    Assert-Rejected 'live process' {Invoke-Recovery $positive {param($p,$s)[pscustomobject]@{Id=$p;StartTime=$s}} -ack}
    Assert-Rejected 'wrong request ID' {Invoke-Recovery $positive {param($p,$s)$null} -requestId 'bad-request-id' -ack}
    Assert-Rejected 'wrong journal hash' {Invoke-Recovery $positive {param($p,$s)$null} -journalHash ('F'*64) -ack}
    Assert-Rejected 'missing manual prompt acknowledgement' {Invoke-Recovery $positive {param($p,$s)$null}}
    $resultPath=$positive.RequestPath+'.result.json';[IO.File]::WriteAllText($resultPath,'{}');Assert-Rejected 'result already exists' {Invoke-Recovery $positive {param($p,$s)$null} -ack};Remove-Item -LiteralPath $resultPath
    Assert-Rejected 'replay ledger payload mismatch' {Complete-MayaQaRunnerStartupFailureReconciliation -StoreRoot $positive.Root -TaskId $positive.TaskId -AttemptId $positive.AttemptId -RunId $positive.RunId -ClaimId $positive.ClaimId -NativeRequestId $positive.RequestId -ProcessId $positive.ProcessId -ProcessStartedUtc $positive.StartedUtc -RequestPath $positive.RequestPath -RequestSha256 $positive.RequestSha256 -JournalPath $positive.JournalPath -JournalSha256 $positive.JournalSha256 -AgentLedgerPath $positive.LedgerPath -AgentPayloadHash ('F'*64) -FailureDetails 'failure' -ManualPromptEvidence $positive.Prompt -ManualLoadOnceAcknowledged -ProcessInspector {param($p,$s)$null}}
    'Runner startup failure reconciliation checks passed: 8 positive invariants; 6 guarded rejections'
} finally {if(Test-Path $positive.Root){Remove-Item -LiteralPath $positive.Root -Recurse -Force}}
