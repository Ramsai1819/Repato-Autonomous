Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Contract = [ordered]@{
    SchemaVersion = 1
    Account = 'RAMSAI\RepatoQA'
    Sid = 'S-1-5-21-1031246752-3872016183-2454652381-1015'
    InstallRoot = 'C:\Program Files\Repato\QaLaunchAgent'
    Executable = 'C:\Program Files\Repato\QaLaunchAgent\Repato.QaLaunchAgent.exe'
    TaskPath = '\Repato\'
    TaskName = 'Repato QA Launch Agent'
    RuntimeFiles = @('Repato.QaLaunchAgent.exe','Repato.QaLaunchAgent.dll','Repato.QaLaunchAgent.deps.json','Repato.QaLaunchAgent.runtimeconfig.json')
}
$script:PendingInstallRollbacks=@{}

function Get-RepatoQaLaunchAgentBootstrapContract { [pscustomobject]$script:Contract }

function Assert-Administrator {
    $p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Bootstrap requires an elevated administrator PowerShell.' }
}

function Assert-Identity([string]$Account,[string]$ExpectedSid) {
    if ($Account -cne $script:Contract.Account -or $ExpectedSid -cne $script:Contract.Sid) { throw 'The fixed RepatoQA account or SID was changed.' }
    $actual = ([Security.Principal.NTAccount]$Account).Translate([Security.Principal.SecurityIdentifier]).Value
    if ($actual -cne $ExpectedSid) { throw "RepatoQA SID mismatch. Expected $ExpectedSid; resolved $actual." }
}

function Resolve-RepatoAccountSid([string]$Account) {
    if([string]::IsNullOrWhiteSpace($Account)){return $null}
    try { ([Security.Principal.NTAccount]$Account).Translate([Security.Principal.SecurityIdentifier]).Value } catch { $null }
}

function Read-ValidatedManifest([string]$SourceRoot,[string]$ManifestPath,[string]$ManifestSha256) {
    $source = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
    $manifestFull = [IO.Path]::GetFullPath($ManifestPath)
    if (-not (Test-Path -LiteralPath $manifestFull -PathType Leaf)) { throw 'Launch-agent provenance manifest is missing.' }
    if ((Get-FileHash -LiteralPath $manifestFull -Algorithm SHA256).Hash -cne $ManifestSha256) { throw 'Launch-agent provenance manifest hash mismatch.' }
    $m = Get-Content -LiteralPath $manifestFull -Raw | ConvertFrom-Json
    if ($m.schemaVersion -ne 1 -or $m.product -cne 'Repato.QaLaunchAgent' -or $m.account -cne $script:Contract.Account -or $m.sid -cne $script:Contract.Sid) { throw 'Launch-agent provenance contract mismatch.' }
    $names = @($m.files | ForEach-Object name)
    if ($names.Count -ne $script:Contract.RuntimeFiles.Count -or @($script:Contract.RuntimeFiles | Where-Object { $_ -cnotin $names }).Count) { throw 'Launch-agent runtime set is partial or contains unexpected files.' }
    foreach ($entry in $m.files) {
        if ($entry.name -notmatch '^Repato\.QaLaunchAgent\.(exe|dll|deps\.json|runtimeconfig\.json)$' -or $entry.sha256 -notmatch '^[A-F0-9]{64}$') { throw 'Invalid launch-agent manifest entry.' }
        $path = Join-Path $source $entry.name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing runtime file: $($entry.name)" }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $entry.sha256) { throw "Source hash mismatch: $($entry.name)" }
    }
    $exeVersion = (Get-Item -LiteralPath (Join-Path $source 'Repato.QaLaunchAgent.exe')).VersionInfo.ProductVersion
    $dllVersion = (Get-Item -LiteralPath (Join-Path $source 'Repato.QaLaunchAgent.dll')).VersionInfo.ProductVersion
    if ($exeVersion -cne $dllVersion -or $exeVersion -cne $m.productVersion) { throw 'Executable/DLL runtime versions do not match the provenance manifest.' }
    [pscustomobject]@{ SourceRoot=$source; Manifest=$m; ManifestPath=$manifestFull; ManifestSha256=$ManifestSha256 }
}

function New-TaskSpec {
    [pscustomobject]@{ TaskPath=$script:Contract.TaskPath; TaskName=$script:Contract.TaskName; Principal=$script:Contract.Account; Sid=$script:Contract.Sid; LogonType='Interactive'; RunLevel='Limited'; TriggerType='Logon'; TriggerUser=$script:Contract.Account; Execute=$script:Contract.Executable; Arguments=''; WorkingDirectory=$script:Contract.InstallRoot; MultipleInstances='IgnoreNew'; RestartCount=3; RestartInterval='PT1M' }
}

function Get-TaskPropertyValue($Object,[string]$Name) {
    if($null -eq $Object){return $null}
    $property=$Object.PSObject.Properties[$Name]
    if($property){$property.Value}
}

function ConvertTo-TaskSpecEvidence {
    param([Parameter(Mandatory)]$Task,[scriptblock]$SidResolver)
    if(!$SidResolver){$SidResolver={param($account)Resolve-RepatoAccountSid $account}}
    $principal=Get-TaskPropertyValue (Get-TaskPropertyValue $Task 'Principal') 'UserId'
    $principalObject=Get-TaskPropertyValue $Task 'Principal'
    $triggerItems=@(Get-TaskPropertyValue $Task 'Triggers');$trigger=if($triggerItems.Count -eq 1){$triggerItems[0]}else{$null}
    $actionItems=@(Get-TaskPropertyValue $Task 'Actions');$action=if($actionItems.Count -eq 1){$actionItems[0]}else{$null}
    $settings=Get-TaskPropertyValue $Task 'Settings'
    $className=[string](Get-TaskPropertyValue (Get-TaskPropertyValue $trigger 'CimClass') 'CimClassName')
    [pscustomobject]@{
        TaskPath=Get-TaskPropertyValue $Task 'TaskPath';TaskName=Get-TaskPropertyValue $Task 'TaskName'
        Principal=$principal;PrincipalResolvedSid=if($principal){& $SidResolver $principal}else{$null}
        LogonType=[string](Get-TaskPropertyValue $principalObject 'LogonType');RunLevel=[string](Get-TaskPropertyValue $principalObject 'RunLevel')
        TriggerType=if($className -ceq 'MSFT_TaskLogonTrigger'){'Logon'}else{$className}
        TriggerUser=Get-TaskPropertyValue $trigger 'UserId';TriggerResolvedSid=if($trigger){$user=Get-TaskPropertyValue $trigger 'UserId';if($user){& $SidResolver $user}else{$null}}else{$null}
        Execute=Get-TaskPropertyValue $action 'Execute';Arguments=[string](Get-TaskPropertyValue $action 'Arguments');WorkingDirectory=Get-TaskPropertyValue $action 'WorkingDirectory'
        MultipleInstances=[string](Get-TaskPropertyValue $settings 'MultipleInstances');RestartCount=Get-TaskPropertyValue $settings 'RestartCount';RestartInterval=[string](Get-TaskPropertyValue $settings 'RestartInterval')
    }
}

function Get-TaskSpecComparison($Actual) {
    $expected=New-TaskSpec
    foreach($name in $expected.PSObject.Properties.Name) {
        $e=[string]$expected.$name
        $property=if($null -eq $Actual){$null}else{$Actual.PSObject.Properties[$name]}
        $a=if($property){[string]$property.Value}else{$null}
        if($name -eq 'Sid') {
            $principalSidProperty=if($Actual){$Actual.PSObject.Properties['PrincipalResolvedSid']}else{$null}
            $triggerSidProperty=if($Actual){$Actual.PSObject.Properties['TriggerResolvedSid']}else{$null}
            $principalSid=if($principalSidProperty){[string]$principalSidProperty.Value}else{$null}
            $triggerSid=if($triggerSidProperty){[string]$triggerSidProperty.Value}else{$null}
            [pscustomobject]@{Property=$name;Expected=$e;Actual=$a;NormalizedExpected=$e;NormalizedActual=[pscustomobject]@{Principal=$principalSid;Trigger=$triggerSid};Match=($principalSid -ceq $e -and $triggerSid -ceq $e)}
        } elseif($name -eq 'Principal') {
            $expectedSid=$expected.Sid; $actualSid=if($Actual -and $Actual.PSObject.Properties.Name -contains 'PrincipalResolvedSid'){$Actual.PrincipalResolvedSid}elseif($Actual){Resolve-RepatoAccountSid $a}else{$null}
            [pscustomobject]@{Property=$name;Expected=$e;Actual=$a;NormalizedExpected=$expectedSid;NormalizedActual=$actualSid;Match=($actualSid -cne $null -and $actualSid -ceq $expectedSid);ExpectedPrincipalDisplay=$e;ActualPrincipalDisplay=$a;ExpectedPrincipalSid=$expectedSid;ActualPrincipalResolvedSid=$actualSid}
        } elseif($name -eq 'TriggerUser') {
            $expectedSid=$expected.Sid; $actualSid=if($Actual -and $Actual.PSObject.Properties.Name -contains 'TriggerResolvedSid'){$Actual.TriggerResolvedSid}elseif($Actual){Resolve-RepatoAccountSid $a}else{$null}
            [pscustomobject]@{Property=$name;Expected=$e;Actual=$a;NormalizedExpected=$expectedSid;NormalizedActual=$actualSid;Match=($actualSid -cne $null -and $actualSid -ceq $expectedSid);ExpectedTriggerDisplay=$e;ActualTriggerDisplay=$a;ExpectedTriggerSid=$expectedSid;ActualTriggerResolvedSid=$actualSid}
        } else {
            [pscustomobject]@{Property=$name;Expected=$e;Actual=$a;NormalizedExpected=$e;NormalizedActual=$a;Match=($a -cne $null -and $a -ceq $e)}
        }
    }
}

