$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$module=Import-Module (Join-Path $repo 'QaLaunchAgent\Repato.QaLaunchAgent.Bootstrap.psm1') -Force -PassThru
$temp=Join-Path ([IO.Path]::GetTempPath()) ('repato-launchagent-rollback-'+[guid]::NewGuid().ToString('N'))
$names=@('Repato.QaLaunchAgent.exe','Repato.QaLaunchAgent.dll','Repato.QaLaunchAgent.deps.json','Repato.QaLaunchAgent.runtimeconfig.json')
function Write-Runtime([string]$Root,[string]$Version){
    New-Item -ItemType Directory -Path $Root -Force|Out-Null
    foreach($name in $names){[IO.File]::WriteAllText((Join-Path $Root $name),"${Version}:$name")}
}
function New-Validated([string]$Root){
    $files=@(foreach($name in $names){[pscustomobject]@{name=$name;sha256=(Get-FileHash (Join-Path $Root $name) -Algorithm SHA256).Hash}})
    [pscustomobject]@{SourceRoot=$Root;Manifest=[pscustomobject]@{files=$files;productVersion='synthetic'};ManifestSha256=('A'*64)}
}
$state=[pscustomobject]@{Task=$null;FailSet=$false}
$context=[pscustomobject]@{
    IsAdministrator={};ResolveIdentity={param($a,$s)};PrepareAcl={param($p)}
    GetTask={ $state.Task };ExportTask={param($t) if($t){'old-task-xml'}}
    SetTask={param($spec) if($state.FailSet){throw 'synthetic install failure'};$state.Task=$spec}
    RestoreTask={param($xml) if($xml){$state.Task=& $module {New-TaskSpec}}else{$state.Task=$null}}
    RemoveTask={$state.Task=$null}
}
try {
    $installer=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Install-QaLaunchAgentCandidateForPlanViews.ps1') -Raw
    $wrapper=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Run-PlanViewsAgentInstallWithLog.ps1') -Raw
    $healthAt=$installer.IndexOf('Invoke-MayaQaLaunchAgentHealth -TimeoutMilliseconds 3000')
    $commitAt=$installer.IndexOf('Complete-RepatoQaLaunchAgentBootstrapInstall -RollbackToken $rollbackToken')
    $restoreAt=$installer.IndexOf('Restore-RepatoQaLaunchAgentBootstrapInstall -RollbackToken $rollbackToken')
    $restoreHealthAt=$installer.IndexOf('Invoke-MayaQaLaunchAgentHealth -TimeoutMilliseconds 3000',$healthAt+1)
    if(!$installer.Contains('-RetainRollback') -or $healthAt -lt 0 -or $commitAt -lt $healthAt -or $restoreAt -lt 0 -or $restoreHealthAt -lt $restoreAt -or !$installer.Contains('$RecoveryManifestSha256') -or !$wrapper.Contains('New-RepatoQaLaunchAgentInstallArguments')){throw 'Production installer does not retain rollback through both health checks, snapshot validation, and stopped-agent handling.'}
    $source=Join-Path $temp 'candidate';$target=Join-Path $temp 'install'
    Write-Runtime $source 'candidate';Write-Runtime $target 'old'
    $validated=New-Validated $source
    $installed=& $module {param($v,$c,$t) Invoke-InstallCore $v $c $t -AllowTestRoot -RetainRollback -ProcessDetector {$null}} $validated $context $target
    if(!$installed.Installed -or !$installed.RollbackToken -or !(Test-Path -LiteralPath $installed.RollbackToken.BackupRoot)){throw 'successful install did not retain rollback files'}
    $candidateHealth=$true
    if(!$candidateHealth){throw 'synthetic candidate health failed'}
    $complete=& $module {param($token,$target) Complete-InstallCore $token $target -AllowTestRoot} $installed.RollbackToken $target
    if(!$complete.Completed -or !$complete.CleanupComplete -or (Test-Path -LiteralPath $installed.RollbackToken.BackupRoot)){throw 'successful health verification did not clean retained rollback files'}
    foreach($name in $names){if((Get-Content -LiteralPath (Join-Path $target $name) -Raw) -cne "candidate:$name"){throw 'candidate runtime was not installed'}}

    $source2=Join-Path $temp 'candidate-failure';Remove-Item -LiteralPath $target -Recurse -Force;Write-Runtime $source2 'candidate-failure';Write-Runtime $target 'prior';$state.Task=& $module {New-TaskSpec}
    $prior=New-Validated $source2;$installed=& $module {param($v,$c,$t) Invoke-InstallCore $v $c $t -AllowTestRoot -RetainRollback -ProcessDetector {$null}} $prior $context $target
    $candidateHealth=$false
    if(!$candidateHealth){$restored=& $module {param($token,$c,$target) Restore-InstallCore $token $c $target -AllowTestRoot -ProcessDetector {$null}} $installed.RollbackToken $context $target}
    if(!$restored.Restored -or @($restored.RuntimeIntegrity|Where-Object{!$_.Match}).Count -or !( & $module {param($task) Test-TaskSpec $task} $state.Task)){throw 'failed candidate verification did not restore runtime and task'}
    $restoredHealth=$true
    if(!$restoredHealth){throw 'synthetic restored-agent health failed'}
    $complete=& $module {param($token,$target) Complete-InstallCore $token $target -AllowTestRoot} $restored $target
    if(!$complete.Completed -or !$complete.CleanupComplete -or (Test-Path -LiteralPath $restored.CleanupRoot)){throw 'verified rollback did not clean failed candidate files'}
    foreach($name in $names){if((Get-Content -LiteralPath (Join-Path $target $name) -Raw) -cne "prior:$name"){throw 'restored runtime bytes did not match prior installation'}}
    [pscustomobject]@{SuccessfulInstall='PASS';FailedHealthRollback='PASS';RestoredHealth='PASS';Cleanup='PASS'}|ConvertTo-Json -Compress
} finally {Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
