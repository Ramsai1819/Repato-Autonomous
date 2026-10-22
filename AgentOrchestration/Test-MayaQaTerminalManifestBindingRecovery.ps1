$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
$root=Join-Path ([IO.Path]::GetTempPath()) ('repato-terminal-binding-'+[guid]::NewGuid().ToString('N'))
$store=Join-Path $root 'store';$runtime=Join-Path $root 'runtime'
New-Item $store,$runtime -ItemType Directory -Force|Out-Null
try {
    Copy-Item (Join-Path $PSScriptRoot '../QA/MayaRuns/tasks.json') $store
    Copy-Item (Join-Path $PSScriptRoot '../QA/MayaRuns/status.json') $store
    $id='task-bf61fe7f22d74df7a92599681da5919e'
    $d=Read-RepatoTaskStore $store;$t=Find-RepatoTask $d $id
    $x=$t.mayaTaraExecution;$oldAttempt=$x.AttemptId;$modelHash=$x.DisposableModelSha256
    $x.Stage='launch-failed';$x.ExecutionStatus='LaunchFailed';$x.FailureCode='native-process-start-failed'
    $manifest=Join-Path $root 'Repato.CreatePlanViews.TestRunner.addin'
    Copy-Item $x.RunnerManifestPath $manifest
    $w=@($t.deploymentWorkflows|Where-Object workflowId -eq $x.WorkflowId)[0]
    $w.qaBuildEvidence.DeployedRunnerManifestPath=$manifest
    Write-RepatoJsonAtomic (Join-Path $store 'tasks.json') $d
    $before=(Get-FileHash (Join-Path $store 'tasks.json')).Hash
    Set-Content $manifest 'tampered deployed manifest'
    try{Recover-MayaQaTerminalLaunchFailure $store $id -RuntimeRoot $runtime|Out-Null;throw 'Tampered manifest accepted.'}catch{if($_.Exception.Message -notmatch 'manifest hash validation failed'){throw}}
    if((Get-FileHash (Join-Path $store 'tasks.json')).Hash -cne $before -or @(Get-ChildItem $runtime).Count){throw 'Rejected manifest caused mutation.'}
    Copy-Item $x.RunnerManifestPath $manifest -Force
    $new=Recover-MayaQaTerminalLaunchFailure $store $id -RuntimeRoot $runtime -AttemptDurationMinutes 180
    if($new.AttemptId -ceq $oldAttempt -or $new.ValidatedRunnerManifestPath -cne $manifest -or $new.RunnerManifestPath -cne $x.RunnerManifestPath -or $new.ValidatedRunnerManifestSha256 -ine $x.RunnerManifestSha256 -or $new.DisposableModelSha256 -ine $modelHash -or !$new.FixturePreparationEvidence -or $new.NativeProcessId -or $new.EvidencePath -or $new.SideEffectsPerformed){throw 'Terminal recovery manifest or prepared-model contract failed.'}
    if((Get-FileHash $new.DisposableModelPath).Hash -ine $modelHash){throw 'Prepared model bytes changed.'}
    $t=Find-RepatoTask (Read-RepatoTaskStore $store) $id
    $side=Get-Content ($new.DisposableModelPath+'.fixture.json') -Raw|ConvertFrom-Json
    if($side.preparedModelSha256 -ine $modelHash -or @($t.mayaTaraExecutionHistory|Where-Object AttemptId -ceq $oldAttempt).Count -ne 1){throw 'Prepared sidecar or failure history lost.'}
    $d=Read-RepatoTaskStore $store;$t=Find-RepatoTask $d $id;$t.status='in-progress'
    foreach($q in @($t.approvalRequests|Where-Object status -ceq 'pending')){$q.status='superseded'}
    Write-RepatoJsonAtomic (Join-Path $store 'tasks.json') $d
    $revision=[long]$t.revision;$candidate=$w.qaBuildEvidence
    $params=@{StoreRoot=$store;TaskId=$id;WorkflowId=$x.WorkflowId;FailedAttemptId=$oldAttempt;RecoveredAttemptId=$new.AttemptId;RecoveredRunId=$new.RunId;ExpectedTaskRevision=$revision;ExpectedCandidateSourceCommit=$candidate.CandidateSourceCommit;ExpectedCandidateSha256=$candidate.ArtifactSha256;LaunchAgentRuntimeVersion='1.0.13+6cf1fa19150f'}
    $before=(Get-FileHash (Join-Path $store 'tasks.json')).Hash
    $params.ExpectedTaskRevision=$revision-1
    try{Request-MayaQaRecoveredLaunchFailureApproval @params|Out-Null;throw 'Stale approval accepted.'}catch{if($_.Exception.Message -notmatch 'pre-approval state'){throw}}
    if((Get-FileHash (Join-Path $store 'tasks.json')).Hash -cne $before){throw 'Stale approval mutated store.'}
    $params.ExpectedTaskRevision=$revision
    $q=Request-MayaQaRecoveredLaunchFailureApproval @params
    if($q.status -cne 'pending' -or $q.requiredLevel -cne 'user' -or $q.decidedBy -or $q.recoveryBinding.DeployedRunnerManifestPath -cne $manifest -or $q.recoveryBinding.SourceRunnerManifestPath -cne $x.RunnerManifestPath -or $q.attemptId -cne $new.AttemptId){throw 'Fresh recovery approval manifest binding failed.'}
    $d=Read-RepatoTaskStore $store;$t=Find-RepatoTask $d $id
    if($t.mayaTaraExecution.TaskRevisionAtPrepare -ne $t.revision){throw 'Approval producer left a stale preparation revision.'}
    $t.mayaTaraExecution.TaskRevisionAtPrepare=[long]$t.revision-2
    Write-RepatoJsonAtomic (Join-Path $store 'tasks.json') $d
    $repaired=Repair-MayaQaRecoveredLaunchApprovalRevision $store $id $q.requestId $t.revision
    $pending=@($repaired.approvalRequests|Where-Object requestId -ceq $q.requestId)[0]
    if($repaired.mayaTaraExecution.TaskRevisionAtPrepare -ne $repaired.revision -or $pending.requestedRevision -ne $repaired.revision -or $pending.expiresUtc -cne $q.expiresUtc -or $pending.bindingHash -cne $q.bindingHash -or $pending.status -cne 'pending' -or $pending.decidedBy){throw 'Revision repair altered authorization or expiry.'}
    'Terminal manifest binding recovery PASS: source/deployed identities distinct, tamper rejected without mutation, prepared model and evidence preserved, failure archived.'
} finally {
    $resolved=[IO.Path]::GetFullPath($root)
    if(!$resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe test cleanup path.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
