$ErrorActionPreference='Stop'
$module=Join-Path $PSScriptRoot 'Repato.QaNativeDisposition.psm1'
Import-Module $module -Force
$root=Join-Path ([IO.Path]::GetTempPath()) ('repato-native-disposition-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
try {
    $store=Join-Path $root 'store';New-Item -ItemType Directory -Path $store | Out-Null
    $runs=Join-Path $root 'runs';New-Item -ItemType Directory -Path $runs | Out-Null
    $taskId='task-synthetic';$workflow=[guid]::NewGuid().ToString('N');$qa='create-plan-views-v1';$test=$qa
    $attempt=[guid]::NewGuid().ToString('N');$run=[guid]::NewGuid().ToString('N');$claim=[guid]::NewGuid().ToString('N');$requestId=[guid]::NewGuid().ToString('N')
    $requestPath=Join-Path $runs 'synthetic.request.json';$resultPath=$requestPath+'.result.json';$reportPath=Join-Path $runs 'synthetic-report.json'
    $request=[ordered]@{requestId=$requestId;taskId=$taskId;workflowId=$workflow;qaWorkflowId=$qa;testId=$test;attemptId=$attempt;runId=$run;claimId=$claim}
    $execution=[ordered]@{TaskId=$taskId;WorkflowId=$workflow;QaWorkflowId=$qa;TestId=$test;AttemptId=$attempt;RunId=$run;ClaimId=$claim;NativeRequestId=$requestId;RequestPath=$requestPath;ArtifactSha256=('A'*64);AuthoritativeFixtureSha256=('C'*64);DisposableModelSha256=('B'*64);Stage='prepared';ExecutionStatus='Prepared';NativeProcessId=$null;LaunchedUtc=$null}
    $task=[ordered]@{taskId=$taskId;revision=1;mayaTaraExecution=$execution}
    $storePath=Join-Path $store 'tasks.json';$taskData=[ordered]@{schemaVersion=1;tasks=@($task)}
    $request|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $requestPath -Encoding UTF8
    $taskData|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $storePath -Encoding UTF8
    $args=@{StoreRoot=$store;EvidenceRoot=$runs;RequestPath=$requestPath;ExpectedRequestId=$requestId;TaskId=$taskId;WorkflowId=$workflow;QaWorkflowId=$qa;TestId=$test;AttemptId=$attempt;RunId=$run;ClaimId=$claim}

    $unknown=Get-RepatoQaNativeDisposition @args
    if($unknown.Status -cne 'Unknown'){throw 'Unaccepted request without result must remain Unknown.'}
    $execution.Stage='executing';$execution.ExecutionStatus='Executing';$execution.NativeProcessId=43210;$execution.LaunchedUtc=[DateTimeOffset]::UtcNow.ToString('O')
    $taskData|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $storePath -Encoding UTF8
    $accepted=Get-RepatoQaNativeDisposition @args
    if($accepted.Status -cne 'Accepted'){throw 'Correlated persisted acceptance must classify as Accepted.'}

    $report=[ordered]@{RequestId=$requestId;TaskId=$taskId;WorkflowId=$workflow;QaWorkflowId=$qa;TestId=$test;AttemptId=$attempt;RunId=$run;ClaimId=$claim;Status='Passed';RollbackStatus='RolledBack';FixtureSha256=('C'*64);RuntimeModelSha256=('B'*64);Errors=@();Assertions=@(@{Passed=$true});AssemblyIdentity=@{Sha256=('A'*64)}}
    $report|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $reportPath -Encoding UTF8
    $receipt=[ordered]@{RequestId=$requestId;TaskId=$taskId;WorkflowId=$workflow;QaWorkflowId=$qa;TestId=$test;AttemptId=$attempt;RunId=$run;ClaimId=$claim;Status='Passed';ReportPath=$reportPath}
    $receipt|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $resultPath -Encoding UTF8
    $completed=Get-RepatoQaNativeDisposition @args -ExpectedArtifactSha256 ('A'*64)
    if($completed.Status -cne 'Completed'){throw "Correlated passing result was not Completed: $($completed.Reason)"}
    $report.Status='Failed';$report.RollbackStatus='RolledBack';$report.Errors=@('Synthetic controlled failure.')
    $report|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $reportPath -Encoding UTF8;$receipt.Status='Failed'
    $receipt|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $resultPath -Encoding UTF8
    $failed=Get-RepatoQaNativeDisposition @args -ExpectedArtifactSha256 ('A'*64)
    if($failed.Status -cne 'Failed'){throw "Correlated failing result was not Failed: $($failed.Reason)"}
    $receipt.RunId=[guid]::NewGuid().ToString('N');$receipt|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $resultPath -Encoding UTF8
    $mismatch=Get-RepatoQaNativeDisposition @args
    if($mismatch.Status -cne 'Unknown'){throw 'Mismatched terminal evidence must remain Unknown.'}
    $outsideArgs=@{};foreach($key in $args.Keys){$outsideArgs[$key]=$args[$key]};$outsideArgs.EvidenceRoot=$store
    $outside=Get-RepatoQaNativeDisposition @outsideArgs
    if($outside.Status -cne 'Unknown' -or $outside.Reason -notlike '*outside*'){throw 'Evidence outside the approved root must remain Unknown.'}
    if($mismatch.SideEffectsPerformed){throw 'Read-only disposition unexpectedly reported side effects.'}
    $stableStore=(Get-FileHash -LiteralPath $storePath -Algorithm SHA256).Hash
    $null=Get-RepatoQaNativeDisposition @args
    if((Get-FileHash -LiteralPath $storePath -Algorithm SHA256).Hash -cne $stableStore){throw 'Disposition inspection mutated the task store.'}
    [pscustomobject]@{Passed=$true;Cases=@('Unknown','Accepted','Completed','Failed','MismatchedEvidenceUnknown','OutsideEvidenceRejected','StoreUnchanged');RealStoreMutated=$false;NativeAgentInvoked=$false;RevitLaunched=$false}|ConvertTo-Json -Compress
}
finally { Remove-Item -LiteralPath $root -Recurse -Force }
