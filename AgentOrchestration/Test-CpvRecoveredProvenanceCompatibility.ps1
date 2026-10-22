$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvRecoveredProvenance.psm1') -Force
$maya=Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -PassThru -WarningAction SilentlyContinue
$root=Join-Path ([IO.Path]::GetTempPath()) ('cpv-provenance-'+[guid]::NewGuid().ToString('N'))
$count=0
function Assert-Check([bool]$ok,[string]$label){if(!$ok){throw "FAIL: $label"};$script:count++}
function Write-Json($path,$value){[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 30 -Compress),[Text.UTF8Encoding]::new($false))}
function Hash($path){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
function Reject([scriptblock]$action,[string]$label){$failed=$false;try{& $action|Out-Null}catch{$failed=$true};Assert-Check $failed $label}
try {
    $qa=Join-Path $root 'QA';$fixtures=Join-Path $qa 'Fixtures';$runtime=Join-Path $qa 'TestRuns';$run=Join-Path $runtime 'cpv-preparation-run';New-Item $fixtures,$run -ItemType Directory -Force|Out-Null
    $source=Join-Path $fixtures 'CreatePlanViewsEmpty.rvt';$model=Join-Path $run 'model.rvt';[IO.File]::WriteAllText($source,'source-fixture');[IO.File]::WriteAllText($model,'prepared-model')
    $sourceHash=Hash $source;$modelHash=Hash $model;$historical=$model+'.fixture.json';$recovered=$model+'.recovered.fixture.json'
    [IO.File]::WriteAllText($historical,"{`r`n  `"fixtureId`": `"CreatePlanViewsEmpty`",`r`n  `"sourceSha256`": `"$sourceHash`"`r`n}`r`n")
    $historicalHash=Hash $historical;$historicalBytes=[Convert]::ToBase64String([IO.File]::ReadAllBytes($historical))
    $requestPath=Join-Path $run 'tara-44444444444444444444444444444444.request.json';$resultPath=$requestPath+'.preparation.json'
    $request=[ordered]@{operation='prepare-disposable-create-plan-views-fixture';taskId='task-11111111111111111111111111111111';workflowId='22222222222222222222222222222222';requestId='33333333333333333333333333333333';attemptId='44444444444444444444444444444444';runId='55555555555555555555555555555555';modelPath=$model;modelSha256=$sourceHash;requestPath=$requestPath;outputPath=$resultPath}
    $result=[ordered]@{Operation='prepare-disposable-create-plan-views-fixture';Status='Passed';TaskId='task-11111111111111111111111111111111';WorkflowId='22222222222222222222222222222222';RequestId='33333333333333333333333333333333';AttemptId='44444444444444444444444444444444';RunId='55555555555555555555555555555555';ModelPath=$model;SourceModelSha256=$sourceHash;PreparedModelSha256=$modelHash}
    Write-Json $requestPath $request;Write-Json $resultPath $result
    $normal=[ordered]@{fixtureId='CreatePlanViewsEmpty';sourceSha256=$sourceHash;preparedModelSha256=$modelHash;fixturePreparationRequestPath=$requestPath;fixturePreparationRequestSha256=(Hash $requestPath);fixturePreparationResultPath=$resultPath;fixturePreparationResultSha256=(Hash $resultPath);fixturePreparationAttemptId='44444444444444444444444444444444';fixturePreparationRunId='55555555555555555555555555555555'}
    $provenance=[ordered]@{};foreach($key in $normal.Keys){$provenance[$key]=$normal[$key]}
    foreach($entry in @(@('schemaVersion',1),@('historicalSidecarPath',$historical),@('historicalSidecarSha256',$historicalHash),@('recoveredFromOutcomeUnknown',$true),@('taskId','task-11111111111111111111111111111111'),@('workflowId','22222222222222222222222222222222'),@('requestId','33333333333333333333333333333333'),@('recoveryApprovalId','66666666666666666666666666666666'),@('approvalBindingHash',('A'*64)),@('originalReceiptSha256',('B'*64)),@('activeMarkerSha256',('C'*64)),@('failureEvidenceSha256',('D'*64)),@('requestSha256',('E'*64)))){$provenance[$entry[0]]=$entry[1]}
    $validate={& $maya {param($qa,$source,$sh,$runtime,$model,$mh) Test-MayaQaCorrelatedDisposableFixtureProvenance -QaRoot $qa -TaskId 'task-11111111111111111111111111111111' -WorkflowId '22222222222222222222222222222222' -FixtureId 'CreatePlanViewsEmpty' -SourcePath $source -SourceSha256 $sh -RuntimeRoot $runtime -ModelPath $model -ModelSha256 $mh} $qa $source $sourceHash $runtime $model $modelHash}
    Reject $validate 'Historical source-only sidecar without recovered evidence rejected'
    Write-Json $recovered $provenance
    Assert-Check ((Read-CpvFixtureProvenance -SidecarPath $historical).preparedModelSha256 -eq $modelHash) 'Historical compatibility'
    Assert-Check ([bool](& $validate)) 'Actual downstream Maya validator accepts recovered provenance'
    $first=Read-CpvFixtureProvenance -SidecarPath $historical;$second=Read-CpvFixtureProvenance -SidecarPath $historical
    Assert-Check (($first|ConvertTo-Json -Compress) -ceq ($second|ConvertTo-Json -Compress)) 'Repeated validation is idempotent'
    foreach($field in @('historicalSidecarSha256','preparedModelSha256','fixturePreparationRequestSha256','fixturePreparationResultSha256')){
        $old=$provenance[$field];$provenance[$field]='0'*64;Write-Json $recovered $provenance
        Reject {Read-CpvFixtureProvenance -SidecarPath $historical} "Invalid $field rejected";Reject $validate "Downstream rejects invalid $field"
        $provenance[$field]=$old
    }
    foreach($field in @('recoveryApprovalId','approvalBindingHash','originalReceiptSha256','activeMarkerSha256','failureEvidenceSha256','requestSha256','taskId','workflowId','requestId','fixturePreparationAttemptId','fixturePreparationRunId')){
        $old=$provenance[$field];$provenance.Remove($field);Write-Json $recovered $provenance
        Reject {Read-CpvFixtureProvenance -SidecarPath $historical} "Missing $field rejected";$provenance[$field]=$old
    }
    foreach($field in @('taskId','workflowId','fixturePreparationAttemptId','fixturePreparationRunId')){
        $old=$provenance[$field];$provenance[$field]='77777777777777777777777777777777';Write-Json $recovered $provenance
        Reject {Read-CpvFixtureProvenance -SidecarPath $historical} "Replayed $field rejected";$provenance[$field]=$old
    }
    Write-Json $recovered $provenance
    $provenance.schemaVersion=2;Write-Json $recovered $provenance;Reject {Read-CpvFixtureProvenance -SidecarPath $historical} 'Unsupported recovered schema rejected';$provenance.schemaVersion=1;Write-Json $recovered $provenance
    Assert-Check ((Read-CpvFixtureProvenance -SidecarPath $historical -ExpectedRecoveredProvenanceSha256 (Hash $recovered)).preparedModelSha256 -eq $modelHash) 'Pinned recovered provenance hash accepted'
    Reject {Read-CpvFixtureProvenance -SidecarPath $historical -ExpectedRecoveredProvenanceSha256 ('0'*64)} 'Invalid pinned recovered provenance hash rejected'
    $savedResult=[IO.File]::ReadAllText($resultPath);[IO.File]::WriteAllText($resultPath,'{}');Reject $validate 'Changed result evidence rejected';[IO.File]::WriteAllText($resultPath,$savedResult)
    $result.Status='Failed';Write-Json $resultPath $result;$provenance.fixturePreparationResultSha256=Hash $resultPath;Write-Json $recovered $provenance;Reject $validate 'Failed preparation result rejected'
    [IO.File]::WriteAllText($resultPath,$savedResult);$provenance.fixturePreparationResultSha256=Hash $resultPath;Write-Json $recovered $provenance
    Assert-Check ((Hash $historical) -ceq $historicalHash) 'Historical evidence hash preserved'
    Assert-Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes($historical)) -ceq $historicalBytes) 'Historical evidence bytes preserved'
    # Exercise the actual Save consumer using an injected in-memory store and
    # synthetic agent root. No live task store, process or installed agent is used.
    $saveModule=Import-Module (Join-Path $PSScriptRoot 'Repato.CpvCompletedOutcomeRecovery.psm1') -Force -PassThru -WarningAction SilentlyContinue
    $saveRequest=[pscustomobject]@{taskId=$request.taskId;workflowId=$request.workflowId;requestId=$request.requestId;attemptId=$request.attemptId;runId=$request.runId;expiresUtc='2020-01-01T00:00:00Z';candidateEvidence=[pscustomobject]@{CandidateDllSha256=('1'*64);RunnerManifestSha256=('2'*64)}}
    $receipt=[pscustomobject]@{Status='Passed';operation='prepare-cpv-fixture';user='RAMSAI\RepatoQA';sid='S-1-5-21-1031246752-3872016183-2454652381-1015';sessionId=1;cleanupVerified=$true;rollbackStatus='CommittedDisposableFixtureOnly';taskId=$request.taskId;workflowId=$request.workflowId;requestId=$request.requestId;attemptId=$request.attemptId;runId=$request.runId;expiresUtc=$saveRequest.expiresUtc;candidateSha256=('1'*64);manifestSha256=('2'*64);modelPath=$model;modelSha256=$modelHash;requestPath=$requestPath;requestSha256=(Hash $requestPath);resultPath=$resultPath;resultSha256=(Hash $resultPath)}
    $commit=[pscustomobject]@{Receipt=$receipt;RecoveredProvenancePath=$recovered;RecoveredProvenanceSha256=(Hash $recovered);RecoveryApprovalId=$provenance.recoveryApprovalId;ApprovalBindingHash=$provenance.approvalBindingHash;OriginalReceiptSha256=$provenance.originalReceiptSha256;ActiveMarkerSha256=$provenance.activeMarkerSha256;FailureEvidenceSha256=$provenance.failureEvidenceSha256;RequestSha256=$provenance.requestSha256}
    $syntheticTask=[pscustomobject]@{taskId=$request.taskId;revision=122;status='in-progress';workflowStage='qa';deploymentWorkflows=@([pscustomobject]@{taskId=$request.taskId;workflowId=$request.workflowId;qaWorkflowId='create-plan-views-v1';workflowRevision=1});cpvPreparationRecovery=[pscustomobject]@{Request=$saveRequest;Status='Dispatching';OutcomeRecoveryApprovalId=$provenance.recoveryApprovalId;OutcomeRecoveryRequest=[pscustomobject]@{token='reserved'};OutcomeRecoveryRequestHash='injected-reservation-hash';PreparationBinding=[pscustomobject]@{FixtureSha256=$sourceHash};OutcomeRecoveryReceipt=$null}}
    & $saveModule {param($t,$fixtureHash,$root)
        $script:CompatibilitySyntheticTask=$t;$script:CpvOutcomeRecoveryFixtureHash=$fixtureHash;$script:CpvOutcomeRecoveryAgentRoot=$root
        function script:Read-RepatoTaskStore {param($StoreRoot) $script:CompatibilitySyntheticTask}
        function script:Find-RepatoTask {param($Data,$TaskId) if($Data.taskId -cne $TaskId){throw 'Synthetic task mismatch'};$Data}
        function script:Get-Process {param($Name,$ErrorAction) @()}
        function script:Get-CpvOutcomeRecoveryHash {param($Value) if($Value.PSObject.Properties['token']){'injected-reservation-hash'}else{$Value|ConvertTo-Json -Depth 30 -Compress}}
        function script:Invoke-RepatoStoreMutation {param($StoreRoot,$Body) & $Body $script:CompatibilitySyntheticTask $false}
        function script:Add-RepatoHistory {param($Task,$Event,$Actor,$Details)}
    } $syntheticTask $sourceHash $run
    $save={& $saveModule {param($id,$c) Save-CpvPreparationOutcomeRecoveryEvidence -StoreRoot 'in-memory-synthetic-only' -TaskId $id -ExpectedTaskRevision 122 -Commit $c} $request.taskId $commit}
    $old=$commit.RecoveredProvenanceSha256;$commit.RecoveredProvenanceSha256='0'*64;Reject $save 'Save rejects changed recovered provenance hash';$commit.RecoveredProvenanceSha256=$old
    foreach($field in @('ApprovalBindingHash','OriginalReceiptSha256','ActiveMarkerSha256','FailureEvidenceSha256','RequestSha256')){
        $old=$commit.$field;$commit.$field='0'*64;Reject $save "Save rejects changed $field";$commit.$field=$old
    }
    $old=$provenance.requestId;$provenance.requestId='88888888888888888888888888888888';Write-Json $recovered $provenance;$commit.RecoveredProvenanceSha256=Hash $recovered;Reject $save 'Save rejects replayed original request identity';$provenance.requestId=$old;Write-Json $recovered $provenance;$commit.RecoveredProvenanceSha256=Hash $recovered
    & $save|Out-Null
    Assert-Check ($syntheticTask.cpvPreparationRecovery.Status -ceq 'RecoveredVerified') 'Save publishes verified recovered state'
    Assert-Check ($syntheticTask.deploymentWorkflows[0].qaFixturePreparationEvidence.RecoveredProvenanceSha256 -ceq $commit.RecoveredProvenanceSha256) 'Save retains recovered provenance hash downstream'
    & $save|Out-Null
    Assert-Check ($syntheticTask.deploymentWorkflows[0].workflowRevision -eq 2) 'Save replay is idempotent'
    Assert-Check ((Hash $historical) -ceq $historicalHash) 'Save preserves historical evidence bytes'
    Remove-Item -LiteralPath $recovered
    Write-Json $historical $normal
    Assert-Check ((Read-CpvFixtureProvenance -SidecarPath $historical).preparedModelSha256 -eq $modelHash) 'Existing normal full sidecar remains supported'
    Assert-Check ([bool](& $validate)) 'Downstream normal provenance remains supported'
    [pscustomobject]@{Passed=$count;PowerShell=$PSVersionTable.PSVersion.ToString();RealStoreTouched=$false;RevitLaunched=$false}|ConvertTo-Json -Compress
} finally {
    if(Test-Path -LiteralPath $root){$resolved=[IO.Path]::GetFullPath($root);if(!$resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe synthetic cleanup path'};Remove-Item -LiteralPath $resolved -Recurse -Force}
}
