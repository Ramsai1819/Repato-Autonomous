$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$module=Import-Module (Join-Path $repo 'QaLaunchAgent\Repato.QaLaunchAgent.Bootstrap.psm1') -Force -PassThru
$temp=Join-Path ([IO.Path]::GetTempPath()) ('repato-snapshot-recovery-'+[guid]::NewGuid().ToString('N'))
$names=@('Repato.QaLaunchAgent.exe','Repato.QaLaunchAgent.dll','Repato.QaLaunchAgent.deps.json','Repato.QaLaunchAgent.runtimeconfig.json')
$account='RAMSAI\RepatoQA';$sid='S-1-5-21-1031246752-3872016183-2454652381-1015'
$pinnedVersion='1.0.10+50d5d752d9a8'
function Write-Runtime([string]$Root,[string]$Version){
    New-Item -ItemType Directory -Path $Root -Force|Out-Null
    foreach($name in $names){[IO.File]::WriteAllText((Join-Path $Root $name),"${Version}:$name")}
}
function New-Fixture([string]$Name){
    $root=Join-Path $temp $Name;$snapshot=Join-Path $root 'snapshot';$target=Join-Path $root 'install'
    Write-Runtime $snapshot 'snapshot-v1.0.10';Write-Runtime $target 'installed-failed-candidate'
    $files=@(foreach($name in $names){[pscustomobject]@{name=$name;sha256=(Get-FileHash (Join-Path $snapshot $name) -Algorithm SHA256).Hash}})
    $manifest=[pscustomobject]@{schemaVersion=1;kind='Repato.QaLaunchAgent.InstalledRuntimeSnapshot';product='Repato.QaLaunchAgent';productVersion=$pinnedVersion;installRoot='C:\Program Files\Repato\QaLaunchAgent';observedByAccount=$account;observedBySid=$sid;files=$files}
    $manifestPath=Join-Path $snapshot 'Repato.QaLaunchAgent.snapshot.json'
    $manifest|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $manifestHash=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
    $task=& $module {New-TaskSpec};$task|Add-Member NoteProperty PrincipalResolvedSid $sid;$task|Add-Member NoteProperty TriggerResolvedSid $sid
    $context=[pscustomobject]@{
        AssertAdministrator={};ResolveIdentity={param($a,$s) if($a -cne $account -or $s -cne $sid){throw 'synthetic identity mismatch'}}.GetNewClosure()
        GetTask={ $task }.GetNewClosure();GetTaskState={'Ready'};GetProcesses={@()}
        CopySecurity={param($source,$destination) Set-Acl -LiteralPath $destination -AclObject (Get-Acl -LiteralPath $source)}
    }
    [pscustomobject]@{Root=$root;Snapshot=$snapshot;Target=$target;Hash=$manifestHash;Manifest=$manifest;Context=$context}
}
function Invoke-Recovery($fixture,[scriptblock]$Hook){
    & $module {param($f,$hook) Invoke-RepatoQaLaunchAgentSnapshotRecoveryCore -SnapshotRoot $f.Snapshot -ManifestSha256 $f.Hash -ExpectedSnapshotRoot $f.Snapshot -ExpectedManifestSha256 $f.Hash -TargetRoot $f.Target -Context $f.Context -AllowTestRoot -InterruptionHook $hook} $fixture $Hook
}
try {
    $success=New-Fixture 'success'
    $beforeRootSddl=(Get-Acl -LiteralPath $success.Target).Sddl
    $beforeFileSddl=@{};foreach($name in $names){$beforeFileSddl[$name]=(Get-Acl -LiteralPath (Join-Path $success.Target $name)).Sddl}
    $result=Invoke-Recovery $success $null
    if(!$result.Recovered -or $result.AlreadyRestored -or !$result.RetainedEvidence -or !$result.RecoveryDirectory){throw 'Recovery did not complete while retaining its evidence.'}
    foreach($name in $names){if((Get-FileHash (Join-Path $success.Target $name) -Algorithm SHA256).Hash -cne ($success.Manifest.files|Where-Object name -eq $name).sha256){throw 'Recovered file does not match the validated snapshot.'};if((Get-Acl -LiteralPath (Join-Path $success.Target $name)).Sddl -cne $beforeFileSddl[$name]){throw 'Recovery changed an installed runtime file ACL.'}}
    if((Get-Acl -LiteralPath $success.Target).Sddl -cne $beforeRootSddl){throw 'Recovery changed the installation root ACL.'}
    if(!(Test-Path -LiteralPath (Join-Path $result.RecoveryDirectory 'previous')) -or !(Test-Path -LiteralPath (Join-Path $success.Snapshot 'Repato.QaLaunchAgent.snapshot.json'))){throw 'Recovery did not preserve the previous runtime and original snapshot.'}
    if(!( & $module {param($task) Test-TaskSpec $task} (& $success.Context.GetTask))){throw 'Recovery changed the scheduled-task contract.'}

    $corrupt=New-Fixture 'corrupt';[IO.File]::AppendAllText((Join-Path $corrupt.Snapshot 'Repato.QaLaunchAgent.dll'),'corruption')
    $before=@{};foreach($name in $names){$before[$name]=(Get-FileHash (Join-Path $corrupt.Target $name) -Algorithm SHA256).Hash}
    $rejected=$false;try{Invoke-Recovery $corrupt $null|Out-Null}catch{$rejected=$true}
    if(!$rejected){throw 'Corrupted snapshot was not rejected.'}
    foreach($name in $names){if((Get-FileHash (Join-Path $corrupt.Target $name) -Algorithm SHA256).Hash -cne $before[$name]){throw 'Corrupted snapshot rejection modified the installation.'}}
    if(@(Get-ChildItem -LiteralPath (Split-Path $corrupt.Target -Parent) -Directory -Force|Where-Object Name -Match '^\.QaLaunchAgent\.snapshot-recovery\.').Count){throw 'Corrupted snapshot rejection created a recovery transaction.'}

    $interrupted=New-Fixture 'interrupted';$interrupt=$false
    try{Invoke-Recovery $interrupted {param($state) if($state -eq 'PreviousMoved'){throw 'synthetic process exit'}}|Out-Null}catch{$interrupt=$true}
    if(!$interrupt -or (Test-Path -LiteralPath $interrupted.Target)){throw 'Synthetic interruption did not leave the expected retained, resumable state.'}
    Remove-Module $module.Name -Force
    $module=Import-Module (Join-Path $repo 'QaLaunchAgent\Repato.QaLaunchAgent.Bootstrap.psm1') -Force -PassThru
    $resumed=Invoke-Recovery $interrupted $null
    if(!$resumed.Recovered -or $resumed.AlreadyRestored -or !(Test-Path -LiteralPath (Join-Path $resumed.RecoveryDirectory 'previous'))){throw 'Recovery did not resume safely after module/process state was lost.'}
    foreach($name in $names){if((Get-FileHash (Join-Path $interrupted.Target $name) -Algorithm SHA256).Hash -cne ($interrupted.Manifest.files|Where-Object name -eq $name).sha256){throw 'Resumed recovery runtime does not match snapshot.'}}

    $deployment=New-Fixture 'deployment-failure'
    Remove-Item -LiteralPath $deployment.Target -Recurse -Force
    Write-Runtime $deployment.Target 'snapshot-v1.0.10'
    $candidate=Join-Path $deployment.Root 'candidate-v1.0.13';Write-Runtime $candidate 'candidate-v1.0.13'
    $candidateFiles=@(foreach($name in $names){[pscustomobject]@{name=$name;sha256=(Get-FileHash (Join-Path $candidate $name) -Algorithm SHA256).Hash}})
    $validated=[pscustomobject]@{SourceRoot=$candidate;Manifest=[pscustomobject]@{files=$candidateFiles;productVersion='1.0.13+synthetic'};ManifestSha256=('C'*64)}
    $installState=[pscustomobject]@{Task=& $module {New-TaskSpec}}
    $installContext=[pscustomobject]@{
        IsAdministrator={};ResolveIdentity={param($a,$s)};PrepareAcl={param($path)}
        GetTask={ $installState.Task }.GetNewClosure();ExportTask={param($task) 'synthetic-task-xml'}
        SetTask={param($spec) $installState.Task=$spec}.GetNewClosure()
        RestoreTask={param($xml) $installState.Task=& $module {New-TaskSpec}}.GetNewClosure()
    }
    $installed=& $module {param($v,$c,$t) Invoke-InstallCore $v $c $t -AllowTestRoot -RetainRollback -ProcessDetector {$null}} $validated $installContext $deployment.Target
    $candidateStartFailed=$true
    if($candidateStartFailed){$autoRollback=& $module {param($token,$c,$t) Restore-InstallCore $token $c $t -AllowTestRoot -ProcessDetector {$null}} $installed.RollbackToken $installContext $deployment.Target}
    $rollbackHealthFailed=$true
    if(!$candidateStartFailed -or !$rollbackHealthFailed -or !$autoRollback.Restored){throw 'Synthetic deployment did not reach the double-health-failure state.'}
    Remove-Module $module.Name -Force
    $module=Import-Module (Join-Path $repo 'QaLaunchAgent\Repato.QaLaunchAgent.Bootstrap.psm1') -Force -PassThru
    if(!$module.ExportedFunctions.ContainsKey('Restore-RepatoQaLaunchAgentSnapshot') -or $module.Path -ine (Join-Path $repo 'QaLaunchAgent\Repato.QaLaunchAgent.Bootstrap.psm1') -or $module.ExportedCommands['Restore-RepatoQaLaunchAgentSnapshot'].Parameters.ContainsKey('RollbackToken')){throw 'Installed repository module does not expose the token-independent recovery command.'}
    $postExit=Invoke-Recovery $deployment $null
    if(!$postExit.Recovered -or !$postExit.AlreadyRestored -or !(Test-Path -LiteralPath $autoRollback.CleanupRoot)){throw 'Post-exit snapshot recovery did not validate restored files while retaining failed-candidate evidence.'}
    if(@(Get-ChildItem -LiteralPath (Split-Path $deployment.Target -Parent) -Directory -Force|Where-Object Name -Match '^\.QaLaunchAgent\.snapshot-recovery\.').Count){throw 'Already-restored recovery unexpectedly rewrote the runtime.'}
    [pscustomobject]@{SuccessfulRecovery='PASS';CorruptedSnapshotRejected='PASS';InterruptedRecoveryResumedAfterModuleReload='PASS';DeploymentAndRollbackHealthFailure='PASS';InstalledModuleRecoveryAfterExitWithoutToken='PASS';InstalledAclPreserved='PASS';TaskContractPreserved='PASS';SnapshotAndFailureEvidenceRetained='PASS'}|ConvertTo-Json -Compress
} finally {Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
