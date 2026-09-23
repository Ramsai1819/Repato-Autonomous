# Loaded in the Maya workflow module. Importing this file performs no execution.
function Invoke-MayaQaTaraExecute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$ModelPath,
        [Parameter(Mandatory)][string]$SidecarPath,
        [Parameter(Mandatory)][string]$ReportDirectory,
        [string]$RevitInstallDir = 'E:\revit\Revit 2025',
        [Parameter(Mandatory)][string]$QaAddinRoot,
        [ValidateRange(1,3600)][int]$TimeoutSeconds = 900,
        [switch]$LocalRun,
        [switch]$DryRun,
        [switch]$IntegrationTest
        ,[string]$HandoffPath
    )
    if($HandoffPath){$h=Get-Content -LiteralPath $HandoffPath -Raw|ConvertFrom-Json;foreach($n in @('StoreRoot','TaskId','WorkflowId','QaWorkflowId','RunId','HandoffId','ModelPath','SidecarPath','ArtifactPath','ArtifactSha256','ManifestPath','ManifestSha256')){if($h.PSObject.Properties.Name -notcontains $n -or [string]::IsNullOrWhiteSpace([string]$h.$n)){throw "Invalid handoff: missing $n"}};foreach($p in @('HandoffPath','StoreRoot','ModelPath','SidecarPath','ArtifactPath','ManifestPath')){ $v=if($p -eq 'HandoffPath'){$HandoffPath}else{$h.$p};if(!(Test-Path -LiteralPath $v)){throw "Invalid handoff accessibility: $p is missing or unreadable ($v)."}};$StoreRoot=$h.StoreRoot;$TaskId=$h.TaskId;$WorkflowId=$h.WorkflowId;$QaWorkflowId=$h.QaWorkflowId;$RunId=$h.RunId;$ModelPath=$h.ModelPath;$SidecarPath=$h.SidecarPath}
    foreach ($identity in @($TaskId,$WorkflowId,$QaWorkflowId,$RunId)) {
        if ($identity -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$') { throw 'Invalid Tara workflow identity.' }
    }
    if (!$DryRun -and !$IntegrationTest) { throw 'Real Tara execution requires explicit -IntegrationTest authorization in an interactive RepatoQA session.' }
    $definition = Get-MayaQaWorkflowDefinition $QaWorkflowId
    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $data = Read-RepatoTaskStore $StoreRoot
    $task = Find-RepatoTask $data $TaskId
    $properties = @($workflow.PSObject.Properties.Name)
    if ($properties -contains 'qaTaraExecutionStatus' -and $workflow.qaTaraExecutionStatus) {
        throw 'Duplicate Tara execution rejected. Preserve the existing execution and prepare a new workflow for any retry.'
    }
    foreach ($required in @('qaBuildEvidence','qaBuildStatus','qaHandoff','qaHandoffId',
        'qaRunId','qaWorkflowId','qaModelPath','qaSidecarPath','qaFixtureId','qaFixtureSha256','qaTestId',
        'qaApprovalId','qaApprovalStatus')) {
        if ($properties -notcontains $required -or !$workflow.$required) { throw "Required Tara prerequisite is missing: $required" }
    }
    $approval = @($task.approvalRequests | Where-Object {
        $_.requestId -ceq $workflow.qaApprovalId -and $_.action -ceq 'qa-run' -and $_.status -ceq 'approved'
    })
    if ($workflow.qaApprovalStatus -cne 'approved' -or $approval.Count -ne 1) { throw 'Persisted Maya QA approval is required.' }
    $build = $workflow.qaBuildEvidence
    $buildExitCode = if ($build.PSObject.Properties.Name -contains 'ExitCode') { $build.ExitCode } else { $null }
    $buildConfiguration = if ($build.PSObject.Properties.Name -contains 'Configuration') { $build.Configuration } else { $null }
    $buildRequestId = if ($build.PSObject.Properties.Name -contains 'BuildRequestId') { $build.BuildRequestId } else { $null }
    $requestBuildId = if ($properties -contains 'qaBuildRequest' -and $workflow.qaBuildRequest -and $workflow.qaBuildRequest.PSObject.Properties.Name -contains 'BuildRequestId') { $workflow.qaBuildRequest.BuildRequestId } else { $null }
    if ([string]::IsNullOrWhiteSpace([string]$buildRequestId)) { $buildRequestId=$requestBuildId }
    if ([string]::IsNullOrWhiteSpace([string]$buildRequestId)) { throw 'Valid Neil build evidence is missing BuildRequestId.' }
    if ($workflow.qaBuildStatus -cne 'succeeded' -or
        (($build.PSObject.Properties.Name -contains 'ExitCode') -and $buildExitCode -ne 0) -or
        (($build.PSObject.Properties.Name -contains 'Configuration') -and $buildConfiguration -cne 'Release') -or
        ($build.PSObject.Properties.Name -contains 'BuildRequestId' -and $buildRequestId -cne $build.BuildRequestId)) {
        throw 'Valid completed Neil Release build evidence is required.'
    }
    if ($build.PSObject.Properties.Name -notcontains 'BuildStatus' -or $build.BuildStatus -cne 'succeeded') {
        throw 'Valid completed Neil Release build evidence is required.'
    }
    $handoff = $workflow.qaHandoff
    if ($handoff.HandoffId -cne $workflow.qaHandoffId -or $handoff.HandoffStatus -cne 'ready' -or
        $handoff.TaskId -cne $TaskId -or $handoff.QaWorkflowId -cne $QaWorkflowId -or
        (($handoff.PSObject.Properties.Name -contains 'BuildRequestId') -and $handoff.BuildRequestId -cne $buildRequestId) -or
        $handoff.FixtureId -cne $definition.FixtureId -or
        $handoff.NativeTestId -cne $definition.TestId) { throw 'Tara handoff identity mismatch.' }
    if ($workflow.taskId -cne $TaskId -or $workflow.qaWorkflowId -cne $QaWorkflowId -or
        $workflow.qaRunId -cne $RunId -or $workflow.qaFixtureId -cne $definition.FixtureId -or
        $workflow.qaTestId -cne $definition.TestId) { throw 'Tara QA run plan identity mismatch.' }
    foreach ($pair in @(@($ModelPath,$workflow.qaModelPath),@($SidecarPath,$workflow.qaSidecarPath),
        @($ModelPath,$handoff.ModelPath),@($SidecarPath,$handoff.SidecarPath),
        @($build.ArtifactPath,$handoff.ArtifactPath),@($build.ManifestPath,$handoff.ManifestPath))) {
        if ([string]::IsNullOrWhiteSpace($pair[1]) -or [IO.Path]::GetFullPath($pair[0]) -ine [IO.Path]::GetFullPath($pair[1])) {
            throw 'Tara handoff or run plan path mismatch.'
        }
    }
    foreach ($kind in @('Artifact','Manifest')) {
        $path = $build.($kind+'Path')
        $hash = $build.($kind+'Sha256')
        if ($hash -notmatch '^[A-Fa-f0-9]{64}$' -or $hash -ine $handoff.($kind+'Sha256') -or
            !(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $hash) {
            throw "Neil build or Tara handoff $kind hash mismatch."
        }
    }
    if ($IntegrationTest) {
        if ([IO.Path]::GetFileName($build.ArtifactPath) -ine 'Repato.Revit.dll' -or (Get-Item -LiteralPath $build.ArtifactPath).Length -lt 1024) {
            throw 'Real integration requires a real Release DLL artifact.'
        }
        try { $artifactXml=[xml](Get-Content -LiteralPath $build.ManifestPath -Raw -ErrorAction Stop) }
        catch { throw 'Real integration requires a real artifact manifest.' }
        if ($artifactXml.DocumentElement.Name -cne 'RevitAddIns') { throw 'Real integration requires a real artifact manifest.' }
    }
    Import-Module (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -WarningAction SilentlyContinue
    $qaRoot = Get-MayaQaRoot
    $context = [pscustomobject]@{
        QaRoot=$qaRoot; SourceFixturePath=(Join-Path (Join-Path $qaRoot 'Fixtures') $definition.Source)
        FixtureId=$definition.FixtureId; FixtureSha256=$workflow.qaFixtureSha256; TestId=$definition.TestId
        ArtifactPath=$build.ArtifactPath; ArtifactSha256=$build.ArtifactSha256
        ManifestPath=$build.ManifestPath; ManifestSha256=$build.ManifestSha256
        TaskId=$TaskId; WorkflowId=$WorkflowId; QaWorkflowId=$QaWorkflowId; RunId=$RunId
    }
    try {
        $plan = New-TaraRevitQaPlan -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId `
            -QaWorkflowId $QaWorkflowId -RunId $RunId -ModelPath $ModelPath -SidecarPath $SidecarPath `
            -ReportDirectory $ReportDirectory -RevitInstallDir $RevitInstallDir -QaAddinRoot $QaAddinRoot `
            -TimeoutSeconds $TimeoutSeconds -Context $context -DryRun:$DryRun
    }
    catch {
        if (!$DryRun) { throw }
        $message=$_.Exception.Message
        $inaccessible=($message -match '^Path inaccessible:')
        return [pscustomobject]@{
            Success=$false;Mode='DryRun';Status='Invalid';Error=$message;ProcessStarted=$false
            SideEffectsPerformed=$false;ExitCode=$null;RequestPath=$null;ExecutablePath=$RevitInstallDir
            ModelPath=$ModelPath;QaAddinRoot=$QaAddinRoot
            ValidationResults=[pscustomobject]@{Validated=$false;PathInaccessible=$inaccessible;InaccessiblePath=$(if($inaccessible){($message -replace '^Path inaccessible: ','').Split('.')[0]}else{$null});PathMissing=(!$inaccessible -and $message -match 'missing');HashMismatch=(!$inaccessible -and $message -match 'hash mismatch')}
        }
    }
    if ($DryRun) { return Invoke-TaraRevitQa -Plan $plan -DryRun }

    # The store mutation uses its lock and optimistic revisions. Only one caller can claim execution.
    $executionId = [guid]::NewGuid().ToString('N')
    $started = [DateTimeOffset]::UtcNow.ToString('O')
    $null = Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {
        param($current)
        if ($current.PSObject.Properties.Name -contains 'qaTaraExecutionStatus' -and $current.qaTaraExecutionStatus) {
            throw 'Duplicate Tara execution rejected.'
        }
        $current | Add-Member NoteProperty qaTaraExecutionStatus 'Running' -Force
        $current | Add-Member NoteProperty qaTaraExecutionId $executionId -Force
        $current | Add-Member NoteProperty qaTaraExecutionStartedUtc $started -Force
        $current
    }
    try { $result = Invoke-TaraRevitQa -Plan $plan }
    catch {
        $result = [pscustomobject]@{Status='Failed'; TaskId=$TaskId; WorkflowId=$WorkflowId; QaWorkflowId=$QaWorkflowId;
            RunId=$RunId; Error=$_.Exception.Message; StartedUtc=$started; FinishedUtc=[DateTimeOffset]::UtcNow.ToString('O');
            SideEffectsPerformed=$true}
    }
    # Reload revisions after the potentially long native run. Never rerun Revit if persistence fails.
    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $task = Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId
    try {
        $null = Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {
            param($current)
            if ($current.qaTaraExecutionId -cne $executionId) { throw 'Tara execution claim changed.' }
            $current.qaTaraExecutionStatus = $result.Status
            $current | Add-Member NoteProperty qaTaraExecutionEvidence $result -Force
            $current
        }
    }
    catch { throw "Tara execution finished but store persistence failed: $($_.Exception.Message). Preserve bridge evidence; do not retry execution." }
    $result
}
