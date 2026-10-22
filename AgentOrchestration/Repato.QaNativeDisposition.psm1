Set-StrictMode -Version Latest

function Get-RepatoSha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-RepatoQaNativeDisposition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$EvidenceRoot,
        [Parameter(Mandatory)][string]$RequestPath,
        [string]$ResultPath,
        [Parameter(Mandatory)][string]$ExpectedRequestId,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$TestId,
        [Parameter(Mandatory)][string]$AttemptId,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$ClaimId,
        [string]$ExpectedArtifactSha256
    )

    # Read-only by design: this function never waits, launches, edits evidence, or writes a task store.
    $resultPathResolved = if ($ResultPath) { $ResultPath } else { $RequestPath + '.result.json' }
    $base = [ordered]@{ RequestPath=$RequestPath; ResultPath=$resultPathResolved; RequestSha256=$null; ResultSha256=$null; ReportPath=$null; ReportSha256=$null; StoreSha256=$null; TaskRevision=$null; Status='Unknown'; Reason='No authoritative terminal evidence was found.'; SideEffectsPerformed=$false }
    $storeFile = Join-Path ([IO.Path]::GetFullPath($StoreRoot)) 'tasks.json'
    if (!(Test-Path -LiteralPath $storeFile -PathType Leaf)) { $base.Reason='Canonical task store is missing; acceptance cannot be established.'; return [pscustomobject]$base }
    try { $store = Get-Content -LiteralPath $storeFile -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { $base.Reason='Canonical task store is malformed; disposition remains unknown.'; return [pscustomobject]$base }
    $base.StoreSha256 = Get-RepatoSha256 $storeFile
    $tasks = @($store.tasks | Where-Object { $_.taskId -ceq $TaskId })
    if ($tasks.Count -ne 1) { $base.Reason='TaskId did not resolve uniquely in the canonical store.'; return [pscustomobject]$base }
    $task = $tasks[0]; $base.TaskRevision = $task.revision
    $execution = $task.mayaTaraExecution
    if (!$execution) { $base.Reason='Canonical task has no persisted execution record; disposition remains unknown.'; return [pscustomobject]$base }
    foreach ($pair in @(@('TaskId',$TaskId),@('WorkflowId',$WorkflowId),@('QaWorkflowId',$QaWorkflowId),@('TestId',$TestId),@('AttemptId',$AttemptId),@('RunId',$RunId),@('ClaimId',$ClaimId),@('NativeRequestId',$ExpectedRequestId))) {
        if ([string]$execution.($pair[0]) -cne $pair[1]) { $base.Reason="Canonical execution identity mismatch: $($pair[0])."; return [pscustomobject]$base }
    }
    if (!(Test-Path -LiteralPath $RequestPath -PathType Leaf)) { $base.Reason='Native request file is missing.'; return [pscustomobject]$base }
    $evidenceRootFull=[IO.Path]::GetFullPath($EvidenceRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    foreach($candidate in @($RequestPath,$resultPathResolved)){
        $candidateFull=[IO.Path]::GetFullPath($candidate)
        if($candidate.StartsWith('\\',[StringComparison]::Ordinal) -or $candidate.IndexOf(':',2) -ge 0 -or !$candidate.Equals($candidateFull,[StringComparison]::OrdinalIgnoreCase) -or !$candidateFull.StartsWith($evidenceRootFull,[StringComparison]::OrdinalIgnoreCase)){$base.Reason='Request/result path is outside the explicitly approved evidence root.';return [pscustomobject]$base}
    }
    try { $request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { $base.Reason='Native request JSON is malformed.'; return [pscustomobject]$base }
    $base.RequestSha256 = Get-RepatoSha256 $RequestPath
    foreach ($pair in @(@('requestId',$ExpectedRequestId),@('taskId',$TaskId),@('workflowId',$WorkflowId),@('qaWorkflowId',$QaWorkflowId),@('testId',$TestId),@('attemptId',$AttemptId),@('runId',$RunId),@('claimId',$ClaimId))) {
        if ($request.PSObject.Properties.Name -notcontains $pair[0] -or [string]$request.($pair[0]) -cne $pair[1]) { $base.Reason="Request identity mismatch: $($pair[0])."; return [pscustomobject]$base }
    }
    if (!(Test-Path -LiteralPath $resultPathResolved -PathType Leaf)) {
        $acceptedStages = @('executing','evidence-collected','rollback-verified','verified','completed')
        $acceptanceRecorded = $execution.Stage -cin $acceptedStages -and [int]$execution.NativeProcessId -gt 0 -and
            $execution.LaunchedUtc -and $execution.RequestPath -and
            [IO.Path]::GetFullPath([string]$execution.RequestPath).Equals([IO.Path]::GetFullPath($RequestPath), [StringComparison]::OrdinalIgnoreCase)
        if ($acceptanceRecorded) {
            $base.Status='Accepted'
            $base.Reason='Canonical execution record proves the Launch Agent acceptance response passed production correlation checks; it does not prove the native process is still running or terminal.'
        } else { $base.Reason='Request is correlated, but canonical acceptance evidence is incomplete and no native result exists; disposition remains unknown.' }
        return [pscustomobject]$base
    }
    $base.ResultSha256 = Get-RepatoSha256 $resultPathResolved
    try { $receipt = Get-Content -LiteralPath $resultPathResolved -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { $base.Reason='Native result JSON is malformed; disposition remains unknown.'; return [pscustomobject]$base }
    foreach ($pair in @(@('RequestId',$ExpectedRequestId),@('TaskId',$TaskId),@('WorkflowId',$WorkflowId),@('QaWorkflowId',$QaWorkflowId),@('TestId',$TestId),@('AttemptId',$AttemptId),@('RunId',$RunId),@('ClaimId',$ClaimId))) {
        if ($receipt.PSObject.Properties.Name -notcontains $pair[0] -or [string]$receipt.($pair[0]) -cne $pair[1]) { $base.Reason="Native result identity mismatch: $($pair[0])."; return [pscustomobject]$base }
    }
    if ([string]::IsNullOrWhiteSpace([string]$receipt.ReportPath) -or !(Test-Path -LiteralPath $receipt.ReportPath -PathType Leaf)) { $base.Reason='Correlated native receipt has no readable report; disposition remains unknown.'; return [pscustomobject]$base }
    $base.ReportPath = [IO.Path]::GetFullPath([string]$receipt.ReportPath)
    if(!$base.ReportPath.StartsWith($evidenceRootFull,[StringComparison]::OrdinalIgnoreCase)){$base.Reason='Native report path is outside the explicitly approved evidence root; disposition remains unknown.';return [pscustomobject]$base}
    $base.ReportSha256 = Get-RepatoSha256 $base.ReportPath
    try { $report = Get-Content -LiteralPath $base.ReportPath -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { $base.Reason='Native report JSON is malformed; disposition remains unknown.'; return [pscustomobject]$base }
    foreach ($pair in @(@('RequestId',$ExpectedRequestId),@('TaskId',$TaskId),@('WorkflowId',$WorkflowId),@('TestId',$TestId),@('AttemptId',$AttemptId),@('RunId',$RunId),@('ClaimId',$ClaimId))) {
        if ($report.PSObject.Properties.Name -notcontains $pair[0] -or [string]$report.($pair[0]) -cne $pair[1]) { $base.Reason="Native report identity mismatch: $($pair[0])."; return [pscustomobject]$base }
    }
    if ([string]$receipt.Status -notin @('Passed','Failed') -or [string]$report.Status -cne [string]$receipt.Status) { $base.Reason='Receipt/report status conflict; disposition remains unknown.'; return [pscustomobject]$base }
    if ($ExpectedArtifactSha256) {
        $assemblyHash = [string]$report.AssemblyIdentity.Sha256
        if ($assemblyHash -notmatch '^[0-9A-Fa-f]{64}$' -or $assemblyHash -ine $ExpectedArtifactSha256) { $base.Reason='Report candidate identity does not match the expected artifact; disposition remains unknown.'; return [pscustomobject]$base }
    }
    if ($receipt.Status -ceq 'Passed') {
        if ($report.RollbackStatus -cne 'RolledBack' -or @($report.Errors).Count -gt 0 -or @($report.Assertions).Count -eq 0 -or @($report.Assertions | Where-Object { $_.Passed -isnot [bool] -or !$_.Passed }).Count -gt 0) {
            $base.Reason='Passing result lacks successful assertions, a clean error list, or rollback proof; disposition remains unknown.'
            return [pscustomobject]$base
        }
        $artifact = if($ExpectedArtifactSha256){$ExpectedArtifactSha256}else{[string]$execution.ArtifactSha256}
        if($artifact -notmatch '^[A-Fa-f0-9]{64}$' -or [string]$report.AssemblyIdentity.Sha256 -ine $artifact){$base.Reason='Terminal report artifact hash does not match canonical execution provenance; disposition remains unknown.';return [pscustomobject]$base}
        if($report.PSObject.Properties.Name -notcontains 'RuntimeModelSha256' -or [string]$report.RuntimeModelSha256 -ine [string]$execution.DisposableModelSha256 -or [string]$report.FixtureSha256 -ine [string]$execution.AuthoritativeFixtureSha256){$base.Reason='Terminal report model/fixture hashes do not match canonical execution provenance; disposition remains unknown.';return [pscustomobject]$base}
        $base.Status='Completed'; $base.Reason='Correlated terminal pass receipt/report and canonical candidate/model/fixture hashes verified; files are checksummed, not digitally signed.'
        return [pscustomobject]$base
    }
    # Failed is terminal only when the runner emitted a correlated report with an explicit error.
    if (@($report.Errors).Count -eq 0 -and $report.RollbackStatus -notin @('RolledBack','NotRequired')) { $base.Reason='Failed receipt lacks sufficient failure/rollback evidence; disposition remains unknown.'; return [pscustomobject]$base }
    $base.Status='Failed'; $base.Reason='Correlated terminal failure receipt/report verified.'
    [pscustomobject]$base
}

Export-ModuleMember -Function Get-RepatoQaNativeDisposition
