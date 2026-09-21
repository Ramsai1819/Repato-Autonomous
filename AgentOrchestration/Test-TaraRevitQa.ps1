$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# All files are synthetic, unique temporary test inputs. No Revit executable is run.
$module = Import-Module (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Force -PassThru
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('repato-tara-regression-' + [guid]::NewGuid().ToString('N'))
$originalAppData = $env:APPDATA
$originalUserName = $env:USERNAME
$script:checkCount = 0
function Assert-Test([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
    $script:checkCount++
}
function Assert-Rejected([scriptblock]$Action, [string]$Pattern, [string]$Label) {
    $message = $null
    try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
    Assert-Test ($null -ne $message) "$Label was accepted."
    Assert-Test ($message -match $Pattern) "$Label returned the wrong rejection: $message"
}
function Write-TestJson([string]$Path, $Value) {
    $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding UTF8
}
function Get-TestSnapshot {
    @((Get-ChildItem -LiteralPath $testRoot -File -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $_.FullName + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    })) -join "`n"
}
try {
    $qa = Join-Path $testRoot 'QA'
    $userRoot = Join-Path $testRoot 'RepatoQA\Addins\2025'
    $machineRoot = Join-Path $testRoot 'MachineAddins'
    $runRoot = Join-Path $qa 'TestRuns\synthetic'
    $reports = Join-Path $qa 'Reports'
    $addinRoot = Join-Path $userRoot 'RepatoQA'
    $revitRoot = Join-Path $testRoot 'Revit 2025'
    foreach ($directory in @($runRoot,$reports,$addinRoot,$machineRoot,$revitRoot,(Join-Path $qa 'Fixtures'))) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $source = Join-Path $qa 'Fixtures\CreateLevelsEmpty.rvt'
    $model = Join-Path $runRoot 'model.rvt'
    $sidecar = $model + '.fixture.json'
    $manifest = Join-Path $qa 'Repato.CreateLevels.TestRunner.addin'
    $artifactManifest = Join-Path $qa 'manifest.addin'
    $installedManifest = Join-Path $userRoot 'Repato.CreateLevels.TestRunner.addin'
    $dll = Join-Path $addinRoot 'Repato.Revit.dll'
    Set-Content -LiteralPath $source -Value 'synthetic disposable fixture; not a Revit model'
    Copy-Item -LiteralPath $source -Destination $model
    Set-Content -LiteralPath $dll -Value 'synthetic DLL; never loaded'
    Set-Content -LiteralPath (Join-Path $revitRoot 'Revit.exe') 'synthetic executable; never launched'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\QA\Repato.CreateLevels.TestRunner.addin') -Destination $manifest
    Set-Content -LiteralPath $artifactManifest -Value 'Neil artifact manifest evidence; intentionally distinct from runner manifest'
    Copy-Item -LiteralPath $manifest -Destination $installedManifest
    $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    Write-TestJson $sidecar @{fixtureId='CreateLevelsEmpty';sourceSha256=$hash}
    $policy = Join-Path $qa 'MachineWideAddins.allowlist.json'
    Write-TestJson $policy @{schemaVersion=1;machineWideRoot=$machineRoot;approvedMachineWideManifests=@()}
    Set-Content -LiteralPath (Join-Path $qa 'Invoke-CreateLevelsQA.ps1') 'param($Action,$ReceiptPath)'
    $roots = [pscustomobject]@{QaRoot=$qa;UserAddinsRoot=$userRoot;MachineRoot=$machineRoot}
    & $module { param($roots) $script:testRoots=$roots; function script:Get-TaraRuntimeRoots { $script:testRoots }; function script:Assert-TaraInteractiveSession {}; function script:Assert-TaraRevitExecutableVersion {param($Path)} } $roots
    $context = [pscustomobject]@{QaRoot=$qa;SourceFixturePath=$source;FixtureId='CreateLevelsEmpty';FixtureSha256=$hash;
        TestId='create-levels-elevations-v1';ArtifactPath=$dll;ArtifactSha256=(Get-FileHash $dll).Hash;
        ManifestPath=$artifactManifest;ManifestSha256=(Get-FileHash $artifactManifest).Hash;TaskId='task-test';WorkflowId='workflow-test';QaWorkflowId='create-levels';RunId='run-test'}
    $parameters = @{StoreRoot=(Join-Path $testRoot 'store');TaskId='task-test';WorkflowId='workflow-test';QaWorkflowId='create-levels';RunId='run-test';
        ModelPath=$model;SidecarPath=$sidecar;ReportDirectory=$reports;RevitInstallDir=$revitRoot;QaAddinRoot=$addinRoot;TimeoutSeconds=1;Context=$context}
    & $module { function script:Start-TaraProcess { throw 'Regression attempted to start a real process.' } }
    $before = Get-TestSnapshot
    $plan = New-TaraRevitQaPlan @parameters -DryRun
    $dry = Invoke-TaraRevitQa -Plan $plan -DryRun
    Assert-Test (!$dry.SideEffectsPerformed -and $null -eq $dry.ProcessId) 'Dry-run process/side-effect contract failed.'
    Assert-Test ((Get-TestSnapshot) -ceq $before) 'Dry-run wrote or changed a file.'
    Assert-Test ($dry.Command -ceq ('"'+(Join-Path $revitRoot 'Revit.exe')+'"')) 'Dry-run command mismatch.'
    Assert-Test ([IO.Path]::GetFileName($plan.ArtifactManifestPath) -ceq 'manifest.addin' -and [IO.Path]::GetFileName($plan.QaRunnerManifestPath) -ceq 'Repato.CreateLevels.TestRunner.addin') 'Two-manifest selection was not preserved.'
    $bad=$parameters.Clone();$bad.QaWorkflowId='grid-bubble-visibility-v1'
    Assert-Rejected { New-TaraRevitQaPlan @bad -DryRun } 'Wrong workflow identity|Required file missing|startup class|fixture' 'Mismatched workflow runner'
    foreach ($case in @(@('ModelPath','missing.rvt','Required file missing','Missing fixture'),@('SidecarPath','missing.fixture.json','Required file missing','Missing sidecar'))) {
        $bad=$parameters.Clone();$bad[$case[0]]=Join-Path $runRoot $case[1]
        Assert-Rejected { New-TaraRevitQaPlan @bad -DryRun } $case[2] $case[3]
    }
    $bad=$parameters.Clone();$bad.WorkflowId='wrong-workflow'
    Assert-Rejected { New-TaraRevitQaPlan @bad -DryRun } 'Wrong workflow identity' 'Wrong workflow'
    $bad=$parameters.Clone();$bad.ModelPath=Join-Path $testRoot 'Production\project.rvt'
    Assert-Rejected { New-TaraRevitQaPlan @bad -DryRun } 'outside approved QA root' 'Production model'
    $bad=$parameters.Clone();$bad.QaAddinRoot=Join-Path $userRoot 'Repato'
    Assert-Rejected { New-TaraRevitQaPlan @bad -DryRun } 'Production add-in path' 'Production add-in folder'
    Move-Item -LiteralPath $installedManifest -Destination ($installedManifest+'.held')
    Assert-Rejected { New-TaraRevitQaPlan @parameters -DryRun } 'Required file missing' 'Missing QA manifest'
    Move-Item -LiteralPath ($installedManifest+'.held') -Destination $installedManifest
    $originalDll=[IO.File]::ReadAllBytes($dll);Add-Content -LiteralPath $dll 'tampered'
    Assert-Rejected { New-TaraRevitQaPlan @parameters -DryRun } 'hash mismatch' 'DLL hash mismatch'
    [IO.File]::WriteAllBytes($dll,$originalDll)
    $originalArtifactManifest=[IO.File]::ReadAllBytes($artifactManifest);Add-Content -LiteralPath $artifactManifest 'tampered'
    Assert-Rejected { New-TaraRevitQaPlan @parameters -DryRun } 'artifact-manifest hash mismatch' 'Artifact manifest hash mismatch'
    [IO.File]::WriteAllBytes($artifactManifest,$originalArtifactManifest)
    $originalRunnerManifest=[IO.File]::ReadAllBytes($installedManifest);Add-Content -LiteralPath $installedManifest 'tampered'
    Assert-Rejected { New-TaraRevitQaPlan @parameters -DryRun } 'QA runner manifest hash mismatch' 'QA runner manifest hash mismatch'
    [IO.File]::WriteAllBytes($installedManifest,$originalRunnerManifest)
    Write-TestJson $policy @{schemaVersion=1;machineWideRoot=$machineRoot;approvedMachineWideManifests=@(@{path=(Join-Path $machineRoot 'bad.addin');sha256='bad';reviewReason='invalid'})}
    Assert-Rejected { New-TaraRevitQaPlan @parameters -DryRun } 'allowlist rejected' 'Invalid allowlist entry'
    Write-TestJson $policy @{schemaVersion=1;machineWideRoot=$machineRoot;approvedMachineWideManifests=@()}
    # Exercise the production timeout loop and termination helper against inert process objects.
    $owned=[pscustomobject]@{Id=123456;StartTime=(Get-Date);ExitTime=(Get-Date);HasExited=$false;ExitCode=0;Kills=0;Disposed=$false}
    $owned|Add-Member ScriptMethod Refresh {}; $owned|Add-Member ScriptMethod Kill {$this.Kills++;$this.HasExited=$true}
    $owned|Add-Member ScriptMethod WaitForExit {param($milliseconds) return $true};$owned|Add-Member ScriptMethod Dispose {$this.Disposed=$true}
    $unrelated=[pscustomobject]@{Kills=0};$unrelated|Add-Member ScriptMethod Kill {$this.Kills++}
    & $module {param($owned) $script:testProcess=$owned;function script:Start-TaraProcess {param($Plan) $script:testProcess}} $owned
    $timeout=Invoke-TaraRevitQa -Plan $plan
    Assert-Test ($timeout.Status -ceq 'TimedOut') "Timeout status incorrect: $($timeout.FailureReason)"
    Assert-Test ($owned.Kills -eq 1 -and $unrelated.Kills -eq 0 -and $owned.Disposed) 'Timeout did not terminate only its owned process.'
    Assert-Test ($timeout.ProcessId -eq $owned.Id -and (Test-Path -LiteralPath $timeout.EvidencePath)) 'Timeout process/evidence missing.'
    Assert-Test ((Test-Path -LiteralPath $timeout.RequestPath) -and $timeout.RequestSha256) 'Timeout request was not preserved.'
    # Common native-result validation executes on real synthetic JSON; native verifier is an inert script.
    $plan=New-TaraRevitQaPlan @parameters -DryRun
    $verifier=Join-Path $qa 'synthetic-verifier.ps1';Set-Content -LiteralPath $verifier 'param($Action,$ReceiptPath)'
    $plan.VerifierPath=$verifier
    $native=[guid]::NewGuid().ToString('N');$reportPath=Join-Path $reports ($native+'.json')
    $request=@{TaskId=$plan.TaskId;WorkflowId=$plan.WorkflowId;QaWorkflowId=$plan.QaWorkflowId;RunId=$plan.RunId;requestId=$plan.RequestId;createdUtc=[DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('O');expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(1).ToString('O')}
    Write-TestJson $plan.RequestPath $request
    $report=[ordered]@{RunId=$native;TestId=$context.TestId;Status='Passed';RollbackStatus='RolledBack';Errors=@();Assertions=@(@{Id='synthetic';Passed=$true});
        DocumentPath=$model;FixtureId=$context.FixtureId;FixtureSha256=$hash;AssemblyIdentity=@{Sha256=$context.ArtifactSha256};AddinIsolation=$plan.Isolation;
        StartedUtc=[DateTimeOffset]::UtcNow.AddSeconds(-30).ToString('O');FinishedUtc=[DateTimeOffset]::UtcNow.AddSeconds(-1).ToString('O')}
    $receipt=@{RequestId=$plan.RequestId;RunId=$native;ReportPath=$reportPath;Status='Passed'}
    Write-TestJson $reportPath $report;Write-TestJson $plan.ResultPath $receipt
    $verified=& $module {param($p) Assert-TaraResult $p} $plan
    Assert-Test ($verified.NativeRunId -ceq $native -and $verified.ReportSha256 -ceq (Get-FileHash $reportPath).Hash) 'Valid native result rejected or wrong report hash.'
    $report.Status='Failed';Write-TestJson $reportPath $report
    Assert-Rejected { & $module {param($p) Assert-TaraResult $p} $plan } 'Failed report' 'Failed report'
    $report.Status='Passed';$report.RollbackStatus='Committed';Write-TestJson $reportPath $report
    Assert-Rejected { & $module {param($p) Assert-TaraResult $p} $plan } 'Failed report' 'Missing rollback'
    $report.RollbackStatus='RolledBack';$report.Errors=@('failure');Write-TestJson $reportPath $report
    Assert-Rejected { & $module {param($p) Assert-TaraResult $p} $plan } 'Failed report' 'Report errors'
    $report.Errors=@();Write-TestJson $reportPath $report
    foreach($identity in @('TaskId','WorkflowId','QaWorkflowId','RunId')) {
        $saved=$request[$identity];$request[$identity]='stale';Write-TestJson $plan.RequestPath $request
        Assert-Rejected { & $module {param($p) Assert-TaraResult $p} $plan } 'mismatched request' "Stale request $identity"
        $request[$identity]=$saved
    }
    Write-TestJson $plan.RequestPath $request
    $receipt.RunId=[guid]::NewGuid().ToString('N');Write-TestJson $plan.ResultPath $receipt
    Assert-Rejected { & $module {param($p) Assert-TaraResult $p} $plan } 'NativeRunId' 'Wrong native identity'
    $receipt.RunId=$native;Write-TestJson $plan.ResultPath $receipt
    Add-Content -LiteralPath $model 'changed'
    Assert-Rejected { & $module {param($p) Assert-TaraResult $p} $plan } 'hash mismatch' 'Post-run model hash'
    "Tara synthetic checks passed: $script:checkCount. No Revit launched. Test evidence: $testRoot"
} finally {
    $env:APPDATA=$originalAppData;$env:USERNAME=$originalUserName
    Remove-Module $module -ErrorAction SilentlyContinue
    # Preserve all synthetic evidence for inspection; never delete existing reports/fixtures.
}
