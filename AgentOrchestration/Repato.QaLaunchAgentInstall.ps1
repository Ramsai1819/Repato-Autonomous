function New-RepatoQaLaunchAgentInstallArguments {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Agents,
        [Parameter(Mandatory)][string]$ReleaseRoot,
        [Parameter(Mandatory)][string]$ManifestSha256,
        [Parameter(Mandatory)][string]$RecoverySnapshotRoot,
        [Parameter(Mandatory)][string]$RecoveryManifestSha256
    )
    if($Agents.Count -gt 1){throw 'Multiple Launch Agent processes are present.'}
    $arguments=@{ExpectedAgentPid=0;ReleaseRoot=$ReleaseRoot;ManifestSha256=$ManifestSha256;RecoverySnapshotRoot=$RecoverySnapshotRoot;RecoveryManifestSha256=$RecoveryManifestSha256}
    if($Agents.Count){
        $agent=$Agents[0]
        if($agent.ProcessName -cne 'Repato.QaLaunchAgent' -or $agent.Path -ine 'C:\Program Files\Repato\QaLaunchAgent\Repato.QaLaunchAgent.exe' -or $agent.Id -le 0 -or !$agent.StartTime -or $agent.SessionId -le 0){throw 'Launch Agent process identity is unexpected or incomplete.'}
        $arguments.ExpectedAgentPid=$agent.Id
        $arguments.ExpectedAgentStartTime=$agent.StartTime.ToString('o')
        $arguments.ExpectedAgentSessionId=[int]$agent.SessionId
    }
    $arguments
}

function ConvertFrom-RepatoCimProcessStartTime($Value) {
    if($Value -is [DateTime]){return $Value}
    if($Value -isnot [string] -or $Value -notmatch '^\d{14}\.\d{6}[+-]\d{3}$'){throw 'Launch Agent CIM process creation timestamp is missing or invalid.'}
    try{[Management.ManagementDateTimeConverter]::ToDateTime($Value)}catch{throw 'Launch Agent CIM process creation timestamp is invalid.'}
}

