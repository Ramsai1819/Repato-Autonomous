param([string]$BootstrapModulePath)
$ErrorActionPreference='Stop'
$modulePath=if($BootstrapModulePath){$BootstrapModulePath}else{Join-Path $PSScriptRoot '../QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1'}
$module=Import-Module $modulePath -Force -PassThru
$testCount=0
function Assert-True([bool]$Condition,[string]$Message){if(!$Condition){throw $Message};$script:testCount++}
function Assert-Throws([scriptblock]$Action,[string]$Message){$threw=$false;try{& $Action}catch{$threw=$true};Assert-True $threw $Message}
function New-Bytes([string]$Root,[string]$Label){New-Item -ItemType Directory -Path $Root -Force|Out-Null;$names=@('Repato.QaLaunchAgent.exe','Repato.QaLaunchAgent.dll','Repato.QaLaunchAgent.deps.json','Repato.QaLaunchAgent.runtimeconfig.json');foreach($name in $names){[IO.File]::WriteAllText((Join-Path $Root $name),"$Label/$name")}}
function New-FakeContext($State){
    $task=& $module { $t=New-TaskSpec;$t|Add-Member -NotePropertyName PrincipalResolvedSid -NotePropertyValue 'S-1-5-21-1031246752-3872016183-2454652381-1015';$t|Add-Member -NotePropertyName TriggerResolvedSid -NotePropertyValue 'S-1-5-21-1031246752-3872016183-2454652381-1015';$t }
    [pscustomobject]@{
        IsAdministrator=({}.GetNewClosure());ResolveIdentity=({param($a,$s)}.GetNewClosure());PrepareAcl=({param($path)}.GetNewClosure())
        GetTask=({$State.Task}.GetNewClosure());GetTaskState=({$State.TaskState}.GetNewClosure());ExportTask=({param($t) '<Task>synthetic prior task</Task>'}.GetNewClosure())
        SetTask=({param($spec) $State.Task=$State.ValidTask}.GetNewClosure());RestoreTask=({param($xml) if($State.FailRestore){throw 'injected task restore failure'};$State.Task=$State.ValidTask}.GetNewClosure())
        StopTask=({if(!$State.Lease -or $State.Lease.Data.state -cne 'RollbackPending'){throw 'rollback state was not persisted before stopping the task'};$State.TaskStopped=$true}.GetNewClosure());StartTask=({$State.TaskStarted=$true}.GetNewClosure());GetProcesses=({@()}.GetNewClosure());StopProcesses=({param($items)if(!$State.TaskStopped){throw 'task stop must precede process stop'};$State.AgentStopCalled=$true}.GetNewClosure());GetProductVersion=({param($path)$State.PriorVersion}.GetNewClosure())
    }
    $State.ValidTask=$task;$State.Task=$task
}
function New-Case([string]$PriorTaskState='Ready',[string]$PriorVersion='1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f',[string]$RequestId='c11b311638a54bfc9ebdd1803671ec40') {
    $root=Join-Path ([IO.Path]::GetTempPath()) ('repato-install-recovery-'+[guid]::NewGuid().ToString('N'));$target=Join-Path $root 'install';$source=Join-Path $root 'candidate';New-Bytes $target 'prior';New-Bytes $source 'candidate'
    $files=@(Get-ChildItem -LiteralPath $source -File|ForEach-Object{[pscustomobject]@{name=$_.Name;sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}})
    $prior=@(Get-ChildItem -LiteralPath $target -File|ForEach-Object{[pscustomobject]@{name=$_.Name;sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}})
    $fake=@{Task=$null;TaskState=$PriorTaskState;FailRestore=$false;PriorVersion=$PriorVersion};$context=New-FakeContext $fake;$fake.Task=& $module {param($ctx)& $ctx.GetTask} $context
    $validated=[pscustomobject]@{SourceRoot=$source;ManifestSha256=('A'*64);Manifest=[pscustomobject]@{productVersion='1.0.22+aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';files=$files}}
    $lease=& $module {param($v,$c,$t,$request) New-InstallJournalCore $v $c $t ([pscustomobject]@{RequestId=$request;TaskId='task-bf61fe7f22d74df7a92599681da5919e'}) -AllowTestRoot} $validated $context $target $RequestId
    $fake.Lease=$lease
    [pscustomobject]@{Root=$root;Target=$target;Source=$source;Files=$files;Prior=$prior;Context=$context;State=$fake;Lease=$lease;Module=$module;Validated=$validated}
}
function Close-Case($Case){& $Case.Module {param($l) Close-InstallJournalLease $l} $Case.Lease;$resolved=[IO.Path]::GetFullPath($Case.Root);$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\';if(!$resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'repato-install-recovery-*'){throw 'Unsafe synthetic cleanup root'};if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}}
function Set-State($Case,[string]$State){& $Case.Module {param($l,$s)$j=Get-InstallJournal $l;Set-InstallJournalState $j $s|Out-Null} $Case.Lease $State}
function Move-Backup($Case){Move-Item -LiteralPath $Case.Target -Destination $Case.Lease.Data.backupRoot}
function Move-Candidate($Case){Move-Item -LiteralPath $Case.Lease.Data.stageRoot -Destination $Case.Target}
function Advance-To($Case,[string]$State){
    if($State -eq 'Prepared'){$j=$Case.Lease.Data;$j.generation++;$j.state='Prepared';& $Case.Module {param($j) Write-InstallJournal $j|Out-Null} $j;return}
    $steps=@('ServiceStopPending','ServiceStopped','BackupMovePending','BackupVerified','ReplacementPending','FilesReplaced','TaskUpdatePending','TaskUpdated','HealthVerificationPending','CommitPending')
    foreach($step in $steps){if($step -ceq 'BackupVerified'){Move-Backup $Case};if($step -ceq 'FilesReplaced'){Move-Candidate $Case};if($step -ceq 'TaskUpdated'){& $Case.Context.SetTask $null};Set-State $Case $step;if($step -ceq $State){return}}
    if($State -eq 'RollbackPending'){Set-State $Case 'RollbackPending';return}
    throw "Unknown synthetic boundary: $State"
}
function Recover($Case,$Detector){& $Case.Module {param($l,$c,$d) Invoke-InstallJournalRecoveryCore $l $c $d} $Case.Lease $Case.Context $Detector}

# Entire test uses disposable directories and injected process/task identities.
# AllowTestRoot changes only the filesystem root; exact 1.0.22 transition guards
# apply equally to these synthetic journals and to the protected runtime.
$case=New-Case
try {
    $read=& $module {param($p,$t) Read-InstallJournal $p $t -AllowTestRoot} $case.Lease.Path $case.Target
    Assert-True ($read.priorVersion -ceq '1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f' -and $read.candidateVersion -ceq '1.0.22+aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa') 'Exact prior/candidate transition did not round-trip.'
    Assert-True ($read.requestId -ceq 'c11b311638a54bfc9ebdd1803671ec40') 'Completed request identity did not round-trip.'
    $original=[IO.File]::ReadAllBytes($case.Lease.Path)
    foreach($prior in @('1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e','1.0.21+ffffffffffffffffffffffffffffffffffffffff','malformed')){
        $j=Get-Content $case.Lease.Path -Raw|ConvertFrom-Json;$j.priorVersion=$prior
        & $module {param($v) $v.journalSha256=Get-InstallJournalHash $v;[IO.File]::WriteAllText($v.journalPath,($v|ConvertTo-Json -Depth 12))} $j
        Assert-Throws {& $module {param($p,$t) Read-InstallJournal $p $t -AllowTestRoot} $case.Lease.Path $case.Target} 'Invalid prior identity was accepted for compatibility journal.'
        [IO.File]::WriteAllBytes($case.Lease.Path,$original)
    }
    $j=Get-Content $case.Lease.Path -Raw|ConvertFrom-Json;$j.requestId='9953e14c15524fe09440d1c7d7353950'
    & $module {param($v) $v.journalSha256=Get-InstallJournalHash $v;[IO.File]::WriteAllText($v.journalPath,($v|ConvertTo-Json -Depth 12))} $j
    Assert-Throws {& $module {param($p,$t) Read-InstallJournal $p $t -AllowTestRoot} $case.Lease.Path $case.Target} 'Old failed-preparation request was accepted for compatibility journal.'
    [IO.File]::WriteAllBytes($case.Lease.Path,$original)
    $j=Get-Content $case.Lease.Path -Raw|ConvertFrom-Json;$j.candidateVersion='1.0.22+invalid'
    & $module {param($v) $v.journalSha256=Get-InstallJournalHash $v;[IO.File]::WriteAllText($v.journalPath,($v|ConvertTo-Json -Depth 12))} $j
    Assert-Throws {& $module {param($p,$t) Read-InstallJournal $p $t -AllowTestRoot} $case.Lease.Path $case.Target} 'Malformed candidate was accepted.'
    [IO.File]::WriteAllBytes($case.Lease.Path,$original)
    [IO.File]::AppendAllText($case.Lease.Path,'x')
    Assert-Throws {& $module {param($p,$t) Read-InstallJournal $p $t -AllowTestRoot} $case.Lease.Path $case.Target} 'Corrupt journal was accepted.'
    [IO.File]::WriteAllBytes($case.Lease.Path,$original)
} finally {Close-Case $case}

# Reject before staging; the fixture wrapper retains cleanup ownership on error.
foreach($prior in @('1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e','malformed')){
    $case=New-Case
    try {
        & $module {param($l) Close-InstallJournalLease $l} $case.Lease
        Remove-Item -LiteralPath $case.Lease.Path -Force
        $case.State.PriorVersion=$prior
        Assert-Throws {& $module {param($v,$c,$t) New-InstallJournalCore $v $c $t ([pscustomobject]@{RequestId='c11b311638a54bfc9ebdd1803671ec40';TaskId='task-bf61fe7f22d74df7a92599681da5919e'}) -AllowTestRoot} $case.Validated $case.Context $case.Target} 'New compatibility journal accepted wrong installed prior.'
        Assert-True (!(Test-Path -LiteralPath $case.Lease.Path)) 'Rejected prior wrote a new journal.'
    } finally {Close-Case $case}
}
$case=New-Case
try {
    & $module {param($l) Close-InstallJournalLease $l} $case.Lease
    Remove-Item -LiteralPath $case.Lease.Path -Force
    Assert-Throws {& $module {param($v,$c,$t) New-InstallJournalCore $v $c $t ([pscustomobject]@{RequestId='9953e14c15524fe09440d1c7d7353950';TaskId='task-bf61fe7f22d74df7a92599681da5919e'}) -AllowTestRoot} $case.Validated $case.Context $case.Target} 'New compatibility journal accepted old request.'
    Assert-True (!(Test-Path -LiteralPath $case.Lease.Path)) 'Rejected request wrote a journal.'
} finally {Close-Case $case}

$boundaries=@('Prepared','CandidateStaged','ServiceStopPending','ServiceStopped','BackupMovePending','BackupVerified','ReplacementPending','FilesReplaced','TaskUpdatePending','TaskUpdated','HealthVerificationPending','CommitPending','RollbackPending')
foreach($boundary in $boundaries){
    $case=New-Case
    try {
        $marker=Join-Path $case.Root 'historical-sidecar.json';[IO.File]::WriteAllText($marker,'protected synthetic historical bytes');$before=(Get-FileHash $marker).Hash
        if($boundary -cne 'CandidateStaged'){Advance-To $case $boundary}
        $result=Recover $case { @() }
        Assert-True ($result.Status -ceq 'RolledBack' -and (& $module {param($p,$f) Test-InstallJournalFileSet $p $f} $case.Target $case.Prior)) "Compatibility rollback failed at $boundary."
        Assert-True ((Get-FileHash $marker).Hash -ceq $before) 'Rollback changed protected historical fixture bytes.'
        $repeat=Recover $case { @() };Assert-True (!$repeat.Recovered -and $repeat.Status -ceq 'RolledBack') 'Compatibility rollback replay was not idempotent.'
    } finally {Close-Case $case}
}
$case=New-Case
try {
    Advance-To $case 'ReplacementPending';Move-Candidate $case;$case.State.FailRestore=$true
    Assert-Throws {Recover $case { @() }} 'Interrupted task restore did not fail.'
    Assert-True ($case.Lease.Data.state -ceq 'RollbackPending') 'Task restore failure lost rollback journal.'
    $case.State.FailRestore=$false;$r=Recover $case { @() }
    Assert-True ($r.Status -ceq 'RolledBack') 'Retry after interrupted compatibility rollback failed.'
} finally {Close-Case $case}
"PASS: $script:testCount compatibility bootstrap assertions; 13 interruption boundaries; synthetic runtime/task only; live mutation=false."
