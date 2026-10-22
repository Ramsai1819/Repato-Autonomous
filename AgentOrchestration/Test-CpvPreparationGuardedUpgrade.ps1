$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationUpgrade.psm1') -Force -PassThru
$bootstrap=Import-Module (Join-Path $PSScriptRoot '../QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1') -Force -PassThru
$temp=Join-Path ([IO.Path]::GetTempPath()) ('cpv-guarded-upgrade-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $temp|Out-Null
$script:count=0;$names=@('Repato.QaLaunchAgent.exe','Repato.QaLaunchAgent.dll','Repato.QaLaunchAgent.deps.json','Repato.QaLaunchAgent.runtimeconfig.json')
function Check($value,$name){$script:count++;if(!$value){throw "FAILED: $name"}}
function Reject($action,$pattern){$script:count++;try{&$action;throw 'Unexpected acceptance'}catch{if($_.Exception.Message -notmatch $pattern){throw}}}
function New-TestTaskEvidence($spec){$evidence=[ordered]@{};foreach($property in $spec.PSObject.Properties){if($property.Name -cne 'Sid'){$evidence[$property.Name]=$property.Value}};$evidence.PrincipalResolvedSid=$spec.Sid;$evidence.TriggerResolvedSid=$spec.Sid;[pscustomobject]$evidence}
function New-Case([string]$name){
    $root=Join-Path $temp $name;$logs=Join-Path $root 'logs\CpvPreparation';$runtime=Join-Path $root 'runtime';$old=Join-Path $root 'old';$candidate=Join-Path $root 'candidate'
    New-Item -ItemType Directory -Path $logs,$runtime,$old,$candidate -Force|Out-Null
    foreach($file in $names){[IO.File]::WriteAllText((Join-Path $old $file),"old:$file");[IO.File]::WriteAllText((Join-Path $candidate $file),"new:$file")}
    $candidateFiles=@(foreach($file in $names){[pscustomobject]@{name=$file;sha256=(Get-FileHash (Join-Path $candidate $file) -Algorithm SHA256).Hash}})
    $manifest=[ordered]@{schemaVersion=1;product='Repato.QaLaunchAgent';productVersion='1.0.18+4b0066247088';sourceCommit=('4b0066247088'.PadRight(40,'0'));account='RAMSAI\RepatoQA';sid='S-1-5-21-1031246752-3872016183-2454652381-1015';files=$candidateFiles}
    $manifestPath=Join-Path $candidate 'Repato.QaLaunchAgent.release.json';[IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false));$manifestHash=(Get-FileHash $manifestPath -Algorithm SHA256).Hash
    $attempt=[guid]::NewGuid().ToString('N');$workflow=[guid]::NewGuid().ToString('N');$request=[ordered]@{schemaVersion=1;operation='prepare-cpv-fixture';requestId='9953e14c15524fe09440d1c7d7353950';taskId='task-bf61fe7f22d74df7a92599681da5919e';workflowId=$workflow;attemptId=$attempt;runId=[guid]::NewGuid().ToString('N');expiresUtc=[DateTimeOffset]::UtcNow.AddHours(1).ToString('O');candidateEvidence=[pscustomobject]@{CandidateDllSha256=('A'*64);RunnerManifestSha256=('B'*64)}}
    $run=Join-Path $runtime ('cpv-preparation-'+$request.runId);New-Item -ItemType Directory -Path $run|Out-Null
    $modelPath=Join-Path $run 'model.rvt';$runnerPath=Join-Path $run ('tara-'+$attempt+'.request.json')
    Copy-Item (Join-Path (Split-Path $PSScriptRoot -Parent) 'QA\Fixtures\CreatePlanViewsEmpty.rvt') $modelPath
    [IO.File]::WriteAllText(($modelPath+'.fixture.json'),('{"fixtureId":"CreatePlanViewsEmpty","sourceSha256":"92CC9E434E2C4DD6720A2AA564E19F4E1A30EB3DA63CEA73CF737F875B9EDD45"}'))
    $runner=[ordered]@{schemaVersion=1;operation='prepare-disposable-create-plan-views-fixture';requestId=$attempt;taskId=$request.taskId;workflowId=$workflow;attemptId=$attempt;runId=$request.runId;requestPath=$runnerPath;modelPath=$modelPath;modelSha256='92CC9E434E2C4DD6720A2AA564E19F4E1A30EB3DA63CEA73CF737F875B9EDD45';selectedManifestPath='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA\Repato.CreatePlanViews.TestRunner.addin';selectedManifestSha256=('B'*64);outputPath=($runnerPath+'.preparation.json');expiresUtc=$request.expiresUtc}
    [IO.File]::WriteAllText($runnerPath,($runner|ConvertTo-Json -Depth 8 -Compress));$requestJson=$request|ConvertTo-Json -Depth 15 -Compress
    [IO.File]::WriteAllText((Join-Path $logs 'active.json'),$requestJson);[IO.File]::WriteAllText((Join-Path $logs '9953e14c15524fe09440d1c7d7353950.request.json'),$requestJson)
    [IO.File]::WriteAllText((Join-Path $logs '9953e14c15524fe09440d1c7d7353950.failure.txt'),'System.IO.InvalidDataException: preparation-exited-without-result')
    $receipt=[ordered]@{schemaVersion=1;operation='prepare-cpv-fixture';requestId=$request.requestId;taskId=$request.taskId;workflowId=$workflow;attemptId=$attempt;runId=$request.runId;status='OutcomeUnknown';user='RAMSAI\RepatoQA';sid='S-1-5-21-1031246752-3872016183-2454652381-1015';sessionId=1;candidateSha256=('A'*64);manifestSha256=('B'*64);modelPath=$modelPath;modelSha256='';requestPath=$runnerPath;requestSha256='';resultPath='';resultSha256='';cleanupVerified=$false;rollbackStatus='Unknown';failureCode='preparation-failed-reconcile-required';expiresUtc=$request.expiresUtc}
    [IO.File]::WriteAllText((Join-Path $logs '9953e14c15524fe09440d1c7d7353950.json'),($receipt|ConvertTo-Json -Depth 8 -Compress))
    $prior=@(foreach($file in $names){[pscustomobject]@{name=$file;sha256=(Get-FileHash (Join-Path $old $file) -Algorithm SHA256).Hash}})
    $caps=[pscustomobject]@{operation='cpv-preparation-capabilities';supported=$true;user='RAMSAI\RepatoQA';sid='S-1-5-21-1031246752-3872016183-2454652381-1015';sessionId=1}
    $agent=[pscustomobject]@{ProcessName='Repato.QaLaunchAgent';Path=(Join-Path $old 'Repato.QaLaunchAgent.exe');ProductVersion='1.0.17+4b0066247088';Id=123;StartTime=[DateTime]::UtcNow;User='RAMSAI\RepatoQA';Sid='S-1-5-21-1031246752-3872016183-2454652381-1015';SessionId=1}
    [pscustomobject]@{Root=$root;Evidence=$logs;Runtime=$runtime;Run=$run;Old=$old;Candidate=$candidate;Manifest=$manifestPath;ManifestHash=$manifestHash;Request=$request;Receipt=[pscustomobject]$receipt;Capabilities=$caps;Agent=$agent;Prior=$prior;PriorTaskValid=$true}
}
try {
    $valid=New-Case 'valid';$gateArgs=@{EvidenceRoot=$valid.Evidence;RuntimeRoot=$valid.Runtime;RequestId=$valid.Request.requestId;TaskId=$valid.Request.taskId;Capabilities=$valid.Capabilities;Receipt=$valid.Receipt;InstalledAgent=$valid.Agent;ProcessSid=$valid.Agent.Sid;ExpectedExecutable=$valid.Agent.Path;ExpectedInstalledVersion='1.0.17+4b0066247088';CandidateRoot=$valid.Candidate;CandidateManifestPath=$valid.Manifest;CandidateManifestSha256=$valid.ManifestHash;PriorRuntimeFiles=$valid.Prior;PriorTaskContractValid=$true;NoRevitProcesses=$true}
    $before=Get-CpvPreparationUpgradeEvidenceSnapshot -EvidenceRoot $valid.Evidence -RunDirectory $valid.Run
    $gate=Assert-CpvPreparationUpgradeEvidence @gateArgs
    Check ($gate.Request.requestId -eq '9953e14c15524fe09440d1c7d7353950' -and $gate.CandidateVersion -eq '1.0.18+4b0066247088') 'valid exact request and candidate accepted'
    $missingSid=@{}+$gateArgs;$missingSid.InstalledAgent=[pscustomobject]@{ProcessName=$valid.Agent.ProcessName;Path=$valid.Agent.Path;ProductVersion=$valid.Agent.ProductVersion;Id=$valid.Agent.Id;StartTime=$valid.Agent.StartTime;User=$valid.Agent.User;SessionId=$valid.Agent.SessionId};Check ((Assert-CpvPreparationUpgradeEvidence @missingSid).CandidateVersion -eq '1.0.18+4b0066247088') 'missing object SID uses the validated process SID'
    $wrongProcessSid=@{}+$gateArgs;$wrongProcessSid.ProcessSid='S-1-5-21-1-2-3-1000';Reject {Assert-CpvPreparationUpgradeEvidence @wrongProcessSid} 'process SID evidence is missing or invalid'
    Check (Test-CpvPreparationUpgradeEvidenceSnapshot -Before $before -EvidenceRoot $valid.Evidence -RunDirectory $valid.Run) 'gate preserves all evidence bytes'
    $wrongRequest=@{}+$gateArgs;$wrongRequest.RequestId='other';Reject {Assert-CpvPreparationUpgradeEvidence @wrongRequest} 'Only the fixed CPV failed request'
    [IO.File]::WriteAllText((Join-Path $valid.Evidence 'active.json'),'corrupt');Reject {Assert-CpvPreparationUpgradeEvidence @gateArgs} 'JSON|identity'
    [IO.File]::WriteAllText((Join-Path $valid.Evidence 'active.json'),($valid.Request|ConvertTo-Json -Depth 15 -Compress))
    [IO.File]::WriteAllText((Join-Path $valid.Candidate 'Repato.QaLaunchAgent.dll'),'tampered');Reject {Assert-CpvPreparationUpgradeEvidence @gateArgs} 'Candidate file hash mismatch'
    [IO.File]::WriteAllText((Join-Path $valid.Candidate 'Repato.QaLaunchAgent.dll'),'new:Repato.QaLaunchAgent.dll')
    $missingBackup=@{}+$gateArgs;$missingBackup.PriorRuntimeFiles=@($valid.Prior|Select-Object -Skip 1);Reject {Assert-CpvPreparationUpgradeEvidence @missingBackup} 'rollback source'
    $processUnknown=@{}+$gateArgs;$processUnknown.NoRevitProcesses=$false;Reject {Assert-CpvPreparationUpgradeEvidence @processUnknown} 'process presence'
    $target=$valid.Old;$manifestObject=Get-Content $valid.Manifest -Raw|ConvertFrom-Json;$validated=[pscustomobject]@{SourceRoot=$valid.Candidate;Manifest=$manifestObject;ManifestSha256=$valid.ManifestHash}
    $state=[pscustomobject]@{Task=$null;FailSet=$false};$context=[pscustomobject]@{IsAdministrator={};ResolveIdentity={param($a,$s)};PrepareAcl={param($p)};GetTask={$state.Task};ExportTask={param($t)if($t){'prior-task'}};SetTask={param($spec)$state.Task=New-TestTaskEvidence $spec};RestoreTask={param($xml)if($xml){$state.Task=New-TestTaskEvidence (&$bootstrap {New-TaskSpec})}else{$state.Task=$null}};RemoveTask={$state.Task=$null}}
    $state.Task=New-TestTaskEvidence (&$bootstrap {New-TaskSpec})
    $markerBefore=(Get-FileHash (Join-Path $valid.Evidence 'active.json')).Hash
    $installed=&$bootstrap {param($v,$c,$t)Invoke-InstallCore $v $c $t -AllowTestRoot -RetainRollback -ProcessDetector {$null}} $validated $context $target
    Check ($installed.Installed -and $installed.RollbackToken -and (Test-Path $installed.RollbackToken.BackupRoot)) 'valid guarded candidate install retains verified rollback evidence'
    foreach($entry in $manifestObject.files){Check ((Get-FileHash (Join-Path $target $entry.name)).Hash -ceq $entry.sha256) "candidate file installed: $($entry.name)"}
    $rollback=&$bootstrap {param($token,$c,$t)Restore-InstallCore $token $c $t -AllowTestRoot -ProcessDetector {$null}} $installed.RollbackToken $context $target
    Check ($rollback.Restored -and @($rollback.RuntimeIntegrity|Where-Object {!$_.Match}).Count -eq 0) 'interruption restores exact prior runtime and task'
    Check ((Get-FileHash (Join-Path $valid.Evidence 'active.json')).Hash -ceq $markerBefore -and (Test-CpvPreparationUpgradeEvidenceSnapshot -Before $before -EvidenceRoot $valid.Evidence -RunDirectory $valid.Run)) 'rollback preserves active marker and diagnostic evidence'
    $installer=Get-Content (Join-Path $PSScriptRoot 'Install-CpvPreparationAgentCandidate.ps1') -Raw
    Check ($installer.Contains('if(!$ReconcileRequestId){throw ''An active/interrupted preparation must be reconciled before agent installation.''}') -and $installer.Contains('if($upgrade){')) 'ordinary unresolved-marker guard remains explicit'
    Check ($installer.Contains('Invoke-MayaQaLaunchAgentHealth -TimeoutMilliseconds 3000') -and $installer.Contains('$agentHealth.SessionId -ne $capabilities.sessionId')) 'installer stop is bound to authenticated Launch Agent health for both guarded and ordinary paths'
    Check (!$installer.Contains('Stop-Process') -and $installer.Contains('Stop-RepatoQaLaunchAgentForUpdate -ExpectedAgentPid $process.Id') -and $installer.Contains('Verified rollback evidence is unavailable; scheduled task remains stopped')) 'exception recovery uses authenticated stop and fails closed without verified rollback evidence'
    'PASS: '+$script:count+' guarded upgrade assertions; synthetic installer/rollback only; Revit launched=false.'
} finally {Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
