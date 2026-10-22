$ErrorActionPreference='Stop'
$modulePath=Join-Path $PSScriptRoot '../QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1'
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
        StopTask=({if(!$State.Lease -or $State.Lease.Data.state -cne 'RollbackPending'){throw 'rollback state was not persisted before stopping the task'};$State.TaskStopped=$true}.GetNewClosure());StartTask=({}.GetNewClosure());GetProcesses=({@()}.GetNewClosure());StopProcesses=({param($items)if(!$State.TaskStopped){throw 'task stop must precede process stop'};$State.AgentStopCalled=$true}.GetNewClosure());GetProductVersion=({param($path)'synthetic-1.0'}.GetNewClosure())
    }
    $State.ValidTask=$task;$State.Task=$task
}
function New-Case {
    $root=Join-Path ([IO.Path]::GetTempPath()) ('repato-install-recovery-'+[guid]::NewGuid().ToString('N'));$target=Join-Path $root 'install';$source=Join-Path $root 'candidate';New-Bytes $target 'prior';New-Bytes $source 'candidate'
    $files=@(Get-ChildItem -LiteralPath $source -File|ForEach-Object{[pscustomobject]@{name=$_.Name;sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}})
    $prior=@(Get-ChildItem -LiteralPath $target -File|ForEach-Object{[pscustomobject]@{name=$_.Name;sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}})
    $fake=@{Task=$null;TaskState='Ready';FailRestore=$false};$context=New-FakeContext $fake;$fake.Task=& $module {param($ctx)& $ctx.GetTask} $context
    $validated=[pscustomobject]@{SourceRoot=$source;ManifestSha256=('A'*64);Manifest=[pscustomobject]@{productVersion='1.0.18+4b0066247088';files=$files}}
    $lease=& $module {param($v,$c,$t) New-InstallJournalCore $v $c $t ([pscustomobject]@{RequestId='9953e14c15524fe09440d1c7d7353950';TaskId='task-bf61fe7f22d74df7a92599681da5919e'}) -AllowTestRoot} $validated $context $target
    $fake.Lease=$lease
    [pscustomobject]@{Root=$root;Target=$target;Source=$source;Files=$files;Prior=$prior;Context=$context;State=$fake;Lease=$lease;Module=$module;Validated=$validated}
}
function Close-Case($Case){& $Case.Module {param($l) Close-InstallJournalLease $l} $Case.Lease;if(Test-Path -LiteralPath $Case.Root){Remove-Item -LiteralPath $Case.Root -Recurse -Force}}
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

$boundaries=@('Prepared','CandidateStaged','ServiceStopPending','ServiceStopped','BackupMovePending','BackupVerified','ReplacementPending','FilesReplaced','TaskUpdatePending','TaskUpdated','HealthVerificationPending','CommitPending','RollbackPending')
foreach($boundary in $boundaries){$case=New-Case;try{if($boundary -cne 'CandidateStaged'){Advance-To $case $boundary};$result=Recover $case { @() };$ok=& $module {param($path,$files) Test-InstallJournalFileSet $path $files} $case.Target $case.Prior;Assert-True ($result.Status -eq 'RolledBack' -and $ok) "Interrupted state $boundary did not restore the prior runtime."}finally{Close-Case $case}}

$case=New-Case;try{Advance-To $case 'ReplacementPending';Move-Candidate $case;$case.State.FailRestore=$true;Assert-Throws {Recover $case { @() }} 'Injected rollback failure must be surfaced.';Assert-True ($case.Lease.Data.state -eq 'RollbackPending') 'Failed rollback must retain a recoverable journal.';$case.State.FailRestore=$false;$r=Recover $case { @() };Assert-True ($r.Status -eq 'RolledBack') 'Recovery retry after task-restore failure did not complete.'}finally{Close-Case $case}

$case=New-Case;try{Advance-To $case 'ReplacementPending';Move-Candidate $case;[IO.File]::WriteAllText((Join-Path $case.Target 'Repato.QaLaunchAgent.exe'),'partial replacement');$null=Recover $case { @() };Assert-True (Test-Path -LiteralPath $case.Lease.Data.failedRoot -PathType Container) 'Partial replacement bytes were not retained as failed-runtime evidence.';Assert-True (& $module {param($p,$f) Test-InstallJournalFileSet $p $f} $case.Target $case.Prior) 'Prior runtime was not restored after partial replacement.'}finally{Close-Case $case}

$case=New-Case;try{Advance-To $case 'BackupMovePending';Move-Backup $case;$r=Recover $case { @() };Assert-True ($r.Status -eq 'RolledBack' -and (& $module {param($p,$f) Test-InstallJournalFileSet $p $f} $case.Target $case.Prior)) 'Interruption after backup move but before BackupVerified did not recover.'}finally{Close-Case $case}
$case=New-Case;try{Advance-To $case 'ReplacementPending';Move-Candidate $case;$r=Recover $case { @() };Assert-True ($r.Status -eq 'RolledBack' -and (& $module {param($p,$f) Test-InstallJournalFileSet $p $f} $case.Target $case.Prior)) 'Interruption after candidate move but before FilesReplaced did not recover.'}finally{Close-Case $case}
$case=New-Case;try{Advance-To $case 'TaskUpdatePending';$case.Context.SetTask.Invoke($null);$r=Recover $case { @() };Assert-True ($r.Status -eq 'RolledBack' -and (& $module {param($p,$f) Test-InstallJournalFileSet $p $f} $case.Target $case.Prior)) 'Interruption during scheduled-task update did not recover.'}finally{Close-Case $case}

