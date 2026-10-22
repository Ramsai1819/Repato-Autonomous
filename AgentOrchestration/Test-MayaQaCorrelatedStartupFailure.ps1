$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
$store=Join-Path ([IO.Path]::GetTempPath()) ('repato-startup-failure-'+[guid]::NewGuid().ToString('N'));New-Item $store -ItemType Directory|Out-Null
try {
    $real=Join-Path (Split-Path $PSScriptRoot -Parent) 'QA/MayaRuns'
    Copy-Item (Join-Path $real 'tasks.json') $store;Copy-Item (Join-Path $real 'status.json') $store
    $id='task-bf61fe7f22d74df7a92599681da5919e';$t=Find-RepatoTask (Read-RepatoTaskStore $store) $id
    $data=Read-RepatoTaskStore $store;$t=Find-RepatoTask $data $id
    $t.mayaTaraExecution.Stage='executing';$t.mayaTaraExecution.ExecutionStatus='Executing'
    Write-RepatoJsonAtomic (Join-Path $store 'tasks.json') $data
    $args=@{StoreRoot=$store;TaskId=$id;AttemptId=$t.mayaTaraExecution.AttemptId;ClaimId=$t.mayaTaraExecution.ClaimId;ExpectedTaskRevision=$t.revision}
    $before=(Get-FileHash (Join-Path $store 'tasks.json')).Hash
    foreach($case in @('stale','wrong-claim')){
        $bad=$args.Clone();if($case -eq 'stale'){$bad.ExpectedTaskRevision--}else{$bad.ClaimId='wrong'}
        try{Register-MayaQaCorrelatedStartupFailure @bad|Out-Null;throw 'Invalid identity accepted.'}catch{if($_.Exception.Message -notmatch 'Exact executing startup-failure identity'){throw}}
        if((Get-FileHash (Join-Path $store 'tasks.json')).Hash -cne $before){throw 'Rejected identity mutated store.'}
    }
    $result=Register-MayaQaCorrelatedStartupFailure @args
    $t=Find-RepatoTask (Read-RepatoTaskStore $store) $id
    if($result.Stage -cne 'qa-failed' -or $result.RollbackStatus -cne 'NotStarted' -or $result.VerificationStatus -cne 'Failed' -or $t.status -cne 'blocked' -or !$result.ReportSha256 -or !$result.ResultSha256 -or $t.mayaTaraAttempt.AttemptId -cne $args.AttemptId){throw 'Terminal failure evidence or state invalid.'}
    'Correlated startup-failure recording PASS: stale and wrong claims rejected without mutation; exact native failure recorded without replacement, rollback claim, or dispatch.'
} finally {
    if(![IO.Path]::GetFullPath($store).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe test cleanup path.'}
    Remove-Item -LiteralPath $store -Recurse -Force
}
