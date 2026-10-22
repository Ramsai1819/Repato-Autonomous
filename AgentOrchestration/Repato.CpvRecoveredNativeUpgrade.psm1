Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvRecoveredProvenance.psm1') -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.CpvNativeContinuation.psm1') -WarningAction SilentlyContinue
function Get-CpvNativeUpgradeHash($Value) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 30 -Compress))))).Replace('-','')}finally{$sha.Dispose()}
}
function Assert-CpvRecoveredNativeUpgrade {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$EvidenceRoot,[Parameter(Mandatory)][string]$RuntimeRoot,
        [Parameter(Mandatory)][string]$RequestId,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][long]$ExpectedTaskRevision,[Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)]$Capabilities,$Receipt,[Parameter(Mandatory)]$RecoveryReceipt,[Parameter(Mandatory)]$InstalledAgent,
        [Parameter(Mandatory)][string]$ProcessSid,[Parameter(Mandatory)][string]$ExpectedExecutable,
        [Parameter(Mandatory)][string]$ExpectedInstalledVersion,[Parameter(Mandatory)][string]$CandidateRoot,
        [Parameter(Mandatory)][string]$CandidateManifestPath,[Parameter(Mandatory)][string]$CandidateManifestSha256,
        [Parameter(Mandatory)][object[]]$PriorRuntimeFiles,[Parameter(Mandatory)][bool]$PriorTaskContractValid,
        [Parameter(Mandatory)][bool]$NoRevitProcesses,[Parameter(Mandatory)]$BootstrapModule)
    $version='1.0.22+6119aceaab0a34c3e0323089a29f1cefb2c14aaa';$user='RAMSAI\RepatoQA';$sid='S-1-5-21-1031246752-3872016183-2454652381-1015'
    $files=@('Repato.QaLaunchAgent.exe','Repato.QaLaunchAgent.dll','Repato.QaLaunchAgent.deps.json','Repato.QaLaunchAgent.runtimeconfig.json')
    # Exact approved immutable 1.0.22 release (manifest SHA256 7612D0657CF6287381F30A470D2B511BBF281B56CC36A095322845982879D726).
    $priorPins=@{'Repato.QaLaunchAgent.exe'='0A947BBD24C8A95CDB5C0AE94AA586ACE922765438DD1430FA4F1BBB8EF737CD';'Repato.QaLaunchAgent.dll'='F22C2E694ABE9A23893A97FFEE804D453191A60C031F48855DB071869A677F03';'Repato.QaLaunchAgent.deps.json'='78FEBC5E3DEB35F8A46125FB39EA36F30CDFE4DB154F76B49502FE92792259D4';'Repato.QaLaunchAgent.runtimeconfig.json'='CA1A6B5B185174698E0F5F9AE732AD3D2D3ED5B122ED666F35CC214283E83B7F'}
    if($RequestId -cne 'c11b311638a54bfc9ebdd1803671ec40' -or $TaskId -cne 'task-bf61fe7f22d74df7a92599681da5919e' -or $ExpectedTaskRevision -ne 127 -or $ExpectedInstalledVersion -cne $version){throw 'Recovered-native upgrade requires the exact revision-127 transition.'}
    if(!$Capabilities -or $Capabilities.operation -cne 'cpv-preparation-capabilities' -or !$Capabilities.supported -or $Capabilities.user -ine $user -or $Capabilities.sid -cne $sid -or $Capabilities.sessionId -le 0 -or $Capabilities.runtimeVersion -cne $version){throw 'Authenticated recovered-native capability identity is invalid.'}
    if(!$InstalledAgent -or $InstalledAgent.ProcessName -cne 'Repato.QaLaunchAgent' -or [IO.Path]::GetFullPath($InstalledAgent.Path) -ine [IO.Path]::GetFullPath($ExpectedExecutable) -or $InstalledAgent.ProductVersion -cne $version -or $InstalledAgent.User -ine $user -or $InstalledAgent.Sid -cne $sid -or $ProcessSid -cne $sid -or $InstalledAgent.SessionId -ne $Capabilities.sessionId -or $InstalledAgent.Id -le 0 -or !$InstalledAgent.StartTime){throw 'Installed recovered-native agent identity is invalid.'}
    if(!$NoRevitProcesses -or !$PriorTaskContractValid -or @($PriorRuntimeFiles).Count -ne 4 -or @($PriorRuntimeFiles.name|Select-Object -Unique).Count -ne 4){throw 'Recovered-native no-Revit or rollback prerequisites failed.'}
    foreach($f in $PriorRuntimeFiles){if($f.name -notin $files -or $f.sha256 -ine $priorPins[$f.name] -or (Get-FileHash -LiteralPath (Join-Path (Split-Path $ExpectedExecutable -Parent) $f.name)).Hash -ine $f.sha256){throw 'Recovered-native rollback artifact mismatch.'}}
    $task=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId;$r=$task.cpvPreparationRecovery
    if($task.revision -ne 127 -or $task.status -cne 'in-progress' -or $task.workflowStage -cne 'qa' -or !$r -or $r.Status -cne 'RecoveredVerified' -or $r.OutcomeRecoveryApprovalId -cne 'b38d9717f0164715a4a9fdbbf21191bd' -or (Get-CpvNativeUpgradeHash $r.Request) -ine $r.RequestHash){throw 'Recovered-native authoritative task binding changed.'}
    foreach($name in 'mayaTaraQaPacket','mayaTaraAttempt','mayaTaraExecution'){if($task.PSObject.Properties[$name] -and $task.$name){throw 'Existing canonical attempt, execution or claim blocks recovered-native upgrade.'}}
    $workflows=@($task.deploymentWorkflows|Where-Object workflowId -ceq $r.Request.workflowId)
    if($workflows.Count -ne 1){throw 'Recovered-native workflow identity is ambiguous.'}
    $null=New-CpvNativeContinuationBinding -Task $task -Workflow $workflows[0] -ExpectedTaskRevision 127
    if(@($task.approvalRequests|Where-Object {$_.status -ceq 'pending' -or ($_.action -ceq 'qa-run' -and $_.status -ceq 'approved' -and !$_.consumedUtc)}).Count){throw 'Pending or executable QA authorization blocks the recovered-native upgrade.'}
    $a=@($task.approvalRequests|Where-Object requestId -CEQ $r.OutcomeRecoveryApprovalId)
    if($a.Count -ne 1 -or $a[0].status -cne 'approved' -or !$a[0].consumedUtc -or [DateTimeOffset]$a[0].consumedUtc -gt [DateTimeOffset]$a[0].expiresUtc -or $a[0].action -cne 'cpv-preparation-outcome-recovery' -or (Get-CpvNativeUpgradeHash $a[0].outcomeRecoveryBinding) -ine $a[0].bindingHash){throw 'Consumed recovery authorization binding changed.'}
    if(!$RecoveryReceipt -or !$RecoveryReceipt.Receipt -or (Get-CpvNativeUpgradeHash $RecoveryReceipt) -ine (Get-CpvNativeUpgradeHash $r.OutcomeRecoveryReceipt) -or $RecoveryReceipt.RecoveryApprovalId -cne $a[0].requestId -or $RecoveryReceipt.ApprovalBindingHash -ine $a[0].bindingHash -or $RecoveryReceipt.ExpectedTaskRevision -ne $a[0].outcomeRecoveryBinding.ExpectedTaskRevision){throw 'Authenticated recovery status differs from the approved persisted commit.'}
    foreach($n in 'requestId','taskId','workflowId','attemptId','runId'){if($RecoveryReceipt.Receipt.$n -cne $r.Request.$n){throw 'Recovered receipt identity mismatch.'}}
    foreach($p in @(@('OriginalReceiptSha256','OriginalReceiptSha256'),@('ActiveMarkerSha256','ActiveMarkerSha256'),@('FailureEvidenceSha256','FailureEvidenceSha256'),@('RequestSha256','PreparationRequestSha256'),@('ResultSha256','ResultSha256'),@('ModelSha256','ModelSha256'))){if($RecoveryReceipt.($p[0]) -ine $a[0].outcomeRecoveryBinding.Snapshot.($p[1])){throw 'Approved recovery snapshot mismatch.'}}
    foreach($p in @(@(($RequestId+'.json'),$RecoveryReceipt.OriginalReceiptSha256),@(($RequestId+'.request.json'),$RecoveryReceipt.RequestSha256),@(($RequestId+'.failure.txt'),$RecoveryReceipt.FailureEvidenceSha256))){if((Get-FileHash -LiteralPath (Join-Path $EvidenceRoot $p[0])).Hash -ine $p[1]){throw 'Protected historical recovery evidence hash changed.'}}
    if(Test-Path -LiteralPath (Join-Path $EvidenceRoot 'active.json')){throw 'Unresolved active preparation blocks recovered-native upgrade.'}
    $run=[IO.Path]::GetFullPath((Join-Path $RuntimeRoot ('cpv-preparation-'+$r.Request.runId)));$model=Join-Path $run 'model.rvt'
    if([IO.Path]::GetFullPath($RecoveryReceipt.Receipt.modelPath) -ine $model -or $RecoveryReceipt.RecoveredProvenancePath -ine ($model+'.recovered.fixture.json') -or (Get-FileHash -LiteralPath $model).Hash -ine $RecoveryReceipt.ModelSha256 -or (Test-Path -LiteralPath ($model+'.lck')) -or (Test-Path -LiteralPath ($model+'.slog'))){throw 'Recovered-native model or lock evidence changed.'}
    $side=Read-CpvFixtureProvenance -SidecarPath ($model+'.fixture.json') -ExpectedRecoveredProvenanceSha256 $RecoveryReceipt.RecoveredProvenanceSha256
    if($side.recoveryApprovalId -cne $a[0].requestId -or $side.approvalBindingHash -ine $a[0].bindingHash){throw 'Recovered-native companion provenance binding changed.'}
    $candidate=[IO.Path]::GetFullPath($CandidateRoot).TrimEnd('\');$manifestPath=[IO.Path]::GetFullPath($CandidateManifestPath)
    $releaseRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\DeploymentCandidates\AgentReleases')).TrimEnd('\')+'\'
    if(!$candidate.StartsWith($releaseRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $candidate -Leaf) -notmatch '^Repato\.QaLaunchAgent-1\.0\.23\+[A-Fa-f0-9]{40}$' -or $manifestPath -ine (Join-Path $candidate 'Repato.QaLaunchAgent.release.json') -or (Get-FileHash -LiteralPath $manifestPath).Hash -ine $CandidateManifestSha256){throw 'Recovered-native immutable release pin is invalid.'}
    $m=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
    if($m.product -cne 'Repato.QaLaunchAgent' -or $m.account -cne $user -or $m.sid -cne $sid -or $m.productVersion -notmatch '^1\.0\.23\+[A-Fa-f0-9]{40}$' -or (Split-Path $candidate -Leaf) -cne ('Repato.QaLaunchAgent-'+$m.productVersion) -or @($m.files).Count -ne 4 -or @($m.files.name|Select-Object -Unique).Count -ne 4){throw 'Recovered-native release identity is invalid.'}
    foreach($f in $m.files){if($f.name -notin $files -or $f.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash -LiteralPath (Join-Path $candidate $f.name)).Hash -ine $f.sha256){throw 'Recovered-native release artifact mismatch.'}}
    $agentRoot=Split-Path $ExpectedExecutable -Parent;$journalPath=Join-Path (Split-Path $agentRoot -Parent) '.QaLaunchAgent.install-journal.json'
    $journal=& $BootstrapModule {param($p,$t) Read-InstallJournal $p $t} $journalPath $agentRoot
    if($journal.state -cne 'Committed' -or $journal.generation -ne 13 -or $journal.candidateVersion -cne $version -or $journal.priorVersion -cne '1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f' -or $journal.taskId -cne $TaskId -or $journal.requestId -cne $RequestId){throw 'Recovered-native committed rollback journal changed.'}
    [pscustomobject]@{CandidateVersion=$m.productVersion;JournalGeneration=[long]$journal.generation;JournalSha256=$journal.journalSha256;RunDirectory=$run;PriorFiles=@($PriorRuntimeFiles);Request=$r.Request}
}
Export-ModuleMember -Function Assert-CpvRecoveredNativeUpgrade
