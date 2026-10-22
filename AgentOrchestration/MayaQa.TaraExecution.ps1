# Loaded in the Maya workflow module. Importing this file performs no execution.
function Invoke-MayaQaTaraExecute {
    [CmdletBinding()]
    param(
        [string]$StoreRoot,
        [string]$TaskId,
        [string]$WorkflowId,
        [string]$QaWorkflowId,
        [string]$RunId,
        [string]$ModelPath,
        [string]$SidecarPath,
        [Parameter(Mandatory)][string]$ReportDirectory,
        [string]$RevitInstallDir = 'E:\revit\Revit 2025',
        [Parameter(Mandatory)][string]$QaAddinRoot,
        [ValidateRange(1,86400)][int]$TimeoutSeconds = 900,
        [switch]$LocalRun,
        [switch]$DryRun,
        [switch]$IntegrationTest
        ,[string]$HandoffPath
        ,[scriptblock]$CanonicalProcessLauncher
        ,[object]$CanonicalResult
    )
    if([string]::IsNullOrWhiteSpace($HandoffPath) -and [string]::IsNullOrWhiteSpace($StoreRoot)){throw 'StoreRoot is required when HandoffPath is not supplied.'}
    $resolvedFromTaskStore=$false
    if([string]::IsNullOrWhiteSpace($HandoffPath) -and $TaskId -and ([string]::IsNullOrWhiteSpace($WorkflowId) -or [string]::IsNullOrWhiteSpace($QaWorkflowId) -or [string]::IsNullOrWhiteSpace($RunId))){
        $storedTask=(Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId)
        $probe=Resolve-MayaQaTaskStoreIdentity $StoreRoot $TaskId $(if($WorkflowId){$WorkflowId}else{$storedTask.mayaPlan.WorkflowId}) $(if($QaWorkflowId){$QaWorkflowId}else{$storedTask.mayaPlan.QaWorkflowId})
        if(@($probe.Errors).Count){throw ('Persisted Maya identity chain is invalid: '+(@($probe.Errors)-join '; '))}
        $WorkflowId=$probe.SelectedWorkflowId;$QaWorkflowId=$probe.SelectedQaWorkflowId;$RunId=$probe.SelectedRunId;$resolvedFromTaskStore=$true
        if($DryRun){
            $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId;$packet=$task.mayaTaraQaPacket
            Import-Module (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -WarningAction SilentlyContinue
            $definition=Get-MayaQaWorkflowDefinition $probe.SelectedQaWorkflowId;$qaRoot=[IO.Path]::GetFullPath((Get-MayaQaRoot));$source=[IO.Path]::GetFullPath($packet.FixturePath);$qaRuns=[IO.Path]::GetFullPath((Join-Path $qaRoot 'TestRuns'));$runtime=[IO.Path]::GetFullPath((Join-Path $qaRuns ($probe.SelectedRunId+'-preflight')));$prefix=$qaRuns.TrimEnd('\')+'\';if(!$runtime.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Disposable QA runtime escaped approved QA root.'};if($source -ieq $runtime -or !$source.StartsWith(([IO.Path]::GetFullPath((Join-Path $qaRoot 'Fixtures')).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Authoritative fixture path is invalid.'};$sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;if($sourceHash -ine $packet.FixtureSha256){throw 'Authoritative fixture hash mismatch.'};New-Item -ItemType Directory -Path $runtime -Force|Out-Null;$model=Join-Path $runtime 'model.rvt';$sidecar=$model+'.fixture.json';Copy-Item -LiteralPath $source -Destination $model -Force;$copyHash=(Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash;if($copyHash -ine $sourceHash){throw 'Disposable fixture hash mismatch.'};[ordered]@{fixtureId=$definition.FixtureId;sourceSha256=$sourceHash}|ConvertTo-Json|Set-Content -LiteralPath $sidecar -Encoding UTF8
            $context=[pscustomobject]@{QaRoot=$qaRoot;SourceFixturePath=$source;FixtureId=$definition.FixtureId;FixtureSha256=$sourceHash;TestId=(Get-MayaQaNativeTestId $definition);ArtifactPath=$packet.ArtifactPath;ArtifactSha256=$packet.ArtifactSha256;ManifestPath=$packet.ManifestPath;ManifestSha256=$packet.ManifestSha256;TaskId=$probe.SelectedTaskId;WorkflowId=$probe.SelectedWorkflowId;QaWorkflowId=$probe.SelectedQaWorkflowId;RunId=$probe.SelectedRunId}
            try{$plan=New-TaraRevitQaPlan -StoreRoot $StoreRoot -TaskId $probe.SelectedTaskId -WorkflowId $probe.SelectedWorkflowId -QaWorkflowId $probe.SelectedQaWorkflowId -RunId $probe.SelectedRunId -ModelPath $model -SidecarPath $sidecar -ReportDirectory $ReportDirectory -RevitInstallDir $RevitInstallDir -QaAddinRoot $QaAddinRoot -TimeoutSeconds $TimeoutSeconds -Context $context -DryRun; $safe=Invoke-TaraRevitQa -Plan $plan -DryRun;return [pscustomobject]@{Success=$safe.Success;Mode='Preflight';Stage='qa-launch-preparation';TaskId=$probe.SelectedTaskId;WorkflowId=$probe.SelectedWorkflowId;QaWorkflowId=$probe.SelectedQaWorkflowId;TestId=$context.TestId;HandoffId=$probe.SelectedHandoffId;AttemptId=$probe.SelectedAttemptId;RunId=$probe.SelectedRunId;FixturePath=$source;FixtureSha256=$sourceHash;DisposableFixturePath=$model;DisposableFixtureSha256=$copyHash;ArtifactPath=$context.ArtifactPath;ArtifactSha256=$context.ArtifactSha256;RunnerManifest=$plan.QaRunnerManifestPath;RunnerManifestSha256=$plan.QaRunnerManifestSha256;Command=$plan.Command;Isolation=$plan.Isolation;ReadyToLaunch=$safe.Success;ProcessStarted=$false;SideEffectsPerformed=$false;Errors=@()}}catch{$msg=$_.Exception.Message;return [pscustomobject]@{Success=$false;Mode='Preflight';Stage='qa-launch-preparation';TaskId=$probe.SelectedTaskId;WorkflowId=$probe.SelectedWorkflowId;QaWorkflowId=$probe.SelectedQaWorkflowId;TestId=$context.TestId;HandoffId=$probe.SelectedHandoffId;AttemptId=$probe.SelectedAttemptId;RunId=$probe.SelectedRunId;FixturePath=$source;FixtureSha256=$sourceHash;DisposableFixturePath=$model;DisposableFixtureSha256=$copyHash;ReadyToLaunch=$false;ProcessStarted=$false;SideEffectsPerformed=$false;Errors=@($msg)}}
        }
    }
    if($HandoffPath){$h=Get-Content -LiteralPath $HandoffPath -Raw|ConvertFrom-Json;foreach($n in @('StoreRoot','TaskId','WorkflowId','QaWorkflowId','RunId','HandoffId','ModelPath','SidecarPath','ArtifactPath','ArtifactSha256','ManifestPath','ManifestSha256')){if($h.PSObject.Properties.Name -notcontains $n -or [string]::IsNullOrWhiteSpace([string]$h.$n)){throw "Invalid handoff: missing $n"}};if($StoreRoot -and [IO.Path]::GetFullPath($StoreRoot) -ine [IO.Path]::GetFullPath($h.StoreRoot)){throw 'Supplied StoreRoot does not match the durable handoff.'};foreach($p in @('HandoffPath','StoreRoot','ModelPath','SidecarPath','ArtifactPath','ManifestPath')){ $v=if($p -eq 'HandoffPath'){$HandoffPath}else{$h.$p};if(!(Test-Path -LiteralPath $v)){throw "Invalid handoff accessibility: $p is missing or unreadable ($v)."}};$StoreRoot=$h.StoreRoot;$TaskId=$h.TaskId;$WorkflowId=$h.WorkflowId;$QaWorkflowId=$h.QaWorkflowId;$RunId=$h.RunId;$ModelPath=$h.ModelPath;$SidecarPath=$h.SidecarPath}
    foreach ($identity in @($TaskId,$WorkflowId,$QaWorkflowId,$RunId)) {
        if ($identity -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$') { throw 'Invalid Tara workflow identity.' }
    }
    if (!$DryRun -and !$IntegrationTest) { throw 'Real Tara execution requires explicit -IntegrationTest authorization in an interactive RepatoQA session.' }

    # Canonical Maya executions are owned by mayaTaraExecution.  Route these
    # through the lifecycle-connected native core before touching the legacy
    # deployment workflow surface.  This is deliberately detected from the
    # task record, so canonical execution remains valid when
    # deploymentWorkflows is absent altogether.
    if ($TaskId -and $StoreRoot) {
        $canonicalData = Read-RepatoTaskStore $StoreRoot
        $canonicalTask = Find-RepatoTask $canonicalData $TaskId
        if ($canonicalTask.PSObject.Properties.Name -contains 'mayaTaraExecution' -and $canonicalTask.mayaTaraExecution) {
            $canonical = $canonicalTask.mayaTaraExecution
            if ($DryRun) {
                return [pscustomobject]@{Success=$true;Mode='Canonical';Stage=$canonical.Stage;ExecutionStatus=$canonical.ExecutionStatus;TaskId=$canonical.TaskId;WorkflowId=$canonical.WorkflowId;QaWorkflowId=$canonical.QaWorkflowId;AttemptId=$canonical.AttemptId;RunId=$canonical.RunId;ClaimId=$canonical.ClaimId;ProcessStarted=$false;SideEffectsPerformed=$false}
            }
            if ([string]::IsNullOrWhiteSpace([string]$canonical.ClaimId)) { throw 'Canonical Maya execution is not claimed.' }
            $exe = Join-Path $RevitInstallDir 'Revit.exe'
            if($canonical.Stage -ceq 'executing') { return Resume-MayaQaCanonicalExecution -StoreRoot $StoreRoot -TaskId $TaskId -ClaimId $canonical.ClaimId -ResultPath $canonical.ResultPath -TimeoutSeconds $TimeoutSeconds }
            return Invoke-MayaQaCanonicalNativeCore -StoreRoot $StoreRoot -TaskId $TaskId -ClaimId $canonical.ClaimId -Executable $exe -Arguments '' -ProcessLauncher $CanonicalProcessLauncher -Result $CanonicalResult
        }
        if ($canonicalTask.PSObject.Properties.Name -contains 'mayaTaraAttempt' -and $canonicalTask.mayaTaraAttempt) {
            throw 'Canonical Maya Tara attempt exists without an execution record; legacy Tara dispatch is forbidden.'
        }
    }
    $definition = Get-MayaQaWorkflowDefinition $QaWorkflowId
    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $data = Read-RepatoTaskStore $StoreRoot
    $task = Find-RepatoTask $data $TaskId
    $properties = @($workflow.PSObject.Properties.Name)
    if ($properties -contains 'qaTaraExecutionStatus' -and $workflow.qaTaraExecutionStatus) {
        throw 'Duplicate Tara execution rejected. Preserve the existing execution and prepare a new workflow for any retry.'
    }
    $missing=@(); foreach ($required in @('qaBuildEvidence','qaBuildStatus','qaHandoff','qaHandoffId','qaApprovalId','qaApprovalStatus',
        'qaRunId','qaWorkflowId','qaModelPath','qaSidecarPath','qaFixtureId','qaFixtureSha256','qaTestId'
        )) { if ($properties -notcontains $required -or !$workflow.$required) { $missing += $required } }
    if($missing.Count){throw "Required Tara prerequisite is missing or invalid: $($missing -join ', ')"}
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
    $nativeTestId = if (Get-Command Get-MayaQaNativeTestId -ErrorAction SilentlyContinue) {
        Get-MayaQaNativeTestId $definition
    } elseif ($definition.PSObject.Properties.Name -contains 'NativeTestId' -and $definition.NativeTestId) {
        [string]$definition.NativeTestId
    } else {
        [string]$definition.TestId
    }
    if ($handoff.HandoffId -cne $workflow.qaHandoffId -or $handoff.HandoffStatus -cne 'ready' -or
        $handoff.TaskId -cne $TaskId -or $handoff.QaWorkflowId -cne $QaWorkflowId -or
        (($handoff.PSObject.Properties.Name -contains 'BuildRequestId') -and $handoff.BuildRequestId -cne $buildRequestId) -or
        $handoff.FixtureId -cne $definition.FixtureId -or
        $handoff.NativeTestId -cne $nativeTestId) { throw 'Tara handoff identity mismatch.' }
    if ($workflow.taskId -cne $TaskId -or $workflow.qaWorkflowId -cne $QaWorkflowId -or
        $workflow.qaRunId -cne $RunId -or $workflow.qaFixtureId -cne $definition.FixtureId -or
        $workflow.qaTestId -cne $nativeTestId) { throw 'Tara QA run plan identity mismatch.' }
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
        FixtureId=$definition.FixtureId; FixtureSha256=$workflow.qaFixtureSha256; TestId=$nativeTestId
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

