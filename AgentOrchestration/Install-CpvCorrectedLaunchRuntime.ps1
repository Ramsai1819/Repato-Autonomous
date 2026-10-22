$ErrorActionPreference='Stop'
$principal=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Corrected runtime installation requires elevated administrator PowerShell before any process or file mutation.'}
$repo=Split-Path $PSScriptRoot -Parent
Start-Transcript -Path (Join-Path $repo 'QA/Reports/CpvCorrectedRuntimeInstall.log') -Append | Out-Null
Import-Module (Join-Path $repo 'QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
. (Join-Path $PSScriptRoot 'Repato.QaLaunchAgentInstall.ps1')
$release=Join-Path $repo 'DeploymentCandidates/AgentReleases/Repato.QaLaunchAgent-1.0.15+4cf5b76be987'
$manifest=Join-Path $release 'Repato.QaLaunchAgent.release.json';$hash='247E36E14C4D6DA2110D51ACA7A30AD3767523A622E10CCFDD22AD460245FF58'
if((Get-FileHash $manifest).Hash -cne $hash){throw 'Corrected runtime release manifest changed.'}
$contract=Get-RepatoQaLaunchAgentBootstrapContract
if(@(Get-Process Revit -ErrorAction SilentlyContinue).Count){throw 'Revit must be stopped before runtime update.'}
$oldExe=Join-Path $contract.InstallRoot 'Repato.QaLaunchAgent.exe';$oldDll=Join-Path $contract.InstallRoot 'Repato.QaLaunchAgent.dll'
if((Get-Item $oldExe).VersionInfo.ProductVersion -cne '1.0.13+6cf1fa19150f' -or (Get-FileHash $oldDll).Hash -cne '36943EC0890740D5B95927685B90327A7BFFBD4D38733C884BC5194EE4EFEE3F'){throw 'Installed runtime differs from the observed failed-attempt runtime.'}
$backup=Join-Path $repo ('DeploymentBackups/CpvLaunchRuntime-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'));New-Item $backup -ItemType Directory|Out-Null
$files=@();foreach($name in $contract.RuntimeFiles){$source=Join-Path $contract.InstallRoot $name;$h=(Get-FileHash $source).Hash;Copy-Item $source (Join-Path $backup $name);if((Get-FileHash (Join-Path $backup $name)).Hash -cne $h){throw 'Runtime snapshot integrity failed.'};$files+=[pscustomobject]@{name=$name;sha256=$h}}
[pscustomobject]@{ProductVersion='1.0.13+6cf1fa19150f';InstallRoot=$contract.InstallRoot;Files=$files}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $backup 'installed-runtime-evidence.json')
$agents=@(Get-Process -Name Repato.QaLaunchAgent -ErrorAction SilentlyContinue)
if($agents.Count -ne 1 -or $agents[0].Path -ine $oldExe){throw 'Exact installed launch agent process required.'}
$agentHealth=Invoke-MayaQaLaunchAgentHealth -TimeoutMilliseconds 3000
if(!$agentHealth.Ready -or $agentHealth.User -ine $contract.Account -or $agentHealth.Sid -cne $contract.Sid -or $agentHealth.SessionId -ne $agents[0].SessionId){throw 'Installed Launch Agent authenticated session identity is invalid.'}
Stop-RepatoQaLaunchAgentForUpdate -ExpectedAgentPid $agents[0].Id -ExpectedAgentStartTime $agents[0].StartTime.ToString('o') -ExpectedSessionId $agentHealth.SessionId -AgentExe $oldExe -TaskPath $contract.TaskPath -TaskName $contract.TaskName
$token=$null
try {
    $installed=Install-RepatoQaLaunchAgentBootstrap -SourceRoot $release -ManifestPath $manifest -ManifestSha256 $hash -RetainRollback
    $token=$installed.RollbackToken
    $test=Test-RepatoQaLaunchAgentBootstrap -ManifestPath $manifest -ManifestSha256 $hash
    if(!$test.InstalledRuntimeIntegrity -or !$test.TaskContractValid){throw 'Installed candidate runtime/task verification failed.'}
    Start-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName
    Start-Sleep -Seconds 2
    $health=Invoke-MayaQaLaunchAgentHealth;$pre=Invoke-MayaQaLaunchAgentPreflightReadonly
    if(!$health.Ready -or $health.User -ine $contract.Account -or $health.SID -cne $contract.Sid -or !$pre.Succeeded){
        [pscustomobject]@{Stage='health-preflight';Health=$health;Preflight=$pre;Test=$test}|ConvertTo-Json -Depth 15|Set-Content (Join-Path $repo 'QA/Reports/CpvCorrectedRuntimeInstallFailure.json')
        throw 'Corrected runtime health/preflight failed.'
    }
    $null=Complete-RepatoQaLaunchAgentBootstrapInstall -RollbackToken $token;$token=$null
    $result=[pscustomobject]@{Installed=$true;Version=$test.ProductVersion;ReleaseManifestPath=$manifest;ReleaseManifestSha256=$hash;RuntimeDllSha256=(Get-FileHash $oldDll).Hash;BackupRoot=$backup;Health=$health;Preflight=$pre;RevitLaunched=$false}
    $result|ConvertTo-Json -Depth 15|Set-Content (Join-Path $repo 'QA/Reports/CpvCorrectedRuntimeInstall.json')
    $result|Select-Object Installed,Version,ReleaseManifestPath,ReleaseManifestSha256,RuntimeDllSha256,BackupRoot,RevitLaunched|ConvertTo-Json
} catch {
    $failure=$_
    if($token){
        $running=@(Get-Process -Name Repato.QaLaunchAgent -ErrorAction SilentlyContinue)
        if($running.Count -gt 1){throw 'Multiple Launch Agent processes prevent a safe rollback.'}
        if($running.Count){
            if($running[0].Path -ine $contract.Executable){throw 'Unexpected Launch Agent process prevents a safe rollback.'}
            $rollbackHealth=Invoke-MayaQaLaunchAgentHealth -TimeoutMilliseconds 3000
            if(!$rollbackHealth.Ready -or $rollbackHealth.User -ine $contract.Account -or $rollbackHealth.Sid -cne $contract.Sid -or $rollbackHealth.SessionId -ne $running[0].SessionId){throw 'Rollback Launch Agent session identity is unverified.'}
            Stop-RepatoQaLaunchAgentForUpdate -ExpectedAgentPid $running[0].Id -ExpectedAgentStartTime $running[0].StartTime.ToString('o') -ExpectedSessionId $rollbackHealth.SessionId -AgentExe $contract.Executable -TaskPath $contract.TaskPath -TaskName $contract.TaskName
        }
        $null=Restore-RepatoQaLaunchAgentBootstrapInstall -RollbackToken $token
    }
    Start-ScheduledTask -TaskPath $contract.TaskPath -TaskName $contract.TaskName
    throw $failure
}
