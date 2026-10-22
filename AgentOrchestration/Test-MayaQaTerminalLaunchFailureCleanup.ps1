$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force

$fixture=Join-Path $root 'QA\Fixtures\CreatePlanViewsEmpty.rvt'
$fixtureHash=(Get-FileHash $fixture -Algorithm SHA256).Hash
$taskId='synthetic-terminal-cleanup-task';$attemptId='synthetic-terminal-cleanup-attempt';$claimId='synthetic-terminal-cleanup-claim'

function New-CleanupStore {
    $store=Join-Path ([IO.Path]::GetTempPath()) ('repato-cleanup-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $store -Force|Out-Null
    $data=Get-Content (Join-Path $root 'QA\MayaRuns\tasks.json') -Raw|ConvertFrom-Json;$task=@($data.tasks|Where-Object taskId -eq 'task-4735f0ae0a4449c6b5ad9dc46c7a5afd')[0];$task.taskId=$taskId;$task.revision=[long]$task.revision
    $runtime=Join-Path $store 'runtime';New-Item -ItemType Directory -Path $runtime -Force|Out-Null;$model=Join-Path $runtime 'model.rvt';Copy-Item $fixture $model; $request=Join-Path $runtime 'maya-tara-synthetic.request.json';Set-Content -LiteralPath $request -Value '{"synthetic":true}' -Encoding UTF8
    $e=$task.mayaTaraExecution;$e.TaskId=$taskId;$e.AttemptId=$attemptId;$e.ClaimId=$claimId;$e.ClaimOwner='Tara';$e.ClaimStatus='claimed';$e.Stage='launch-failed';$e.ExecutionStatus='LaunchFailed';$e.FailureCode='native-process-start-failed';$e.RollbackStatus='Required';$e.DisposableRuntimeRoot=$runtime;$e.DisposableModelPath=$model;$e.DisposableModelSha256=$fixtureHash;$e.AuthoritativeFixturePath=$fixture;$e.AuthoritativeFixtureSha256=$fixtureHash;$e.RequestPath=$request;$e.ResultPath=$null;$e.ReportPath=$null;$e.ReceiptPath=$null;$e.EvidencePath=$null;$e.NativeProcessId=$null;$e.LaunchedUtc=$null;$e.ExecutingUtc=$null;$e.CompletedUtc=$null;$e.SideEffectsPerformed=$false
    $task.mayaTaraAttempt.AttemptId=$attemptId;$task.mayaTaraAttempt.RunId=$e.RunId
    $data.tasks=@($task);$data.schemaVersion=1;$queue=Join-Path $store 'tasks.json';$data|ConvertTo-Json -Depth 40|Set-Content -LiteralPath $queue -Encoding UTF8
    [pscustomobject]@{Store=$store;Runtime=$runtime;Request=$request;TaskId=$taskId;AttemptId=$attemptId;ClaimId=$claimId}
}

$ctx=New-CleanupStore
try {
    $first=Complete-MayaQaTerminalLaunchFailureCleanup -StoreRoot $ctx.Store -TaskId $ctx.TaskId -AttemptId $ctx.AttemptId -ClaimId ([string]$ctx.ClaimId)
    if($first.RollbackStatus -cne 'Verified' -or $first.ClaimStatus -cne 'released' -or !$first.RequestEvidencePreserved -or $first.ReplacementAttemptCreated){throw 'Cleanup-only success contract failed.'}
    $after=Get-Content (Join-Path $ctx.Store 'tasks.json') -Raw|ConvertFrom-Json;$t=@($after.tasks|Where-Object taskId -eq $ctx.TaskId)[0];$e=$t.mayaTaraExecution
    if($e.ClaimStatus -cne 'released' -or $e.ClaimId -or $e.RollbackStatus -cne 'Verified' -or $e.Stage -cne 'rollback-verified' -or !(Test-Path -LiteralPath $e.RequestPath -PathType Leaf) -or (Test-Path -LiteralPath $ctx.Runtime -PathType Container)){throw 'Cleanup state/evidence verification failed.'}
    $second=Complete-MayaQaTerminalLaunchFailureCleanup -StoreRoot $ctx.Store -TaskId $ctx.TaskId -AttemptId $ctx.AttemptId -ClaimId $ctx.ClaimId
    if($second.Mode -cne 'AlreadyCompleted' -or $second.ReplacementAttemptCreated){throw 'Cleanup idempotency failed.'}
    $source=Get-Content (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Raw
    foreach($guard in @('Cleanup identity mismatch','Cleanup claim identity mismatch','launch-failed','native-process-start-failed','Cleanup found prohibited terminal evidence','Cleanup found recorded side effects','Authoritative fixture integrity failed','Disposable model identity/hash validation failed','Request evidence cannot be safely preserved','Cleanup compare-and-swap failed')){if($source -notmatch [regex]::Escape($guard)){throw "Missing cleanup guard: $guard"}}
    $bad=New-CleanupStore;$badTask=Get-Content (Join-Path $bad.Store 'tasks.json') -Raw|ConvertFrom-Json;$bt=@($badTask.tasks|Where-Object taskId -eq $bad.TaskId)[0];$bt.mayaTaraExecution.ClaimId='wrong';$badTask|ConvertTo-Json -Depth 40|Set-Content (Join-Path $bad.Store 'tasks.json') -Encoding UTF8
    $rejected=$false;try{Complete-MayaQaTerminalLaunchFailureCleanup -StoreRoot $bad.Store -TaskId $bad.TaskId -AttemptId $bad.AttemptId -ClaimId $bad.ClaimId|Out-Null}catch{$rejected=$true};if(!$rejected -or (Test-Path $bad.Runtime -PathType Container) -eq $false){throw 'Negative claim validation failed.'}
    Remove-Item -LiteralPath $bad.Store -Recurse -Force
    [pscustomobject]@{CleanupOnlySyntheticTest='PASS';FirstCleanup=$first.Mode;SecondCleanup=$second.Mode;ClaimReleased=$true;RollbackTerminal=$true;RequestEvidencePreserved=$true;DisposableRuntimeNoLongerBlocking=$true;ReplacementAttemptCreated=$false;ReplacementRuntimeCreated=$false;LiveQaLaunchRequestSent=$false;RevitLaunched=$false}
} finally { if(Test-Path $ctx.Store){Remove-Item -LiteralPath $ctx.Store -Recurse -Force} }
