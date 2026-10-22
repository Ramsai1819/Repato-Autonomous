$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue
$qa=Join-Path $root 'QA';$runs=Join-Path $qa 'TestRuns';$fixture=Join-Path $qa 'Fixtures\CreatePlanViewsEmpty.rvt';$madeFixture=$false
if(!(Test-Path -LiteralPath $fixture)){New-Item -ItemType Directory -Path (Split-Path $fixture -Parent) -Force|Out-Null;[IO.File]::WriteAllBytes($fixture,[byte[]](1..128));$madeFixture=$true}
$fixtureHash=(Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash
$prepRun=Join-Path $runs ('provenance-contract-'+[guid]::NewGuid().ToString('N'));$qaRun=$null;$store=Join-Path ([IO.Path]::GetTempPath()) ('maya-prepared-fixture-'+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $prepRun|Out-Null
    $savedModel=Join-Path $prepRun 'synthetic-prepared-model.rvt';[IO.File]::WriteAllBytes($savedModel,[byte[]](129..255))
    $saved=[pscustomobject]@{Status='Passed';SourceModelSha256=$fixtureHash;PreparedModelSha256=(Get-FileHash -LiteralPath $savedModel -Algorithm SHA256).Hash;ModelPath=$savedModel}
    $prepModel=Join-Path $prepRun 'model.rvt';Copy-Item -LiteralPath $saved.ModelPath -Destination $prepModel
    $preparedHash=(Get-FileHash -LiteralPath $prepModel -Algorithm SHA256).Hash
    if($preparedHash -ine $saved.PreparedModelSha256){throw 'Copied Revit-prepared model hash mismatch.'}
    $bootstrap=New-MayaQaBootstrap -StoreRoot $store -QaWorkflowId 'create-plan-views-v1' -RunId 'provenance-test'
    $taskId=$bootstrap.TaskId;$workflowId=$bootstrap.WorkflowId;$prepRequestPath=Join-Path $prepRun 'preparation.request.json';$prepResultPath=$prepRequestPath+'.preparation.json'
    $prepAttempt=[guid]::NewGuid().ToString('N');$prepRunId=[guid]::NewGuid().ToString('N')
    $prepRequest=[ordered]@{operation='prepare-disposable-create-plan-views-fixture';taskId=$taskId;workflowId=$workflowId;attemptId=$prepAttempt;runId=$prepRunId;requestPath=$prepRequestPath;modelPath=$prepModel;modelSha256=$fixtureHash;selectedManifestPath=(Join-Path $prepRun 'Repato.CreatePlanViews.TestRunner.addin');selectedManifestSha256=('A'*64);outputPath=$prepResultPath;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(5).ToString('O')}
    $prepResult=[ordered]@{SchemaVersion=1;Operation='prepare-disposable-create-plan-views-fixture';Status='Passed';TaskId=$taskId;WorkflowId=$workflowId;AttemptId=$prepAttempt;RunId=$prepRunId;ModelPath=$prepModel;SourceModelSha256=$fixtureHash;PreparedModelSha256=$preparedHash}
    $prepRequest|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $prepRequestPath -Encoding UTF8
    $prepResult|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $prepResultPath -Encoding UTF8
    $candidate=Join-Path $prepRun 'synthetic-candidate';New-Item -ItemType Directory -Path $candidate|Out-Null
    $dll=Join-Path $candidate 'Repato.Revit.dll';$provenance=Join-Path $candidate 'release-manifest.json'
    [IO.File]::WriteAllText($dll,'synthetic fixture provenance candidate');[IO.File]::WriteAllText($provenance,'{"synthetic":true}')
    $dHash=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash;$pHash=(Get-FileHash -LiteralPath $provenance -Algorithm SHA256).Hash
    Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$w=@($t.deploymentWorkflows|Where-Object workflowId -ceq $workflowId)[0];$w|Add-Member NoteProperty qaBuildStatus 'succeeded' -Force;$w|Add-Member NoteProperty qaBuildEvidence ([pscustomobject]@{ArtifactPath=$dll;ArtifactSha256=$dHash;ManifestPath=$provenance;ManifestSha256=$pHash}) -Force;$d}|Out-Null
    Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$t.status='in-progress';$t.workflowStage='build-checks';foreach($q in @($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved'})){$q.status='rejected';$q.reason='superseded synthetic bootstrap approval'};$w=@($t.deploymentWorkflows|Where-Object workflowId -ceq $workflowId)[0];foreach($n in 'qaApprovalId','qaApprovalStatus','qaRunId','qaModelPath','qaSidecarPath','qaFixtureId','qaFixtureSha256','qaTestId'){$w.PSObject.Properties.Remove($n)};Add-RepatoHistory $t 'synthetic-fresh-build-checks-state' 'Maya' 'prepare fixture provenance regression';$d}|Out-Null
    $badResult=[ordered]@{};foreach($property in $prepResult.GetEnumerator()){$badResult[$property.Key]=$property.Value};$badResult.AttemptId=[guid]::NewGuid().ToString('N')
    $badResult|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $prepResultPath -Encoding UTF8
    $mismatchRejected=$false;try{New-MayaQaRun -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId 'create-plan-views-v1' -RunId ('MAYA-'+[guid]::NewGuid().ToString('N')) -FixturePreparationResultPath $prepResultPath|Out-Null}catch{$mismatchRejected=$true}
    if(!$mismatchRejected){throw 'Mismatched preparation result identity was accepted.'}
    $prepResult|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $prepResultPath -Encoding UTF8
    $canonicalRunId='MAYA-'+[guid]::NewGuid().ToString('N')
    $created=New-MayaQaRun -StoreRoot $store -TaskId $taskId -WorkflowId $workflowId -QaWorkflowId 'create-plan-views-v1' -RunId $canonicalRunId -FixturePreparationResultPath $prepResultPath
    $qaRun=[IO.Path]::GetDirectoryName($created.ModelPath);$side=Get-Content -LiteralPath $created.SidecarPath -Raw|ConvertFrom-Json
    if($created.FixtureSha256 -ine $fixtureHash -or $created.ModelSha256 -ine $preparedHash -or $created.FixtureSha256 -ieq $created.ModelSha256 -or $side.sourceSha256 -ine $fixtureHash -or $side.preparedModelSha256 -ine $preparedHash -or $side.fixturePreparationAttemptId -cne $prepAttempt -or $side.fixturePreparationRunId -cne $prepRunId -or $side.fixturePreparationRequestSha256 -ine (Get-FileHash $prepRequestPath -Algorithm SHA256).Hash -or $side.fixturePreparationResultSha256 -ine (Get-FileHash $prepResultPath -Algorithm SHA256).Hash){throw ('Canonical run model/sidecar provenance mismatch: source={0}/{1}; model={2}/{3}; prepared={4}/{5}; attempt={6}/{7}; run={8}/{9}' -f $created.FixtureSha256,$fixtureHash,$created.ModelSha256,$preparedHash,$side.preparedModelSha256,$preparedHash,$side.fixturePreparationAttemptId,$prepAttempt,$side.fixturePreparationRunId,$prepRunId)}
    if((Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash -ine $fixtureHash){throw 'Authoritative source fixture changed during provenance test.'}
    [pscustomobject]@{Status='PASS';MismatchedPreparationIdentityRejected=$mismatchRejected;FixtureSha256=$fixtureHash;PreparedModelSha256=$preparedHash;PreparationAttemptId=$prepAttempt;PreparationRunId=$prepRunId;CanonicalModelPath=$created.ModelPath;CanonicalModelSha256=$created.ModelSha256;SidecarPath=$created.SidecarPath}|ConvertTo-Json -Compress
} finally {
    foreach($path in @($qaRun,$prepRun)){if($path -and (Test-Path -LiteralPath $path)){ $full=[IO.Path]::GetFullPath($path);$base=[IO.Path]::GetFullPath($runs).TrimEnd('\')+'\';if($full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $full -Recurse -Force}else{throw "Test cleanup target escaped QA runs: $full"}}}
    if(Test-Path -LiteralPath $store){Remove-Item -LiteralPath $store -Recurse -Force}
    if($madeFixture -and (Test-Path -LiteralPath $fixture)){Remove-Item -LiteralPath $fixture -Force -ErrorAction Stop}
}
