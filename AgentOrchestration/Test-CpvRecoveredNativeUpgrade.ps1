$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $PSScriptRoot 'Repato.CpvRecoveredNativeUpgrade.psm1') -Force -PassThru -WarningAction SilentlyContinue
& $module {
    # Every filesystem/store/provenance dependency is synthetic; no production paths are opened.
    $script:hash='A'*64;$script:modelHash='B'*64;$script:version='1.0.22+6119aceaab0a34c3e0323089a29f1cefb2c14aaa'
    $id='task-bf61fe7f22d74df7a92599681da5919e';$requestId='c11b311638a54bfc9ebdd1803671ec40';$user='RAMSAI\RepatoQA';$sid='S-1-5-21-1031246752-3872016183-2454652381-1015'
    $request=[pscustomobject]@{requestId=$requestId;taskId=$id;workflowId=('c'*32);attemptId=('d'*32);runId=('e'*32)}
    $runtime='C:\synthetic\runtime';$run=Join-Path $runtime ('cpv-preparation-'+$request.runId);$model=Join-Path $run 'model.rvt'
    $receipt=[pscustomobject]@{requestId=$requestId;taskId=$id;workflowId=$request.workflowId;attemptId=$request.attemptId;runId=$request.runId;modelPath=$model}
    $snapshot=[pscustomobject]@{OriginalReceiptSha256=$script:hash;ActiveMarkerSha256=$script:hash;FailureEvidenceSha256=$script:hash;PreparationRequestSha256=$script:hash;ResultSha256=$script:hash;ModelSha256=$script:modelHash}
    $binding=[pscustomobject]@{ExpectedTaskRevision=123;Snapshot=$snapshot}
    $approval=[pscustomobject]@{requestId='b38d9717f0164715a4a9fdbbf21191bd';status='approved';action='cpv-preparation-outcome-recovery';consumedUtc='2026-10-19T16:07:00Z';expiresUtc='2026-10-19T16:29:34Z';outcomeRecoveryBinding=$binding;bindingHash=(Get-CpvNativeUpgradeHash $binding)}
    $commit=[pscustomobject]@{Receipt=$receipt;RecoveryApprovalId=$approval.requestId;ApprovalBindingHash=$approval.bindingHash;ExpectedTaskRevision=123;OriginalReceiptSha256=$script:hash;ActiveMarkerSha256=$script:hash;FailureEvidenceSha256=$script:hash;RequestSha256=$script:hash;ResultSha256=$script:hash;ModelSha256=$script:modelHash;RecoveredProvenanceSha256=$script:hash;RecoveredProvenancePath=($model+'.recovered.fixture.json')}
    $script:task=[pscustomobject]@{revision=127;status='in-progress';workflowStage='qa';deploymentWorkflows=@([pscustomobject]@{workflowId=$request.workflowId});approvalRequests=@($approval);cpvPreparationRecovery=[pscustomobject]@{Status='RecoveredVerified';Request=$request;RequestHash=(Get-CpvNativeUpgradeHash $request);OutcomeRecoveryApprovalId=$approval.requestId;OutcomeRecoveryReceipt=$commit}}
    $names=@('Repato.QaLaunchAgent.exe','Repato.QaLaunchAgent.dll','Repato.QaLaunchAgent.deps.json','Repato.QaLaunchAgent.runtimeconfig.json')
    $entries=@($names|ForEach-Object{[pscustomobject]@{name=$_;sha256=$script:hash}})
    $script:priorPins=@{'Repato.QaLaunchAgent.exe'='0A947BBD24C8A95CDB5C0AE94AA586ACE922765438DD1430FA4F1BBB8EF737CD';'Repato.QaLaunchAgent.dll'='F22C2E694ABE9A23893A97FFEE804D453191A60C031F48855DB071869A677F03';'Repato.QaLaunchAgent.deps.json'='78FEBC5E3DEB35F8A46125FB39EA36F30CDFE4DB154F76B49502FE92792259D4';'Repato.QaLaunchAgent.runtimeconfig.json'='CA1A6B5B185174698E0F5F9AE732AD3D2D3ED5B122ED666F35CC214283E83B7F'}
    $prior=@($names|ForEach-Object{[pscustomobject]@{name=$_;sha256=$script:priorPins[$_]}})
    $script:manifest=[pscustomobject]@{product='Repato.QaLaunchAgent';account=$user;sid=$sid;productVersion=('1.0.23+'+('f'*40));files=$entries}
    $candidate=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\DeploymentCandidates\AgentReleases'))) ('Repato.QaLaunchAgent-'+$script:manifest.productVersion)
    $script:side=[pscustomobject]@{recoveryApprovalId=$approval.requestId;approvalBindingHash=$approval.bindingHash}
    function Read-RepatoTaskStore($root){[pscustomobject]@{tasks=@($script:task)}}
    function Find-RepatoTask($store,$id){$script:task}
    function Get-FileHash {param($LiteralPath,$Algorithm) [pscustomobject]@{Hash=$(if($LiteralPath -like 'C:\synthetic\agent\*'){$script:priorPins[(Split-Path $LiteralPath -Leaf)]}elseif($LiteralPath -like '*model.rvt'){$script:modelHash}else{$script:hash})}}
    function Get-Content {param($LiteralPath,[switch]$Raw) $script:manifest|ConvertTo-Json -Depth 8}
    function Test-Path {param($LiteralPath) $false}
    function Read-CpvFixtureProvenance {param($SidecarPath,$ExpectedRecoveredProvenanceSha256) $script:side}
    $script:continuationCalls=0
    function New-CpvNativeContinuationBinding {param($Task,$Workflow,$ExpectedTaskRevision)$script:continuationCalls++;if($script:rejectContinuation){throw 'Synthetic continuation evidence mismatch.'};[pscustomobject]@{SchemaVersion='synthetic'}}
    $script:rejectContinuation=$false
    $journal=[pscustomobject]@{state='Committed';generation=13;candidateVersion=$script:version;priorVersion='1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f';taskId=$id;requestId=$requestId;journalSha256=$script:hash}
    $bootstrap=New-Module -ArgumentList $journal -ScriptBlock {param($j)$script:journal=$j;function Read-InstallJournal($p,$t){$script:journal}}
    $caps=[pscustomobject]@{operation='cpv-preparation-capabilities';supported=$true;user=$user;sid=$sid;sessionId=1;runtimeVersion=$script:version}
    $agent=[pscustomobject]@{ProcessName='Repato.QaLaunchAgent';Path='C:\synthetic\agent\Repato.QaLaunchAgent.exe';ProductVersion=$script:version;User=$user;Sid=$sid;SessionId=1;Id=123;StartTime='2026-10-19T16:00:00Z'}
    $args=@{EvidenceRoot='C:\synthetic\evidence';RuntimeRoot=$runtime;RequestId=$requestId;TaskId=$id;ExpectedTaskRevision=127;StoreRoot='C:\synthetic\store';Capabilities=$caps;RecoveryReceipt=$commit;InstalledAgent=$agent;ProcessSid=$sid;ExpectedExecutable=$agent.Path;ExpectedInstalledVersion=$script:version;CandidateRoot=$candidate;CandidateManifestPath=(Join-Path $candidate 'Repato.QaLaunchAgent.release.json');CandidateManifestSha256=$script:hash;PriorRuntimeFiles=$prior;PriorTaskContractValid=$true;NoRevitProcesses=$true;BootstrapModule=$bootstrap}
    $script:assertions=0
    function Check($v){$script:assertions++;if(!$v){throw 'Recovered-native upgrade assertion failed.'}}
    function Reject($a){$script:assertions++;try{$null=&$a;throw 'Unexpected acceptance'}catch{if($_.Exception.Message -ceq 'Unexpected acceptance'){throw}}}
    $before=$script:task|ConvertTo-Json -Depth 30 -Compress
    $result=Assert-CpvRecoveredNativeUpgrade @args
    Check ($result.CandidateVersion -ceq $script:manifest.productVersion -and $result.JournalGeneration -eq 13 -and $result.RunDirectory -ceq $run)
    Check ($script:continuationCalls -eq 1)
    $script:rejectContinuation=$true;Reject {Assert-CpvRecoveredNativeUpgrade @args};$script:rejectContinuation=$false
    foreach($name in 'mayaTaraQaPacket','mayaTaraAttempt','mayaTaraExecution'){$task|Add-Member NoteProperty $name ([pscustomobject]@{ClaimId='synthetic'});Reject {Assert-CpvRecoveredNativeUpgrade @args};$task.PSObject.Properties.Remove($name)}
    $bad=@{}+$args;$bad.PriorRuntimeFiles=$entries;Reject {Assert-CpvRecoveredNativeUpgrade @bad}
    foreach($pair in @(@('ExpectedTaskRevision',128),@('RequestId','other'),@('ProcessSid','wrong'),@('ExpectedInstalledVersion','1.0.21+other'),@('PriorTaskContractValid',$false),@('NoRevitProcesses',$false),@('CandidateManifestSha256',('0'*64)))){$bad=@{}+$args;$bad[$pair[0]]=$pair[1];Reject {Assert-CpvRecoveredNativeUpgrade @bad}}
    $task.revision=128;Reject {Assert-CpvRecoveredNativeUpgrade @args};$task.revision=127
    $task.cpvPreparationRecovery.Status='Dispatching';Reject {Assert-CpvRecoveredNativeUpgrade @args};$task.cpvPreparationRecovery.Status='RecoveredVerified'
    $oldHash=$task.cpvPreparationRecovery.RequestHash;$task.cpvPreparationRecovery.RequestHash='0'*64;Reject {Assert-CpvRecoveredNativeUpgrade @args};$task.cpvPreparationRecovery.RequestHash=$oldHash
    $task.approvalRequests+=([pscustomobject]@{status='pending'});Reject {Assert-CpvRecoveredNativeUpgrade @args};$task.approvalRequests=@($approval)
    $bad=@{}+$args;$bad.RecoveryReceipt=$commit|ConvertTo-Json -Depth 15|ConvertFrom-Json;$bad.RecoveryReceipt.ModelSha256='0'*64;Reject {Assert-CpvRecoveredNativeUpgrade @bad}
    $approval.consumedUtc='2026-10-19T17:00:00Z';Reject {Assert-CpvRecoveredNativeUpgrade @args};$approval.consumedUtc='2026-10-19T16:07:00Z'
    $journal.generation=14;Reject {Assert-CpvRecoveredNativeUpgrade @args};$journal.generation=13
    $side.approvalBindingHash='0'*64;Reject {Assert-CpvRecoveredNativeUpgrade @args};$side.approvalBindingHash=$approval.bindingHash
    Check (($script:task|ConvertTo-Json -Depth 30 -Compress) -ceq $before)
    "PASS: $script:assertions recovered-native upgrade assertions; pure synthetic, no production IO."
}
