$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
$upgradeModule=Import-Module (Join-Path $PSScriptRoot 'Repato.CpvCompletedOutcomeUpgrade.psm1') -Force -PassThru -WarningAction SilentlyContinue
$releaseCatalog=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\DeploymentCandidates\AgentReleases'))
$testRelease=Join-Path $releaseCatalog ('.cpv-recovery-test-'+[guid]::NewGuid().ToString('N'))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('cpv-completed-upgrade-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRelease,$temp -Force|Out-Null
$script:assertions=0
function Check($Value,$Name){$script:assertions++;if(!$Value){throw "FAILED: $Name"}}
function Reject($Action,$Pattern){$script:assertions++;try{& $Action;throw 'Unexpected acceptance'}catch{if($_.Exception.Message -notmatch $Pattern){throw}}}
function Get-Hash($Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()}
try {
    $logs=Join-Path $temp 'logs\CpvPreparation';$runtime=Join-Path $temp 'runtime';$run=Join-Path $runtime 'cpv-preparation-b0de5c9687594098bc61b32bdd86f9a3'
    $priorRoot=Join-Path $temp 'prior';New-Item -ItemType Directory -Path $logs,$runtime,$run,$priorRoot -Force|Out-Null
    $requestId='c11b311638a54bfc9ebdd1803671ec40';$taskId='task-bf61fe7f22d74df7a92599681da5919e'
    $attempt='63b5401b7f8341fe8608310b4dac0f4f';$workflow='fa2c2f578cbc40cbacac45c96313ca4c';$runId='b0de5c9687594098bc61b32bdd86f9a3'
    $dll=Join-Path $temp 'candidate.dll';$prov=Join-Path $temp 'candidate.provenance.json';$runnerManifest=Join-Path $temp 'runner.addin'
    $deployedManifest=Join-Path (Join-Path $temp 'deployed-addins') 'runner.addin'
    [IO.File]::WriteAllText($dll,'candidate');[IO.File]::WriteAllText($prov,'candidate provenance');[IO.File]::WriteAllText($runnerManifest,'runner manifest')
    New-Item -ItemType Directory -Path (Split-Path $deployedManifest) -Force|Out-Null;[IO.File]::WriteAllText($deployedManifest,'runner manifest')
    $dllHash=Get-Hash $dll;$provHash=Get-Hash $prov;$runnerHash=Get-Hash $runnerManifest
    $candidate=[pscustomobject]@{CandidateDllPath=$dll;CandidateDllSha256=$dllHash;CandidateProvenancePath=$prov;RunnerManifestPath=$runnerManifest;RunnerManifestSha256=$runnerHash;CandidateSourceCommit=('a'*40)}
    $request=[pscustomobject][ordered]@{schemaVersion=1;operation='prepare-cpv-fixture';requestId=$requestId;taskId=$taskId;workflowId=$workflow;attemptId=$attempt;runId=$runId;expiresUtc='2026-10-18T18:38:41.7797045+00:00';timeoutSeconds=7200;candidateEvidence=$candidate}
    $request=$request|ConvertTo-Json -Depth 20|ConvertFrom-Json
    $request.expiresUtc=([DateTimeOffset]$request.expiresUtc).ToUniversalTime().ToString('O')
    $binding=[pscustomobject]@{CandidateSha256=$dllHash;CandidateProvenanceSha256=$provHash;RunnerManifestSha256=$runnerHash;FixtureSha256='92CC9E434E2C4DD6720A2AA564E19F4E1A30EB3DA63CEA73CF737F875B9EDD45';RequestId=$requestId;TaskId=$taskId}
    $hashRequest=& $upgradeModule {param($v)Get-CpvCompletedUpgradeHash $v} $request
    $hashBinding=& $upgradeModule {param($v)Get-CpvCompletedUpgradeHash $v} $binding
    $task=[pscustomobject]@{taskId=$taskId;title='Synthetic CPV recovery';description='Isolated contract fixture';assignedAgent='Maya';status='in-progress';workflowStage='qa';branchName='qa/cpv-recovery-test';createdUtc=[DateTimeOffset]::UtcNow.ToString('O');startedUtc=$null;finishedUtc=$null;logs=[object[]]@();reportPaths=[object[]]@();errorDetails=$null;requiredApprovalLevel='user';approvalRequests=[object[]]@([pscustomobject]@{requestId='7386efa2519b4c518e3d149f3a645a05';action='cpv-prepare-fixture';status='approved';requiredLevel='user';consumedUtc='2026-10-18T14:43:06Z';bindingHash=$hashBinding;preparationBinding=$binding});executorRuns=[object[]]@();revision=[long]101;cpvPreparationRecovery=[pscustomobject]@{Status='Dispatching';PreparationApprovalId='7386efa2519b4c518e3d149f3a645a05';PreparationBinding=[pscustomobject]@{TaskRevision=98;RequestId=$requestId;StoreRoot=$temp};Request=$request;RequestHash=$hashRequest;OutcomeRecoveryApprovalId=$null};history=[object[]]@([pscustomobject]@{timestampUtc=[DateTimeOffset]::UtcNow.ToString('O')})}
    $store=Join-Path $temp 'store';New-Item -ItemType Directory -Path $store|Out-Null
    [IO.File]::WriteAllText((Join-Path $store 'tasks.json'),(ConvertTo-Json -InputObject ([pscustomobject]@{schemaVersion=1;tasks=[object[]]@($task)}) -Depth 20))
    $roundTrip=& $upgradeModule {param($root,$id) Find-RepatoTask (Read-RepatoTaskStore $root) $id} $store $taskId
    $roundTrip.cpvPreparationRecovery.RequestHash=& $upgradeModule {param($v)Get-CpvCompletedUpgradeHash $v} $roundTrip.cpvPreparationRecovery.Request
    [IO.File]::WriteAllText((Join-Path $store 'tasks.json'),(ConvertTo-Json -InputObject ([pscustomobject]@{schemaVersion=1;tasks=[object[]]@($roundTrip)}) -Depth 20))
    $model=Join-Path $run 'model.rvt';[IO.File]::WriteAllText($model,'prepared disposable create-plan-views fixture')
    $modelHash=Get-Hash $model;$runnerPath=Join-Path $run ('tara-'+$attempt+'.request.json');$resultPath=$runnerPath+'.preparation.json'
    $runner=[pscustomobject]@{schemaVersion=1;operation='prepare-disposable-create-plan-views-fixture';requestId=$attempt;taskId=$taskId;workflowId=$workflow;attemptId=$attempt;runId=$runId;requestPath=$runnerPath;modelPath=$model;modelSha256='92CC9E434E2C4DD6720A2AA564E19F4E1A30EB3DA63CEA73CF737F875B9EDD45';selectedManifestPath=$deployedManifest;selectedManifestSha256=$runnerHash;outputPath=$resultPath;expiresUtc=$request.expiresUtc}
    $runner|ConvertTo-Json -Compress|Set-Content -LiteralPath $runnerPath -Encoding UTF8
    $result=[pscustomobject]@{Status='Passed';Operation='prepare-disposable-create-plan-views-fixture';TaskId=$taskId;WorkflowId=$workflow;AttemptId=$attempt;RunId=$runId;ModelPath=$model;SourceModelSha256='92CC9E434E2C4DD6720A2AA564E19F4E1A30EB3DA63CEA73CF737F875B9EDD45';PreparedModelSha256=$modelHash}
    $result|ConvertTo-Json -Compress|Set-Content -LiteralPath $resultPath -Encoding UTF8
    [IO.File]::WriteAllText(($model+'.fixture.json'),'{"fixtureId":"CreatePlanViewsEmpty","sourceSha256":"92CC9E434E2C4DD6720A2AA564E19F4E1A30EB3DA63CEA73CF737F875B9EDD45"}')
    $savedRequest=$request|ConvertTo-Json -Depth 12 -Compress
    [IO.File]::WriteAllText((Join-Path $logs 'active.json'),$savedRequest)
    [IO.File]::WriteAllText((Join-Path $logs ($requestId+'.request.json')),$savedRequest)
    [IO.File]::WriteAllText((Join-Path $logs ($requestId+'.failure.txt')),'System.IO.IOException: preparation-failed-reconcile-required')
    $receipt=[pscustomobject]@{schemaVersion=1;operation='prepare-cpv-fixture';requestId=$requestId;taskId=$taskId;workflowId=$workflow;attemptId=$attempt;runId=$runId;status='OutcomeUnknown';user='RAMSAI\RepatoQA';sid='S-1-5-21-1031246752-3872016183-2454652381-1015';sessionId=2;candidateSha256=$dllHash;manifestSha256=$runnerHash;modelPath=$model;modelSha256='';requestPath=$runnerPath;requestSha256='';resultPath='';resultSha256='';cleanupVerified=$false;rollbackStatus='Unknown';failureCode='preparation-failed-reconcile-required';expiresUtc=$request.expiresUtc}
    $receipt|ConvertTo-Json -Compress|Set-Content -LiteralPath (Join-Path $logs ($requestId+'.json')) -Encoding UTF8
    $activeHash=Get-Hash (Join-Path $logs 'active.json')
    $fileNames=@('Repato.QaLaunchAgent.exe','Repato.QaLaunchAgent.dll','Repato.QaLaunchAgent.deps.json','Repato.QaLaunchAgent.runtimeconfig.json')
    foreach($n in $fileNames){[IO.File]::WriteAllText((Join-Path $priorRoot $n),('prior '+$n))}
    $prior=@(foreach($n in $fileNames){[pscustomobject]@{name=$n;sha256=(Get-Hash (Join-Path $priorRoot $n))}})
    $candidateRoot=Join-Path $testRelease 'Repato.QaLaunchAgent-1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f';New-Item -ItemType Directory -Path $candidateRoot|Out-Null
    $candidateFiles=@(foreach($n in $fileNames){$p=Join-Path $candidateRoot $n;[IO.File]::WriteAllText($p,('candidate '+$n));[pscustomobject]@{name=$n;sha256=(Get-Hash $p)}})
    $release=[ordered]@{schemaVersion=1;product='Repato.QaLaunchAgent';productVersion='1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f';sourceCommit='3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f';account='RAMSAI\RepatoQA';sid='S-1-5-21-1031246752-3872016183-2454652381-1015';files=$candidateFiles}
    $manifest=Join-Path $candidateRoot 'Repato.QaLaunchAgent.release.json';$release|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $manifest -Encoding UTF8;$manifestHash=Get-Hash $manifest
    $installedIdentity=[pscustomobject]@{ProcessName='Repato.QaLaunchAgent';Path=(Join-Path $priorRoot $fileNames[0]);ProductVersion='1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e';Id=123;StartTime=[DateTime]::UtcNow;User='RAMSAI\RepatoQA';Sid='S-1-5-21-1031246752-3872016183-2454652381-1015';SessionId=2}
    $caps=[pscustomobject]@{operation='cpv-preparation-capabilities';supported=$true;user='RAMSAI\RepatoQA';sid='S-1-5-21-1031246752-3872016183-2454652381-1015';sessionId=2}
    $bootstrapPath=Join-Path $temp 'SyntheticBootstrap.psm1';@'
function Read-InstallJournal { param($Path,$TargetRoot) [pscustomobject]@{state='Committed';generation=13;candidateVersion='1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e';requestId='c11b311638a54bfc9ebdd1803671ec40';taskId='task-bf61fe7f22d74df7a92599681da5919e';journalSha256=('D'*64)} }
'@|Set-Content -LiteralPath $bootstrapPath -Encoding UTF8
    $bootstrap=Import-Module $bootstrapPath -Force -PassThru
    $args=@{EvidenceRoot=$logs;RuntimeRoot=$runtime;RequestId=$requestId;TaskId=$taskId;ExpectedTaskRevision=101;StoreRoot=$store;Capabilities=$caps;Receipt=$receipt;InstalledAgent=$installedIdentity;ProcessSid=$installedIdentity.Sid;ExpectedExecutable=$installedIdentity.Path;ExpectedInstalledVersion='1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e';CandidateRoot=$candidateRoot;CandidateManifestPath=$manifest;CandidateManifestSha256=$manifestHash;PriorRuntimeFiles=$prior;PriorTaskContractValid=$true;NoRevitProcesses=$true;BootstrapModule=$bootstrap}
    $accepted=Assert-CpvCompletedOutcomeUpgrade @args
    Check ($accepted.CandidateVersion -eq '1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f' -and $accepted.JournalGeneration -eq 13) 'exact request and committed journal-13 upgrade gate accepts synthetic candidate'
    Check ((Get-Hash (Join-Path $logs 'active.json')) -ceq $activeHash) 'upgrade preflight preserves active marker bytes'
    $stale=@{}+$args;$stale.ExpectedTaskRevision=100;Reject {Assert-CpvCompletedOutcomeUpgrade @stale} 'revision|state'
    $noRollback=@{}+$args;$noRollback.PriorRuntimeFiles=@($prior|Select-Object -Skip 1);Reject {Assert-CpvCompletedOutcomeUpgrade @noRollback} 'rollback'
    $restartedSession=@{}+$args;$restartedSession.Capabilities=$caps|Select-Object *;$restartedSession.Capabilities.SessionId=1
    $restartedSession.InstalledAgent=[pscustomobject]@{ProcessName=$installedIdentity.ProcessName;Path=$installedIdentity.Path;ProductVersion=$installedIdentity.ProductVersion;Id=$installedIdentity.Id;StartTime=$installedIdentity.StartTime;User=$installedIdentity.User;Sid=$installedIdentity.Sid;SessionId=1}
    $restartedAccepted=Assert-CpvCompletedOutcomeUpgrade @restartedSession
    Check ($restartedAccepted.CandidateVersion -eq '1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f') 'a restarted authenticated RepatoQA session with self-consistent live identity and unchanged historical receipt session is accepted'
    $zeroSession=@{}+$args;$zeroSession.Capabilities=$caps|Select-Object *;$zeroSession.Capabilities.SessionId=0;Reject {Assert-CpvCompletedOutcomeUpgrade @zeroSession} 'capability identity'
    $mismatchedSession=@{}+$args;$mismatchedSession.Capabilities=$caps|Select-Object *;$mismatchedSession.Capabilities.SessionId=3;Reject {Assert-CpvCompletedOutcomeUpgrade @mismatchedSession} 'process owner'
    $tamperedReceiptSession=@{}+$args;$tamperedReceiptSession.Receipt=[pscustomobject]@{};foreach($p in $receipt.PSObject.Properties){$tamperedReceiptSession.Receipt|Add-Member NoteProperty $p.Name $p.Value};$tamperedReceiptSession.Receipt.sessionId=3;Reject {Assert-CpvCompletedOutcomeUpgrade @tamperedReceiptSession} 'unresolved preparation result'
    $badJournalPath=Join-Path $temp 'BadBootstrap.psm1';@'
function Read-InstallJournal { param($Path,$TargetRoot) [pscustomobject]@{state='RollbackPending';generation=13;candidateVersion='1.0.18+4b0066247088';requestId='9953e14c15524fe09440d1c7d7353950';taskId='task-bf61fe7f22d74df7a92599681da5919e';journalSha256=('D'*64)} }
'@|Set-Content -LiteralPath $badJournalPath -Encoding UTF8;$badBootstrap=Import-Module $badJournalPath -Force -PassThru;$badJournal=@{}+$args;$badJournal.BootstrapModule=$badBootstrap;Reject {Assert-CpvCompletedOutcomeUpgrade @badJournal} 'generation-13'
    $reservationId='590da474d11d42e2b2fedbf99edaba03'
    $recoveryRequest=[pscustomobject]@{schemaVersion=1;operation='cpv-preparation-recover-completed';requestId=$requestId;taskId=$taskId;workflowId=$workflow;attemptId=$attempt;runId=$runId}
    $reservedTask=(ConvertTo-Json -InputObject $roundTrip -Depth 20|ConvertFrom-Json)
    $reservedTask.cpvPreparationRecovery.OutcomeRecoveryApprovalId=$reservationId
    $reservedTask.cpvPreparationRecovery.OutcomeRecoveryRequest=$recoveryRequest
    $reservedTask.cpvPreparationRecovery.OutcomeRecoveryRequestHash=('A'*64)
    $reservedTask.cpvPreparationRecovery.RequestHash=& $upgradeModule {param($v)Get-CpvCompletedUpgradeHash $v} $reservedTask.cpvPreparationRecovery.Request
    $reservedTask.approvalRequests=@($reservedTask.approvalRequests)+@([pscustomobject]@{requestId=$reservationId;action='cpv-preparation-outcome-recovery';status='approved';requiredLevel='user';consumedUtc='2026-10-19T06:50:07Z'})
    [IO.File]::WriteAllText((Join-Path $store 'tasks.json'),(ConvertTo-Json -InputObject ([pscustomobject]@{schemaVersion=1;tasks=[object[]]@($reservedTask)}) -Depth 20))
    $reservedArgs=@{}+$args
    $reservedAccepted=Assert-CpvCompletedOutcomeUpgrade @reservedArgs
    Check ($reservedAccepted.CandidateVersion -eq '1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f') 'the exact stale consumed outcome-recovery reservation does not block the 1.0.21 upgrade gate'
    # Exact revision-122 transition: synthetic consumed human authorization and
    # correlated non-execution proof; no live store, pipe, or runtime operations.
    $currentTask=ConvertTo-Json -InputObject $roundTrip -Depth 25|ConvertFrom-Json
    $currentTask.revision=[long]122
    $currentTask.cpvPreparationRecovery.RequestHash=& $upgradeModule {param($v)Get-CpvCompletedUpgradeHash $v} $currentTask.cpvPreparationRecovery.Request
    $currentId='acfd8643ed2846b8a43b98d3a74c3217'
    $snapshot=[pscustomobject][ordered]@{TaskId=$taskId;OriginalReceiptSha256=('1'*64);ActiveMarkerSha256=('2'*64);FailureEvidenceSha256=('3'*64);PreparationRequestSha256=('4'*64);ResultSha256=('5'*64);ModelSha256=('6'*64);AgentVersion='1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f';AgentSessionId=2}
    $outcomeModule=Import-Module (Join-Path $PSScriptRoot 'Repato.CpvCompletedOutcomeRecovery.psm1') -PassThru -WarningAction SilentlyContinue
    $binding122=[pscustomobject][ordered]@{SchemaVersion='cpv-preparation-outcome-recovery-approval-v1';ApprovalId=$currentId;TaskId=$taskId;RecoveryRequestId=$requestId;ExpectedTaskRevision=120;Snapshot=$snapshot;SnapshotHash=(& $outcomeModule {param($v)Get-CpvOutcomeRecoveryHash $v} $snapshot)}
    $approvalHash=& $outcomeModule {param($v)Get-CpvOutcomeRecoveryHash $v} $binding122
    $payload=[pscustomobject][ordered]@{schemaVersion=1;operation='cpv-preparation-recover-completed';requestId=$requestId;taskId=$taskId;workflowId=$workflow;attemptId=$attempt;runId=$runId;recoveryApprovalId=$currentId;expectedTaskRevision=120;approvalBindingHash=$approvalHash;authorizationExpiresUtc='2026-10-19T07:00:00Z';originalReceiptSha256=$snapshot.OriginalReceiptSha256;activeMarkerSha256=$snapshot.ActiveMarkerSha256;failureEvidenceSha256=$snapshot.FailureEvidenceSha256;requestSha256=$snapshot.PreparationRequestSha256;resultSha256=$snapshot.ResultSha256;modelSha256=$snapshot.ModelSha256}
    $currentTask.cpvPreparationRecovery.OutcomeRecoveryApprovalId=$currentId
    $currentTask.cpvPreparationRecovery.OutcomeRecoveryRequest=$payload
    $currentTask.cpvPreparationRecovery.OutcomeRecoveryRequestHash=& $outcomeModule {param($v)Get-CpvOutcomeRecoveryHash $v} $payload
    $currentTask.approvalRequests=@($currentTask.approvalRequests)+@([pscustomobject]@{requestId=$currentId;action='cpv-preparation-outcome-recovery';requiredLevel='user';status='approved';decidedBy='user';consumedUtc='2026-10-19T06:50:07Z';approvedRevision=121;expiresUtc=$payload.authorizationExpiresUtc;bindingHash=$approvalHash;outcomeRecoveryBinding=$binding122})
    [IO.File]::WriteAllText((Join-Path $store 'tasks.json'),(ConvertTo-Json -InputObject ([pscustomobject]@{schemaVersion=1;tasks=[object[]]@($currentTask)}) -Depth 25))
    $proof=$payload|Select-Object *;$proof.operation='cpv-preparation-recover-completed-reconcile';$proof|Add-Member NoteProperty status 'NotExecuted'
    $nextRoot=Join-Path $testRelease ('Repato.QaLaunchAgent-1.0.22+'+('a'*40));New-Item -ItemType Directory -Path $nextRoot|Out-Null
    foreach($n in $fileNames){Copy-Item -LiteralPath (Join-Path $candidateRoot $n) -Destination (Join-Path $nextRoot $n)}
    $nextRelease=$release|ConvertTo-Json -Depth 6|ConvertFrom-Json;$nextRelease.productVersion='1.0.22+'+('a'*40);$nextRelease.sourceCommit=('a'*40)
    $nextManifest=Join-Path $nextRoot 'Repato.QaLaunchAgent.release.json';$nextRelease|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $nextManifest -Encoding UTF8
    $nextBootstrapPath=Join-Path $temp 'Revision122Bootstrap.psm1';@'
function Read-InstallJournal {param($Path,$TargetRoot) [pscustomobject]@{state='Committed';generation=13;candidateVersion='1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f';priorVersion='1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e';requestId='c11b311638a54bfc9ebdd1803671ec40';taskId='task-bf61fe7f22d74df7a92599681da5919e';journalSha256=('D'*64)}}
'@|Set-Content -LiteralPath $nextBootstrapPath -Encoding UTF8
    $nextArgs=@{}+$args;$nextArgs.ExpectedTaskRevision=122;$nextArgs.ExpectedInstalledVersion=$snapshot.AgentVersion;$nextArgs.InstalledAgent=$installedIdentity|Select-Object *;$nextArgs.InstalledAgent.ProductVersion=$snapshot.AgentVersion;$nextArgs.CandidateRoot=$nextRoot;$nextArgs.CandidateManifestPath=$nextManifest;$nextArgs.CandidateManifestSha256=Get-Hash $nextManifest;$nextArgs.BootstrapModule=Import-Module $nextBootstrapPath -PassThru -Force;$nextArgs.NonExecutionProof=$proof;$nextArgs.CurrentApprovedSnapshot=$snapshot
    $storeBefore=Get-Hash (Join-Path $store 'tasks.json');$historicalBefore=Get-Hash ($model+'.fixture.json')
    $nextArgs.Capabilities=$caps|Select-Object *;$nextArgs.Capabilities|Add-Member NoteProperty runtimeVersion $snapshot.AgentVersion
    $nextAccepted=Assert-CpvCompletedOutcomeUpgrade @nextArgs
    Check ($nextAccepted.CandidateVersion -eq $nextRelease.productVersion) 'exact consumed revision-122 reservation permits 1.0.22 candidate'
    $null=Assert-CpvCompletedOutcomeUpgrade @nextArgs
    Check ((Get-Hash (Join-Path $store 'tasks.json')) -ceq $storeBefore -and (Get-Hash ($model+'.fixture.json')) -ceq $historicalBefore -and (Get-Hash (Join-Path $logs 'active.json')) -ceq $activeHash) 'repeated preflight preserves reservation and protected historical bytes'
    $badNext=@{}+$nextArgs;$badNext.NonExecutionProof=$null;Reject {Assert-CpvCompletedOutcomeUpgrade @badNext} 'non-execution'
    $badNext=@{}+$nextArgs;$badNext.CurrentApprovedSnapshot=$snapshot|Select-Object *;$badNext.CurrentApprovedSnapshot.AgentSessionId=1;Reject {Assert-CpvCompletedOutcomeUpgrade @badNext} 'runtime or session'
    $badNext=@{}+$nextArgs;$badNext.NonExecutionProof=$proof|Select-Object *;$badNext.NonExecutionProof.status='Executed';Reject {Assert-CpvCompletedOutcomeUpgrade @badNext} 'reports.*executed'
    $badNext=@{}+$nextArgs;$badNext.NonExecutionProof=$proof|Select-Object *;$badNext.NonExecutionProof.approvalBindingHash=('0'*64);Reject {Assert-CpvCompletedOutcomeUpgrade @badNext} 'non-execution'
    $badNext=@{}+$nextArgs;$badNext.CurrentApprovedSnapshot=$snapshot|Select-Object *;$badNext.CurrentApprovedSnapshot.ModelSha256=('0'*64);Reject {Assert-CpvCompletedOutcomeUpgrade @badNext} 'approved snapshot'
    $badNext=@{}+$nextArgs;$badNext.ExpectedTaskRevision=123;Reject {Assert-CpvCompletedOutcomeUpgrade @badNext} 'revision changed'
    $badNext=@{}+$nextArgs;$badNext.CandidateRoot=$candidateRoot;$badNext.CandidateManifestPath=$manifest;$badNext.CandidateManifestSha256=$manifestHash;Reject {Assert-CpvCompletedOutcomeUpgrade @badNext} 'pinned agent-release'
    $storeBytes=[IO.File]::ReadAllBytes((Join-Path $store 'tasks.json'))
    $currentTask.cpvPreparationRecovery.OutcomeRecoveryRequestHash=('0'*64)
    [IO.File]::WriteAllText((Join-Path $store 'tasks.json'),(ConvertTo-Json -InputObject ([pscustomobject]@{schemaVersion=1;tasks=[object[]]@($currentTask)}) -Depth 25))
    Reject {Assert-CpvCompletedOutcomeUpgrade @nextArgs} 'request hash changed'
    [IO.File]::WriteAllBytes((Join-Path $store 'tasks.json'),$storeBytes)
    $proofWithoutHash=$proof|Select-Object * -ExcludeProperty originalReceiptSha256
    $badNext=@{}+$nextArgs;$badNext.NonExecutionProof=$proofWithoutHash;Reject {Assert-CpvCompletedOutcomeUpgrade @badNext} 'non-execution'
    [IO.File]::WriteAllText((Join-Path $store 'tasks.json'),(ConvertTo-Json -InputObject ([pscustomobject]@{schemaVersion=1;tasks=[object[]]@($reservedTask)}) -Depth 20))
    $reservedTask.cpvPreparationRecovery.OutcomeRecoveryApprovalId=[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText((Join-Path $store 'tasks.json'),(ConvertTo-Json -InputObject ([pscustomobject]@{schemaVersion=1;tasks=[object[]]@($reservedTask)}) -Depth 20))
    Reject {Assert-CpvCompletedOutcomeUpgrade @reservedArgs} 'unexpected outcome recovery reservation'
    $reservedTask.cpvPreparationRecovery.OutcomeRecoveryApprovalId=$reservationId
    $reservedTask.cpvPreparationRecovery.OutcomeRecoveryRequest.requestId=[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText((Join-Path $store 'tasks.json'),(ConvertTo-Json -InputObject ([pscustomobject]@{schemaVersion=1;tasks=[object[]]@($reservedTask)}) -Depth 20))
    Reject {Assert-CpvCompletedOutcomeUpgrade @reservedArgs} 'unexpected outcome recovery reservation'
    $reservedTask.cpvPreparationRecovery.OutcomeRecoveryRequestHash='not-a-hash'
    $reservedTask.cpvPreparationRecovery.OutcomeRecoveryRequest=$recoveryRequest
    [IO.File]::WriteAllText((Join-Path $store 'tasks.json'),(ConvertTo-Json -InputObject ([pscustomobject]@{schemaVersion=1;tasks=[object[]]@($reservedTask)}) -Depth 20))
    Reject {Assert-CpvCompletedOutcomeUpgrade @reservedArgs} 'unexpected outcome recovery reservation'
    [IO.File]::WriteAllText((Join-Path $store 'tasks.json'),(ConvertTo-Json -InputObject ([pscustomobject]@{schemaVersion=1;tasks=[object[]]@($roundTrip)}) -Depth 20))
    $wrongVersion=@{}+$args;$wrongVersion.ExpectedInstalledVersion='1.0.18+4b0066247088';Reject {Assert-CpvCompletedOutcomeUpgrade @wrongVersion} 'restricted to the exact active request'
    $oldRoot=Join-Path $testRelease 'Repato.QaLaunchAgent-1.0.19+05933ab8b587';New-Item -ItemType Directory -Path $oldRoot -Force|Out-Null
    foreach($n in $fileNames){[IO.File]::WriteAllText((Join-Path $oldRoot $n),('old '+$n))}
    $oldFiles=@(foreach($n in $fileNames){[pscustomobject]@{name=$n;sha256=(Get-Hash (Join-Path $oldRoot $n))}})
    $oldRelease=[ordered]@{schemaVersion=1;product='Repato.QaLaunchAgent';productVersion='1.0.19+05933ab8b587';sourceCommit=('05933ab8b587'.PadRight(40,'0'));account='RAMSAI\RepatoQA';sid='S-1-5-21-1031246752-3872016183-2454652381-1015';files=$oldFiles}
    $oldManifest=Join-Path $oldRoot 'Repato.QaLaunchAgent.release.json';$oldRelease|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $oldManifest -Encoding UTF8;$oldManifestHash=Get-Hash $oldManifest
    $oldCandidate=@{}+$args;$oldCandidate.CandidateRoot=$oldRoot;$oldCandidate.CandidateManifestPath=$oldManifest;$oldCandidate.CandidateManifestSha256=$oldManifestHash
    Reject {Assert-CpvCompletedOutcomeUpgrade @oldCandidate} 'pinned agent-release catalog'
    $prevRoot=Join-Path $testRelease 'Repato.QaLaunchAgent-1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e';New-Item -ItemType Directory -Path $prevRoot -Force|Out-Null
    foreach($n in $fileNames){[IO.File]::WriteAllText((Join-Path $prevRoot $n),('prev '+$n))}
    $prevFiles=@(foreach($n in $fileNames){[pscustomobject]@{name=$n;sha256=(Get-Hash (Join-Path $prevRoot $n))}})
    $prevRelease=[ordered]@{schemaVersion=1;product='Repato.QaLaunchAgent';productVersion='1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e';sourceCommit='09eef230b24bd1169da8b99e2bdf9b5d3b32c40e';account='RAMSAI\RepatoQA';sid='S-1-5-21-1031246752-3872016183-2454652381-1015';files=$prevFiles}
    $prevManifest=Join-Path $prevRoot 'Repato.QaLaunchAgent.release.json';$prevRelease|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $prevManifest -Encoding UTF8;$prevManifestHash=Get-Hash $prevManifest
    $prevCandidate=@{}+$args;$prevCandidate.CandidateRoot=$prevRoot;$prevCandidate.CandidateManifestPath=$prevManifest;$prevCandidate.CandidateManifestSha256=$prevManifestHash
    Reject {Assert-CpvCompletedOutcomeUpgrade @prevCandidate} 'pinned agent-release catalog'
    $wrongManifest=@{}+$args;$wrongManifest.CandidateManifestSha256=('0'*64);Reject {Assert-CpvCompletedOutcomeUpgrade @wrongManifest} 'manifest is not pinned'
    $oldInstalled=@{}+$args;$oldInstalled.InstalledAgent=[pscustomobject]@{ProcessName=$installedIdentity.ProcessName;Path=$installedIdentity.Path;ProductVersion='1.0.19+05933ab8b587';Id=$installedIdentity.Id;StartTime=$installedIdentity.StartTime;User=$installedIdentity.User;Sid=$installedIdentity.Sid;SessionId=$installedIdentity.SessionId}
    Reject {Assert-CpvCompletedOutcomeUpgrade @oldInstalled} 'process owner, version, path, or session is invalid'
    $staleJournalPath=Join-Path $temp 'StaleBootstrap.psm1';@'
function Read-InstallJournal { param($Path,$TargetRoot) [pscustomobject]@{state='Committed';generation=13;candidateVersion='1.0.18+4b0066247088';requestId='c11b311638a54bfc9ebdd1803671ec40';taskId='task-bf61fe7f22d74df7a92599681da5919e';journalSha256=('D'*64)} }
'@|Set-Content -LiteralPath $staleJournalPath -Encoding UTF8;$staleBootstrap=Import-Module $staleJournalPath -Force -PassThru;$staleJournal=@{}+$args;$staleJournal.BootstrapModule=$staleBootstrap;Reject {Assert-CpvCompletedOutcomeUpgrade @staleJournal} 'generation-13'
    $unknownJournalPath=Join-Path $temp 'UnknownBootstrap.psm1';@'
function Read-InstallJournal { param($Path,$TargetRoot) [pscustomobject]@{state='Committed';generation=13;candidateVersion='1.0.19+05933ab8b587';requestId='deadbeefdeadbeefdeadbeefdeadbeef';taskId='task-bf61fe7f22d74df7a92599681da5919e';journalSha256=('D'*64)} }
'@|Set-Content -LiteralPath $unknownJournalPath -Encoding UTF8;$unknownBootstrap=Import-Module $unknownJournalPath -Force -PassThru;$unknownJournal=@{}+$args;$unknownJournal.BootstrapModule=$unknownBootstrap;Reject {Assert-CpvCompletedOutcomeUpgrade @unknownJournal} 'generation-13'
    $savedManifestPath=$runner.selectedManifestPath
    $runner.selectedManifestPath=Join-Path (Split-Path $deployedManifest) 'Other.addin';$runner|ConvertTo-Json -Compress|Set-Content -LiteralPath $runnerPath -Encoding UTF8
    $badManifestName=@{}+$args;Reject {Assert-CpvCompletedOutcomeUpgrade @badManifestName} 'Frozen fixture|inconsistent'
    $runner.selectedManifestPath=$savedManifestPath;$runner|ConvertTo-Json -Compress|Set-Content -LiteralPath $runnerPath -Encoding UTF8
    [IO.File]::AppendAllText($model,'tampered');$badModel=@{}+$args;Reject {Assert-CpvCompletedOutcomeUpgrade @badModel} 'Frozen fixture|inconsistent'
    $installer=Get-Content (Join-Path $PSScriptRoot 'Install-CpvPreparationAgentCandidate.ps1') -Raw
    Check ($installer.Contains('$CompletedOutcomeRecoveryRequestId') -and $installer.Contains('Assert-CpvCompletedOutcomeUpgrade') -and $installer.Contains('recoveryStatusOperation')) 'supported installer has a distinct protected-marker recovery-upgrade branch'
    Check (!$installer.Contains("operation='cpv-preparation-reconcile-failed'") -and !$installer.Contains("operation='prepare-cpv-fixture'")) 'upgrade branch reads status only and never dispatches preparation or reconciliation'
    Check ($installer.Contains("`$expectedCompletedVersion='1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e'")) 'installer preserves the exact installed 1.0.20 runtime baseline'
    $guardText=Get-Content (Join-Path $PSScriptRoot 'Repato.CpvCompletedOutcomeUpgrade.psm1') -Raw
    Check ($guardText.Contains('1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e') -and $guardText.Contains('1\.0\.21\+[A-Fa-f0-9]{12,40}') -and $guardText.Contains('590da474d11d42e2b2fedbf99edaba03')) 'completed-outcome guard pins the 1.0.21 candidate and the exact stale reservation'
    $bootstrapText=Get-Content (Join-Path $PSScriptRoot '..\QaLaunchAgent\Repato.QaLaunchAgent.Bootstrap.psm1') -Raw
    Check ($bootstrapText.Contains("'1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e'") -and $bootstrapText.Contains('1\.0\.21\+[A-Fa-f0-9]{12,40}')) 'install journal validates the 1.0.20 baseline and the 1.0.21 candidate identity'
    'PASS: '+$script:assertions+' completed-outcome upgrade assertions; synthetic journal/runtime only; Revit launched=false.'
} finally {
    foreach($path in @($testRelease,$temp)){ $full=[IO.Path]::GetFullPath($path);$base=if($path -eq $testRelease){[IO.Path]::GetFullPath($releaseCatalog).TrimEnd('\')+'\'}else{[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'};if($full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $full)){Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue} }
}
