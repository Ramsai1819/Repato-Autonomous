$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=Split-Path $PSScriptRoot -Parent
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if($PSVersionTable.PSVersion.Major -ne 5 -or $identity.Name -ine 'RAMSAI\RepatoQA' -or $identity.User.Value -cne 'S-1-5-21-1031246752-3872016183-2454652381-1015'){throw 'Windows PowerShell5.1 under RepatoQA required.'}
$logs=Join-Path $repo 'QA\Engineering\CPV-RecoveredQaBindingEngineering130\readonly';New-Item -ItemType Directory -Path $logs -Force|Out-Null
$maya=Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -PassThru -WarningAction SilentlyContinue
& $maya {
    param($repo,$logs)
    $store=Join-Path $repo 'QA\MayaRuns';$id='task-bf61fe7f22d74df7a92599681da5919e';$wid='fa2c2f578cbc40cbacac45c96313ca4c'
    $commit='1b1a95443c2ff884aa69f068f26f6741aaa412bf';$hash='01C700B2F113871DAB18F4049FF3539A6BCB82FBA9716C2E398C70F86C441A54'
    $task=Find-RepatoTask (Read-RepatoTaskStore $store) $id;$w=Get-DeployWorkflow $store $id $wid;$e=$w.qaBuildEvidence
    if($task.revision -ne 130 -or $task.cpvPreparationRecovery.Status -cne 'RecoveredVerified' -or $e.CandidateSourceCommit -cne $commit -or $e.ArtifactSha256 -cne $hash -or $e.BuildRequestId -cne 'build-0cb433fde96248ea94ef0fe5e86a2c23'){throw 'Expected revision130 adopted candidate mismatch.'}
    if($e.DeploymentValidation -or $e.ManifestIntegrityValidation -or $e.QaIsolation){throw 'Existing binding changed.'}
    if(@(Get-Process Revit,RevitWorker -ErrorAction SilentlyContinue).Count){throw 'Revit process present.'}
    $prior=Get-Content (Join-Path $repo 'QA\Engineering\CPV-CandidateAdoption127-20261019\protected-before.json') -Raw|ConvertFrom-Json
    $paths=@($prior.Path)+@((Join-Path $store 'tasks.json'),(Join-Path $store 'status.json'))
    $before=@($paths|Sort-Object -Unique|ForEach-Object{[pscustomobject]@{Path=$_;Sha256=(Get-FileHash -LiteralPath $_).Hash}})
    foreach($file in $prior){if((Get-FileHash -LiteralPath $file.Path).Hash -cne $file.Sha256){throw 'Protected deployment evidence changed since adoption.'}}
    $release=Join-Path $repo ('DeploymentCandidates\AgentReleases\Repato.QaLaunchAgent-1.0.23+'+$commit)
    if((Get-FileHash (Join-Path $release 'Repato.QaLaunchAgent.release.json')).Hash -cne '13D029BA4366E2FDF2321FAEE37F0BD765A592389AFC9D74C213B06C7E71A128'){throw 'Agent manifest changed.'}
    $manifest=Get-Content (Join-Path $release 'Repato.QaLaunchAgent.release.json') -Raw|ConvertFrom-Json
    foreach($f in $manifest.files){if((Get-FileHash (Join-Path $release $f.name)).Hash -cne $f.sha256 -or (Get-FileHash (Join-Path 'C:\Program Files\Repato\QaLaunchAgent' $f.name)).Hash -cne $f.sha256){throw 'Immutable or installed agent hash changed.'}}
    $health=Invoke-MayaQaLaunchAgentHealth -TimeoutMilliseconds 10000
    $cpv=Import-Module (Join-Path $repo 'AgentOrchestration\Repato.CpvPreparationRecovery.psm1') -PassThru -WarningAction SilentlyContinue
    $cap=& $cpv {Get-CpvPreparationCapabilities}
    if(!$health.Ready -or !$health.UserInteractive -or $health.User -ine 'RAMSAI\RepatoQA' -or $health.SID -cne 'S-1-5-21-1031246752-3872016183-2454652381-1015' -or $cap.runtimeVersion -cne ('1.0.23+'+$commit) -or $health.SessionId -ne $cap.sessionId){throw 'Authenticated agent identity mismatch.'}
    $candidate=New-MayaQaPersistedCandidateEvidence -StoreRoot $store -TaskId $id -WorkflowId $wid -QaWorkflowId 'create-plan-views-v1' -TestId 'create-plan-views-v1'
    $preflight=Invoke-MayaQaLaunchAgentPreflightReadonly -CandidateEvidence $candidate -TaskId $id -WorkflowId $wid -QaWorkflowId 'create-plan-views-v1' -TestId 'create-plan-views-v1' -CandidateCommit $commit -ExpectedCandidateSha256 $hash -TimeoutMilliseconds 10000
    if(!$preflight.Succeeded){throw 'Candidate-aware installed deployment preflight failed.'}
    $blocker=$null
    try {
        # Audited DryRun returns before creating any validation operation or sending validation.
        $dryRun=Invoke-MayaQaIndependentDeploymentValidationRecovery -StoreRoot $store -TaskId $id -WorkflowId $wid -ExpectedTaskRevision 130 -ExpectedBuildRequestId $e.BuildRequestId -ExpectedCandidateSourceCommit $commit -ExpectedCandidateSha256 $hash -ExpectedRunnerManifestPath 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin' -ExpectedRunnerManifestSha256 $e.RunnerManifestSha256 -DryRun
    }catch{$blocker=$_.Exception.Message}
    foreach($file in $before){if((Get-FileHash -LiteralPath $file.Path).Hash -cne $file.Sha256){throw 'Read-only binding preflight changed protected evidence.'}}
    if($blocker){throw $blocker};if($dryRun.Status -cne 'DryRun' -or $dryRun.SideEffectsPerformed){throw 'Read-only continuation validation failed.'}
    $result=[pscustomobject]@{BindingAttempted=$false;BindingReady=$true;TaskRevision=130;WorkflowStage=$task.workflowStage;DeploymentEvidenceBound=$false;HashesVerified=$true;AgentHealth=$health;EvidenceIntegrity=$true;ProtectedFileCount=$before.Count;RevitLaunched=$false;GuardFailure=$blocker;SupportedCommand='Invoke-MayaQaIndependentDeploymentValidationRecovery';ProductionMutation=$false}
    [IO.File]::WriteAllText((Join-Path $logs 'readonly-result.json'),($result|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
    $result|ConvertTo-Json -Depth 8
} $repo $logs
