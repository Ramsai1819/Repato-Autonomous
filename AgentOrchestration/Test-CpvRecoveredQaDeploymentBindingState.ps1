$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvNativeContinuation.psm1') -Force
$root=Join-Path ([IO.Path]::GetTempPath()) ('cpv-native-contract-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
$count=0
function Check($ok,$message){if(!$ok){throw $message};$script:count++}
function Reject([scriptblock]$body){$failed=$false;try{& $body}catch{$failed=$true};Check $failed 'Expected rejection.'}
function Clone($x){$x|ConvertTo-Json -Depth 40|ConvertFrom-Json}
function Hash($x){$s=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($s.ComputeHash([Text.Encoding]::UTF8.GetBytes(($x|ConvertTo-Json -Depth 40 -Compress))))).Replace('-','')}finally{$s.Dispose()}}
function Write-Fixture($name,$bytes){$path=Join-Path $root $name;[IO.File]::WriteAllText($path,$bytes);[pscustomobject]@{Path=$path;Hash=(Get-FileHash $path).Hash}}
$model=Write-Fixture 'model.rvt' 'synthetic model';$request=Write-Fixture 'request.json' '{}';$result=Write-Fixture 'result.json' '{}';$old=Write-Fixture 'model.rvt.fixture.json' '{"fixtureId":"CreatePlanViewsEmpty"}';$dll=Write-Fixture 'native.dll' 'new synthetic candidate'
$historic=Write-Fixture 'historical.dll' 'historical';$historicManifest=Write-Fixture 'historical.addin' 'historical';$historicProvenance=Write-Fixture 'historical-release.json' 'historical';$sourceFixture=Write-Fixture 'source.rvt' 'historical';$fixtureProvenance=Write-Fixture 'source-provenance.json' 'historical'
$h=$historic.Hash;$expiry='2020-01-01T00:00:00Z';$attempt='a'*32;$run='b'*32
$q=[pscustomobject]@{requestId='request';taskId='task';workflowId='workflow';attemptId=$attempt;runId=$run;expiresUtc=$expiry;candidateEvidence=@{CandidateDllSha256=$h;RunnerManifestSha256=$h;CandidateSourceCommit=('a'*40)}}
$receipt=[pscustomobject]@{requestId='request';taskId='task';workflowId='workflow';attemptId=$attempt;runId=$run;expiresUtc=$expiry;status='Passed';user='RAMSAI\RepatoQA';sid='S-1-5-21-1031246752-3872016183-2454652381-1015';sessionId=1;operation='prepare-cpv-fixture';cleanupVerified=$true;rollbackStatus='CommittedDisposableFixtureOnly';candidateSha256=$h;manifestSha256=$h;modelPath=$model.Path;modelSha256=$model.Hash;requestPath=$request.Path;requestSha256=$request.Hash;resultPath=$result.Path;resultSha256=$result.Hash}
$companion=@{recoveredFromOutcomeUnknown=$true;taskId='task';workflowId='workflow';requestId='request';preparedModelSha256=$model.Hash;approvalBindingHash=$h;recoveryApprovalId='historical';fixturePreparationAttemptId=$attempt;fixturePreparationRunId=$run;sourceSha256=$h;fixturePreparationRequestSha256=$request.Hash;fixturePreparationResultSha256=$result.Hash;historicalSidecarPath=$old.Path;historicalSidecarSha256=$old.Hash}
$comp=Write-Fixture 'model.rvt.recovered.fixture.json' ($companion|ConvertTo-Json -Compress)
$commit=[pscustomobject]@{RecoveryApprovalId='historical';ApprovalBindingHash=$h;Receipt=$receipt;RecoveredProvenancePath=$comp.Path;RecoveredProvenanceSha256=$comp.Hash}
$prep=[pscustomobject]@{AttemptId=$attempt;RunId=$run;ExpiresUtc=$expiry;PreparedModelPath=$model.Path;PreparedModelSha256=$model.Hash;RequestPath=$request.Path;RequestSha256=$request.Hash;ResultPath=$result.Path;ResultSha256=$result.Hash;RecoveredProvenancePath=$comp.Path;RecoveredProvenanceSha256=$comp.Hash;SourceSha256=$h}
$workflow=[pscustomobject]@{taskId='task';workflowId='workflow';qaWorkflowId='create-plan-views-v1';qaRunId=$run;qaModelPath=$model.Path;qaSidecarPath=$old.Path;qaDisposableModelSha256=$model.Hash;qaFixturePreparationEvidence=$prep;qaBuildEvidence=[pscustomobject]@{ArtifactPath=$dll.Path;ArtifactSha256=$dll.Hash;CandidateSourceCommit=('b'*40);BuildStatus='succeeded';EvidenceSource='FrozenCandidate';BuildRequestId='new-build'}}
$task=[pscustomobject]@{taskId='task';revision=127;cpvPreparationRecovery=[pscustomobject]@{Status='RecoveredVerified';Request=$q;OutcomeRecoveryReceipt=$commit};approvalRequests=@([pscustomobject]@{requestId='historical';action='cpv-preparation-recover-completed';status='approved';consumedUtc='2020-01-01T00:00:00Z';expiresUtc='2020-01-01T01:00:00Z';bindingHash=$h})}
$q.candidateEvidence['CandidateDllPath']=$historic.Path;$q.candidateEvidence['RunnerManifestPath']=$historicManifest.Path;$q.candidateEvidence['CandidateProvenancePath']=$historicProvenance.Path
$task.cpvPreparationRecovery|Add-Member NoteProperty PreparationBinding ([pscustomobject]@{TaskId='task';WorkflowId='workflow';CandidateSourceCommit=('a'*40);CandidateSha256=$h;CandidateProvenancePath=$historicProvenance.Path;CandidateProvenanceSha256=$h;RunnerManifestPath=$historicManifest.Path;RunnerManifestSha256=$h;FixturePath=$sourceFixture.Path;FixtureSha256=$h;FixtureProvenancePath=$fixtureProvenance.Path;FixtureProvenanceSha256=$h})
$task|Add-Member NoteProperty status 'in-progress';$task|Add-Member NoteProperty workflowStage 'qa'
$task|Add-Member NoteProperty deploymentWorkflows @($workflow)
$workflow|Add-Member NoteProperty qaBuildStatus 'succeeded'
$workflow|Add-Member NoteProperty qaBuildRequest ([pscustomobject]@{BuildRequestId='new-build'})
$workflow.qaBuildEvidence|Add-Member NoteProperty SourceCommit ('b'*40)
$guard=@{ExpectedTaskRevision=127;TaskId='task';WorkflowId='workflow';BuildRequestId='new-build';CandidateSourceCommit=('b'*40);CandidateSha256=$dll.Hash}
$before=Hash $task
$binding=Assert-CpvRecoveredQaDeploymentBindingState -Task $task -Workflow $workflow @guard
Check ($binding.SchemaVersion -ceq 'cpv-native-continuation-v1') 'Recovered QA-ready deployment binding rejected.'
Check ((Hash $task) -ceq $before) 'Read-only binding validator modified task.'
foreach($field in 'status','workflowStage','revision','taskId'){
    $bad=Clone $task;$bad.$field=switch($field){status{'passed'}workflowStage{'build-checks'}revision{128}taskId{'other'}}
    Reject {Assert-CpvRecoveredQaDeploymentBindingState -Task $bad -Workflow $bad.deploymentWorkflows[0] @guard}
}
foreach($name in 'mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'){
    $bad=Clone $task;$bad|Add-Member NoteProperty $name ([pscustomobject]@{Stage='prepared'})
    Reject {Assert-CpvRecoveredQaDeploymentBindingState -Task $bad -Workflow $bad.deploymentWorkflows[0] @guard}
}
foreach($approval in @([pscustomobject]@{action='other';status='pending';consumedUtc=$null},[pscustomobject]@{action='qa-run';status='approved';consumedUtc=$null})){
    $bad=Clone $task;$bad.approvalRequests=@($bad.approvalRequests)+$approval
    Reject {Assert-CpvRecoveredQaDeploymentBindingState -Task $bad -Workflow $bad.deploymentWorkflows[0] @guard}
}
foreach($status in 'Dispatching','OutcomeUnknown','NotExecuted'){
    $bad=Clone $task;$bad.cpvPreparationRecovery.Status=$status
    Reject {Assert-CpvRecoveredQaDeploymentBindingState -Task $bad -Workflow $bad.deploymentWorkflows[0] @guard}
}
$bad=Clone $task;$bad.PSObject.Properties.Remove('cpvPreparationRecovery');Reject {Assert-CpvRecoveredQaDeploymentBindingState -Task $bad -Workflow $bad.deploymentWorkflows[0] @guard}
foreach($property in 'BuildRequestId','CandidateSourceCommit','SourceCommit','ArtifactSha256','BuildStatus','EvidenceSource'){
    $bad=Clone $task;$bad.deploymentWorkflows[0].qaBuildEvidence.$property='invalid'
    Reject {Assert-CpvRecoveredQaDeploymentBindingState -Task $bad -Workflow $bad.deploymentWorkflows[0] @guard}
}
$detached=Clone $workflow;$detached.qaBuildRequest.BuildRequestId='other';Reject {Assert-CpvRecoveredQaDeploymentBindingState -Task $task -Workflow $detached @guard}
$bad=Clone $task;$bad.deploymentWorkflows=@($bad.deploymentWorkflows)+$bad.deploymentWorkflows[0];Reject {Assert-CpvRecoveredQaDeploymentBindingState -Task $bad -Workflow $workflow @guard}
$bad=Clone $task;$bad|Add-Member NoteProperty taraRuns @([pscustomobject]@{status='running'});Reject {Assert-CpvRecoveredQaDeploymentBindingState -Task $bad -Workflow $bad.deploymentWorkflows[0] @guard}
$bad=Clone $task;$bad.cpvPreparationRecovery.OutcomeRecoveryReceipt.Receipt.modelSha256='A'*64;Reject {Assert-CpvRecoveredQaDeploymentBindingState -Task $bad -Workflow $bad.deploymentWorkflows[0] @guard}
foreach($file in @($historic,$historicManifest,$historicProvenance,$sourceFixture,$fixtureProvenance)){
    [IO.File]::WriteAllText($file.Path,'tampered');Reject {Assert-CpvRecoveredQaDeploymentBindingState -Task $task -Workflow $workflow @guard};[IO.File]::WriteAllText($file.Path,'historical')
}
[IO.File]::WriteAllText($dll.Path,'tampered');Reject {Assert-CpvRecoveredQaDeploymentBindingState -Task $task -Workflow $workflow @guard};[IO.File]::WriteAllText($dll.Path,'new synthetic candidate')
Check ((Get-FileHash $old.Path).Hash -ceq $old.Hash) 'Protected historical sidecar changed.'
Check ($prep.ExpiresUtc -ceq $expiry -and (Hash $task) -ceq $before) 'Original expiry or task changed.'
Write-Output "Recovered QA deployment binding: $count assertions passed; synthetic root=$root"
