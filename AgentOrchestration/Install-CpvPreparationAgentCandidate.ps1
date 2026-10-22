[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReleaseRoot,[Parameter(Mandatory)][string]$ManifestSha256,[switch]$Execute,[switch]$PreflightOnly,
    [string]$ReconcileRequestId,[string]$CompletedOutcomeRecoveryRequestId,[switch]$RecoveredNativeContinuation,[long]$ExpectedTaskRevision=101,
    [string]$TaskId='task-bf61fe7f22d74df7a92599681da5919e')
$ErrorActionPreference='Stop'
function Get-CpvRevitProcesses {
    try { @(Get-Process -Name Revit -ErrorAction Stop) }
    catch {
        if($_.FullyQualifiedErrorId -like 'NoProcessFoundForGivenName,*'){ return @() }
        throw
    }
}
if($Execute -and $PreflightOnly){throw '-Execute and -PreflightOnly are mutually exclusive; installation is not authorized by a preflight.'}
if(!$Execute -and !$PreflightOnly){throw 'Installation is not automatic. Explicit deployment authorization and -Execute are required.'}
$principal=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Installation requires an elevated administrator PowerShell.'}
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationRecovery.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationUpgrade.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvCompletedOutcomeUpgrade.psm1') -Force -WarningAction SilentlyContinue
if($RecoveredNativeContinuation){Import-Module (Join-Path $PSScriptRoot 'Repato.CpvRecoveredNativeUpgrade.psm1') -Force -WarningAction SilentlyContinue}
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
. (Join-Path $PSScriptRoot 'Repato.QaLaunchAgentInstall.ps1')
$bootstrap=Resolve-RepatoQaLaunchAgentBootstrapModule -ModulePath (Join-Path $PSScriptRoot '../QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1')
$contract=Get-RepatoQaLaunchAgentBootstrapContract
$manifest=Join-Path $ReleaseRoot 'Repato.QaLaunchAgent.release.json'
if((Get-FileHash $manifest).Hash -cne $ManifestSha256){throw 'Release manifest hash mismatch.'}
$requestedVersion=[string](Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json).productVersion
if(($requestedVersion -match '^1\.0\.23\+') -ne [bool]$RecoveredNativeContinuation){throw 'Release 1.0.23 requires exactly the explicit recovered-native continuation deployment mode.'}
$activeRoot='C:\Users\RepatoQA\AppData\Local\Repato\QaLaunchAgent\Logs\CpvPreparation'
$activePath=Join-Path $activeRoot 'active.json';$upgrade=$null;$evidenceSnapshot=$null;$validated=$null;$priorFiles=@();$priorTaskValid=$false
if((Test-Path -LiteralPath $activePath) -or $RecoveredNativeContinuation){
    if($RecoveredNativeContinuation){
        if($ReconcileRequestId -or $CompletedOutcomeRecoveryRequestId -or $ExpectedTaskRevision -ne 127){throw 'Recovered-native upgrade requires revision 127 and no legacy upgrade mode.'}
        $upgradeRequestId='c11b311638a54bfc9ebdd1803671ec40';$completedOutcomeUpgrade=$false
    }elseif($CompletedOutcomeRecoveryRequestId){
        if($ReconcileRequestId -or $CompletedOutcomeRecoveryRequestId -cne 'c11b311638a54bfc9ebdd1803671ec40') {throw 'Completed-outcome upgrade request identity is invalid or ambiguous.'}
        $upgradeRequestId=$CompletedOutcomeRecoveryRequestId;$completedOutcomeUpgrade=$true
    }else{
        if(!$ReconcileRequestId){throw 'An active/interrupted preparation must be reconciled before agent installation.'}
        if($ReconcileRequestId -cne '9953e14c15524fe09440d1c7d7353950'){throw 'Only an exact supported CPV recovery request may use this upgrade exception.'}
        $upgradeRequestId=$ReconcileRequestId;$completedOutcomeUpgrade=$false
    }
    if($TaskId -cne 'task-bf61fe7f22d74df7a92599681da5919e'){throw 'Guarded CPV upgrade task identity is invalid.'}
    if(@(Get-CpvRevitProcesses).Count){throw 'Revit is running; the guarded upgrade is unavailable.'}
    $agents=@(Get-Process -Name Repato.QaLaunchAgent -ErrorAction Stop)
    if($agents.Count -ne 1 -or $agents[0].ProcessName -cne 'Repato.QaLaunchAgent' -or $agents[0].Path -ine $contract.Executable){throw 'One exact installed Launch Agent process is required.'}
    $processIdentity=Get-RepatoQaLaunchAgentProcessIdentity -ProcessId $agents[0].Id
    if(!$processIdentity -or $processIdentity.ProcessName -cne 'Repato.QaLaunchAgent' -or $processIdentity.Path -ine $contract.Executable){throw 'Installed Launch Agent process identity is unavailable.'}
    $ownerSid=[string]$processIdentity.OwnerSid
    if(!$ownerSid){throw 'Installed Launch Agent process SID is unavailable.'}
    $ownerName=([Security.Principal.SecurityIdentifier]$ownerSid).Translate([Security.Principal.NTAccount]).Value
    $capabilities=Get-CpvPreparationCapabilities
    $request=[pscustomobject]@{schemaVersion=1;operation='cpv-preparation-status';requestId=$upgradeRequestId}
    $receipt=Invoke-CpvPreparationTransport $request
    $priorFiles=@(foreach($name in $contract.RuntimeFiles){$path=Join-Path $contract.InstallRoot $name;if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Prior runtime rollback file is missing: $name"};[pscustomobject]@{name=$name;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}})
    $priorTaskEvidence=Get-RepatoQaLaunchAgentTaskEvidence -BootstrapModule $bootstrap
    $priorTaskValid=[bool]$priorTaskEvidence.Valid
    $validated=& $bootstrap {param($root,$path,$hash) Read-ValidatedManifest $root $path $hash} $ReleaseRoot $manifest $ManifestSha256.ToUpperInvariant()
    $productVersion=(Get-Item -LiteralPath $agents[0].Path).VersionInfo.ProductVersion
    $installedIdentity=[pscustomobject]@{ProcessName=$agents[0].ProcessName;Path=$agents[0].Path;ProductVersion=$productVersion;Id=$agents[0].Id;StartTime=$agents[0].StartTime;User=$ownerName;Sid=$ownerSid;SessionId=$agents[0].SessionId}
    if($RecoveredNativeContinuation){
        $recoveredReceipt=Invoke-CpvPreparationTransport ([pscustomobject]@{schemaVersion=1;operation='cpv-preparation-recover-completed-status';requestId=$upgradeRequestId})
        $upgrade=Assert-CpvRecoveredNativeUpgrade -EvidenceRoot $activeRoot -RuntimeRoot 'C:\Repato-Autonomous\Source\QA\TestRuns' `
            -RequestId $upgradeRequestId -TaskId $TaskId -ExpectedTaskRevision $ExpectedTaskRevision -StoreRoot (Join-Path $PSScriptRoot '..\QA\MayaRuns') `
            -Capabilities $capabilities -Receipt $receipt -InstalledAgent $installedIdentity -ProcessSid $ownerSid `
            -ExpectedExecutable $contract.Executable -ExpectedInstalledVersion '1.0.22+6119aceaab0a34c3e0323089a29f1cefb2c14aaa' -CandidateRoot $validated.SourceRoot `
            -CandidateManifestPath $manifest -CandidateManifestSha256 $ManifestSha256 -PriorRuntimeFiles $priorFiles `
            -PriorTaskContractValid ([bool]$priorTaskValid) -NoRevitProcesses $true -BootstrapModule $bootstrap -RecoveryReceipt $recoveredReceipt
    }elseif($completedOutcomeUpgrade){
        $transitionEvidence=@{}
        $expectedCompletedVersion='1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e'
        if($productVersion -ceq '1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f'){
            $expectedCompletedVersion=$productVersion
            $recoveryModule=Import-Module (Join-Path $PSScriptRoot 'Repato.CpvCompletedOutcomeRecovery.psm1') -PassThru -WarningAction SilentlyContinue
            $transitionEvidence=& $recoveryModule {param($store,$id,$revision)
                $t=Find-RepatoTask (Read-RepatoTaskStore $store) $id
                if($t.revision -ne $revision -or $revision -ne 122){throw 'Revision-122 transition is stale.'}
                $a=Assert-CpvOutcomeRecoveryReservationResettable -Task $t -ApprovalId 'acfd8643ed2846b8a43b98d3a74c3217'
                $current=Assert-CpvOutcomeRecoveryResult -Task $t -Recovery $t.cpvPreparationRecovery -ExpectedTaskRevision $a.outcomeRecoveryBinding.ExpectedTaskRevision -Transport $null
                $null=Assert-CpvOutcomeRecoveryApprovedSnapshotCurrent -Binding $a.outcomeRecoveryBinding -Current $current
                $b=$a.outcomeRecoveryBinding;$r=$t.cpvPreparationRecovery.Request
                $query=[pscustomobject]@{schemaVersion=1;operation='cpv-preparation-recover-completed-reconcile';requestId=$r.requestId;taskId=$id;workflowId=$r.workflowId;attemptId=$r.attemptId;runId=$r.runId;recoveryApprovalId=$a.requestId;approvalBindingHash=$a.bindingHash;originalReceiptSha256=$b.Snapshot.OriginalReceiptSha256;activeMarkerSha256=$b.Snapshot.ActiveMarkerSha256;failureEvidenceSha256=$b.Snapshot.FailureEvidenceSha256;requestSha256=$b.Snapshot.PreparationRequestSha256}
                $proof=Invoke-CpvPreparationTransport $query
                $null=Assert-CpvOutcomeRecoveryNonExecutionProof -Proof $proof -Approval $a -Request $r
                @{NonExecutionProof=$proof;CurrentApprovedSnapshot=$current}
            } (Join-Path $PSScriptRoot '..\QA\MayaRuns') $TaskId $ExpectedTaskRevision
        }
        $upgrade=Assert-CpvCompletedOutcomeUpgrade -EvidenceRoot $activeRoot -RuntimeRoot 'C:\Repato-Autonomous\Source\QA\TestRuns' `
            -RequestId $upgradeRequestId -TaskId $TaskId -ExpectedTaskRevision $ExpectedTaskRevision -StoreRoot (Join-Path $PSScriptRoot '..\QA\MayaRuns') `
            -Capabilities $capabilities -Receipt $receipt -InstalledAgent $installedIdentity -ProcessSid $ownerSid `
            -ExpectedExecutable $contract.Executable -ExpectedInstalledVersion $expectedCompletedVersion -CandidateRoot $validated.SourceRoot `
            -CandidateManifestPath $manifest -CandidateManifestSha256 $ManifestSha256 -PriorRuntimeFiles $priorFiles `
            -PriorTaskContractValid ([bool]$priorTaskValid) -NoRevitProcesses $true -BootstrapModule $bootstrap @transitionEvidence
    }else{
        $upgrade=Assert-CpvPreparationUpgradeEvidence -EvidenceRoot $activeRoot -RuntimeRoot 'C:\Repato-Autonomous\Source\QA\TestRuns' `
            -RequestId $upgradeRequestId -TaskId $TaskId -Capabilities $capabilities -Receipt $receipt -InstalledAgent $installedIdentity -ProcessSid $ownerSid `
            -ExpectedExecutable $contract.Executable -ExpectedInstalledVersion '1.0.17+4b0066247088' -CandidateRoot $validated.SourceRoot `
            -CandidateManifestPath $manifest -CandidateManifestSha256 $ManifestSha256 -PriorRuntimeFiles $priorFiles `
            -PriorTaskContractValid ([bool]$priorTaskValid) -NoRevitProcesses $true
    }
    $evidenceSnapshot=Get-CpvPreparationUpgradeEvidenceSnapshot -EvidenceRoot $activeRoot -RunDirectory $upgrade.RunDirectory
} elseif($ReconcileRequestId -or $CompletedOutcomeRecoveryRequestId -or $RecoveredNativeContinuation){throw 'A guarded upgrade request was supplied but no matching active marker exists.'}
$revit=@(Get-CpvRevitProcesses)
if($revit.Count){throw 'Revit must be stopped.'}
$agents=@(Get-Process Repato.QaLaunchAgent -ErrorAction SilentlyContinue)
if($agents.Count -ne 1 -or $agents[0].Path -ine $contract.Executable){throw 'One exact installed Launch Agent process is required.'}
if(!$capabilities){$capabilities=Get-CpvPreparationCapabilities}
$agentHealth=Invoke-MayaQaLaunchAgentHealth -TimeoutMilliseconds 3000
$agentHealthSid=Get-CpvHealthSid -Health $agentHealth
if(!$agentHealth.Ready -or $agentHealth.User -ine 'RAMSAI\RepatoQA' -or $agentHealthSid -cne 'S-1-5-21-1031246752-3872016183-2454652381-1015' -or $agentHealth.SessionId -ne $agents[0].SessionId -or $agentHealth.SessionId -ne $capabilities.sessionId){throw 'Installed Launch Agent authenticated session identity is invalid.'}
$token=$null;$installAttempted=$false;$journalLease=$null
if($PreflightOnly){
    [pscustomobject]@{
        Mode='PreflightOnly';TaskId=$TaskId;ExpectedTaskRevision=[long]$ExpectedTaskRevision
        RequestId=$(if($upgrade){$upgradeRequestId}else{$null});UpgradeAccepted=[bool]$upgrade
        CandidateVersion=$(if($upgrade){$upgrade.CandidateVersion}else{$null})
        JournalGeneration=$(if($upgrade){$upgrade.JournalGeneration}else{$null})
        ManifestSha256=$ManifestSha256.ToUpperInvariant()
        RuntimeVersion=$(if($validated){$validated.Manifest.productVersion}else{$null})
        PriorRuntimeFileCount=@($priorFiles).Count
        PriorTaskContractValid=[bool]$priorTaskValid
        EvidenceSnapshotPresent=[bool]$evidenceSnapshot
        AgentPid=$agents[0].Id;AgentStartTime=$agents[0].StartTime.ToString('o');AgentSessionId=[long]$agents[0].SessionId
        AgentHealthReady=[bool]$agentHealth.Ready;AgentHealthSessionId=[long]$agentHealth.SessionId
        CapabilitiesSessionId=[long]$capabilities.sessionId
        RevitProcessCount=0
        SideEffectsPerformed=$false;RevitLaunched=$false;InstallationPerformed=$false
    }|ConvertTo-Json -Depth 5
    return
}
try {
    if($upgrade){
        $journalLease=New-RepatoQaLaunchAgentBootstrapInstallJournal -SourceRoot $ReleaseRoot -ManifestPath $manifest -ManifestSha256 $ManifestSha256 -RequestId $upgradeRequestId -TaskId $TaskId -RecoveredNativeContinuation:$RecoveredNativeContinuation
        & $bootstrap {param($lease) $j=Get-InstallJournal $lease;if($j.state -cne 'CandidateStaged'){throw 'Candidate stage was not durably verified.'};Set-InstallJournalState $j 'ServiceStopPending'|Out-Null} $journalLease
    }
    Stop-RepatoQaLaunchAgentForUpdate -ExpectedAgentPid $agents[0].Id -ExpectedAgentStartTime $agents[0].StartTime.ToString('o') -ExpectedSessionId $capabilities.sessionId -AgentExe $contract.Executable -TaskPath $contract.TaskPath -TaskName $contract.TaskName -BootstrapModule $bootstrap
    if($journalLease){& $bootstrap {param($lease) $j=Get-InstallJournal $lease;if($j.state -cne 'ServiceStopPending'){throw 'Service-stop boundary was not durably recorded.'};Set-InstallJournalState $j 'ServiceStopped'|Out-Null} $journalLease}
    $installAttempted=$true
    $installed=Install-RepatoQaLaunchAgentBootstrap -SourceRoot $ReleaseRoot -ManifestPath $manifest -ManifestSha256 $ManifestSha256 -RetainRollback -DurableJournal $journalLease
    $token=$installed.RollbackToken
    if($upgrade){
        if(!$token -or !$token.Updated -or !$token.BackupRoot -or !(Test-Path -LiteralPath $token.BackupRoot -PathType Container) -or !$token.OldTaskXml){throw 'Verified prior-runtime rollback evidence was not retained.'}
        $backup=Get-RepatoQaLaunchAgentRuntimeIntegrity $token.BackupRoot ([pscustomobject]@{files=$token.PriorFiles})
        if(@($backup|Where-Object {!$_.Match}).Count){throw 'Retained rollback bytes failed integrity validation.'}
        foreach($prior in $upgrade.PriorFiles){$bound=@($token.PriorFiles|Where-Object name -ceq $prior.name);if($bound.Count -ne 1 -or $bound[0].sha256 -ine $prior.sha256){throw 'Retained rollback bytes differ from the verified prior runtime.'}}
    }
    $checked=Test-RepatoQaLaunchAgentBootstrap -ManifestPath $manifest -ManifestSha256 $ManifestSha256
    if(!$checked.InstalledRuntimeIntegrity -or !$checked.TaskContractValid){throw 'Installed runtime/task integrity failed.'}
    if($journalLease){Set-RepatoQaLaunchAgentBootstrapInstallHealthVerification -JournalLease $journalLease}
    Start-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName
    Start-Sleep -Seconds 2
    $capabilities=Get-CpvPreparationCapabilities
    if($upgrade){
        if($capabilities.reconciliationOperation -cne 'cpv-preparation-reconcile-failed'){throw 'Installed agent does not advertise the exact reconciliation capability.'}
        if(($completedOutcomeUpgrade -or $RecoveredNativeContinuation) -and ($capabilities.recoveryOperation -cne 'cpv-preparation-recover-completed' -or
            $capabilities.recoveryStatusOperation -cne 'cpv-preparation-recover-completed-status' -or $capabilities.runtimeVersion -cne $validated.Manifest.productVersion)){
            throw 'Installed agent does not advertise the exact completed-outcome recovery runtime.'
        }
        $status=Invoke-CpvPreparationTransport $request
        foreach($name in 'requestId','taskId','workflowId','attemptId','runId','status','failureCode') {if($status.$name -cne $receipt.$name){throw "Protected preparation status changed during upgrade: $name"}}
        if(!(Test-CpvPreparationUpgradeEvidenceSnapshot -Before $evidenceSnapshot -EvidenceRoot $activeRoot -RunDirectory $upgrade.RunDirectory)){throw 'Protected preparation evidence changed during upgrade.'}
    }
    $null=Complete-RepatoQaLaunchAgentBootstrapInstall -RollbackToken $token;$token=$null;$journalLease=$null
    $capabilities|ConvertTo-Json
} catch {
    $failure=$_
    $durableRecoveryHandled=$false
    if($token -and $token.DurableJournal){Restore-RepatoQaLaunchAgentBootstrapInstall -RollbackToken $token|Out-Null;$durableRecoveryHandled=$true}
    elseif($journalLease){
        try{& $bootstrap {param($lease,$context) Invoke-InstallJournalRecoveryCore $lease $context} $journalLease (& $bootstrap { New-RealBootstrapContext })|Out-Null}
        finally{& $bootstrap {param($lease) Close-InstallJournalLease $lease} $journalLease}
        $durableRecoveryHandled=$true
    }
    if(!$durableRecoveryHandled){
        $rollbackVerified=$false
        $processes=@(Get-Process -Name Repato.QaLaunchAgent -ErrorAction SilentlyContinue)
        if($processes.Count -gt 1){throw 'Multiple Launch Agent processes prevent safe installer recovery; task remains stopped.'}
        if($processes.Count){
            $process=$processes[0]
            if($process.Path -ine $contract.Executable){throw 'Unexpected Launch Agent process prevents safe installer recovery; task remains stopped.'}
            try {
                $health=Invoke-MayaQaLaunchAgentHealth -TimeoutMilliseconds 3000
                $healthSid=Get-CpvHealthSid -Health $health
                if(!$health.Ready -or $health.User -ine 'RAMSAI\RepatoQA' -or $healthSid -cne 'S-1-5-21-1031246752-3872016183-2454652381-1015' -or $health.SessionId -ne $process.SessionId){throw 'Launch Agent session identity is unverified; task remains stopped.'}
            } catch { throw "Installer failure: $($failure.Exception.Message); rollback identity verification failed: $($_.Exception.Message)" }
            Stop-RepatoQaLaunchAgentForUpdate -ExpectedAgentPid $process.Id -ExpectedAgentStartTime $process.StartTime.ToString('o') -ExpectedSessionId $health.SessionId -AgentExe $contract.Executable -TaskPath $contract.TaskPath -TaskName $contract.TaskName -BootstrapModule $bootstrap
        } else {
            $task=Get-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName -ErrorAction Stop
            if($task.State.ToString() -ceq 'Running'){throw 'Scheduled task is running without an identifiable agent; installer recovery is ambiguous.'}
        }
        if($token){
            $token=Restore-RepatoQaLaunchAgentBootstrapInstall -RollbackToken $token
            if(@($token.RuntimeIntegrity|Where-Object {!$_.Match}).Count){throw 'Restored Launch Agent runtime integrity failed; task remains stopped.'}
            $task=Get-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName -ErrorAction Stop
            if(!(& $bootstrap {param($task) Test-TaskSpec $task} $task)){throw 'Restored Launch Agent task contract failed; task remains stopped.'}
            $rollbackVerified=$true
        }
        elseif($upgrade -and $installAttempted){
            $targetIntegrity=Get-RepatoQaLaunchAgentRuntimeIntegrity $contract.InstallRoot ([pscustomobject]@{files=$upgrade.PriorFiles})
            $restoredTask=Get-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName -ErrorAction SilentlyContinue
            $restoredTaskValid=$false;if($restoredTask){$restoredTaskValid=& $bootstrap {param($task) Test-TaskSpec $task} $restoredTask}
            if(@($targetIntegrity|Where-Object {!$_.Match}).Count -or !$restoredTaskValid){throw 'Rollback token is unavailable and prior runtime/task could not be verified; scheduled task remains stopped.'}
            $rollbackVerified=$true
        }
        if(!$rollbackVerified){throw 'Verified rollback evidence is unavailable; scheduled task remains stopped for manual recovery.'}
        Start-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName
    }
    if($upgrade -and !(Test-CpvPreparationUpgradeEvidenceSnapshot -Before $evidenceSnapshot -EvidenceRoot $activeRoot -RunDirectory $upgrade.RunDirectory)){throw 'Protected preparation evidence changed during rollback.'}
    throw $failure
}
