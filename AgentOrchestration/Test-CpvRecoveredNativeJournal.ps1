[CmdletBinding()]param()
$ErrorActionPreference='Stop'
# Reuse the isolated filesystem/context fixture and full existing recovery regression suite.
. (Join-Path $PSScriptRoot 'Test-QaLaunchAgentDurableInstallRecovery.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('repato-native-journal-'+[guid]::NewGuid().ToString('N'))
$target=Join-Path $root 'install';$source=Join-Path $root 'candidate';$lease=$null
try {
    New-Bytes $target 'prior';New-Bytes $source 'candidate'
    $files=@(Get-ChildItem -LiteralPath $source -File|ForEach-Object{[pscustomobject]@{name=$_.Name;sha256=(Get-FileHash $_.FullName).Hash}})
    $priorFiles=@(Get-ChildItem -LiteralPath $target -File|ForEach-Object{[pscustomobject]@{name=$_.Name;sha256=(Get-FileHash $_.FullName).Hash}})
    $state=@{Task=$null;TaskState='Running';FailRestore=$false};$context=New-FakeContext $state
    $state.Task=& $module {param($ctx)& $ctx.GetTask} $context
    $context.GetProductVersion={param($path)'1.0.22+6119aceaab0a34c3e0323089a29f1cefb2c14aaa'}
    $validated=[pscustomobject]@{SourceRoot=$source;ManifestSha256=('A'*64);Manifest=[pscustomobject]@{productVersion=('1.0.23+'+('a'*40));files=$files}}
    $id=[pscustomobject]@{RequestId='c11b311638a54bfc9ebdd1803671ec40';TaskId='task-bf61fe7f22d74df7a92599681da5919e';RecoveredNativeContinuation=$true}
    $lease=& $module {param($v,$ctx,$t,$i)New-InstallJournalCore $v $ctx $t $i -AllowTestRoot} $validated $context $target $id
    $state.Lease=$lease
    Assert-True ($lease.Data.state -ceq 'CandidateStaged' -and $lease.Data.priorVersion -ceq '1.0.22+6119aceaab0a34c3e0323089a29f1cefb2c14aaa') 'Explicit recovered journal stages exact transition.'
    $case=[pscustomobject]@{Root=$root;Target=$target;Source=$source;Files=$files;Prior=$priorFiles;Context=$context;State=$state;Lease=$lease;Module=$module;Validated=$validated}
    Advance-To $case 'ServiceStopped'
    $installed=& $module {param($v,$c,$t,$l)Invoke-InstallCore $v $c $t -AllowTestRoot -ProcessDetector { @() } -RetainRollback -DurableJournal $l} $validated $context $target $lease
    Assert-True ($lease.Data.state -ceq 'TaskUpdated') 'Exact immutable release installed through its bound durable journal.'
    Set-State $case 'HealthVerificationPending'
    $result=Recover $case { @() }
    Assert-True ($result.Status -ceq 'RolledBack') 'Recovered-native interrupted upgrade rolls back.'
    Assert-True (& $module {param($p,$f)Test-InstallJournalFileSet $p $f} $target $priorFiles) 'Exact prior runtime restored.'
    $journal=& $module {param($l)Get-InstallJournal $l} $lease
    Assert-True ($journal.candidateVersion -match '^1\.0\.23\+' -and $journal.requestId -ceq $id.RequestId) 'Recovered journal remains readable with exact pins.'
    $bad=$journal|ConvertTo-Json -Depth 10|ConvertFrom-Json;$bad.priorVersion='1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f';$bad.generation++
    & $module {param($j)Write-InstallJournal $j|Out-Null} $bad
    Assert-Throws {& $module {param($p,$t)Read-InstallJournal $p $t -AllowTestRoot} $lease.Path $target} 'Resealed wrong prior version rejects during read.'
    Write-Output 'PASS: 6 recovered-native durable journal assertions plus existing recovery suite.'
} finally {
    if($lease){& $module {param($l)Close-InstallJournalLease $l} $lease}
    $resolved=[IO.Path]::GetFullPath($root);$temporary=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($temporary,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe synthetic cleanup target.'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
