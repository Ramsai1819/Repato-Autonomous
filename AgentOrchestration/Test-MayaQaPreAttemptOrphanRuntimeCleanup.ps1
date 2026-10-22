$ErrorActionPreference='Stop'
$root=$PSScriptRoot
Import-Module (Join-Path $root 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $root 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
$qaRoot=[IO.Path]::GetFullPath((Join-Path $root '..\QA'))
$runs=[IO.Path]::GetFullPath((Join-Path $qaRoot 'TestRuns'))
$fixture=[IO.Path]::GetFullPath((Join-Path $qaRoot 'Fixtures\CreatePlanViewsEmpty.rvt'))
$created=[Collections.Generic.List[string]]::new()
function New-Case([string]$name){
    $store=Join-Path ([IO.Path]::GetTempPath()) ('repato-preattempt-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $store -Force|Out-Null
    $taskId='task-'+[guid]::NewGuid().ToString('N');$runId=[guid]::NewGuid().ToString('N');New-RepatoTask $store $taskId 'Maya QA request' 'Create Plan Views' 'qa/maya-qa-workflow' 'maya'|Out-Null
    $runtime=Join-Path $runs ($runId+'-preattempt-test-'+$name);New-Item -ItemType Directory -Path $runtime -Force|Out-Null;$created.Add($runtime)
    Copy-Item $fixture (Join-Path $runtime 'model.rvt');Set-Content (Join-Path $runtime 'model.rvt.fixture.json') '{"fixtureId":"CreatePlanViewsEmpty"}'
    Invoke-RepatoStoreMutation $store {param($d,$p)$t=Find-RepatoTask $d $taskId;$t|Add-Member NoteProperty deploymentWorkflows ([object[]]@([pscustomobject]@{taskId=$taskId;qaRunId=$runId;qaModelPath=(Join-Path $runtime 'model.rvt');qaSidecarPath=(Join-Path $runtime 'model.rvt.fixture.json')})) -Force;$t}|Out-Null
    [pscustomobject]@{Store=$store;TaskId=$taskId;RunId=$runId;Runtime=$runtime}
}
function Assert-Rejected($ctx,[scriptblock]$mutator,[string]$name){& $mutator $ctx;$before=Test-Path $ctx.Runtime; $rejected=$false;try{Complete-MayaQaPreAttemptOrphanRuntimeCleanup -StoreRoot $ctx.Store -TaskId $ctx.TaskId -RunId $ctx.RunId|Out-Null}catch{$rejected=$true};if(!$rejected){throw "$name was accepted."};if($before -and !(Test-Path $ctx.Runtime)){throw "$name deleted a runtime."}}
$positive=New-Case positive
try{
    $r=Complete-MayaQaPreAttemptOrphanRuntimeCleanup -StoreRoot $positive.Store -TaskId $positive.TaskId -RunId $positive.RunId
    if($r.Mode -ne 'Completed' -or (Test-Path $positive.Runtime)){throw 'Positive cleanup failed.'}
    $after=Find-RepatoTask (Read-RepatoTaskStore $positive.Store) $positive.TaskId;if($after.PreAttemptRuntimeCleanupStatus -ne 'Completed'){throw 'Cleanup audit was not persisted.'}
    $again=Complete-MayaQaPreAttemptOrphanRuntimeCleanup -StoreRoot $positive.Store -TaskId $positive.TaskId -RunId $positive.RunId;if($again.Mode -ne 'AlreadyCleaned'){throw 'Idempotency failed.'}
}finally{Remove-Item $positive.Store -Recurse -Force -ErrorAction SilentlyContinue}
$cases=@('wrong-task','wrong-run','outside-root','ownership','attempt','claim','execution','handoff','native-evidence','model-escape','sidecar-escape','fixture-source')
foreach($name in $cases){$c=New-Case $name;try{switch($name){
'wrong-task'{ $bad='task-'+[guid]::NewGuid().ToString('N');$thrown=$false;try{Complete-MayaQaPreAttemptOrphanRuntimeCleanup $c.Store $bad $c.RunId|Out-Null}catch{$thrown=$true};if(!$thrown){throw 'wrong-task was accepted.'}}
'wrong-run'{$thrown=$false;try{Complete-MayaQaPreAttemptOrphanRuntimeCleanup $c.Store $c.TaskId ([guid]::NewGuid().ToString('N'))|Out-Null}catch{$thrown=$true};if(!$thrown){throw 'wrong-run was accepted.'}}
'outside-root'{Assert-Rejected $c {param($x)$d=Read-RepatoTaskStore $x.Store;$t=Find-RepatoTask $d $x.TaskId;$t.deploymentWorkflows[0].qaModelPath=(Join-Path $x.Store 'model.rvt');Write-RepatoJsonAtomic (Join-Path $x.Store 'tasks.json') $d} $name}
'ownership'{Assert-Rejected $c {param($x)$d=Read-RepatoTaskStore $x.Store;$t=Find-RepatoTask $d $x.TaskId;$t.deploymentWorkflows[0].qaModelPath=(Join-Path $runs 'other\model.rvt');Write-RepatoJsonAtomic (Join-Path $x.Store 'tasks.json') $d} $name}
'attempt'{Assert-Rejected $c {param($x)$d=Read-RepatoTaskStore $x.Store;$t=Find-RepatoTask $d $x.TaskId;$t|Add-Member NoteProperty mayaTaraAttempt ([pscustomobject]@{AttemptId='a'}) -Force;Write-RepatoJsonAtomic (Join-Path $x.Store 'tasks.json') $d} $name}
'claim'{Assert-Rejected $c {param($x)$d=Read-RepatoTaskStore $x.Store;$t=Find-RepatoTask $d $x.TaskId;$t|Add-Member NoteProperty mayaTaraAttempt ([pscustomobject]@{AttemptId=$null;ClaimId='c'}) -Force;Write-RepatoJsonAtomic (Join-Path $x.Store 'tasks.json') $d} $name}
'execution'{Assert-Rejected $c {param($x)$d=Read-RepatoTaskStore $x.Store;$t=Find-RepatoTask $d $x.TaskId;$t|Add-Member NoteProperty mayaTaraExecution ([pscustomobject]@{}) -Force;Write-RepatoJsonAtomic (Join-Path $x.Store 'tasks.json') $d} $name}
'handoff'{Assert-Rejected $c {param($x)$d=Read-RepatoTaskStore $x.Store;$t=Find-RepatoTask $d $x.TaskId;$t|Add-Member NoteProperty mayaTaraQaPacket ([pscustomobject]@{HandoffId='h'}) -Force;Write-RepatoJsonAtomic (Join-Path $x.Store 'tasks.json') $d} $name}
'native-evidence'{Assert-Rejected $c {param($x)$d=Read-RepatoTaskStore $x.Store;$t=Find-RepatoTask $d $x.TaskId;$t.deploymentWorkflows[0]|Add-Member NoteProperty qaReportPath 'report.json' -Force;Write-RepatoJsonAtomic (Join-Path $x.Store 'tasks.json') $d} $name}
'model-escape'{Assert-Rejected $c {param($x)$d=Read-RepatoTaskStore $x.Store;$t=Find-RepatoTask $d $x.TaskId;$t.deploymentWorkflows[0].qaModelPath=(Join-Path $x.Store 'model.rvt');Write-RepatoJsonAtomic (Join-Path $x.Store 'tasks.json') $d} $name}
'sidecar-escape'{Assert-Rejected $c {param($x)$d=Read-RepatoTaskStore $x.Store;$t=Find-RepatoTask $d $x.TaskId;$t.deploymentWorkflows[0].qaSidecarPath=(Join-Path $x.Store 'sidecar.json');Write-RepatoJsonAtomic (Join-Path $x.Store 'tasks.json') $d} $name}
'fixture-source'{Assert-Rejected $c {param($x)$d=Read-RepatoTaskStore $x.Store;$t=Find-RepatoTask $d $x.TaskId;$t.deploymentWorkflows[0].qaModelPath=$fixture;Write-RepatoJsonAtomic (Join-Path $x.Store 'tasks.json') $d} $name}
}}
finally{Remove-Item $c.Store -Recurse -Force -ErrorAction SilentlyContinue}}
foreach($p in @($created)){if(Test-Path $p){Remove-Item $p -Recurse -Force}}
[pscustomobject]@{PreAttemptOrphanRuntimeCleanup='PASS';Positive='PASS';NegativeCasesPassed=12;Idempotency='PASS';RealTaskModified=$false;RealRuntimeDeleted=$false;LiveQaLaunchRequestSent=$false;RevitLaunched=$false}
