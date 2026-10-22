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
$binding=New-CpvNativeContinuationBinding $task $workflow 127
Check ($binding.HistoricalPreparationExpiresUtc -ceq $expiry) 'Historical expiry changed.'
Check ($binding.NativeCandidateSha256 -ine $binding.HistoricalPreparationCandidateSha256) 'Distinct candidate lineage required.'
Assert-CpvNativeContinuationBinding $task $workflow $binding;Check $true 'Valid lineage'
$b=[pscustomobject][ordered]@{TaskId='task';WorkflowId='workflow';CandidateSha256=$dll.Hash;CandidateSourceCommit=('b'*40);NativeContinuation=$binding}
$now=[DateTimeOffset]::Parse('2030-01-01T00:00:00Z')
$approval=[pscustomobject]@{requestId='fresh-native';action='qa-run';requiredLevel='user';status='approved';decidedBy='user';decidedUtc=$now.AddMinutes(-1).ToString('O');expiresUtc=$now.AddMinutes(10).ToString('O');consumedUtc=$null;executionBinding=$b;bindingHash=(Hash $b)}
$task.approvalRequests=@($task.approvalRequests)+$approval
$resolved=Resolve-CpvNativeContinuationExpiry $task $workflow $approval -NowUtc $now
Check ($resolved -eq $now.AddMinutes(10)) 'Fresh approval expiry cap not enforced.'
foreach($n in 'status','requiredLevel','decidedBy','consumedUtc','expiresUtc','bindingHash'){$bad=Clone $approval;$bad.$n=switch($n){status{'pending'}requiredLevel{'maya'}decidedBy{'Maya'}consumedUtc{$now.ToString('O')}expiresUtc{$now.ToString('O')}bindingHash{'B'*64}};$badTask=Clone $task;$badTask.approvalRequests[1]=$bad;Reject {Resolve-CpvNativeContinuationExpiry $badTask $workflow $bad -NowUtc $now}}
foreach($n in 'PreparedModelSha256','ExpiresUtc','RecoveredProvenanceSha256','AttemptId','RequestSha256'){$bad=Clone $workflow;$bad.qaFixturePreparationEvidence.$n='invalid';Reject {New-CpvNativeContinuationBinding $task $bad 127}}
$bad=Clone $task;$bad.cpvPreparationRecovery.Status='Dispatching';Reject {New-CpvNativeContinuationBinding $bad $workflow 127}
$bad=Clone $binding;$bad.NativeCandidateSha256=$h;Reject {Assert-CpvNativeContinuationBinding $task $workflow $bad}
$bad=Clone $binding;$bad.SourceTaskRevision=128;Reject {Assert-CpvNativeContinuationBinding $task $workflow $bad}
$bad=Clone $task;$bad.cpvPreparationRecovery.OutcomeRecoveryReceipt.Receipt.candidateSha256='B'*64;Reject {New-CpvNativeContinuationBinding $bad $workflow 127}
Reject {New-CpvNativeContinuationBinding $task $workflow 126}
foreach($file in @($historic,$historicManifest,$historicProvenance,$sourceFixture,$fixtureProvenance)){
    [IO.File]::WriteAllText($file.Path,'tampered')
    Reject {New-CpvNativeContinuationBinding $task $workflow 127}
    [IO.File]::WriteAllText($file.Path,'historical')
}
Check ((Get-FileHash $old.Path).Hash -ceq $old.Hash) 'Historical evidence modified.'
Check ($prep.ExpiresUtc -ceq $expiry) 'Preparation expiry modified.'
$parseTokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1'),[ref]$parseTokens,[ref]$parseErrors)
Check (@($parseErrors).Count -eq 0) 'Approval decision source parse failed.'
$gate=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.IfStatementAst] -and $node.Extent.Text.StartsWith("if(`$preparation -and `$preparation.PSObject.Properties['RecoveredProvenanceSha256'])")},$true))
Check ($gate.Count -eq 1) 'Decision continuation guard missing.'
$decisionGate=[scriptblock]::Create($gate[0].Extent.Text)
$runnerRequestFixture=$request;$workflows=@($workflow);$preparation=$prep;$bindingForDecision=$b;$binding=$b;$requestForDecision=$approval;$request=$approval;$Actor='user'
& $decisionGate;Check $true 'Valid decision continuation rejected.'
$Actor='Maya';Reject {& $decisionGate};$Actor='user'
$binding=Clone $b;$binding.PSObject.Properties.Remove('NativeContinuation');Reject {& $decisionGate};$binding=$bindingForDecision
$nativeRequest=[ordered]@{expiresUtc=$approval.expiresUtc};Add-CpvNativeCompanionRequestBinding $nativeRequest $prep
Check ($nativeRequest.recoveredProvenanceSha256 -ceq $comp.Hash) 'Native request companion hash missing.'
$partial=Clone $prep;$partial.PSObject.Properties.Remove('RecoveredProvenancePath');Reject {Add-CpvNativeCompanionRequestBinding ([ordered]@{}) $partial}
$m=Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -PassThru -WarningAction SilentlyContinue
$approval.decidedUtc=[DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('O');$approval.expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(10).ToString('O')
$workflow|Add-Member NoteProperty qaHandoff ([pscustomobject]@{HandoffId='handoff';NativeTestId='create-plan-views-v1';ArtifactPath=$dll.Path;ArtifactSha256=$dll.Hash;ManifestPath=$request.Path;ManifestSha256=$request.Hash;RunnerManifestPath=$result.Path;RunnerManifestSha256=$result.Hash;QaApprovalId='fresh-native'})
$workflow|Add-Member NoteProperty qaFixtureSha256 $h
& $m {param($t,$w) $script:ContinuationSyntheticTask=$t;$script:ContinuationSyntheticWorkflow=$w;function script:Get-DeployWorkflow {param($StoreRoot,$TaskId,$WorkflowId) $script:ContinuationSyntheticWorkflow};function script:Read-RepatoTaskStore {param($StoreRoot) $script:ContinuationSyntheticTask};function script:Find-RepatoTask {param($Data,$TaskId) $Data}} $task $workflow
$prepared=New-MayaQaCanonicalPreparation -StoreRoot $root -TaskId task -WorkflowId workflow -QaWorkflowId create-plan-views-v1 -DryRun
Check ([DateTimeOffset]::Parse($prepared.Attempt.RequestExpiresUtc) -le [DateTimeOffset]::Parse($approval.expiresUtc)) 'Canonical preparation exceeded fresh native approval.'
Check ($prepared.Packet.FixturePreparationEvidence.ExpiresUtc -ceq $expiry) 'Canonical preparation revived historical expiry.'
Check ($prepared.Attempt.AttemptId -ceq $attempt -and $prepared.Attempt.RunId -ceq $run) 'Historical attempt/run lineage changed.'
$approval.consumedUtc=[DateTimeOffset]::UtcNow.ToString('O');Reject {New-MayaQaCanonicalPreparation -StoreRoot $root -TaskId task -WorkflowId workflow -QaWorkflowId create-plan-views-v1 -DryRun};$approval.consumedUtc=$null
$approval.expiresUtc=[DateTimeOffset]::UtcNow.AddSeconds(-1).ToString('O');Reject {New-MayaQaCanonicalPreparation -StoreRoot $root -TaskId task -WorkflowId workflow -QaWorkflowId create-plan-views-v1 -DryRun}
$task|Add-Member NoteProperty status 'in-progress';$task|Add-Member NoteProperty workflowStage 'qa'
$workflow|Add-Member NoteProperty qaBuildStatus 'succeeded';$workflow|Add-Member NoteProperty qaBuildRequest ([pscustomobject]@{BuildRequestId='old-build'})
$task.approvalRequests=@($task.approvalRequests[0])
& $m {param($root) function script:Resolve-MayaQaAuthenticatedBuildSource {param($source) [pscustomobject]@{RepositoryRoot='synthetic';ProjectPath='synthetic';ExpectedSourceCommit=('b'*40)}};function script:Get-MayaQaTrustedBuildSourceCommit {param($RepositoryRoot,$ProjectPath) ('b'*40)}} $root
$expiredQaApproval=Clone $approval;$expiredQaApproval.expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('O');$task.approvalRequests=@($task.approvalRequests)+$expiredQaApproval
$replacement=New-MayaQaCandidateReplacementBuildRequest -StoreRoot $root -TaskId task -WorkflowId workflow -QaWorkflowId create-plan-views-v1 -PreserveRecoveredPreparation -ExpectedTaskRevision 127 -DryRun
Check ($replacement.BuildStatus -ceq 'planned') 'Recovered preparation replacement contract unsupported.'
Check ($workflow.qaFixturePreparationEvidence.ExpiresUtc -ceq $expiry -and $workflow.qaModelPath -ceq $model.Path) 'Replacement planning modified historical preparation.'
Reject {New-MayaQaCandidateReplacementBuildRequest -StoreRoot $root -TaskId task -WorkflowId workflow -QaWorkflowId create-plan-views-v1 -PreserveRecoveredPreparation -ExpectedTaskRevision 126 -DryRun}
Reject {New-MayaQaCandidateReplacementBuildRequest -StoreRoot $root -TaskId task -WorkflowId workflow -QaWorkflowId create-plan-views-v1 -DryRun}
$task.approvalRequests=@($task.approvalRequests[0]);$approval.expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(5).ToString('O');$task.approvalRequests=@($task.approvalRequests)+$approval
Reject {New-MayaQaCandidateReplacementBuildRequest -StoreRoot $root -TaskId task -WorkflowId workflow -QaWorkflowId create-plan-views-v1 -PreserveRecoveredPreparation -ExpectedTaskRevision 127 -DryRun}
Write-Output "CPV native continuation: $count assertions passed; synthetic root=$root"