function Test-TaskSpec($Actual) {
    -not @(Get-TaskSpecComparison $Actual | Where-Object { -not $_.Match }).Count
}

function Get-RepatoQaLaunchAgentDiagnosticRoot {
    $root=Join-Path $PSScriptRoot '..\QA\Reports\RepatoQaLaunchAgentBootstrap'
    [IO.Path]::GetFullPath($root)
}

function Write-RepatoQaLaunchAgentDiagnostics($Snapshot,$Comparison,$RuntimeIntegrity,$ErrorMessage) {
    $root=Get-RepatoQaLaunchAgentDiagnosticRoot
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $path=Join-Path $root ('failure-'+(Get-Date -Format 'yyyyMMdd-HHmmssfff')+'-'+[guid]::NewGuid().ToString('N')+'.json')
    [pscustomobject]@{SchemaVersion=1;CapturedAtUtc=[DateTime]::UtcNow.ToString('o');TaskSnapshot=$Snapshot;ContractComparison=@($Comparison);RuntimeIntegrity=$RuntimeIntegrity;Error=$ErrorMessage} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    $path
}

function Get-RepatoQaLaunchAgentRuntimeIntegrity([string]$TargetRoot,$Manifest) {
    foreach($entry in $Manifest.files) {
        $path=Join-Path $TargetRoot $entry.name
        $actual=if(Test-Path -LiteralPath $path -PathType Leaf){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}else{$null}
        [pscustomobject]@{File=$entry.name;ExpectedSha256=$entry.sha256;ActualSha256=$actual;Match=($actual -cne $null -and $actual -ceq $entry.sha256)}
    }
}

