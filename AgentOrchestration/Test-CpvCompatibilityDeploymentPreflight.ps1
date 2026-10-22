[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReleaseRoot,[Parameter(Mandatory)][string]$ManifestSha256,
    [Parameter(Mandatory)][string]$EvidencePath)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$store=Join-Path $repo 'QA\MayaRuns'
$task=@((Get-Content -LiteralPath (Join-Path $store 'tasks.json') -Raw|ConvertFrom-Json).tasks|Where-Object taskId -ceq 'task-bf61fe7f22d74df7a92599681da5919e')
if($task.Count -ne 1 -or $task[0].revision -ne 122){throw 'Preflight requires the exact revision-122 task.'}
$r=$task[0].cpvPreparationRecovery
$roots=@('C:\Users\RepatoQA\AppData\Local\Repato\QaLaunchAgent\Logs\CpvPreparation',(Join-Path $repo ('QA\TestRuns\cpv-preparation-'+$r.Request.runId)))
$fixed=@((Join-Path $store 'tasks.json'),(Join-Path $store 'status.json'),'C:\Program Files\Repato\.QaLaunchAgent.install-journal.json')
$fixed+=@('Repato.QaLaunchAgent.exe','Repato.QaLaunchAgent.dll','Repato.QaLaunchAgent.deps.json','Repato.QaLaunchAgent.runtimeconfig.json')|ForEach-Object {Join-Path 'C:\Program Files\Repato\QaLaunchAgent' $_}
$fixed+=@($r.Request.candidateEvidence.CandidateDllPath,$r.Request.candidateEvidence.RunnerManifestPath,$r.Request.candidateEvidence.CandidateProvenancePath,$r.PreparationBinding.FixturePath,$r.PreparationBinding.FixtureProvenancePath)
function Snapshot {
    $paths=@($fixed)+@(Get-ChildItem -LiteralPath $roots -File -Recurse -ErrorAction Stop|Select-Object -ExpandProperty FullName)
    @($paths|Sort-Object -Unique|ForEach-Object {[pscustomobject]@{Path=$_;Sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256 -ErrorAction Stop).Hash}})
}
$before=Snapshot
$agent=Get-Process -Name Repato.QaLaunchAgent -ErrorAction Stop
$identity="$($agent.Id)|$($agent.StartTime.ToUniversalTime().ToString('O'))"
$passed=$false
try {
    & (Join-Path $PSScriptRoot 'Install-CpvPreparationAgentCandidate.ps1') -ReleaseRoot $ReleaseRoot -ManifestSha256 $ManifestSha256 -PreflightOnly -CompletedOutcomeRecoveryRequestId 'c11b311638a54bfc9ebdd1803671ec40' -ExpectedTaskRevision 122 -TaskId 'task-bf61fe7f22d74df7a92599681da5919e'
    $passed=$true
} finally {
    $after=Snapshot
    if(($before|ConvertTo-Json -Depth 5 -Compress) -cne ($after|ConvertTo-Json -Depth 5 -Compress)){throw 'Protected evidence or installed runtime bytes changed during read-only preflight.'}
    $agentAfter=Get-Process -Name Repato.QaLaunchAgent -ErrorAction Stop
    if("$($agentAfter.Id)|$($agentAfter.StartTime.ToUniversalTime().ToString('O'))" -cne $identity){throw 'Installed agent process changed during read-only preflight.'}
    $evidence=[pscustomobject]@{TaskRevision=122;PreflightPassed=$passed;AgentIdentity=$identity;ProtectedFiles=$before;Sha256Comparisons=$before.Count;Unchanged=$true;InstallationPerformed=$false;ReservationReset=$false;RecoveryDispatched=$false;RevitLaunched=$false}
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($EvidencePath),($evidence|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    "Unchanged protected/runtime files: $($before.Count); agent process unchanged."
}
