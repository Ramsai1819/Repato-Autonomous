$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
$workflowModule=Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -PassThru -WarningAction SilentlyContinue
$store=Join-Path ([IO.Path]::GetTempPath()) ('repato-date-locale-'+[guid]::NewGuid().ToString('N'))
$thread=[Threading.Thread]::CurrentThread
$originalCulture=$thread.CurrentCulture
$originalUiCulture=$thread.CurrentUICulture
try {
    $culture=[Globalization.CultureInfo]::GetCultureInfo('en-IN')
    $thread.CurrentCulture=$culture
    $thread.CurrentUICulture=$culture
    Initialize-RepatoTaskStore $store|Out-Null
    $createdTask=New-RepatoTask $store 'task-date-locale' 'Timestamp locale regression' 'Read a task under a non-US culture' 'fix/task-store-date-locale' 'none'
    $task=Find-RepatoTask (Read-RepatoTaskStore $store) 'task-date-locale'
    if(!$task -or $task.createdUtc -isnot [string] -or $task.createdUtc -cne [string]$createdTask.createdUtc){throw 'Task store did not preserve its exact UTC creation timestamp.'}
    $approval=[pscustomobject][ordered]@{requestId='approval-date-locale';action='qa-run';status='approved';requestedUtc='2026-10-19T18:00:27.2645831Z';expiresUtc='2026-10-19T18:30:27.2701570+00:00';consumedUtc=$null}
    $expectedHash=& $workflowModule {param($value)Get-MayaQaCanonicalObjectSha256 $value} $approval
    Invoke-RepatoStoreMutation $store {
        param($data,$preview)
        $task=Find-RepatoTask $data 'task-date-locale'
        $task.approvalRequests=[object[]]@([pscustomobject][ordered]@{requestId='approval-date-locale';action='qa-run';status='approved';requestedUtc='2026-10-19T18:00:27.2645831Z';expiresUtc='2026-10-19T18:30:27.2701570+00:00';consumedUtc=$null})
        $data
    }|Out-Null
    $task=Find-RepatoTask (Read-RepatoTaskStore $store) 'task-date-locale'
    $storedApproval=$task.approvalRequests[0]
    $actualHash=& $workflowModule {param($value)Get-MayaQaCanonicalObjectSha256 $value} $storedApproval
    if($storedApproval.expiresUtc -cne $approval.expiresUtc -or $actualHash -cne $expectedHash){throw 'Task-store round-trip changed the exact approval timestamp or its canonical hash.'}
    [pscustomobject]@{Status='PASS';Culture=$culture.Name;TaskId=$task.taskId;TaskRevision=$task.revision;ApprovalHashStable=$true}|ConvertTo-Json -Compress
} finally {
    $thread.CurrentCulture=$originalCulture
    $thread.CurrentUICulture=$originalUiCulture
    if(Test-Path -LiteralPath $store){Remove-Item -LiteralPath $store -Recurse -Force}
}
