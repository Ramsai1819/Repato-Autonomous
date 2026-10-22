$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $repo
$logs=Join-Path $repo 'QA\Engineering\CPV-AuthorizedInstall-20261019-1.0.22-6119'
$release=Join-Path $repo 'DeploymentCandidates\AgentReleases\Repato.QaLaunchAgent-1.0.22+6119aceaab0a34c3e0323089a29f1cefb2c14aaa'
$diagnosis=$null
try {
    & {
        Set-StrictMode -Version Latest
        # Reproduce only the read-only preflight with the wrapper's inherited strict mode.
        & (Join-Path $PSScriptRoot 'Install-CpvPreparationAgentCandidate.ps1') -ReleaseRoot $release -ManifestSha256 '7612D0657CF6287381F30A470D2B511BBF281B56CC36A095322845982879D726' -PreflightOnly -CompletedOutcomeRecoveryRequestId 'c11b311638a54bfc9ebdd1803671ec40' -ExpectedTaskRevision 122 -TaskId 'task-bf61fe7f22d74df7a92599681da5919e'
    }|Out-Null
} catch {$diagnosis=[pscustomobject]@{ExceptionType=$_.Exception.GetType().FullName;Message=$_.Exception.Message;Position=$_.InvocationInfo.PositionMessage;ScriptStackTrace=$_.ScriptStackTrace}}
$bootstrap=Import-Module (Join-Path $repo 'QaLaunchAgent\Repato.QaLaunchAgent.Bootstrap.psm1') -PassThru -WarningAction SilentlyContinue
$journal=& $bootstrap {Read-InstallJournal 'C:\Program Files\Repato\.QaLaunchAgent.install-journal.json' 'C:\Program Files\Repato\QaLaunchAgent'}
$prior=Get-Content -LiteralPath (Join-Path $logs 'journal-before.json') -Raw|ConvertFrom-Json
if($journal.journalSha256 -cne $prior.journalSha256 -or $journal.transactionId -cne $prior.transactionId){throw 'Installation journal changed; outcome requires manual review.'}
$files=@(foreach($entry in $journal.candidateFiles){$path=Join-Path 'C:\Program Files\Repato\QaLaunchAgent' $entry.name;$hash=(Get-FileHash -LiteralPath $path).Hash;[pscustomobject]@{Name=$entry.name;Sha256=$hash;MatchesPriorInstalledRuntime=($hash -ceq $entry.sha256)}})
if(@($files|Where-Object {!$_.MatchesPriorInstalledRuntime}).Count){throw 'Installed runtime differs from unchanged prior journal.'}
$maya=Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -PassThru -WarningAction SilentlyContinue
$health=& $maya {Invoke-MayaQaLaunchAgentHealth -TimeoutMilliseconds 10000}
$recovery=Import-Module (Join-Path $PSScriptRoot 'Repato.CpvPreparationRecovery.psm1') -PassThru -WarningAction SilentlyContinue
$cap=& $recovery {Get-CpvPreparationCapabilities}
$agents=@(Get-Process -Name Repato.QaLaunchAgent -ErrorAction Stop)
. (Join-Path $PSScriptRoot 'Repato.QaLaunchAgentInstall.ps1')
$identity=Get-RepatoQaLaunchAgentProcessIdentity -ProcessId $agents[0].Id
$before=Get-Content -LiteralPath (Join-Path $logs 'fresh-preflight-protected.json') -Raw|ConvertFrom-Json
foreach($entry in $before.ProtectedFiles){if((Get-FileHash -LiteralPath $entry.Path).Hash -cne $entry.Sha256){throw "Protected/runtime bytes changed: $($entry.Path)"}}
$task=@((Get-Content -LiteralPath 'QA\MayaRuns\tasks.json' -Raw|ConvertFrom-Json).tasks|Where-Object taskId -ceq 'task-bf61fe7f22d74df7a92599681da5919e')[0]
$result=[pscustomobject]@{InstallationAttempted=$true;InstallationAttemptCount=1;RuntimeReplacementPerformed=$false;AgentRestarted=$false;InstalledVersion=$cap.runtimeVersion;ApprovedVersionInstalled=($cap.runtimeVersion -ceq '1.0.22+6119aceaab0a34c3e0323089a29f1cefb2c14aaa');PriorRuntimeHashesVerified=$true;InstalledFiles=$files;AgentHealth=$health;AgentProcessId=$identity.ProcessId;AgentOwnerSid=$identity.OwnerSid;AgentStartTime=$identity.StartTime;TaskRevision=$task.revision;ReservationPreserved=($task.cpvPreparationRecovery.OutcomeRecoveryApprovalId -ceq 'acfd8643ed2846b8a43b98d3a74c3217');ProtectedRuntimeFilesUnchanged=$true;ProtectedRuntimeComparisons=$before.ProtectedFiles.Count;JournalState=$journal.state;JournalTransactionId=$journal.transactionId;JournalUnchanged=$true;RevitPresent=(@(Get-Process -Name Revit -ErrorAction SilentlyContinue).Count -gt 0);NoRetryPerformed=$true;Diagnosis=$diagnosis}
[IO.File]::WriteAllText((Join-Path $logs 'read-only-outcome.json'),($result|ConvertTo-Json -Depth 9),[Text.UTF8Encoding]::new($false))
$result|ConvertTo-Json -Depth 9