function Read-ValidatedRepatoQaLaunchAgentSnapshot([string]$SnapshotRoot,[string]$ManifestSha256,[string]$ExpectedRoot,[string]$ExpectedManifestSha256) {
    $root=[IO.Path]::GetFullPath($SnapshotRoot).TrimEnd('\')
    if($root -ine [IO.Path]::GetFullPath($ExpectedRoot).TrimEnd('\') -or $ManifestSha256 -ine $ExpectedManifestSha256){throw 'Recovery snapshot identity differs from the approved v1.0.10 handoff.'}
    $manifestPath=Join-Path $root 'Repato.QaLaunchAgent.snapshot.json'
    if(!(Test-Path -LiteralPath $manifestPath -PathType Leaf) -or (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ine $ExpectedManifestSha256){throw 'Recovery snapshot manifest hash validation failed.'}
    $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
    if($manifest.schemaVersion -ne 1 -or $manifest.kind -cne 'Repato.QaLaunchAgent.InstalledRuntimeSnapshot' -or $manifest.product -cne 'Repato.QaLaunchAgent' -or $manifest.productVersion -cne '1.0.10+50d5d752d9a8' -or $manifest.installRoot -ine $script:Contract.InstallRoot -or $manifest.observedByAccount -ine $script:Contract.Account -or $manifest.observedBySid -cne $script:Contract.Sid){throw 'Recovery snapshot metadata does not match the fixed RepatoQA runtime contract.'}
    $files=@($manifest.files);$names=@($files|ForEach-Object name)
    if($files.Count -ne $script:Contract.RuntimeFiles.Count -or $names.Count -ne (@($names|Select-Object -Unique)).Count -or @($script:Contract.RuntimeFiles|Where-Object{$_ -cnotin $names}).Count){throw 'Recovery snapshot runtime file set is incomplete or ambiguous.'}
    foreach($entry in $files){
        if($entry.name -notin $script:Contract.RuntimeFiles -or $entry.sha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Recovery snapshot contains an invalid runtime entry.'}
        $path=Join-Path $root $entry.name
        if(!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $entry.sha256){throw "Recovery snapshot file hash validation failed: $($entry.name)"}
    }
    [pscustomobject]@{Root=$root;ManifestPath=$manifestPath;ManifestSha256=$ExpectedManifestSha256;Manifest=$manifest}
}

function Test-RepatoQaLaunchAgentFileSet([string]$Root) {
    if(!(Test-Path -LiteralPath $Root -PathType Container)){return $false}
    $children=@(Get-ChildItem -LiteralPath $Root -Force)
    $children.Count -eq $script:Contract.RuntimeFiles.Count -and @($children|Where-Object{$_.PSIsContainer -or $_.Name -cnotin $script:Contract.RuntimeFiles}).Count -eq 0 -and @($script:Contract.RuntimeFiles|Where-Object{!(Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf)}).Count -eq 0
}

function Test-RepatoQaLaunchAgentSnapshotFiles([string]$Root,$Manifest) {
    $integrity=Get-RepatoQaLaunchAgentRuntimeIntegrity $Root $Manifest
    @($integrity).Count -eq $script:Contract.RuntimeFiles.Count -and @($integrity|Where-Object{!$_.Match}).Count -eq 0
}

function Invoke-RepatoQaLaunchAgentSnapshotRecoveryCore {
    param(
        [Parameter(Mandatory)][string]$SnapshotRoot,[Parameter(Mandatory)][string]$ManifestSha256,
        [Parameter(Mandatory)][string]$ExpectedSnapshotRoot,[Parameter(Mandatory)][string]$ExpectedManifestSha256,
        [Parameter(Mandatory)][string]$TargetRoot,[Parameter(Mandatory)]$Context,
        [switch]$AllowTestRoot,[scriptblock]$InterruptionHook
    )
    $snapshot=Read-ValidatedRepatoQaLaunchAgentSnapshot $SnapshotRoot $ManifestSha256 $ExpectedSnapshotRoot $ExpectedManifestSha256
    & $Context.AssertAdministrator
    & $Context.ResolveIdentity $script:Contract.Account $script:Contract.Sid
    $target=[IO.Path]::GetFullPath($TargetRoot).TrimEnd('\')
    if(!$AllowTestRoot -and $target -cne $script:Contract.InstallRoot){throw 'Snapshot recovery is restricted to the fixed protected install root.'}
    if($target -cne [IO.Path]::GetFullPath($script:Contract.InstallRoot).TrimEnd('\') -and !$AllowTestRoot){throw 'Snapshot recovery target identity mismatch.'}
    $parent=Split-Path $target -Parent
    $transactions=@(Get-ChildItem -LiteralPath $parent -Force -Directory|Where-Object{$_.Name -match '^\.QaLaunchAgent\.snapshot-recovery\.[A-Fa-f0-9]{32}$'})
    if($transactions.Count -gt 1){throw 'Multiple snapshot-recovery transactions exist; refusing ambiguous recovery.'}
    if(!(Test-Path -LiteralPath $target -PathType Container) -and !$transactions.Count){throw 'Installed runtime root is missing; refusing ambiguous recovery.'}
    $task=& $Context.GetTask
    if(!$task -or !(Test-TaskSpec $task)){throw 'Scheduled-task identity or interactive logon contract is invalid; refusing recovery.'}
    if([string](& $Context.GetTaskState) -cne 'Ready'){throw 'Scheduled task is not in the safe Ready state; refusing recovery.'}
    if(@(& $Context.GetProcesses).Count){throw 'Launch Agent is running; refusing snapshot recovery.'}

    if(!$transactions.Count -and (Test-RepatoQaLaunchAgentSnapshotFiles $target $snapshot.Manifest)){return [pscustomobject]@{Recovered=$true;AlreadyRestored=$true;ProductVersion=$snapshot.Manifest.productVersion;SnapshotManifestSha256=$snapshot.ManifestSha256;TaskChanged=$false;AclPolicyChanged=$false;RetainedEvidence=$true}}

    if(!$transactions.Count){
        if(!(Test-RepatoQaLaunchAgentFileSet $target)){throw 'Installed runtime file set is incomplete or contains unrelated files; refusing recovery.'}
        $transactionRoot=Join-Path $parent ('.QaLaunchAgent.snapshot-recovery.'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $transactionRoot|Out-Null
        & $Context.CopySecurity $target $transactionRoot
        $stage=Join-Path $transactionRoot 'stage';$backup=Join-Path $transactionRoot 'previous';$journalPath=Join-Path $transactionRoot 'recovery.json'
        New-Item -ItemType Directory -Path $stage|Out-Null
        & $Context.CopySecurity $target $stage
        $priorFiles=@()
        foreach($entry in $snapshot.Manifest.files){
            $installedFile=Join-Path $target $entry.name
            $priorFiles+=[pscustomobject]@{name=$entry.name;sha256=(Get-FileHash -LiteralPath $installedFile -Algorithm SHA256).Hash}
            Copy-Item -LiteralPath (Join-Path $snapshot.Root $entry.name) -Destination (Join-Path $stage $entry.name)
            & $Context.CopySecurity $installedFile (Join-Path $stage $entry.name)
        }
        if(!(Test-RepatoQaLaunchAgentSnapshotFiles $stage $snapshot.Manifest)){throw 'Staged recovery runtime failed snapshot hash verification.'}
        $journal=[pscustomobject]@{schemaVersion=1;targetRoot=$target;snapshotRoot=$snapshot.Root;snapshotManifestSha256=$snapshot.ManifestSha256;stageRoot=$stage;backupRoot=$backup;priorFiles=$priorFiles;createdUtc=[DateTime]::UtcNow.ToString('o')}
        $journal|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $journalPath -Encoding UTF8
        if($InterruptionHook){& $InterruptionHook 'Prepared'}
        $transaction=Get-Item -LiteralPath $transactionRoot
    } else {
        $transaction=$transactions[0];$transactionRoot=$transaction.FullName;$journalPath=Join-Path $transactionRoot 'recovery.json'
        if(!(Test-Path -LiteralPath $journalPath -PathType Leaf)){throw 'An incomplete snapshot-recovery directory has no journal; refusing ambiguous recovery.'}
        $journal=Get-Content -LiteralPath $journalPath -Raw|ConvertFrom-Json
        $stage=Join-Path $transactionRoot 'stage';$backup=Join-Path $transactionRoot 'previous'
        $priorNames=@($journal.priorFiles|ForEach-Object name)
        if($journal.schemaVersion -ne 1 -or [IO.Path]::GetFullPath($journal.targetRoot).TrimEnd('\') -cne $target -or [IO.Path]::GetFullPath($journal.snapshotRoot).TrimEnd('\') -ine $snapshot.Root -or $journal.snapshotManifestSha256 -ine $snapshot.ManifestSha256 -or [IO.Path]::GetFullPath($journal.stageRoot) -ine [IO.Path]::GetFullPath($stage) -or [IO.Path]::GetFullPath($journal.backupRoot) -ine [IO.Path]::GetFullPath($backup) -or $priorNames.Count -ne $script:Contract.RuntimeFiles.Count -or $priorNames.Count -ne (@($priorNames|Select-Object -Unique)).Count -or @($script:Contract.RuntimeFiles|Where-Object{$_ -cnotin $priorNames}).Count -or @($journal.priorFiles|Where-Object{$_.sha256 -notmatch '^[A-Fa-f0-9]{64}'}).Count){throw 'Snapshot-recovery journal identity is invalid; refusing recovery.'}
        if(Test-Path -LiteralPath $backup -PathType Container){if(!(Test-RepatoQaLaunchAgentFileSet $backup) -or !(Test-RepatoQaLaunchAgentSnapshotFiles $backup ([pscustomobject]@{files=@($journal.priorFiles)}))){throw 'Retained pre-recovery runtime failed integrity validation; refusing recovery.'}}
        if(Test-Path -LiteralPath $stage -PathType Container){if(!(Test-RepatoQaLaunchAgentFileSet $stage) -or !(Test-RepatoQaLaunchAgentSnapshotFiles $stage $snapshot.Manifest)){throw 'Interrupted recovery stage failed snapshot validation; refusing recovery.'}}
    }

    $hasStage=Test-Path -LiteralPath $stage -PathType Container
    $hasBackup=Test-Path -LiteralPath $backup -PathType Container
    $hasTarget=Test-Path -LiteralPath $target -PathType Container
    if($hasTarget -and (Test-RepatoQaLaunchAgentSnapshotFiles $target $snapshot.Manifest)){
        if($hasStage -or !$hasBackup){throw 'Snapshot runtime is present with an ambiguous recovery transaction; refusing cleanup.'}
        return [pscustomobject]@{Recovered=$true;AlreadyRestored=$true;ProductVersion=$snapshot.Manifest.productVersion;SnapshotManifestSha256=$snapshot.ManifestSha256;TaskChanged=$false;AclPolicyChanged=$false;RetainedEvidence=$true;RecoveryDirectory=$transactionRoot}
    }
    if($hasTarget -and $hasStage -and !$hasBackup){
        $prior=@($journal.priorFiles)
        if(!(Test-RepatoQaLaunchAgentFileSet $target) -or !(Test-RepatoQaLaunchAgentSnapshotFiles $target ([pscustomobject]@{files=$prior}))){throw 'Installed runtime changed after recovery staging; refusing to move it.'}
        if([string](& $Context.GetTaskState) -cne 'Ready' -or @(& $Context.GetProcesses).Count){throw 'Launch Agent or scheduled task changed before recovery; refusing to move the installed runtime.'}
        Move-Item -LiteralPath $target -Destination $backup
        if($InterruptionHook){& $InterruptionHook 'PreviousMoved'}
        $hasTarget=$false;$hasBackup=$true
    }
    if(!$hasTarget -and $hasStage -and $hasBackup){
        if([string](& $Context.GetTaskState) -cne 'Ready' -or @(& $Context.GetProcesses).Count){throw 'Launch Agent or scheduled task changed before recovery; refusing to install the snapshot runtime.'}
        Move-Item -LiteralPath $stage -Destination $target
        if($InterruptionHook){& $InterruptionHook 'SnapshotMoved'}
        $hasTarget=$true;$hasStage=$false
    }
    if(!$hasTarget -or !(Test-RepatoQaLaunchAgentSnapshotFiles $target $snapshot.Manifest) -or !$hasBackup){throw 'Snapshot recovery did not reach a verified, recoverable state; preserve the transaction directory for administrator review.'}
    [pscustomobject]@{Recovered=$true;AlreadyRestored=$false;ProductVersion=$snapshot.Manifest.productVersion;SnapshotManifestSha256=$snapshot.ManifestSha256;TaskChanged=$false;AclPolicyChanged=$false;RetainedEvidence=$true;RecoveryDirectory=$transactionRoot;PreviousRuntime=$backup}
}

function New-RealBootstrapContext {
    [pscustomobject]@{
        IsAdministrator = { Assert-Administrator }
        ResolveIdentity = { param($a,$s) Assert-Identity $a $s }
        PrepareAcl = { param($path)
            $acl=New-Object Security.AccessControl.DirectorySecurity
            $acl.SetAccessRuleProtection($true,$false)
            foreach($r in @(
                (New-Object Security.AccessControl.FileSystemAccessRule('SYSTEM','FullControl','ContainerInherit,ObjectInherit','None','Allow')),
                (New-Object Security.AccessControl.FileSystemAccessRule('Administrators','FullControl','ContainerInherit,ObjectInherit','None','Allow')),
                (New-Object Security.AccessControl.FileSystemAccessRule($script:Contract.Account,'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')))){$acl.AddAccessRule($r)|Out-Null}
            Set-Acl -LiteralPath $path -AclObject $acl
        }
        GetTask = {
            $t=Get-ScheduledTask -TaskPath $script:Contract.TaskPath -TaskName $script:Contract.TaskName -ErrorAction SilentlyContinue
            if(!$t){return $null}
            ConvertTo-TaskSpecEvidence -Task $t
        }
        GetTaskState = { $t=Get-ScheduledTask -TaskPath $script:Contract.TaskPath -TaskName $script:Contract.TaskName -ErrorAction SilentlyContinue; if($t){$t.State.ToString()}else{'Absent'} }
        StopTask = { Stop-ScheduledTask -TaskPath $script:Contract.TaskPath -TaskName $script:Contract.TaskName -ErrorAction SilentlyContinue }
        StartTask = { Start-ScheduledTask -TaskPath $script:Contract.TaskPath -TaskName $script:Contract.TaskName -ErrorAction Stop }
        GetProcesses = { @(Get-CimInstance -ClassName Win32_Process -Filter "Name='Repato.QaLaunchAgent.exe'" -ErrorAction Stop) }
        GetProductVersion = { param($path) (Get-Item -LiteralPath $path -ErrorAction Stop).VersionInfo.ProductVersion }
        StopProcesses = { param($processes)
            foreach($item in @($processes)){
                if($item.ExecutablePath -ine $script:Contract.Executable -or !$item.ProcessId){throw 'A same-name process has an unexpected executable identity; refusing to stop it.'}
                $owner=Invoke-CimMethod -InputObject $item -MethodName GetOwner -ErrorAction Stop
                if($owner.ReturnValue -ne 0){throw 'Launch Agent process owner could not be verified.'}
                $ownerSid=([Security.Principal.NTAccount]($owner.Domain+'\'+$owner.User)).Translate([Security.Principal.SecurityIdentifier]).Value
                if($ownerSid -cne $script:Contract.Sid){throw 'Launch Agent process owner is not the fixed RepatoQA identity.'}
                $current=Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$($item.ProcessId)" -ErrorAction Stop
                if(!$current -or $current.ExecutablePath -ine $script:Contract.Executable -or $current.CreationDate -ne $item.CreationDate){throw 'Launch Agent process identity changed before stop.'}
                $process=Get-Process -Id ([int]$item.ProcessId) -ErrorAction Stop
                if($process.Path -ine $script:Contract.Executable){throw 'Launch Agent process path changed before stop.'}
                Stop-Process -InputObject $process -Force -Confirm:$false -ErrorAction Stop
                $deadline=(Get-Date).AddSeconds(20)
                while((Get-Process -Id ([int]$item.ProcessId) -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 100}
                if(Get-Process -Id ([int]$item.ProcessId) -ErrorAction SilentlyContinue){throw 'Verified Launch Agent process did not exit after stop.'}
            }
        }
        GetTaskSnapshot = {
            $t=Get-ScheduledTask -TaskPath $script:Contract.TaskPath -TaskName $script:Contract.TaskName -ErrorAction SilentlyContinue
            if(!$t){return $null}; $a=@($t.Actions)[0]; $g=@($t.Triggers)[0]
            $v=& $Context.GetTask
            [pscustomobject]@{TaskPath=$t.TaskPath;TaskName=$t.TaskName;State=$t.State;PrincipalUserId=$t.Principal.UserId;PrincipalLogonType=[string]$t.Principal.LogonType;PrincipalRunLevel=[string]$t.Principal.RunLevel;TriggerType=$g.CimClass.CimClassName;TriggerUserId=$g.UserId;ActionExecute=$a.Execute;ActionArguments=[string]$a.Arguments;ActionWorkingDirectory=$a.WorkingDirectory;MultipleInstances=[string]$t.Settings.MultipleInstances;RestartCount=$t.Settings.RestartCount;RestartInterval=[string]$t.Settings.RestartInterval;ExpectedPrincipalDisplay=$script:Contract.Account;ActualPrincipalDisplay=$t.Principal.UserId;ExpectedPrincipalSid=$script:Contract.Sid;ActualPrincipalResolvedSid=$v.PrincipalResolvedSid;ExpectedTriggerDisplay=$script:Contract.Account;ActualTriggerDisplay=$g.UserId;ExpectedTriggerSid=$script:Contract.Sid;ActualTriggerResolvedSid=$v.TriggerResolvedSid;AccountDisplayCanonicalizationObserved=(($t.Principal.UserId -cne $script:Contract.Account -or $g.UserId -cne $script:Contract.Account) -and $v.PrincipalResolvedSid -ceq $script:Contract.Sid -and $v.TriggerResolvedSid -ceq $script:Contract.Sid);ValidatorRepresentation=$v}
        }
        ExportTask = { param($task) if($task){ Export-ScheduledTask -TaskPath $script:Contract.TaskPath -TaskName $script:Contract.TaskName } }
        SetTask = { param($spec)
            $action=New-ScheduledTaskAction -Execute $spec.Execute -WorkingDirectory $spec.WorkingDirectory
            $trigger=New-ScheduledTaskTrigger -AtLogOn -User $spec.Principal
            $principal=New-ScheduledTaskPrincipal -UserId $spec.Principal -LogonType Interactive -RunLevel Limited
            $settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
            Register-ScheduledTask -TaskPath $spec.TaskPath -TaskName $spec.TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        }
        RestoreTask = { param($xml) if($xml){Register-ScheduledTask -TaskPath $script:Contract.TaskPath -TaskName $script:Contract.TaskName -Xml $xml -Force|Out-Null}else{Unregister-ScheduledTask -TaskPath $script:Contract.TaskPath -TaskName $script:Contract.TaskName -Confirm:$false -ErrorAction SilentlyContinue} }
        RemoveTask = { Unregister-ScheduledTask -TaskPath $script:Contract.TaskPath -TaskName $script:Contract.TaskName -Confirm:$false -ErrorAction SilentlyContinue }
    }
}

function Get-InstallJournalPayload($Journal) {
    [ordered]@{schemaVersion=[int]$Journal.schemaVersion;transactionId=[string]$Journal.transactionId;generation=[long]$Journal.generation;state=[string]$Journal.state;targetRoot=[string]$Journal.targetRoot;journalPath=[string]$Journal.journalPath;stageRoot=[string]$Journal.stageRoot;backupRoot=[string]$Journal.backupRoot;failedRoot=[string]$Journal.failedRoot;hadTarget=[bool]$Journal.hadTarget;priorVersion=[string]$Journal.priorVersion;priorFiles=@($Journal.priorFiles|ForEach-Object{[ordered]@{name=[string]$_.name;sha256=[string]$_.sha256}});priorTaskXml=[string]$Journal.priorTaskXml;priorTaskSha256=[string]$Journal.priorTaskSha256;priorTaskState=[string]$Journal.priorTaskState;taskPresent=[bool]$Journal.taskPresent;requestId=[string]$Journal.requestId;taskId=[string]$Journal.taskId;candidateVersion=[string]$Journal.candidateVersion;candidateManifestSha256=[string]$Journal.candidateManifestSha256;candidateFiles=@($Journal.candidateFiles|ForEach-Object{[ordered]@{name=[string]$_.name;sha256=[string]$_.sha256}})}
}

function Get-InstallJournalHash($Journal) {
    $json=ConvertTo-Json -InputObject (Get-InstallJournalPayload $Journal) -Depth 12 -Compress
    $json=$json.Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026').Replace("'","\u0027")
    $sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}finally{$sha.Dispose()}
}

function Write-InstallJournal($Journal) {
    $tmp=$Journal.journalPath+'.'+$Journal.transactionId+'.'+$Journal.generation+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    $Journal.journalSha256=Get-InstallJournalHash $Journal
    $json=ConvertTo-Json -InputObject ([ordered]@{schemaVersion=$Journal.schemaVersion;transactionId=$Journal.transactionId;generation=$Journal.generation;state=$Journal.state;targetRoot=$Journal.targetRoot;journalPath=$Journal.journalPath;stageRoot=$Journal.stageRoot;backupRoot=$Journal.backupRoot;failedRoot=$Journal.failedRoot;hadTarget=$Journal.hadTarget;priorVersion=$Journal.priorVersion;priorFiles=$Journal.priorFiles;priorTaskXml=$Journal.priorTaskXml;priorTaskSha256=$Journal.priorTaskSha256;priorTaskState=$Journal.priorTaskState;taskPresent=$Journal.taskPresent;requestId=$Journal.requestId;taskId=$Journal.taskId;candidateVersion=$Journal.candidateVersion;candidateManifestSha256=$Journal.candidateManifestSha256;candidateFiles=$Journal.candidateFiles;journalSha256=$Journal.journalSha256}) -Depth 12
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes($json)
    $stream=[IO.FileStream]::new($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    if(Test-Path -LiteralPath $Journal.journalPath){$previous=$Journal.journalPath+'.'+$Journal.transactionId+'.'+([long]$Journal.generation-1)+'.previous';if(Test-Path -LiteralPath $previous){throw 'Install-journal history destination already exists.'};[IO.File]::Replace($tmp,$Journal.journalPath,$previous,$true)}else{[IO.File]::Move($tmp,$Journal.journalPath)}
    $Journal
}

function Assert-InstallJournalUniqueProperties([string]$Json) {
    $depth=0;$inString=$false;$escaped=$false;$start=-1;$seenByDepth=@{}
    for($i=0;$i -lt $Json.Length;$i++){
        $ch=$Json[$i]
        if($inString){if($escaped){$escaped=$false}elseif($ch -eq '\'){$escaped=$true}elseif($ch -eq '"'){$inString=$false;$j=$i+1;while($j -lt $Json.Length -and [char]::IsWhiteSpace($Json[$j])){$j++};if($j -lt $Json.Length -and $Json[$j] -eq ':'){$key=$Json.Substring($start+1,$i-$start-1);if($depth -lt 1 -or $key.Contains('\') -or $seenByDepth[$depth].ContainsKey($key)){throw 'Install journal has duplicate or escaped property names.'};$seenByDepth[$depth][$key]=$true}};continue}
        if($ch -eq '"'){$inString=$true;$start=$i;continue};if($ch -eq '{'){$depth++;$seenByDepth[$depth]=@{}}elseif($ch -eq '}'){$seenByDepth.Remove($depth);$depth--}
    }
    if($inString -or $depth -ne 0){throw 'Install journal JSON is incomplete.'}
}

function Read-InstallJournal([string]$JournalPath,[string]$TargetRoot,[switch]$AllowTestRoot) {
    $target=[IO.Path]::GetFullPath($TargetRoot).TrimEnd('\\');$expectedTarget=[IO.Path]::GetFullPath($script:Contract.InstallRoot).TrimEnd('\\')
    if(!$AllowTestRoot -and $target -cne $expectedTarget){throw 'Install-journal target is not the fixed protected root.'}
    $expectedPath=Join-Path (Split-Path $target -Parent) '.QaLaunchAgent.install-journal.json'
    if([IO.Path]::GetFullPath($JournalPath) -ine [IO.Path]::GetFullPath($expectedPath)){throw 'Install-journal path is not the fixed sibling of the target.'}
    if(!(Test-Path -LiteralPath $JournalPath -PathType Leaf)){throw 'Install journal is missing; preserve all evidence for manual review.'}
    $raw=Get-Content -LiteralPath $JournalPath -Raw;Assert-InstallJournalUniqueProperties $raw
    $j=$raw|ConvertFrom-Json
    $expectedNames=@('schemaVersion','transactionId','generation','state','targetRoot','journalPath','stageRoot','backupRoot','failedRoot','hadTarget','priorVersion','priorFiles','priorTaskXml','priorTaskSha256','priorTaskState','taskPresent','requestId','taskId','candidateVersion','candidateManifestSha256','candidateFiles','journalSha256')
    if(@($j.PSObject.Properties.Name|Sort-Object) -join '|' -cne (@($expectedNames|Sort-Object) -join '|')){throw 'Install journal schema is incomplete or contains unknown fields.'}
    $tx=[guid]::Empty;if($j.schemaVersion -ne 1 -or ![guid]::TryParseExact([string]$j.transactionId,'N',[ref]$tx) -or $tx -eq [guid]::Empty -or $j.generation -lt 1 -or $j.state -notin @('Prepared','CandidateStaged','ServiceStopPending','ServiceStopped','BackupMovePending','BackupVerified','ReplacementPending','FilesReplaced','TaskUpdatePending','TaskUpdated','HealthVerificationPending','CommitPending','Committed','RollbackPending','RolledBack')){throw 'Install journal version, generation, or state is invalid.'}
    if([IO.Path]::GetFullPath($j.targetRoot).TrimEnd('\\') -ine $target -or [IO.Path]::GetFullPath($j.journalPath) -ine [IO.Path]::GetFullPath($JournalPath)){throw 'Install journal target identity mismatch.'}
    $parent=Split-Path $target -Parent;$expectedStage=Join-Path $parent ('.QaLaunchAgent.stage.'+$j.transactionId);$expectedBackup=Join-Path $parent ('.QaLaunchAgent.backup.'+$j.transactionId);$expectedFailed=Join-Path $parent ('.QaLaunchAgent.failed.'+$j.transactionId)
    foreach($pair in @(@($j.stageRoot,$expectedStage),@($j.backupRoot,$expectedBackup),@($j.failedRoot,$expectedFailed))){if([IO.Path]::GetFullPath($pair[0]) -ine [IO.Path]::GetFullPath($pair[1])){throw 'Install journal contains an unsafe sibling path.'}}
    foreach($set in @(@($j.priorFiles),@($j.candidateFiles))){$names=@($set|ForEach-Object name);if($names.Count -ne $script:Contract.RuntimeFiles.Count -or $names.Count -ne @($names|Select-Object -Unique).Count -or @($script:Contract.RuntimeFiles|Where-Object{$_ -cnotin $names}).Count -or @($set|Where-Object{$_.sha256 -notmatch '^[A-Fa-f0-9]{64}'}).Count){throw 'Install journal file inventory is incomplete or invalid.'}}
    if(!$j.hadTarget -and @($j.priorFiles).Count -or $j.hadTarget -and @($j.priorFiles).Count -ne $script:Contract.RuntimeFiles.Count){throw 'Install journal prior runtime presence does not match its hash inventory.'}
    if([string]::IsNullOrWhiteSpace([string]$j.priorVersion) -or (!$AllowTestRoot -and $j.priorVersion -notin @('1.0.17+4b0066247088','1.0.18+4b0066247088','1.0.19+05933ab8b587','1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e','1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f','1.0.22+6119aceaab0a34c3e0323089a29f1cefb2c14aaa'))){throw 'Install journal prior release identity is invalid.'}
    if($j.taskPresent -and (!$j.priorTaskXml -or $j.priorTaskSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-InstallJournalTextHash ([string]$j.priorTaskXml)) -ine $j.priorTaskSha256 -or $j.priorTaskState -notin @('Ready','Running','Disabled'))){throw 'Install journal prior scheduled-task evidence is invalid.'}
    if(!$j.taskPresent -and ($j.priorTaskXml -or $j.priorTaskSha256)){throw 'Install journal has unexpected prior task evidence.'}
    if($j.requestId -notin @('9953e14c15524fe09440d1c7d7353950','c11b311638a54bfc9ebdd1803671ec40') -or $j.taskId -cne 'task-bf61fe7f22d74df7a92599681da5919e' -or !$j.taskPresent){throw 'Install journal request/task identity or prior task presence mismatch.'}
    if($j.candidateManifestSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
       $j.candidateVersion -notmatch '^(1\.0\.18\+4b0066247088|1\.0\.19\+[A-Fa-f0-9]{12,40}|1\.0\.20\+[A-Fa-f0-9]{12,40}|1\.0\.21\+[A-Fa-f0-9]{12,40}|1\.0\.22\+[A-Fa-f0-9]{12,40}|1\.0\.23\+[A-Fa-f0-9]{12,40})$'){throw 'Install journal candidate identity is invalid.'}
    if($j.candidateVersion -match '^1\.0\.22\+' -and ($j.priorVersion -cne '1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f' -or $j.requestId -cne 'c11b311638a54bfc9ebdd1803671ec40')){throw 'Recovery compatibility journal requires the exact 1.0.21 prior release and completed preparation request.'}
    Assert-CpvRecoveredNativeJournalTransition $j.candidateVersion $j.priorVersion $j.requestId
    if((Get-InstallJournalHash $j) -ine $j.journalSha256){throw 'Install journal integrity hash mismatch; preserve all evidence for manual review.'}
    $j
}

function Get-InstallJournalTextHash([string]$Value) { $sha=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value)))).Replace('-','')}finally{$sha.Dispose()} }

function Assert-CpvRecoveredNativeJournalTransition([string]$CandidateVersion,[string]$PriorVersion,[string]$RequestId) {
    if(($CandidateVersion -match '^1\.0\.23\+' -or $PriorVersion -ceq '1.0.22+6119aceaab0a34c3e0323089a29f1cefb2c14aaa') -and ($CandidateVersion -cnotmatch '^1\.0\.23\+[A-Fa-f0-9]{12,40}$' -or
        $PriorVersion -cne '1.0.22+6119aceaab0a34c3e0323089a29f1cefb2c14aaa' -or
        $RequestId -cne 'c11b311638a54bfc9ebdd1803671ec40')){throw 'Recovered-native journal requires exact 1.0.22 prior release and recovered preparation identity.'}
}

function Set-InstallJournalState($Journal,[string]$State) {
    $allowed=@{Prepared=@('CandidateStaged','RollbackPending');CandidateStaged=@('ServiceStopPending','RollbackPending');ServiceStopPending=@('ServiceStopped','RollbackPending');ServiceStopped=@('BackupMovePending','RollbackPending');BackupMovePending=@('BackupVerified','RollbackPending');BackupVerified=@('ReplacementPending','RollbackPending');ReplacementPending=@('FilesReplaced','RollbackPending');FilesReplaced=@('TaskUpdatePending','RollbackPending');TaskUpdatePending=@('TaskUpdated','RollbackPending');TaskUpdated=@('HealthVerificationPending','RollbackPending');HealthVerificationPending=@('CommitPending','RollbackPending');CommitPending=@('Committed','RollbackPending');RollbackPending=@('RolledBack');Committed=@();RolledBack=@()}
    if($State -notin @($allowed[[string]$Journal.state])){throw "Invalid install-journal transition: $($Journal.state) -> $State"}
    $Journal.generation=[long]$Journal.generation+1;$Journal.state=$State;Write-InstallJournal $Journal
}

function Test-InstallJournalFileSet([string]$Root,$ExpectedFiles) {
    if(!(Test-Path -LiteralPath $Root -PathType Container)){return $false}
    $directory=Get-Item -LiteralPath $Root -Force;if(($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
    $items=@(Get-ChildItem -LiteralPath $Root -Force);if($items.Count -ne $script:Contract.RuntimeFiles.Count -or @($items|Where-Object{$_.PSIsContainer -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $_.Name -cnotin $script:Contract.RuntimeFiles}).Count){return $false}
    $integrity=Get-RepatoQaLaunchAgentRuntimeIntegrity $Root ([pscustomobject]@{files=$ExpectedFiles});@($integrity|Where-Object{!$_.Match}).Count -eq 0
}

function New-InstallJournalCore($Validated,$Context,[string]$TargetRoot,$JournalIdentity,[switch]$AllowTestRoot) {
    & $Context.IsAdministrator;& $Context.ResolveIdentity $script:Contract.Account $script:Contract.Sid
    $target=[IO.Path]::GetFullPath($TargetRoot).TrimEnd('\\');if(!$AllowTestRoot -and $target -cne [IO.Path]::GetFullPath($script:Contract.InstallRoot).TrimEnd('\\')){throw 'Install-journal target must be the fixed protected install root.'}
    if(!$JournalIdentity -or $JournalIdentity.RequestId -notin @('9953e14c15524fe09440d1c7d7353950','c11b311638a54bfc9ebdd1803671ec40') -or $JournalIdentity.TaskId -cne 'task-bf61fe7f22d74df7a92599681da5919e'){throw 'Durable CPV journal identity is not the fixed approved request.'}
    if($Validated.Manifest.productVersion -match '^1\.0\.22\+' -and $JournalIdentity.RequestId -cne 'c11b311638a54bfc9ebdd1803671ec40'){throw 'Recovery compatibility journal requires the completed preparation request.'}
    if($Validated.Manifest.productVersion -match '^1\.0\.23\+' -and
        (!$JournalIdentity.PSObject.Properties['RecoveredNativeContinuation'] -or $JournalIdentity.RecoveredNativeContinuation -ne $true)){
        throw 'Recovered-native journal requires the explicit guarded continuation transition.'
    }
    $parent=Split-Path $target -Parent;New-Item -ItemType Directory -Path $parent -Force|Out-Null;$path=Join-Path $parent '.QaLaunchAgent.install-journal.json';$lockPath=$path+'.lock'
    $lock=[IO.FileStream]::new($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        if(Test-Path -LiteralPath $path){$old=Read-InstallJournal $path $target -AllowTestRoot:$AllowTestRoot;if($old.state -notin @('Committed','RolledBack')){throw 'An interrupted Launch Agent install must be recovered before another install.'};if($old.state -eq 'Committed' -and (!(Test-InstallJournalFileSet $target $old.candidateFiles) -or !(Test-TaskSpec (& $Context.GetTask)) -or !(Test-InstallJournalFileSet $old.backupRoot $old.priorFiles))){throw 'Committed journal does not match installed runtime/task/rollback copy; manual intervention required.'};if($old.state -eq 'RolledBack' -and ($old.hadTarget -and !(Test-InstallJournalFileSet $target $old.priorFiles) -or !(Test-TaskSpec (& $Context.GetTask)))){throw 'Rolled-back journal does not match restored runtime/task; manual intervention required.'};$archive=Join-Path $parent ('.QaLaunchAgent.install-journal.'+$old.transactionId+'.json');if(Test-Path -LiteralPath $archive){throw 'Install-journal archive destination already exists.'};[IO.File]::Move($path,$archive)}
        $task=& $Context.GetTask;$taskPresent=$null -ne $task;$taskXml=if($taskPresent){[string](& $Context.ExportTask $task)}else{''};if($taskPresent -and !$taskXml){throw 'Prior scheduled-task XML could not be preserved.'}
        $state=if($Context.PSObject.Properties.Name -contains 'GetTaskState'){[string](& $Context.GetTaskState)}elseif($taskPresent){'Ready'}else{'Absent'}
        if(!$taskPresent -or $state -notin @('Ready','Running','Disabled')){throw 'Prior scheduled-task presence or state is not recoverable.'}
        if(!(Test-TaskSpec $task)){throw 'Prior scheduled task does not match the fixed Launch Agent contract.'}
        $had=Test-Path -LiteralPath $target -PathType Container;if(!$had){throw 'Durable CPV upgrade requires a complete prior runtime.'}
        $priorVersion=if($Context.PSObject.Properties.Name -contains 'GetProductVersion'){[string](& $Context.GetProductVersion (Join-Path $target 'Repato.QaLaunchAgent.exe'))}else{[string](Get-Item -LiteralPath (Join-Path $target 'Repato.QaLaunchAgent.exe')).VersionInfo.ProductVersion}
        $priorDllVersion=if($Context.PSObject.Properties.Name -contains 'GetProductVersion'){[string](& $Context.GetProductVersion (Join-Path $target 'Repato.QaLaunchAgent.dll'))}else{[string](Get-Item -LiteralPath (Join-Path $target 'Repato.QaLaunchAgent.dll')).VersionInfo.ProductVersion}
        if(!$priorVersion -or $priorVersion -cne $priorDllVersion -or (!$AllowTestRoot -and $priorVersion -notin @('1.0.17+4b0066247088','1.0.18+4b0066247088','1.0.19+05933ab8b587','1.0.20+09eef230b24bd1169da8b99e2bdf9b5d3b32c40e','1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f','1.0.22+6119aceaab0a34c3e0323089a29f1cefb2c14aaa'))){throw 'Prior executable and DLL do not prove the expected installed release identity.'}
        if($Validated.Manifest.productVersion -match '^1\.0\.22\+' -and $priorVersion -cne '1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f'){throw 'Recovery compatibility journal requires the exact installed 1.0.21 release.'}
        Assert-CpvRecoveredNativeJournalTransition $Validated.Manifest.productVersion $priorVersion $JournalIdentity.RequestId
        $prior=@(foreach($name in $script:Contract.RuntimeFiles){$file=Join-Path $target $name;if(!(Test-Path -LiteralPath $file -PathType Leaf)){throw "Prior runtime is incomplete: $name"};[pscustomobject]@{name=$name;sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}})
        if(!(Test-InstallJournalFileSet $target $prior)){throw 'Prior runtime has unexpected files or failed integrity validation.'}
        $id=[guid]::NewGuid().ToString('N');$journal=[pscustomobject][ordered]@{schemaVersion=1;transactionId=$id;generation=[long]1;state='Prepared';targetRoot=$target;journalPath=$path;stageRoot=(Join-Path $parent ('.QaLaunchAgent.stage.'+$id));backupRoot=(Join-Path $parent ('.QaLaunchAgent.backup.'+$id));failedRoot=(Join-Path $parent ('.QaLaunchAgent.failed.'+$id));hadTarget=$had;priorVersion=$priorVersion;priorFiles=$prior;priorTaskXml=$taskXml;priorTaskSha256=if($taskPresent){Get-InstallJournalTextHash $taskXml}else{''};priorTaskState=$state;taskPresent=$taskPresent;requestId=if($JournalIdentity){[string]$JournalIdentity.RequestId}else{''};taskId=if($JournalIdentity){[string]$JournalIdentity.TaskId}else{''};candidateVersion=[string]$Validated.Manifest.productVersion;candidateManifestSha256=[string]$Validated.ManifestSha256;candidateFiles=@($Validated.Manifest.files|ForEach-Object{[pscustomobject]@{name=$_.name;sha256=$_.sha256}});journalSha256=''}
        Write-InstallJournal $journal|Out-Null
        New-Item -ItemType Directory -Path $journal.stageRoot|Out-Null
        foreach($entry in $Validated.Manifest.files){Copy-Item -LiteralPath (Join-Path $Validated.SourceRoot $entry.name) -Destination (Join-Path $journal.stageRoot $entry.name)}
        & $Context.PrepareAcl $journal.stageRoot
        if(!(Test-InstallJournalFileSet $journal.stageRoot $journal.candidateFiles)){throw 'Staged candidate does not match its immutable manifest.'}
        Set-InstallJournalState $journal 'CandidateStaged'|Out-Null
        [pscustomobject]@{Data=$journal;Path=$path;Lock=$lock;TargetRoot=$target;AllowTestRoot=[bool]$AllowTestRoot;Context=$Context;Closed=$false}
    } catch {$lock.Dispose();throw}
}

function Close-InstallJournalLease($Lease) { if($Lease -and !$Lease.Closed){$Lease.Lock.Dispose();$Lease.Closed=$true} }

function Get-InstallJournal($Lease) {
    if(!$Lease -or !$Lease.Lock -or !$Lease.Lock.CanWrite){throw 'Install journal lease is not held.'}
    $disk=Read-InstallJournal $Lease.Path $Lease.TargetRoot -AllowTestRoot:$Lease.AllowTestRoot
    if($disk.transactionId -cne $Lease.Data.transactionId -or $disk.generation -ne $Lease.Data.generation -or $disk.journalSha256 -cne $Lease.Data.journalSha256){throw 'Install journal changed during transaction.'}
    $Lease.Data
}

function Invoke-InstallJournalRecoveryCore($Lease,$Context,[scriptblock]$ProcessDetector) {
    $j=Get-InstallJournal $Lease
    if($j.state -eq 'Committed'){if(!(Test-InstallJournalFileSet $j.targetRoot $j.candidateFiles) -or !(Test-TaskSpec (& $Context.GetTask)) -or !(Test-InstallJournalFileSet $j.backupRoot $j.priorFiles)){throw 'Committed install or retained rollback copy does not match journal evidence; manual intervention required.'};return [pscustomobject]@{Status='Committed';Recovered=$false;JournalPath=$Lease.Path;RetainedBackup=$j.backupRoot}}
    if($j.state -eq 'RolledBack'){if($j.hadTarget -and !(Test-InstallJournalFileSet $j.targetRoot $j.priorFiles)){throw 'Rolled-back install does not match prior runtime evidence.'};return [pscustomobject]@{Status='RolledBack';Recovered=$false;JournalPath=$Lease.Path}}
    if(!$ProcessDetector){$ProcessDetector={if($Context.PSObject.Properties.Name -contains 'GetProcesses'){@(& $Context.GetProcesses)}else{@(Get-Process -Name Repato.QaLaunchAgent -ErrorAction Stop)}}}
    $activeProcesses=& $ProcessDetector
    $currentTask=& $Context.GetTask;if($currentTask -and !(Test-TaskSpec $currentTask)){throw 'Current scheduled-task contract is ambiguous; preserve journal for manual intervention.'}
    $priorAtTarget=if($j.hadTarget){Test-InstallJournalFileSet $j.targetRoot $j.priorFiles}else{!(Test-Path -LiteralPath $j.targetRoot)}
    $backupValid=if($j.hadTarget){Test-InstallJournalFileSet $j.backupRoot $j.priorFiles}else{$false}
    if(!$priorAtTarget -and !$backupValid){throw 'Neither installed target nor retained backup proves the prior runtime; manual recovery required.'}
    if($j.state -ne 'RollbackPending'){Set-InstallJournalState $j 'RollbackPending'|Out-Null}
    if($Context.PSObject.Properties.Name -contains 'StopTask'){& $Context.StopTask}
    $activeProcesses=& $ProcessDetector
    if($activeProcesses){if($Context.PSObject.Properties.Name -notcontains 'StopProcesses'){throw 'Launch Agent process remains active and no verified stop boundary is available.'};& $Context.StopProcesses $activeProcesses}
    if(& $ProcessDetector){throw 'Launch Agent process remains active after exact-process stop; manual intervention required.'}
    if(!$priorAtTarget){
        if(Test-Path -LiteralPath $j.targetRoot){
            $targetItem=Get-Item -LiteralPath $j.targetRoot -Force;if(($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Install target is a reparse point; manual recovery required.'}
            if(Test-Path -LiteralPath $j.failedRoot){throw 'Failed-runtime evidence path already exists; manual recovery required.'}
            Move-Item -LiteralPath $j.targetRoot -Destination $j.failedRoot
        }
        if($j.hadTarget){Move-Item -LiteralPath $j.backupRoot -Destination $j.targetRoot}
    }
    if($j.taskPresent){& $Context.RestoreTask $j.priorTaskXml;if(!(Test-TaskSpec (& $Context.GetTask))){throw 'Prior scheduled task could not be verified after restore.'};$restoredState=if($Context.PSObject.Properties.Name -contains 'GetTaskState'){[string](& $Context.GetTaskState)}else{'Unknown'};if($j.priorTaskState -ceq 'Running' -and $restoredState -cne 'Running' -and $Context.PSObject.Properties.Name -contains 'StartTask'){& $Context.StartTask}}
    else {& $Context.RestoreTask ''}
    if($j.hadTarget -and !(Test-InstallJournalFileSet $j.targetRoot $j.priorFiles)){throw 'Restored prior runtime failed hashes; journal retained for manual recovery.'}
    Set-InstallJournalState $j 'RolledBack'|Out-Null
    [pscustomobject]@{Status='RolledBack';Recovered=$true;JournalPath=$Lease.Path;RestoredVersion=$j.priorTaskState;RetainedFailedRuntime=$j.failedRoot}
}

function Open-InstallJournalLease([string]$TargetRoot,[switch]$AllowTestRoot) {
    $target=[IO.Path]::GetFullPath($TargetRoot).TrimEnd('\');$path=Join-Path (Split-Path $target -Parent) '.QaLaunchAgent.install-journal.json';$lockPath=$path+'.lock'
    $lock=[IO.FileStream]::new($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{$data=Read-InstallJournal $path $target -AllowTestRoot:$AllowTestRoot;[pscustomobject]@{Data=$data;Path=$path;Lock=$lock;TargetRoot=$target;AllowTestRoot=[bool]$AllowTestRoot;Closed=$false}}catch{$lock.Dispose();throw}
}

function New-RepatoQaLaunchAgentBootstrapInstallJournal {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ManifestSha256,[Parameter(Mandatory)][string]$RequestId,[Parameter(Mandatory)][string]$TaskId,[switch]$RecoveredNativeContinuation)
    Assert-Administrator;Assert-Identity $script:Contract.Account $script:Contract.Sid
    if($RequestId -notin @('9953e14c15524fe09440d1c7d7353950','c11b311638a54bfc9ebdd1803671ec40') -or $TaskId -cne 'task-bf61fe7f22d74df7a92599681da5919e'){throw 'Durable installation journal is restricted to a pinned CPV request identity.'}
    $v=Read-ValidatedManifest $SourceRoot $ManifestPath $ManifestSha256.ToUpperInvariant()
    New-InstallJournalCore $v (New-RealBootstrapContext) $script:Contract.InstallRoot ([pscustomobject]@{RequestId=$RequestId;TaskId=$TaskId;RecoveredNativeContinuation=[bool]$RecoveredNativeContinuation})
}

function Set-RepatoQaLaunchAgentBootstrapInstallHealthVerification {
    [CmdletBinding()]param([Parameter(Mandatory)]$JournalLease)
    $j=Get-InstallJournal $JournalLease
    if($j.state -cne 'TaskUpdated'){throw 'Health verification can begin only after the task update is verified.'}
    Set-InstallJournalState $j 'HealthVerificationPending'|Out-Null
}

function Assert-CpvPreparationRecoveryJournalIdentity($Journal,[string]$RequestId,[string]$TaskId) {
    if($Journal.transactionId -cne 'ea59f13044b04c65a6ce4360bec9f806' -or $Journal.requestId -cne $RequestId -or $Journal.taskId -cne $TaskId -or $RequestId -cne '9953e14c15524fe09440d1c7d7353950' -or $TaskId -cne 'task-bf61fe7f22d74df7a92599681da5919e'){throw 'Install journal transaction or request identity does not match the reviewed CPV recovery.'}
}

function Recover-RepatoQaLaunchAgentBootstrapInstall {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$RequestId,[Parameter(Mandatory)][string]$TaskId)
    Assert-Administrator;Assert-Identity $script:Contract.Account $script:Contract.Sid
    if($RequestId -cne '9953e14c15524fe09440d1c7d7353950' -or $TaskId -cne 'task-bf61fe7f22d74df7a92599681da5919e'){throw 'Recovery request identity does not match the approved CPV attempt.'}
    $lease=Open-InstallJournalLease $script:Contract.InstallRoot
    try{Assert-CpvPreparationRecoveryJournalIdentity $lease.Data $RequestId $TaskId;Invoke-InstallJournalRecoveryCore $lease (New-RealBootstrapContext)}finally{Close-InstallJournalLease $lease}
}

function New-RealSnapshotRecoveryContext {
    [pscustomobject]@{
        AssertAdministrator = { Assert-Administrator }
        ResolveIdentity = { param($a,$s) Assert-Identity $a $s }
        GetTask = { $context=New-RealBootstrapContext; & $context.GetTask }
        GetTaskState = { (Get-ScheduledTask -TaskPath $script:Contract.TaskPath -TaskName $script:Contract.TaskName -ErrorAction Stop).State.ToString() }
        GetProcesses = { @(Get-Process -Name Repato.QaLaunchAgent -ErrorAction SilentlyContinue) }
        CopySecurity = { param($source,$destination) Set-Acl -LiteralPath $destination -AclObject (Get-Acl -LiteralPath $source) }
    }
}

function Restore-RepatoQaLaunchAgentSnapshot {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')]
    param()
    $snapshotRoot='C:\Repato-Autonomous\RecoveryHandoff\QaLaunchAgent-v1.0.10-50d5d752d9a8\Snapshot'
    $manifestSha256='F25A3DE088188E7ACB87CA950B199B89110813C4007FADB99AA27F81B5ACC738'
    Assert-Administrator
    Assert-Identity $script:Contract.Account $script:Contract.Sid
    if($PSCmdlet.ShouldProcess($script:Contract.InstallRoot,'Restore independently verified v1.0.10 Launch Agent snapshot')){
        Invoke-RepatoQaLaunchAgentSnapshotRecoveryCore -SnapshotRoot $snapshotRoot -ManifestSha256 $manifestSha256 -ExpectedSnapshotRoot $snapshotRoot -ExpectedManifestSha256 $manifestSha256 -TargetRoot $script:Contract.InstallRoot -Context (New-RealSnapshotRecoveryContext)
    }
}

function Invoke-InstallCore($Validated,$Context,[string]$TargetRoot,[switch]$AllowTestRoot,[scriptblock]$ProcessDetector,[switch]$RetainRollback,$DurableJournal) {
    & $Context.IsAdministrator
    & $Context.ResolveIdentity $script:Contract.Account $script:Contract.Sid
    if($Validated.Manifest.productVersion -match '^1\.0\.23\+'){
        if(!$DurableJournal){throw 'Recovered-native release installation requires its validated durable journal.'}
        $boundJournal=Get-InstallJournal $DurableJournal
        Assert-CpvRecoveredNativeJournalTransition $boundJournal.candidateVersion $boundJournal.priorVersion $boundJournal.requestId
        if($boundJournal.candidateVersion -cne $Validated.Manifest.productVersion -or
            $boundJournal.candidateManifestSha256 -cne $Validated.ManifestSha256){throw 'Recovered-native installation journal does not bind this exact immutable release.'}
    }
    if (-not $AllowTestRoot -and [IO.Path]::GetFullPath($TargetRoot).TrimEnd('\') -cne $script:Contract.InstallRoot) { throw 'Install root must be the fixed protected Program Files path.' }
    if (-not $ProcessDetector) { $ProcessDetector = { Get-Process -Name Repato.QaLaunchAgent -ErrorAction SilentlyContinue } }
    if (& $ProcessDetector) { throw 'Refusing update while the launch agent is running.' }
    $parent=Split-Path $TargetRoot -Parent; New-Item -ItemType Directory -Path $parent -Force|Out-Null
    if($DurableJournal){$j=Get-InstallJournal $DurableJournal;if($j.state -cne 'ServiceStopped' -or [IO.Path]::GetFullPath($j.targetRoot).TrimEnd('\') -ine [IO.Path]::GetFullPath($TargetRoot).TrimEnd('\')){throw 'Durable journal is not at the verified stopped-service boundary.'};$stage=$j.stageRoot;$backup=$j.backupRoot}
    else{$stage=Join-Path $parent ('.QaLaunchAgent.stage.'+[guid]::NewGuid().ToString('N')); $backup=Join-Path $parent ('.QaLaunchAgent.backup.'+[guid]::NewGuid().ToString('N'))}
    $oldTask=& $Context.GetTask; $oldXml=& $Context.ExportTask $oldTask
    $hadTarget=Test-Path -LiteralPath $TargetRoot
    $oldFiles=@()
    if($hadTarget){foreach($name in $script:Contract.RuntimeFiles){$path=Join-Path $TargetRoot $name;if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Existing runtime is incomplete: $name"};$oldFiles+= [pscustomobject]@{name=$name;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}}}
    try {
        if(!$DurableJournal){New-Item -ItemType Directory -Path $stage|Out-Null;foreach($e in $Validated.Manifest.files){Copy-Item -LiteralPath (Join-Path $Validated.SourceRoot $e.name) -Destination (Join-Path $stage $e.name)};& $Context.PrepareAcl $stage;foreach($e in $Validated.Manifest.files){if((Get-FileHash -LiteralPath (Join-Path $stage $e.name) -Algorithm SHA256).Hash -cne $e.sha256){throw "Staged hash mismatch: $($e.name)"}}}
        else {if(!(Test-InstallJournalFileSet $stage $j.candidateFiles)){throw 'Durably staged candidate failed its manifest hashes.'};Set-InstallJournalState $j 'BackupMovePending'|Out-Null}
        if($hadTarget){Move-Item -LiteralPath $TargetRoot -Destination $backup}
        if($DurableJournal){if(!(Test-InstallJournalFileSet $backup $j.priorFiles)){throw 'Moved prior runtime failed journal hashes.'};Set-InstallJournalState $j 'BackupVerified'|Out-Null;Set-InstallJournalState $j 'ReplacementPending'|Out-Null}
        Move-Item -LiteralPath $stage -Destination $TargetRoot
        if($DurableJournal){if(!(Test-InstallJournalFileSet $TargetRoot $j.candidateFiles)){throw 'Replaced runtime failed candidate hashes.'};Set-InstallJournalState $j 'FilesReplaced'|Out-Null;Set-InstallJournalState $j 'TaskUpdatePending'|Out-Null}
        & $Context.SetTask (New-TaskSpec)
        $actual=& $Context.GetTask
        $snapshot=if($Context.PSObject.Properties.Name -contains 'GetTaskSnapshot'){& $Context.GetTaskSnapshot}else{$actual}
        $comparison=@(Get-TaskSpecComparison $actual)
        if(-not (Test-TaskSpec $actual)) {
            $report=Write-RepatoQaLaunchAgentDiagnostics $snapshot $comparison (Get-RepatoQaLaunchAgentRuntimeIntegrity $TargetRoot $Validated.Manifest) 'Registered scheduled task does not match the security contract.'
            throw "Registered scheduled task does not match the security contract. Diagnostic report: $report"
        }
        if($DurableJournal){Set-InstallJournalState $j 'TaskUpdated'|Out-Null}
        foreach($e in $Validated.Manifest.files){if((Get-FileHash -LiteralPath (Join-Path $TargetRoot $e.name) -Algorithm SHA256).Hash -cne $e.sha256){throw "Installed hash mismatch: $($e.name)"}}
        $token=$null
        if($RetainRollback){$token=[pscustomobject]@{Id=[guid]::NewGuid().ToString('N');TargetRoot=[IO.Path]::GetFullPath($TargetRoot);BackupRoot=if(Test-Path -LiteralPath $backup){$backup}else{$null};PriorFiles=$oldFiles;InstalledFiles=@($Validated.Manifest.files);OldTaskXml=$oldXml;Updated=$hadTarget;CleanupRoot=$null;Restored=$false;DurableJournal=$DurableJournal};$script:PendingInstallRollbacks[$token.Id]=$token}
        elseif(Test-Path -LiteralPath $backup){Remove-Item -LiteralPath $backup -Recurse -Force}
        [pscustomobject]@{Installed=$true;Updated=$hadTarget;Task=(New-TaskSpec);ProductVersion=$Validated.Manifest.productVersion;ManifestSha256=$Validated.ManifestSha256;RollbackToken=$token}
    } catch {
        if($DurableJournal){throw}
        & $Context.RestoreTask $oldXml
        if(Test-Path -LiteralPath $TargetRoot){Remove-Item -LiteralPath $TargetRoot -Recurse -Force}
        if(Test-Path -LiteralPath $backup){Move-Item -LiteralPath $backup -Destination $TargetRoot}
        if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force}
        throw
    }
}

function Assert-InstallRollbackToken($Token,[string]$TargetRoot,[switch]$AllowTestRoot) {
    if(!$Token.Id -or !$script:PendingInstallRollbacks.ContainsKey([string]$Token.Id) -or ![object]::ReferenceEquals($script:PendingInstallRollbacks[[string]$Token.Id],$Token)){throw 'Rollback token is unknown or was modified.'}
    $target=[IO.Path]::GetFullPath($TargetRoot).TrimEnd('\');$expected=[IO.Path]::GetFullPath($Token.TargetRoot).TrimEnd('\')
    if($target -cne $expected -or (!$AllowTestRoot -and $target -cne $script:Contract.InstallRoot)){throw 'Rollback token does not match the fixed install root.'}
    foreach($path in @($Token.BackupRoot,$Token.CleanupRoot)|Where-Object{$_}) {
        $full=[IO.Path]::GetFullPath($path);$parent=Split-Path $target -Parent
        if((Split-Path $full -Parent) -ine $parent -or (Split-Path $full -Leaf) -notmatch '^\.QaLaunchAgent\.(backup\.[0-9a-fA-F]{32}|failed\.[0-9a-fA-F-]{36})$'){throw 'Rollback token contains an unsafe sibling path.'}
    }
}

function Restore-InstallCore($Token,$Context,[string]$TargetRoot,[switch]$AllowTestRoot,[scriptblock]$ProcessDetector) {
    Assert-InstallRollbackToken $Token $TargetRoot -AllowTestRoot:$AllowTestRoot
    if($Token.DurableJournal){try{$result=Invoke-InstallJournalRecoveryCore $Token.DurableJournal $Context $ProcessDetector;if($result.Status -eq 'RolledBack'){$Token.Restored=$true};return $result}finally{Close-InstallJournalLease $Token.DurableJournal}}
    if(!$ProcessDetector){$ProcessDetector={Get-Process -Name Repato.QaLaunchAgent -ErrorAction SilentlyContinue}}
    if(& $ProcessDetector){throw 'Stop the Launch Agent before restoring its runtime.'}
    if($Token.Updated){
        if(!(Test-Path -LiteralPath $Token.BackupRoot -PathType Container)){throw 'Verified prior runtime backup is missing.'}
        $prior=Get-RepatoQaLaunchAgentRuntimeIntegrity $Token.BackupRoot ([pscustomobject]@{files=$Token.PriorFiles})
        if(@($prior|Where-Object{!$_.Match}).Count){throw 'Prior runtime backup integrity failed; refusing rollback.'}
    }
    & $Context.RestoreTask $Token.OldTaskXml
    $failed=if(Test-Path -LiteralPath $TargetRoot){Join-Path (Split-Path $TargetRoot -Parent) ('.QaLaunchAgent.failed.'+[guid]::NewGuid().ToString('D'))}else{$null}
    if($failed){Move-Item -LiteralPath $TargetRoot -Destination $failed}
    try {
        if($Token.Updated){Move-Item -LiteralPath $Token.BackupRoot -Destination $TargetRoot}
        $expected=if($Token.Updated){$Token.PriorFiles}else{@()}
        $integrity=if($Token.Updated){Get-RepatoQaLaunchAgentRuntimeIntegrity $TargetRoot ([pscustomobject]@{files=$expected})}else{@()}
        if(@($integrity|Where-Object{!$_.Match}).Count){throw 'Restored runtime integrity failed.'}
        $Token.Restored=$true;$Token.CleanupRoot=$failed
        $Token | Add-Member -NotePropertyName RuntimeIntegrity -NotePropertyValue $integrity -Force
        $Token | Add-Member -NotePropertyName RestoredTask -NotePropertyValue ($null -ne $Token.OldTaskXml) -Force
        $Token
    } catch {
        if($Token.Updated -and (Test-Path -LiteralPath $TargetRoot) -and !(Test-Path -LiteralPath $Token.BackupRoot)){Move-Item -LiteralPath $TargetRoot -Destination $Token.BackupRoot}
        if($failed -and (Test-Path -LiteralPath $failed) -and !(Test-Path -LiteralPath $TargetRoot)){Move-Item -LiteralPath $failed -Destination $TargetRoot}
        throw
    }
}

function Complete-InstallCore($Token,[string]$TargetRoot,[switch]$AllowTestRoot) {
    Assert-InstallRollbackToken $Token $TargetRoot -AllowTestRoot:$AllowTestRoot
    if($Token.DurableJournal){$lease=$Token.DurableJournal;$j=Get-InstallJournal $lease;if($j.state -cne 'HealthVerificationPending' -or !(Test-InstallJournalFileSet $TargetRoot $j.candidateFiles) -or !(Test-TaskSpec (& $lease.Context.GetTask)) -or !(Test-InstallJournalFileSet $j.backupRoot $j.priorFiles)){throw 'Durable installation health or rollback evidence is incomplete.'};Set-InstallJournalState $j 'CommitPending'|Out-Null;Set-InstallJournalState $j 'Committed'|Out-Null;Close-InstallJournalLease $lease;[void]$script:PendingInstallRollbacks.Remove([string]$Token.Id);return [pscustomobject]@{Completed=$true;Committed=$true;BackupRetained=$j.backupRoot;JournalPath=$lease.Path}}
    $expected=if($Token.Restored){$Token.PriorFiles}else{$Token.InstalledFiles}
    $integrity=if(@($expected).Count){Get-RepatoQaLaunchAgentRuntimeIntegrity $TargetRoot ([pscustomobject]@{files=$expected})}else{@()}
    if(@($integrity|Where-Object{!$_.Match}).Count){throw 'Runtime changed before rollback retention could be finalized.'}
    $cleanup=if($Token.Restored){$Token.CleanupRoot}else{$Token.BackupRoot}
    $cleanupComplete=$true;$cleanupError=$null
    if($cleanup -and (Test-Path -LiteralPath $cleanup)){try{Remove-Item -LiteralPath $cleanup -Recurse -Force -ErrorAction Stop}catch{$cleanupComplete=$false;$cleanupError=$_.Exception.Message}}
    [void]$script:PendingInstallRollbacks.Remove([string]$Token.Id)
    [pscustomobject]@{Completed=$true;Restored=[bool]$Token.Restored;RuntimeIntegrity=$integrity;CleanupComplete=$cleanupComplete;CleanupError=$cleanupError}
}

function Install-RepatoQaLaunchAgentBootstrap {
    [CmdletBinding(SupportsShouldProcess)]param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ManifestSha256,[string]$Account=$script:Contract.Account,[string]$ExpectedSid=$script:Contract.Sid,[switch]$RetainRollback,$DurableJournal)
    Assert-Administrator; Assert-Identity $Account $ExpectedSid
    $v=Read-ValidatedManifest $SourceRoot $ManifestPath $ManifestSha256.ToUpperInvariant()
    if($PSCmdlet.ShouldProcess($script:Contract.InstallRoot,'Atomically install launch-agent runtime and reconcile its logon task')){Invoke-InstallCore $v (New-RealBootstrapContext) $script:Contract.InstallRoot -RetainRollback:$RetainRollback -DurableJournal $DurableJournal}
}

function Restore-RepatoQaLaunchAgentBootstrapInstall {
    [CmdletBinding()]param([Parameter(Mandatory)]$RollbackToken,[string]$Account=$script:Contract.Account,[string]$ExpectedSid=$script:Contract.Sid)
    Assert-Administrator;Assert-Identity $Account $ExpectedSid
    Restore-InstallCore $RollbackToken (New-RealBootstrapContext) $script:Contract.InstallRoot
}

function Complete-RepatoQaLaunchAgentBootstrapInstall {
    [CmdletBinding()]param([Parameter(Mandatory)]$RollbackToken,[string]$Account=$script:Contract.Account,[string]$ExpectedSid=$script:Contract.Sid)
    Assert-Administrator;Assert-Identity $Account $ExpectedSid
    Complete-InstallCore $RollbackToken $script:Contract.InstallRoot
}

function Test-RepatoQaLaunchAgentBootstrap {
    [CmdletBinding()]param([Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$ManifestSha256)
    $v=Read-ValidatedManifest $script:Contract.InstallRoot $ManifestPath $ManifestSha256.ToUpperInvariant(); $ctx=New-RealBootstrapContext; $task=& $ctx.GetTask
    [pscustomobject]@{ScheduledTaskRegistered=[bool]$task;TaskContractValid=($task -and (Test-TaskSpec $task));InstalledRuntimeIntegrity=[bool]$v;ProductVersion=$v.Manifest.productVersion}
}

function Uninstall-RepatoQaLaunchAgentBootstrap {
    [CmdletBinding(SupportsShouldProcess)]param()
    Assert-Administrator
    if($PSCmdlet.ShouldProcess($script:Contract.InstallRoot,'Remove launch-agent task and runtime')){$ctx=New-RealBootstrapContext;& $ctx.RemoveTask;if(Test-Path -LiteralPath $script:Contract.InstallRoot){Remove-Item -LiteralPath $script:Contract.InstallRoot -Recurse -Force}}
}

Export-ModuleMember -Function Get-RepatoQaLaunchAgentBootstrapContract,Install-RepatoQaLaunchAgentBootstrap,Restore-RepatoQaLaunchAgentBootstrapInstall,Restore-RepatoQaLaunchAgentSnapshot,Complete-RepatoQaLaunchAgentBootstrapInstall,New-RepatoQaLaunchAgentBootstrapInstallJournal,Set-RepatoQaLaunchAgentBootstrapInstallHealthVerification,Recover-RepatoQaLaunchAgentBootstrapInstall,Test-RepatoQaLaunchAgentBootstrap,Uninstall-RepatoQaLaunchAgentBootstrap,Get-TaskSpecComparison,Get-RepatoQaLaunchAgentRuntimeIntegrity