function Get-RepatoQaLaunchAgentProcessIdentity {
    param([Parameter(Mandatory)][int]$ProcessId)
    $process=Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if(!$process){return $null}
    if($process.Id -ne $ProcessId){throw 'Process ID changed during Launch Agent identity lookup.'}
    # Open the process handle before reading identity; the same handle is used for termination.
    $null=$process.Handle
    $items=@(Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction Stop)
    if($items.Count -ne 1){throw 'Launch Agent process identity is missing or ambiguous.'}
    $item=$items[0]
    if([int]$item.ProcessId -ne $ProcessId -or $item.ExecutablePath -ine $process.Path -or [int]$item.SessionId -ne $process.SessionId){throw 'Launch Agent process identity changed during lookup.'}
    $owner=Invoke-CimMethod -InputObject $item -MethodName GetOwner -ErrorAction Stop
    if($owner.ReturnValue -ne 0){throw 'Launch Agent process owner could not be verified.'}
    $ownerSid=([Security.Principal.NTAccount]($owner.Domain+'\'+$owner.User)).Translate([Security.Principal.SecurityIdentifier]).Value
    $cimStart=ConvertFrom-RepatoCimProcessStartTime $item.CreationDate
    if([Math]::Abs(($cimStart-$process.StartTime).TotalSeconds) -gt 0.05){throw 'Launch Agent process creation identity changed during lookup.'}
    [pscustomobject]@{Process=$process;ProcessId=$ProcessId;ProcessName=$process.ProcessName;Path=$process.Path;StartTime=$process.StartTime.ToString('o');SessionId=[int]$process.SessionId;OwnerSid=$ownerSid}
}

function Resolve-RepatoQaLaunchAgentBootstrapModule {
    [CmdletBinding()]
    param(
        [string]$ModulePath=(Join-Path $PSScriptRoot '../QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1'),
        [scriptblock]$ImportProvider
    )
    $expectedPath=[IO.Path]::GetFullPath($ModulePath)
    $imported=@(if($ImportProvider){& $ImportProvider $expectedPath}else{Import-Module -Name $expectedPath -Force -PassThru -ErrorAction Stop})
    if($imported.Count -ne 1){throw 'The trusted Launch Agent bootstrap module import is missing or ambiguous.'}
    $module=$imported[0]
    if($module -isnot [Management.Automation.PSModuleInfo] -or $module.Name -cne 'Repato.QaLaunchAgent.Bootstrap' -or
        [IO.Path]::GetFullPath([string]$module.Path) -ine $expectedPath){throw 'The trusted Launch Agent bootstrap module identity does not match its expected source.'}
    $module
}

function Get-RepatoQaLaunchAgentTaskEvidence {
    param([Parameter(Mandatory)][Management.Automation.PSModuleInfo]$BootstrapModule,[scriptblock]$GetTask,[scriptblock]$GetRawTask,[scriptblock]$ExportTask)
    $bootstrap=$BootstrapModule
    if(!$GetTask){$context=& $bootstrap { New-RealBootstrapContext };$GetTask=$context.GetTask}
    if(!$GetRawTask){$GetRawTask={Get-ScheduledTask -TaskPath '\Repato\' -TaskName 'Repato QA Launch Agent' -ErrorAction Stop}}
    if(!$ExportTask){$ExportTask={param($task)Export-ScheduledTask -TaskPath '\Repato\' -TaskName 'Repato QA Launch Agent' -ErrorAction Stop}}
    $actual=& $GetTask
    $raw=& $GetRawTask
    $valid=& $bootstrap {param($task) Test-TaskSpec $task} $actual
    $xml=[string](& $ExportTask $raw)
    $sha=[Security.Cryptography.SHA256]::Create();try{$xmlHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($xml)))).Replace('-','')}finally{$sha.Dispose()}
    [pscustomobject]@{Valid=[bool]$valid;TaskPath=[string]$actual.TaskPath;TaskName=[string]$actual.TaskName;PrincipalSid=[string]$actual.PrincipalResolvedSid;TriggerSid=[string]$actual.TriggerResolvedSid;State=$raw.State.ToString();XmlSha256=$xmlHash}
}

function Stop-RepatoQaLaunchAgentForUpdate {
    param(
        [Parameter(Mandatory)][ValidateRange(1,[int]::MaxValue)][int]$ExpectedAgentPid,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExpectedAgentStartTime,
        [Parameter(Mandatory)][string]$AgentExe,
        [Parameter(Mandatory)][string]$TaskPath,
        [Parameter(Mandatory)][string]$TaskName,
        [int]$ExpectedSessionId,
        [scriptblock]$GetProcessIdentity,
        [scriptblock]$GetTaskEvidence,
        [Management.Automation.PSModuleInfo]$BootstrapModule,
        [scriptblock]$StopTask = { param($path,$name) Stop-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction Stop },
        [scriptblock]$StopProcess = { param($identity) $identity.Process.Kill() },
        [scriptblock]$StartTask = { param($path,$name) Start-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction Stop },
        [scriptblock]$Wait = { param($milliseconds) Start-Sleep -Milliseconds $milliseconds }
    )
    $contract=Get-RepatoQaLaunchAgentBootstrapContract
    if([IO.Path]::GetFullPath($AgentExe) -ine [IO.Path]::GetFullPath($contract.Executable) -or $TaskPath -cne $contract.TaskPath -or $TaskName -cne $contract.TaskName){throw 'Installer stop target differs from the fixed Launch Agent contract.'}
    if($ExpectedSessionId -lt 0){throw 'Expected session identity is invalid.'}
    if(!$GetProcessIdentity){$GetProcessIdentity={param($id)Get-RepatoQaLaunchAgentProcessIdentity -ProcessId $id}}
    if(!$BootstrapModule){$BootstrapModule=Resolve-RepatoQaLaunchAgentBootstrapModule}
    if(!$GetTaskEvidence){$GetTaskEvidence={Get-RepatoQaLaunchAgentTaskEvidence -BootstrapModule $BootstrapModule}.GetNewClosure()}
    $assertTask={
        param($evidence)
        if(@($evidence).Count -ne 1 -or !$evidence.Valid -or $evidence.TaskPath -cne $contract.TaskPath -or $evidence.TaskName -cne $contract.TaskName -or
            $evidence.PrincipalSid -cne $contract.Sid -or $evidence.TriggerSid -cne $contract.Sid -or $evidence.XmlSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
            $evidence.State -notin @('Ready','Running')){throw 'Scheduled-task identity, principal, state, or export is invalid or ambiguous.'}
    }
    $assertProcess={
        param($identity)
        if(@($identity).Count -ne 1 -or !$identity){throw 'Launch Agent process identity is missing or ambiguous.'}
        if([int]$identity.ProcessId -ne $ExpectedAgentPid -or $identity.ProcessName -cne 'Repato.QaLaunchAgent' -or
            [IO.Path]::GetFullPath([string]$identity.Path) -ine [IO.Path]::GetFullPath($contract.Executable) -or
            [string]$identity.StartTime -cne $ExpectedAgentStartTime -or [int]$identity.SessionId -le 0 -or
            $identity.OwnerSid -cne $contract.Sid -or ($ExpectedSessionId -gt 0 -and [int]$identity.SessionId -ne $ExpectedSessionId)){
            throw 'Launch Agent process identity changed or does not match the fixed RepatoQA session.'
        }
    }
    $initialTask=& $GetTaskEvidence; & $assertTask $initialTask
    $initialTaskState=[string]$initialTask.State;$initialTaskXmlSha256=[string]$initialTask.XmlSha256
    $initialProcess=& $GetProcessIdentity $ExpectedAgentPid; & $assertProcess $initialProcess
    $taskStopAttempted=$false
    try {
        if($initialTaskState -ceq 'Running'){$taskStopAttempted=$true;& $StopTask $TaskPath $TaskName}
        $afterTask=& $GetTaskEvidence; & $assertTask $afterTask
        if($afterTask.XmlSha256 -cne $initialTaskXmlSha256){throw 'Scheduled-task definition changed during installer stop.'}
        $current=& $GetProcessIdentity $ExpectedAgentPid
        if($current){& $assertProcess $current;& $StopProcess $current}
        $deadline=(Get-Date).AddSeconds(20)
        do {
            & $Wait 250
            $current=& $GetProcessIdentity $ExpectedAgentPid
            if($current){& $assertProcess $current}
        } while($current -and (Get-Date) -lt $deadline)
        if($current){throw 'Existing Launch Agent did not exit; install was not attempted.'}
        $finalTask=& $GetTaskEvidence; & $assertTask $finalTask
        if($finalTask.XmlSha256 -cne $initialTaskXmlSha256){throw 'Scheduled-task definition changed during installer stop.'}
        if($finalTask.State -ceq 'Running'){throw 'Scheduled task remains running after agent exit; install was not attempted.'}
    } catch {
        $failure=$_
        if($taskStopAttempted -and $initialTaskState -ceq 'Running'){
            $remaining=& $GetProcessIdentity $ExpectedAgentPid
            if($remaining){
                try{& $assertProcess $remaining}catch{throw 'Launch Agent process identity is ambiguous after failed stop; scheduled task remains stopped for manual review.'}
                throw 'Launch Agent process remains active after failed stop; scheduled task remains stopped for manual review.'
            }
            $restoreTask=& $GetTaskEvidence; & $assertTask $restoreTask
            if($restoreTask.XmlSha256 -cne $initialTaskXmlSha256){throw 'Scheduled task changed during failed stop; it was left untouched for manual review.'}
            if($restoreTask.State -cne 'Running'){& $StartTask $TaskPath $TaskName}
        }
        throw $failure
    }
}
