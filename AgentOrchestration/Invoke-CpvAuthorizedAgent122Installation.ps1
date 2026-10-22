[CmdletBinding()]
param([switch]$Worker)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $repo
$version='1.0.22+6119aceaab0a34c3e0323089a29f1cefb2c14aaa'
$release=Join-Path $repo ('DeploymentCandidates\AgentReleases\Repato.QaLaunchAgent-'+$version)
$manifestHash='7612D0657CF6287381F30A470D2B511BBF281B56CC36A095322845982879D726'
$taskId='task-bf61fe7f22d74df7a92599681da5919e'
$reservation='acfd8643ed2846b8a43b98d3a74c3217'
$logs=Join-Path $repo 'QA\Engineering\CPV-AuthorizedInstall-20261019-1.0.22-6119'
New-Item -ItemType Directory -Path $logs -Force|Out-Null
$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'The authorized guarded installation requires elevated administrator permissions.'}
if(!$Worker){
    try {
        & (Join-Path $PSScriptRoot 'Invoke-CpvEngineeringProcess.ps1') -Executable 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Arguments @('-NoProfile','-NonInteractive','-ExecutionPolicy','RemoteSigned','-File',$PSCommandPath,'-Worker') -LogPrefix (Join-Path $logs 'installation') -TimeoutSeconds 7200|Out-Null
        [IO.File]::WriteAllText((Join-Path $logs 'complete.txt'),'PASS')
    } catch {[IO.File]::WriteAllText((Join-Path $logs 'complete.txt'),($_|Out-String));exit 1}
    return
}
# This engineering receipt prevents a second invocation under this single authorization.
$lease=[IO.File]::Open((Join-Path $logs 'single-authorization-lease.json'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$bytes=[Text.Encoding]::UTF8.GetBytes((@{Version=$version;TaskId=$taskId;Revision=122;MaximumAttempts=1;AuthorizedBy='user';CreatedUtc=[DateTimeOffset]::UtcNow.ToString('O')}|ConvertTo-Json));$lease.Write($bytes,0,$bytes.Length);$lease.Flush($true)}finally{$lease.Dispose()}
$attempts=0;$installerReturned=$false;$baseline=$null;$failure=$null
function Save-Json($Name,$Value){[IO.File]::WriteAllText((Join-Path $logs $Name),($Value|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
function Read-Task {
    $all=Get-Content -LiteralPath (Join-Path $repo 'QA\MayaRuns\tasks.json') -Raw|ConvertFrom-Json
    $found=@($all.tasks|Where-Object taskId -ceq $taskId)
    if($found.Count -ne 1 -or $found[0].revision -ne 122 -or $found[0].cpvPreparationRecovery.OutcomeRecoveryApprovalId -cne $reservation){throw 'Exact revision-122 retained reservation is unavailable.'}
    $found[0]
}
function Snapshot-Protected {
    $paths=@($fixed)+@(Get-ChildItem -LiteralPath $protectedRoots -File -Recurse -ErrorAction Stop|Select-Object -ExpandProperty FullName)
    @($paths|Sort-Object -Unique|ForEach-Object {[pscustomobject]@{Path=$_;Sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256 -ErrorAction Stop).Hash}})
}
try {
    $task=Read-Task;$r=$task.cpvPreparationRecovery
    $protectedRoots=@('C:\Users\RepatoQA\AppData\Local\Repato\QaLaunchAgent\Logs\CpvPreparation',(Join-Path $repo ('QA\TestRuns\cpv-preparation-'+$r.Request.runId)))
    $fixed=@((Join-Path $repo 'QA\MayaRuns\tasks.json'),(Join-Path $repo 'QA\MayaRuns\status.json'),'C:\Users\RepatoQA\AppData\Local\Repato\QaLaunchAgent\replay.json',
        $r.Request.candidateEvidence.CandidateDllPath,$r.Request.candidateEvidence.RunnerManifestPath,$r.Request.candidateEvidence.CandidateProvenancePath,$r.PreparationBinding.FixturePath,$r.PreparationBinding.FixtureProvenancePath)
    $baseline=Snapshot-Protected;Save-Json 'protected-before.json' $baseline
    if(@(Get-Process -Name Revit -ErrorAction SilentlyContinue).Count){throw 'Revit is running; installation is refused.'}
    $manifestPath=Join-Path $release 'Repato.QaLaunchAgent.release.json'
    if((Get-FileHash -LiteralPath $manifestPath).Hash -cne $manifestHash){throw 'Approved immutable manifest hash mismatch.'}
    $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
    if($manifest.productVersion -cne $version -or $manifest.sourceCommit -cne '6119aceaab0a34c3e0323089a29f1cefb2c14aaa'){throw 'Approved release provenance mismatch.'}
    & git cat-file -e ($manifest.sourceCommit+'^{commit}');if($LASTEXITCODE){throw 'Release source commit is unavailable.'}
    & git diff --quiet $manifest.sourceCommit -- 'QaLaunchAgent/*.cs' 'QaLaunchAgent/Repato.QaLaunchAgent.csproj';if($LASTEXITCODE){throw 'Runtime source differs from approved release provenance.'}
    Save-Json 'approved-manifest.json' $manifest
    # Separate process keeps the supported read-only preflight and its evidence intact.
    & (Join-Path $PSScriptRoot 'Invoke-CpvEngineeringProcess.ps1') -Executable 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Arguments @('-NoProfile','-NonInteractive','-ExecutionPolicy','RemoteSigned','-File',(Join-Path $PSScriptRoot 'Test-CpvCompatibilityDeploymentPreflight.ps1'),'-ReleaseRoot',$release,'-ManifestSha256',$manifestHash,'-EvidencePath',(Join-Path $logs 'fresh-preflight-protected.json')) -LogPrefix (Join-Path $logs 'fresh-preflight') -TimeoutSeconds 7200|Out-Null
    Save-Json 'journal-before.json' (Get-Content -LiteralPath 'C:\Program Files\Repato\.QaLaunchAgent.install-journal.json' -Raw|ConvertFrom-Json)
    $marker=[IO.File]::Open((Join-Path $logs 'installation-attempt-1.txt'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.Encoding]::UTF8.GetBytes([DateTimeOffset]::UtcNow.ToString('O'));$marker.Write($bytes,0,$bytes.Length);$marker.Flush($true)}finally{$marker.Dispose()}
    $attempts=1
    # The sole mutation call. No retry, reservation reset or recovery dispatch exists here.
    & (Join-Path $PSScriptRoot 'Install-CpvPreparationAgentCandidate.ps1') -ReleaseRoot $release -ManifestSha256 $manifestHash -Execute -CompletedOutcomeRecoveryRequestId 'c11b311638a54bfc9ebdd1803671ec40' -ExpectedTaskRevision 122 -TaskId $taskId
    $installerReturned=$true
    $bootstrap=Import-Module (Join-Path $repo 'QaLaunchAgent\Repato.QaLaunchAgent.Bootstrap.psm1') -PassThru -WarningAction SilentlyContinue
    $contract=& $bootstrap {Get-RepatoQaLaunchAgentBootstrapContract}
    $journal=& $bootstrap {param($p,$root) Read-InstallJournal $p $root} 'C:\Program Files\Repato\.QaLaunchAgent.install-journal.json' $contract.InstallRoot
    Save-Json 'journal-after.json' $journal
    if($journal.state -cne 'Committed' -or $journal.candidateVersion -cne $version -or $journal.taskId -cne $taskId -or $journal.requestId -cne 'c11b311638a54bfc9ebdd1803671ec40'){throw 'Installation journal does not confirm the exact approved committed transition.'}
    $hashes=@(foreach($entry in $manifest.files){$path=Join-Path $contract.InstallRoot $entry.name;$hash=(Get-FileHash -LiteralPath $path).Hash;if($hash -cne $entry.sha256){throw "Installed runtime hash mismatch: $($entry.name)"};[pscustomobject]@{Name=$entry.name;Sha256=$hash;Match=$true}})
    foreach($name in @('Repato.QaLaunchAgent.exe','Repato.QaLaunchAgent.dll')){if((Get-Item -LiteralPath (Join-Path $contract.InstallRoot $name)).VersionInfo.ProductVersion -cne $version){throw 'Installed EXE/DLL product version mismatch.'}}
    $maya=Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -PassThru -WarningAction SilentlyContinue
    $health=& $maya {Invoke-MayaQaLaunchAgentHealth -TimeoutMilliseconds 10000}
    $recovery=Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationRecovery.psm1') -PassThru -WarningAction SilentlyContinue
    $cap=& $recovery {Get-CpvPreparationCapabilities}
    $agents=@(Get-Process -Name Repato.QaLaunchAgent -ErrorAction Stop)
    if($agents.Count -ne 1){throw 'Installed agent process count is ambiguous.'}
    . (Join-Path $PSScriptRoot 'Repato.QaLaunchAgentInstall.ps1')
    $identity=Get-RepatoQaLaunchAgentProcessIdentity -ProcessId $agents[0].Id
    if(!$health.Ready -or !$health.UserInteractive -or $health.User -ine 'RAMSAI\RepatoQA' -or $health.SID -cne 'S-1-5-21-1031246752-3872016183-2454652381-1015' -or
        $cap.runtimeVersion -cne $version -or $health.SessionId -ne $cap.sessionId -or $identity.SessionId -ne $health.SessionId -or $identity.OwnerSid -cne $health.SID -or $identity.Path -ine $contract.Executable){throw 'Installed authenticated runtime health, owner or interactive session mismatch.'}
    $task=Read-Task
    if(@(Get-Process -Name Revit -ErrorAction SilentlyContinue).Count){throw 'Revit appeared during deployment verification.'}
    $after=Snapshot-Protected;Save-Json 'protected-after.json' $after
    if(($baseline|ConvertTo-Json -Depth 5 -Compress) -cne ($after|ConvertTo-Json -Depth 5 -Compress)){throw 'Protected task, CPV evidence, replay ledger or frozen artifact bytes changed.'}
    $result=[pscustomobject]@{InstallationAttempted=$true;InstallationAttemptCount=1;InstalledVersion=$version;InstalledHashesVerified=$true;InstalledFiles=$hashes;AgentHealth=$health;Capabilities=$cap;AgentProcessId=$agents[0].Id;TaskRevision=$task.revision;ReservationPreserved=$true;Reservation=$reservation;ProtectedFilesUnchanged=$true;ProtectedFileComparisons=$after.Count;JournalState=$journal.state;JournalTransactionId=$journal.transactionId;RollbackRoot=$journal.backupRoot;RevitLaunched=$false;RecoveryDispatched=$false;ReservationReset=$false;ManifestSha256=$manifestHash}
    Save-Json 'deployment-result.json' $result
    $result|ConvertTo-Json -Depth 8
} catch {
    $failure=$_
    $diagnostic=[ordered]@{InstallationAttempted=($attempts -eq 1);InstallationAttemptCount=$attempts;InstallerReturned=$installerReturned;Error=($_|Out-String);NoRetryPerformed=$true}
    try{$diagnostic.Journal=Get-Content -LiteralPath 'C:\Program Files\Repato\.QaLaunchAgent.install-journal.json' -Raw|ConvertFrom-Json}catch{$diagnostic.JournalReadError=$_.Exception.Message}
    try{$diagnostic.AgentProcesses=@(Get-Process -Name Repato.QaLaunchAgent -ErrorAction SilentlyContinue|Select-Object Id,Path,StartTime,SessionId)}catch{$diagnostic.AgentReadError=$_.Exception.Message}
    try{if($null -ne $baseline){$after=Snapshot-Protected;Save-Json 'protected-after-failure.json' $after;$diagnostic.ProtectedFilesUnchanged=(($baseline|ConvertTo-Json -Depth 5 -Compress) -ceq ($after|ConvertTo-Json -Depth 5 -Compress))}}catch{$diagnostic.EvidenceReadError=$_.Exception.Message}
    Save-Json 'deployment-failure.json' $diagnostic
    throw $failure
}
