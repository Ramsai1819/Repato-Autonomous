$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationRecovery.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
$root=Join-Path $env:TEMP ('cpv-failed-reconcile-'+[guid]::NewGuid().ToString('N'));New-Item $root -ItemType Directory|Out-Null;$script:count=0
function Check($v,$n){$script:count++;if(!$v){throw "FAILED: $n"}}
function Reject($f,$pattern){$script:count++;try{&$f;throw 'Unexpected acceptance'}catch{if($_.Exception.Message -notmatch $pattern){throw}}}
try {
  $taskId='synthetic-cpv-failed-reconcile';New-RepatoTask $root $taskId 'Synthetic reconciliation' 'isolated test' 'qa/cpv-reconcile'|Out-Null
  $req=[pscustomobject][ordered]@{schemaVersion=1;operation='prepare-cpv-fixture';requestId=[guid]::NewGuid().ToString('N');taskId=$taskId;workflowId=[guid]::NewGuid().ToString('N');attemptId=[guid]::NewGuid().ToString('N');runId=[guid]::NewGuid().ToString('N')}
  $hash=& (Get-Module Repato.CpvPreparationRecovery) {param($x)Get-CpvRecoveryHash $x} $req
  Invoke-RepatoStoreMutation $root {param($d,$p)$t=Find-RepatoTask $d $taskId;$t|Add-Member NoteProperty cpvPreparationRecovery ([pscustomobject]@{Status='Dispatching';Request=$req;RequestHash=$hash;Receipt=$null});$t}|Out-Null
  $t=Find-RepatoTask (Read-RepatoTaskStore $root) $taskId;$revision=[long]$t.revision
  $script:receipt=[pscustomobject]@{requestId=$req.requestId;taskId=$taskId;workflowId=$req.workflowId;attemptId=$req.attemptId;runId=$req.runId;status='FailedReconciled';failureCode='preparation-exited-without-result';cleanupVerified=$false;rollbackStatus='NotRequired-NoPreparationResult'}
  $script:calls=0;$transport={param($q)$script:calls++;if($q.operation -cne 'cpv-preparation-reconcile-failed'){throw 'wrong operation'};$script:receipt}
  Reject {Set-CpvPreparationRecoveryFailedReconciled $root $taskId ($revision-1) -Transport $transport} 'revision is stale'
  Check ($script:calls -eq 0) 'revision conflict checked before agent call'
  Reject {Set-CpvPreparationRecoveryFailedReconciled $root $taskId $revision -Transport {param($q)throw 'response lost after durable agent transition'}} 'response lost'
  $done=Set-CpvPreparationRecoveryFailedReconciled $root $taskId $revision -Transport $transport
  $after=Find-RepatoTask (Read-RepatoTaskStore $root) $taskId
  Check ($done.Status -ceq 'FailedReconciled' -and $after.cpvPreparationRecovery.Receipt.status -ceq 'FailedReconciled') 'lost response completed with same terminal request'
  Check (@($after.approvalRequests|Where-Object status -ceq pending).Count -eq 0) 'reconciliation creates no approval'
  $next=[long]$after.revision;$again=Set-CpvPreparationRecoveryFailedReconciled $root $taskId ($next-1) -Transport $transport
  Check ($again.Status -ceq 'FailedReconciled' -and (Find-RepatoTask (Read-RepatoTaskStore $root) $taskId).revision -eq $next) 'duplicate canonical call idempotent'
  Reject {Set-CpvPreparationRecoveryFailedReconciled $root $taskId $next -Transport {param($q)$x=$script:receipt|Select-Object *;$x.runId=[guid]::NewGuid().ToString('N');$x}} 'identity mismatch'
  'PASS: '+$script:count+' synthetic canonical reconciliation assertions; isolated store; no agent or Revit process invoked.'
} finally {Remove-Item -LiteralPath $root -Recurse -Force}