$case=New-Case;try{$before=$case.Lease.Data.state;Assert-Throws {Recover $case {throw 'process state unavailable'}} 'Process uncertainty must block recovery.';Assert-True ($case.Lease.Data.state -eq $before) 'Process uncertainty changed the journal.'}finally{Close-Case $case}
$case=New-Case;try{$script:queries=0;$detector={if($script:queries++ -lt 2){@([pscustomobject]@{ProcessId=7})}else{@()}};$r=Recover $case $detector;Assert-True ($r.Status -eq 'RolledBack' -and $case.State.AgentStopCalled) 'Verified active Launch Agent was not stopped through the injected process boundary.'}finally{Close-Case $case}

$case=New-Case;try{$orphan=$case.Lease.Path+'.interrupted-write.tmp';[IO.File]::WriteAllText($orphan,'partial journal write');$r=Recover $case { @() };Assert-True ($r.Status -eq 'RolledBack' -and (Test-Path -LiteralPath $orphan)) 'Valid prior journal did not recover safely while retaining an interrupted temp write.'}finally{Close-Case $case}
$case=New-Case;try{$marker=Join-Path $case.Root 'active.json';[IO.File]::WriteAllText($marker,'synthetic unresolved active marker');$hash=(Get-FileHash $marker -Algorithm SHA256).Hash;$null=Recover $case { @() };Assert-True ((Get-FileHash $marker -Algorithm SHA256).Hash -ceq $hash) 'Recovery modified the unresolved active marker.'}finally{Close-Case $case}

$case=New-Case;try{Set-State $case 'ServiceStopPending';$raw=Get-Content -LiteralPath $case.Lease.Path -Raw;$j=$raw|ConvertFrom-Json;$j.generation++;$j.requestId='wrong-request';$j.journalSha256='';& $module {param($j) Write-InstallJournal $j|Out-Null} $j;Assert-Throws {& $module {param($p,$t) Read-InstallJournal $p $t -AllowTestRoot} $case.Lease.Path $case.Target} 'Wrong request identity must reject the journal.'}finally{Close-Case $case}

$case=New-Case;try{[IO.File]::AppendAllText($case.Lease.Path,'x');Assert-Throws {& $module {param($l) Get-InstallJournal $l} $case.Lease} 'Corrupted journal must reject recovery.'}finally{Close-Case $case}
$case=New-Case;try{$raw=Get-Content -LiteralPath $case.Lease.Path -Raw;$raw=[regex]::Replace($raw,'("name"\s*:\s*"[^"]+")','$1,$1',1);[IO.File]::WriteAllText($case.Lease.Path,$raw);Assert-Throws {& $module {param($l) Get-InstallJournal $l} $case.Lease} 'Duplicate nested journal properties must reject recovery.'}finally{Close-Case $case}

$case=New-Case;try{$j=Get-Content -LiteralPath $case.Lease.Path -Raw|ConvertFrom-Json;$j.generation++;$j.state='ServiceStopPending';& $module {param($j) Write-InstallJournal $j|Out-Null} $j;Assert-Throws {& $module {param($l) Get-InstallJournal $l} $case.Lease} 'Journal generation conflict must reject the stale lease.'}finally{Close-Case $case}

$case=New-Case;try{$null=Recover $case { @() };$result=Recover $case { @() };Assert-True ($result.Status -eq 'RolledBack' -and !$result.Recovered) 'Repeated recovery was not idempotent.'}finally{Close-Case $case}

$case=New-Case;try{Advance-To $case 'FilesReplaced';$task=$case.State.Task;$null=Set-State $case 'TaskUpdatePending';Set-State $case 'TaskUpdated';Set-State $case 'HealthVerificationPending';Set-State $case 'CommitPending';Set-State $case 'Committed';$result=Recover $case { @() };Assert-True ($result.Status -eq 'Committed' -and (Test-Path -LiteralPath $case.Lease.Data.backupRoot)) 'Committed install was not distinguished or its rollback copy was lost.'}finally{Close-Case $case}

$case=New-Case;try{Advance-To $case 'ServiceStopPending';Set-State $case 'ServiceStopped';$installed=& $module {param($v,$c,$target,$lease)$detector={@()};Invoke-InstallCore $v $c $target -AllowTestRoot -ProcessDetector $detector -RetainRollback -DurableJournal $lease} $case.Validated $case.Context $case.Target $case.Lease;Assert-True ($case.Lease.Data.state -eq 'TaskUpdated' -and (Test-Path -LiteralPath $case.Lease.Data.backupRoot)) 'Durable installer did not persist replacement/task boundaries and verified backup.';& $module {param($token,$target)Set-RepatoQaLaunchAgentBootstrapInstallHealthVerification -JournalLease $token.DurableJournal;Complete-InstallCore $token $target -AllowTestRoot|Out-Null} $installed.RollbackToken $case.Target;Assert-True (Test-Path -LiteralPath $case.Lease.Data.backupRoot) 'Successful installation discarded the verified rollback runtime.'}finally{Close-Case $case}

Write-Output "PASS: $script:testCount assertions across $($boundaries.Count) interruption boundaries and corruption, mismatch, partial replacement, process uncertainty, rollback failure, repeat recovery, and committed recovery."
