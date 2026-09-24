Set-StrictMode -Version Latest

function Assert-TaraPath {
    param([string]$Path,[string]$Root,[switch]$Leaf)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:\\' -or $Path.Substring(2).Contains(':') -or $Path -match '["\r\n]') { throw 'An absolute local path without alternate streams is required.' }
    $full=[IO.Path]::GetFullPath($Path)
    if($Root -and !$full.StartsWith(([IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw "Path outside approved QA root: $full"}
    if(([IO.DriveInfo]::new([IO.Path]::GetPathRoot($full))).DriveType -ne [IO.DriveType]::Fixed){throw 'A fixed local drive is required.'}
    for($part=$full;$part;$part=[IO.Path]::GetDirectoryName($part)){
        try { $exists=Test-Path -LiteralPath $part -ErrorAction Stop }
        catch { throw "Path inaccessible: $part. Access was denied while validating the QA path." }
        if($exists){
            try { $item=Get-Item -LiteralPath $part -Force -ErrorAction Stop }
            catch { throw "Path inaccessible: $part. Access was denied while validating the QA path." }
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Reparse point rejected: $part"}
        }
    }
    if($Leaf){
        try { $leafExists=Test-Path -LiteralPath $full -PathType Leaf -ErrorAction Stop }
        catch { throw "Path inaccessible: $full. Access was denied while validating the QA path." }
        if(!$leafExists){throw "Required file missing: $full"}
    }
    $full
}
function Get-TaraSha256([string]$Path){
    $s=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite);$h=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($h.ComputeHash($s))).Replace('-','')}finally{$h.Dispose();$s.Dispose()}
}
# Names required by the existing shared isolation policy, scoped to this module.
function Assert-ChildPath([string]$Path,[string]$Parent){Assert-TaraPath $Path $Parent}
function Get-Sha256([string]$Path){Get-TaraSha256 $Path}
. (Join-Path $PSScriptRoot '..\QA\AddinIsolation.ps1')
function Get-TaraRuntimeRoots {
    $profile='C:\Users\RepatoQA'
    if([Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1] -ieq 'RepatoQA'){$profile=[Environment]::GetFolderPath('UserProfile')}
    [pscustomobject]@{QaRoot='C:\Repato-Autonomous\Source\QA';UserAddinsRoot=(Join-Path $profile 'AppData\Roaming\Autodesk\Revit\Addins\2025');MachineRoot='C:\ProgramData\Autodesk\Revit\Addins\2025'}
}
function Assert-TaraInteractiveSession {
    if([Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1] -ine 'RepatoQA'){throw 'Real execution requires the dedicated RepatoQA Windows identity.'}
    if(![Environment]::UserInteractive -or [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){throw 'An interactive RepatoQA desktop session is required; Session 0 is prohibited.'}
    if(!( 'Repato.TaraDesktop' -as [type])){
        Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; namespace Repato { public static class TaraDesktop { [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access); [DllImport("user32.dll", SetLastError=true)] public static extern bool SwitchDesktop(IntPtr desktop); [DllImport("user32.dll")] public static extern bool CloseDesktop(IntPtr desktop); } }'
    }
    $desktop=[Repato.TaraDesktop]::OpenInputDesktop(0,$false,0x0100)
    if($desktop -eq [IntPtr]::Zero){throw 'RepatoQA must be logged in with an unlocked interactive desktop.'}
    try{if(![Repato.TaraDesktop]::SwitchDesktop($desktop)){throw 'RepatoQA desktop is locked or inaccessible.'}}finally{[void][Repato.TaraDesktop]::CloseDesktop($desktop)}
    if(@(Get-Process -Name Revit -ErrorAction SilentlyContinue).Count){throw 'A Revit process already exists; a fresh isolated QA session is required.'}
}
function Assert-TaraRevitExecutableVersion([string]$Path){
    if((Get-Item -LiteralPath $Path).VersionInfo.ProductMajorPart -ne 25){throw 'Configured executable must be Revit 2025 (product major version 25).'} 
}
function Get-TaraQaTrustConfiguration($QaAddinRoot,$QaRoot,$Inventory){
    $names=@('Repato.CreateLevels.TestRunner.addin','Repato.CreateGrids.TestRunner.addin','Repato.GridBubbleVisibility.TestRunner.addin','Repato.GridBubbleOffset.TestRunner.addin','Repato.GridResequence.TestRunner.addin')
    $records=@();foreach($n in $names){$p=Join-Path (Split-Path $QaAddinRoot -Parent) $n;$source=Join-Path $QaRoot $n;if(!(Test-Path $source -PathType Leaf)){continue};$h=Get-TaraSha256 $source;$records+=[pscustomobject]@{Name=$n;Path=$p;Sha256=$h}}
    [pscustomobject]@{Path=(Join-Path $QaAddinRoot 'RepatoQA.trust.json');ApprovedManifests=$records;PromptFree=$true;ProfileRoot=$QaAddinRoot}
}
function New-TaraRevitQaPlan {
    param([string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$QaWorkflowId,[string]$RunId,[string]$ModelPath,[string]$SidecarPath,[string]$ReportDirectory,[string]$RevitInstallDir,[string]$QaAddinRoot,[ValidateRange(1,3600)][int]$TimeoutSeconds=900,[switch]$DryRun,[Parameter(Mandatory)]$Context)
    $QaWorkflowId=$QaWorkflowId.Trim()
    $runners=@{
        'create-levels'=@('Repato.CreateLevels.TestRunner.addin','REPATO_QA_LEVELS_REQUEST','Invoke-CreateLevelsQA.ps1','Repato.Revit.TestRunner.CreateLevelsQaApplication')
        'grid-bubble-visibility-v1'=@('Repato.GridBubbleVisibility.TestRunner.addin','REPATO_QA_GRID_BUBBLE_REQUEST','Invoke-GridBubbleVisibilityQA.ps1','Repato.Revit.TestRunner.GridBubbleVisibilityQaApplication')
        'grid-bubble-offset-v1'=@('Repato.GridBubbleOffset.TestRunner.addin','REPATO_QA_GRID_BUBBLE_OFFSET_REQUEST','Invoke-GridBubbleOffsetQA.ps1','Repato.Revit.TestRunner.GridBubbleOffsetQaApplication')
          'grid-resequence-v1'=@('Repato.GridResequence.TestRunner.addin','REPATO_QA_GRID_RESEQUENCE_REQUEST','Invoke-GridResequenceQA.ps1','Repato.Revit.TestRunner.GridResequenceQaApplication')
          'create-grids-world-axis-v1'=@('Repato.CreateGrids.TestRunner.addin','REPATO_QA_CREATE_GRIDS_REQUEST','Invoke-CreateGridsQA.ps1','Repato.Revit.TestRunner.CreateGridsQaApplication')
    }
      $runners['create-levels-elevations-v1']=$runners['create-levels']
    if(!$runners.ContainsKey($QaWorkflowId)){throw "Workflow has no supported unattended startup runner. Normalized ID='$QaWorkflowId'; available runner keys=$($runners.Keys -join ', ')."}
    foreach($name in @('TaskId','WorkflowId','QaWorkflowId','RunId')){ $value=Get-Variable $name -ValueOnly;if($value -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$' -or $Context.$name -cne $value){throw "Wrong workflow identity: $name"} }
    $roots=Get-TaraRuntimeRoots
    if([IO.Path]::GetFullPath($Context.QaRoot) -ine $roots.QaRoot){throw 'Native runner requires the fixed Source QA root.'}
    $qa=Assert-TaraPath $Context.QaRoot
    $model=Assert-TaraPath $ModelPath (Join-Path $qa 'TestRuns') -Leaf
    if([IO.Path]::GetExtension($model) -ine '.rvt'){throw 'A disposable Revit fixture is required.'}
    $sidecar=Assert-TaraPath $SidecarPath (Join-Path $qa 'TestRuns') -Leaf
    if($sidecar -ine ($model+'.fixture.json')){throw 'Sidecar must be adjacent to the supplied model.'}
    $reportRoot=Assert-TaraPath $ReportDirectory $qa
    if($reportRoot -ine (Join-Path $qa 'Reports') -or !(Test-Path -LiteralPath $reportRoot -PathType Container)){throw 'ReportDirectory must be the existing native QA Reports directory.'}
    $source=Assert-TaraPath $Context.SourceFixturePath (Join-Path $qa 'Fixtures') -Leaf
    $side=Get-Content -LiteralPath $sidecar -Raw|ConvertFrom-Json
    if($side.fixtureId -cne $Context.FixtureId -or $side.sourceSha256 -ine $Context.FixtureSha256){throw 'Fixture sidecar identity or expected source hash mismatch.'}
    foreach($p in @($source,$model)){if((Get-TaraSha256 $p) -ine $Context.FixtureSha256){throw 'Fixture/model hash mismatch.'}}
    $addin=Assert-TaraPath $QaAddinRoot $roots.UserAddinsRoot
    if($addin -ine (Join-Path $roots.UserAddinsRoot 'RepatoQA')){throw 'Production add-in path rejected: only the dedicated RepatoQA folder is allowed.'}
    $runner=$runners[$QaWorkflowId]
    $manifest=Assert-TaraPath (Join-Path $roots.UserAddinsRoot $runner[0]) $roots.UserAddinsRoot -Leaf
    $dll=Assert-TaraPath (Join-Path $addin 'Repato.Revit.dll') $addin -Leaf
    $artifactManifest=Assert-TaraPath $Context.ManifestPath -Leaf
    $qaRunnerSourceManifest=Assert-TaraPath (Join-Path $qa $runner[0]) $qa -Leaf
    $artifactPairs=@(@($dll,$Context.ArtifactSha256),@($Context.ArtifactPath,$Context.ArtifactSha256),@($artifactManifest,$Context.ManifestSha256))
    foreach($pair in $artifactPairs){$null=Assert-TaraPath $pair[0] -Leaf;if($pair[1] -notmatch '^[a-fA-F0-9]{64}$' -or (Get-TaraSha256 $pair[0]) -ine $pair[1]){throw 'Artifact or artifact-manifest hash mismatch.'}}
    $qaRunnerManifestSha256=Get-TaraSha256 $qaRunnerSourceManifest
    if((Get-TaraSha256 $manifest) -ine $qaRunnerManifestSha256){throw 'QA runner manifest hash mismatch.'}
    $xml=[xml](Get-Content -LiteralPath $manifest -Raw)
    if(@($xml.RevitAddIns.AddIn|Where-Object Type -eq 'Application').Count -ne 1){throw 'QA startup application manifest is required.'}
    $appEntries=@($xml.RevitAddIns.AddIn|Where-Object Type -eq 'Application')
    if($appEntries.Count -ne 1 -or $appEntries[0].FullClassName -cne $runner[3]){throw 'QA runner startup class does not match the selected workflow.'}
    foreach($entry in $xml.RevitAddIns.AddIn){if([IO.Path]::GetFullPath((Join-Path $roots.UserAddinsRoot ([string]$entry.Assembly))) -ine $dll){throw 'Manifest assembly path is outside the QA deployment.'}}
    $inventory=Get-AddinIsolationInventory -PolicyPath (Join-Path $qa 'MachineWideAddins.allowlist.json') -MachineRoot $roots.MachineRoot -UserRoot $roots.UserAddinsRoot -QaSourceRoot $qa
    if(!$inventory.Allowed -or @($inventory.Errors).Count){throw ('Add-in allowlist rejected: '+(@($inventory.Errors)+@($inventory.DetectedAddins|Where-Object {!$_.Allowlisted}|ForEach-Object Reason)-join '; '))}
    $exe=Assert-TaraPath (Join-Path $RevitInstallDir 'Revit.exe') $RevitInstallDir -Leaf
    Assert-TaraRevitExecutableVersion $exe
    $verifier=Assert-TaraPath (Join-Path $qa $runner[2]) $qa -Leaf
    if(!$DryRun){Assert-TaraInteractiveSession}
    $requestId=[guid]::NewGuid().ToString('N');$requestPath=Join-Path ([IO.Path]::GetDirectoryName($model)) ('tara-'+$requestId+'.request.json')
    $trust=Get-TaraQaTrustConfiguration $addin $qa $inventory
    [pscustomobject]@{StoreRoot=$StoreRoot;TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;RunId=$RunId;Context=$Context;ModelPath=$model;SidecarPath=$sidecar;SidecarSha256=(Get-TaraSha256 $sidecar);ReportDirectory=$reportRoot;RevitInstallDir=$RevitInstallDir;QaAddinRoot=$addin;TrustConfiguration=$trust;TimeoutSeconds=$TimeoutSeconds;Executable=$exe;ExecutableSha256=(Get-TaraSha256 $exe);Command=('"'+$exe+'"');Arguments='';EnvironmentVariable=$runner[1];VerifierPath=$verifier;VerifierSha256=(Get-TaraSha256 $verifier);RequestId=$requestId;RequestPath=$requestPath;ResultPath=($requestPath+'.result.json');EvidencePath=(Join-Path $reportRoot ('tara-'+$requestId+'.json'));InstalledDll=$dll;ArtifactManifestPath=$artifactManifest;ArtifactManifestSha256=$Context.ManifestSha256;QaRunnerManifestPath=$manifest;QaRunnerManifestSha256=$qaRunnerManifestSha256;InstalledManifest=$manifest;Isolation=$inventory;SideEffectsPerformed=$false}
}
function Write-TaraJsonNew($Path,$Value){
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 30));$stream=[IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}
function Start-TaraProcess($Plan){
    if($Plan.TrustConfiguration -and $Plan.TrustConfiguration.PromptFree){$Plan.TrustConfiguration|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $Plan.TrustConfiguration.Path -Encoding UTF8}
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$Plan.Executable;$info.Arguments='';$info.UseShellExecute=$false;$info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    # Environment changes are confined to this child. Clear every other QA dispatch.
    foreach($key in @($info.EnvironmentVariables.Keys)){if($key -like 'REPATO_QA_*_REQUEST'){$info.EnvironmentVariables.Remove($key)}}
    $info.EnvironmentVariables[$Plan.EnvironmentVariable]=$Plan.RequestPath
    $info.EnvironmentVariables['REPATO_QA_REPOSITORY_ROOT']=(Split-Path (Split-Path $Plan.VerifierPath -Parent) -Parent)
    $child=[Diagnostics.Process]::Start($info);$null=$child.Handle;return $child
}
function Stop-TaraOwnedProcess($Process){
    # Never discover/reacquire by PID or name. The original Process handle owns this termination.
    $Process.Refresh();if(!$Process.HasExited){$Process.Kill();[void]$Process.WaitForExit(5000)}
}
function Close-TaraOwnedProcess($Process,[int]$GraceSeconds=30){
    $Process.Refresh(); if($Process.HasExited){ return [pscustomobject]@{State='Exited';ExitCode=$Process.ExitCode;Forced=$false} }
    $requested=$false; try{$requested=$Process.CloseMainWindow()}catch{}
    $deadline=[DateTime]::UtcNow.AddSeconds($GraceSeconds)
    while(!$Process.HasExited -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Seconds 1;$Process.Refresh()}
    if(!$Process.HasExited){ Stop-TaraOwnedProcess $Process; return [pscustomobject]@{State='ForceTerminated';ExitCode=$Process.ExitCode;Forced=$true} }
    return [pscustomobject]@{State='Exited';ExitCode=$Process.ExitCode;Forced=$false}
}
function Assert-TaraModelUnlocked([string]$Path){
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None);$stream.Dispose()
}
function Wait-TaraResult($Plan,$Process){
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while(!(Test-Path -LiteralPath $Plan.ResultPath -PathType Leaf)){
        $Process.Refresh();if($Process.HasExited){throw 'QA Revit exited before publishing a result.'}
        if($timer.Elapsed.TotalSeconds -ge $Plan.TimeoutSeconds){Stop-TaraOwnedProcess $Process;throw [TimeoutException]::new('QA hard timeout; only the bridge-owned Revit process was terminated.')}
        Start-Sleep -Seconds 20
    }
}
function Assert-TaraResult($Plan){
    $request=Get-Content -LiteralPath $Plan.RequestPath -Raw|ConvertFrom-Json
    foreach($name in @('TaskId','WorkflowId','QaWorkflowId','RunId')){if($request.$name -cne $Plan.$name){throw "Stale or mismatched request $name."}}
    if($request.requestId -cne $Plan.RequestId){throw 'Request identity mismatch.'}
    $receipt=Get-Content -LiteralPath $Plan.ResultPath -Raw|ConvertFrom-Json
    $reportPath=Assert-TaraPath $receipt.ReportPath $Plan.ReportDirectory -Leaf
    $reportHash=Get-TaraSha256 $reportPath;$report=Get-Content -LiteralPath $reportPath -Raw|ConvertFrom-Json
    if($receipt.RequestId -cne $Plan.RequestId -or $receipt.RunId -cne $report.RunId -or $report.RunId -notmatch '^[a-fA-F0-9]{32}$' -or [IO.Path]::GetFileName($reportPath) -cne ($report.RunId+'.json')){throw 'NativeRunId or RequestId mismatch.'}
    foreach($value in @($receipt,$report)){foreach($name in @('TaskId','WorkflowId','QaWorkflowId')){if($value.PSObject.Properties.Name -contains $name -and $value.$name -cne $Plan.$name){throw "Result $name mismatch."}};if($value.PSObject.Properties.Name -contains 'NativeRunId' -and $value.NativeRunId -cne $report.RunId){throw 'NativeRunId mismatch.'}}
    if($receipt.Status -cne 'Passed' -or $report.Status -cne 'Passed' -or $report.RollbackStatus -cne 'RolledBack' -or @($report.Errors).Count -or !$report.Assertions -or @($report.Assertions|Where-Object {$_.Passed -isnot [bool] -or !$_.Passed}).Count){throw 'Failed report: Passed, RolledBack, successful assertions and no errors are required.'}
    if($report.TestId -cne $Plan.Context.TestId -or $report.DocumentPath -ine $Plan.ModelPath -or $report.FixtureId -cne $Plan.Context.FixtureId -or $report.FixtureSha256 -ine $Plan.Context.FixtureSha256 -or $report.AssemblyIdentity.Sha256 -ine $Plan.Context.ArtifactSha256){throw 'Report model, fixture, artifact or test identity mismatch.'}
    if([DateTimeOffset]::Parse($report.StartedUtc) -lt [DateTimeOffset]::Parse($request.createdUtc) -or [DateTimeOffset]::Parse($report.FinishedUtc) -lt [DateTimeOffset]::Parse($report.StartedUtc) -or [DateTimeOffset]::Parse($report.FinishedUtc) -gt [DateTimeOffset]::UtcNow.AddSeconds(5)){throw 'Report is stale or has invalid timestamps.'}
    if([DateTimeOffset]::Parse($report.FinishedUtc) -gt [DateTimeOffset]::Parse($request.expiresUtc)){throw 'Report completed after request expiry.'}
    foreach($pair in @(@($Plan.ModelPath,$Plan.Context.FixtureSha256),@($Plan.Context.SourceFixturePath,$Plan.Context.FixtureSha256),@($Plan.SidecarPath,$Plan.SidecarSha256),@($Plan.InstalledDll,$Plan.Context.ArtifactSha256),@($Plan.InstalledManifest,$Plan.QaRunnerManifestSha256),@($Plan.Context.ManifestPath,$Plan.Context.ManifestSha256),@($Plan.Context.ArtifactPath,$Plan.Context.ArtifactSha256))){if((Get-TaraSha256 $pair[0]) -ine $pair[1]){throw 'Post-run evidence hash mismatch.'}}
    $repoRoot=[IO.Path]::GetDirectoryName($Plan.Context.QaRoot)
    Assert-ReportedAddinIsolation $Plan.Isolation $report.AddinIsolation
    # Existing runner verifier supplies workflow-specific assertions and input checks.
    if((Get-TaraSha256 $Plan.VerifierPath) -ine $Plan.VerifierSha256){throw 'Runner verifier changed since preflight.'}
    & $Plan.VerifierPath -Action Verify -ReceiptPath $Plan.ResultPath 6>$null | Out-Null
    if((Get-TaraSha256 $reportPath) -ine $reportHash){throw 'Report changed during verification.'}
    [pscustomobject]@{ReportPath=$reportPath;ReportSha256=$reportHash;NativeRunId=$report.RunId;ResultSha256=(Get-TaraSha256 $Plan.ResultPath)}
}
function Invoke-TaraRevitQa {
    param([Parameter(Mandatory)]$Plan,[switch]$DryRun)
    if($DryRun){
        return [pscustomobject]@{
            Success=$true;Status='DryRun';Mode='DryRun';Error=$null
            Command=$Plan.Command;RequestPath=$Plan.RequestPath;ResultPath=$Plan.ResultPath
            ExecutablePath=$Plan.Executable;ModelPath=$Plan.ModelPath;QaAddinRoot=$Plan.QaAddinRoot;ArtifactManifestPath=$Plan.ArtifactManifestPath;ArtifactManifestSha256=$Plan.ArtifactManifestSha256;QaRunnerManifestPath=$Plan.QaRunnerManifestPath;QaRunnerManifestSha256=$Plan.QaRunnerManifestSha256
            EnvironmentVariable=$Plan.EnvironmentVariable;EnvironmentValue=$Plan.RequestPath
            ValidationResults=[pscustomobject]@{FixtureId=$Plan.Context.FixtureId;FixtureSha256=$Plan.Context.FixtureSha256;ArtifactSha256=$Plan.Context.ArtifactSha256;ManifestSha256=$Plan.Context.ManifestSha256;PolicySha256=$Plan.Isolation.PolicySha256;Validated=$true}
            SideEffectsPerformed=$false;ProcessStarted=$false;ProcessId=$null;ExitCode=$null
        }
    }
    Assert-TaraInteractiveSession
    $result=[ordered]@{Success=$false;Mode='Real';Status='Failed';TaskId=$Plan.TaskId;WorkflowId=$Plan.WorkflowId;QaWorkflowId=$Plan.QaWorkflowId;RunId=$Plan.RunId;RequestId=$Plan.RequestId;RequestPath=$Plan.RequestPath;ResultPath=$Plan.ResultPath;EvidencePath=$Plan.EvidencePath;ReportPath=$null;ReportSha256=$null;NativeRunId=$null;ResultSha256=$null;RequestSha256=$null;ModelPath=$Plan.ModelPath;SidecarPath=$Plan.SidecarPath;SidecarSha256=$Plan.SidecarSha256;FixtureId=$Plan.Context.FixtureId;FixtureSha256=$Plan.Context.FixtureSha256;ArtifactPath=$Plan.InstalledDll;ArtifactSha256=$Plan.Context.ArtifactSha256;ArtifactManifestPath=$Plan.ArtifactManifestPath;ArtifactManifestSha256=$Plan.ArtifactManifestSha256;QaRunnerManifestPath=$Plan.QaRunnerManifestPath;QaRunnerManifestSha256=$Plan.QaRunnerManifestSha256;ManifestPath=$Plan.InstalledManifest;ManifestSha256=$Plan.QaRunnerManifestSha256;ExecutableSha256=$Plan.ExecutableSha256;PolicySha256=$Plan.Isolation.PolicySha256;Command=$Plan.Command;EnvironmentVariable=$Plan.EnvironmentVariable;EnvironmentValue=$Plan.RequestPath;ModelSha256=$Plan.Context.FixtureSha256;ProcessStarted=$false;ProcessId=$null;ProcessStartUtc=$null;ProcessEndUtc=$null;StartedUtc=[DateTimeOffset]::UtcNow.ToString('O');FinishedUtc=$null;ExitState='NotStarted';ExitCode=$null;FailureReason=$null;Error=$null;SideEffectsPerformed=$false}
    $process=$null
    try{
        # Revalidate the filesystem immediately before writing/launching; a dry plan is not authorization.
        $args=@{};foreach($name in @('StoreRoot','TaskId','WorkflowId','QaWorkflowId','RunId','ModelPath','SidecarPath','ReportDirectory','RevitInstallDir','QaAddinRoot','TimeoutSeconds','Context')){$args[$name]=$Plan.$name};$fresh=New-TaraRevitQaPlan @args
        if($fresh.ExecutableSha256 -ine $Plan.ExecutableSha256 -or $fresh.SidecarSha256 -ine $Plan.SidecarSha256 -or $fresh.Isolation.PolicySha256 -ine $Plan.Isolation.PolicySha256 -or $fresh.VerifierSha256 -ine $Plan.VerifierSha256){throw 'Preflight evidence changed before launch.'}
        $request=[ordered]@{requestId=$Plan.RequestId;testId=$Plan.Context.TestId;modelPath=$Plan.ModelPath;assemblySha256=$Plan.Context.ArtifactSha256;createdUtc=$result.StartedUtc;expiresUtc=[DateTimeOffset]::UtcNow.AddSeconds($Plan.TimeoutSeconds).ToString('O');addinIsolation=$Plan.Isolation;TaskId=$Plan.TaskId;WorkflowId=$Plan.WorkflowId;QaWorkflowId=$Plan.QaWorkflowId;RunId=$Plan.RunId}
        Write-TaraJsonNew $Plan.RequestPath $request;$result.SideEffectsPerformed=$true;$result.RequestSha256=Get-TaraSha256 $Plan.RequestPath
        $process=Start-TaraProcess $Plan;$result.ProcessStarted=$true;$result.ProcessId=$process.Id;$result.ProcessStartUtc=$process.StartTime.ToUniversalTime().ToString('O');$result.ExitState='Running'
        Wait-TaraResult $Plan $process
        if((Get-TaraSha256 $Plan.RequestPath) -ine $result.RequestSha256){throw 'Request changed during execution.'}
        $observed=Get-Content -LiteralPath $Plan.ResultPath -Raw|ConvertFrom-Json
        $result.ResultSha256=Get-TaraSha256 $Plan.ResultPath
        $result.ReportPath=Assert-TaraPath $observed.ReportPath $Plan.ReportDirectory -Leaf
        $result.ReportSha256=Get-TaraSha256 $result.ReportPath
        $result.NativeRunId=$observed.RunId
        $verified=Assert-TaraResult $Plan
        foreach($name in @('ReportPath','ReportSha256','NativeRunId','ResultSha256')){$result[$name]=$verified.$name};$result.Status='Passed'
    }catch{$result.FailureReason=$_.Exception.Message;$result.Error=$_.Exception.Message;if($_.Exception -is [TimeoutException]){$result.Status='TimedOut'}}
    finally{
        $result.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('O');$result.Success=($result.Status -ceq 'Passed')
        if($process){try{$cleanup=Close-TaraOwnedProcess $process;if($cleanup.Forced){$result.ExitState='ForceTerminated';$result.FailureReason=([string]$result.FailureReason+' Graceful Revit close timed out; bridge-owned process force-terminated.')}else{$result.ExitState='Exited'};$result.ExitCode=$cleanup.ExitCode;$process.Refresh();$result.ProcessEndUtc=$process.ExitTime.ToUniversalTime().ToString('O');Assert-TaraModelUnlocked $Plan.ModelPath}catch{$result.ExitState='CleanupFailed';$result.FailureReason=([string]$result.FailureReason+' Cleanup failed: '+$_.Exception.Message);$result.Error=$result.FailureReason};$process.Dispose()}
        $result.SideEffectsPerformed=$true
        try{Write-TaraJsonNew $Plan.EvidencePath ([pscustomobject]$result)}catch{$result.FailureReason=([string]$result.FailureReason+' Evidence persistence failed: '+$_.Exception.Message);$result.Status='Failed'}
    }
    [pscustomobject]$result
}
Export-ModuleMember -Function New-TaraRevitQaPlan,Invoke-TaraRevitQa
