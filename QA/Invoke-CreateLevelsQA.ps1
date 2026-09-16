[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Install', 'Run', 'Verify')]
    [string]$Action,
    [string]$ReceiptPath,
    [ValidateRange(30, 900)]
    [int]$TimeoutSeconds = 900
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = 'C:\Repato-Autonomous\Source'
$runsRoot = Join-Path $repoRoot 'QA\TestRuns'
$reportsRoot = Join-Path $repoRoot 'QA\Reports'
$screenshotsRoot = Join-Path $repoRoot 'QA\Screenshots'
$testId = 'create-levels-elevations-v1'
. (Join-Path $PSScriptRoot 'AddinIsolation.ps1')

function Assert-ChildPath([string]$Path, [string]$Parent) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:\\' -or $Path.Substring(2).Contains(':')) {
        throw 'An absolute local path without alternate streams is required.'
    }
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = [IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    if (!$full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe path: $full" }
    if (([IO.DriveInfo]::new([IO.Path]::GetPathRoot($full))).DriveType -ne [IO.DriveType]::Fixed) { throw 'A fixed local drive is required.' }
    for ($part = $full; $part; $part = [IO.Path]::GetDirectoryName($part)) {
        if ((Test-Path -LiteralPath $part) -and ((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Reparse point rejected: $part"
        }
    }
    return $full
}

function Get-Sha256([string]$Path) {
    # The Revit process can still have the test file open when verification runs.
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '') }
    finally { $algorithm.Dispose(); $stream.Dispose() }
}

function Report-StaleRequests {
    $now = [DateTimeOffset]::UtcNow
    foreach ($request in @(Get-ChildItem -LiteralPath $runsRoot -Filter 'levels.request.json' -File -Recurse -ErrorAction SilentlyContinue)) {
        try {
            $data = Get-Content -LiteralPath $request.FullName -Raw | ConvertFrom-Json
            if ([DateTimeOffset]::Parse($data.expiresUtc) -lt $now) {
                $reportPath = Join-Path $reportsRoot ('stale-request-' + $request.Directory.Name + '.json')
                if (!(Test-Path -LiteralPath $reportPath)) {
                    @{Status='StaleRequestPreserved';RequestPath=$request.FullName;RequestId=$data.requestId;DetectedUtc=$now.ToString('O');Action='Preserved; fresh request created'} | ConvertTo-Json | Set-Content -LiteralPath $reportPath -Encoding UTF8
                }
            }
        } catch {
            $reportPath = Join-Path $reportsRoot ('stale-request-invalid-' + $request.Directory.Name + '.json')
            if (!(Test-Path -LiteralPath $reportPath)) {
                @{Status='InvalidRequestPreserved';RequestPath=$request.FullName;DetectedUtc=$now.ToString('O');Error=$_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath $reportPath -Encoding UTF8
            }
        }
    }
}

function Verify-Result([string]$Path) {
    $Path = Assert-ChildPath $Path $runsRoot
    if (!$Path.EndsWith('.request.json.result.json', [StringComparison]::Ordinal)) { throw 'Select a levels request receipt.' }
    $requestPath = $Path.Substring(0, $Path.Length - '.result.json'.Length)
    $request = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
    $receipt = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $reportPath = Assert-ChildPath $receipt.ReportPath $reportsRoot
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    Assert-ReportedAddinIsolation $request.addinIsolation $report.AddinIsolation
    if ($request.testId -cne $testId -or $report.TestId -cne $testId -or $receipt.RequestId -cne $request.requestId -or $receipt.RunId -cne $report.RunId) {
        throw 'Run identity mismatch.'
    }
    $model = Assert-ChildPath $report.DocumentPath $runsRoot
    if ($model -ine $request.modelPath -or $report.FixtureId -cne 'CreateLevelsEmpty' -or $report.AssemblyIdentity.Sha256 -ine $request.assemblySha256) {
        throw 'Model, fixture, or artifact identity mismatch.'
    }
    $required = @('addin-isolation', 'safety-gate', 'service-commit-observed', 'created-level-count', 'total-level-count', 'exact-created-names',
        'service-result', 'only-level-additions', 'no-preexisting-deletions-during-test',
        'baseline-levels-unchanged-during-test', 'baseline-levels-unchanged-after-rollback',
        'rollback-status', 'baseline-element-ids-restored', 'no-test-levels-after-rollback',
        'source-fixture-unchanged', 'disk-copy-unchanged', 'screenshot-before', 'screenshot-created', 'screenshot-rolled-back')
    foreach ($name in $report.Inputs.Names) { $required += 'elevation-' + $name }
    $failed = @($report.Assertions | Where-Object { $_.Passed -isnot [bool] -or $_.Passed -ne $true })
    if ($receipt.Status -cne 'Passed' -or $report.Status -cne 'Passed' -or $report.RollbackStatus -cne 'RolledBack' -or
        @($report.Errors).Count -ne 0 -or $failed.Count -ne 0 -or @($report.CreatedIds | Select-Object -Unique).Count -ne 3 -or
        @($report.Inputs.Names).Count -ne 3 -or @($report.Screenshots).Count -ne 3) {
        throw "QA failed or incomplete. Inspect $reportPath"
    }
    if (($report.Inputs.ElevationsMm -join ',') -cne '-1200,3450,7800' -or $report.Inputs.ElevationReference -cne 'Project' -or $report.Inputs.ToleranceMm -ne 0.1) {
        throw 'Unexpected level inputs.'
    }
    foreach ($id in $required) {
        if (@($report.Assertions | Where-Object { $_.Id -ceq $id -and $_.Passed -eq $true }).Count -ne 1) {
            throw "Missing or duplicated assertion: $id"
        }
    }
    foreach ($phase in @('before', 'created', 'rolled-back')) {
        $matches = @($report.Screenshots | Where-Object { $_.Phase -ceq $phase })
        if ($matches.Count -ne 1) { throw "Missing screenshot phase: $phase" }
        $png = Assert-ChildPath $matches[0].Path (Join-Path $screenshotsRoot $report.RunId)
        if ([IO.Path]::GetExtension($png) -ine '.png' -or (Get-Item -LiteralPath $png).Length -eq 0 -or
            (Get-Sha256 $png) -ine $matches[0].Sha256) { throw "Screenshot evidence invalid: $png" }
        $signature = [IO.File]::ReadAllBytes($png)
        if ($signature.Length -lt 8 -or ([BitConverter]::ToString($signature, 0, 8)) -cne '89-50-4E-47-0D-0A-1A-0A') {
            throw "Not a PNG screenshot: $png"
        }
    }
    if ((Get-Sha256 $model) -ine $report.FixtureSha256 -or
        (Get-Sha256 (Join-Path $repoRoot 'QA\Fixtures\CreateLevelsEmpty.rvt')) -ine $report.FixtureSha256) {
        throw 'Fixture or disposable file changed on disk.'
    }
    Write-Host "PASSED: $reportPath (three levels verified; rollback confirmed; three image hashes verified)."
}

if ($Action -eq 'Verify') {
    if (!$ReceiptPath) { throw '-ReceiptPath is required for Verify.' }
    Verify-Result $ReceiptPath
    return
}

if ($env:USERNAME -ine 'RepatoQA') { throw 'Install and Run must execute in the isolated RepatoQA Windows account.' }
if (Get-Process -Name Revit -ErrorAction SilentlyContinue) { throw 'Close Revit before installing or starting a fresh QA run.' }
$addinsRoot = Join-Path $env:APPDATA 'Autodesk\Revit\Addins\2025'
$deployRoot = Assert-ChildPath (Join-Path $addinsRoot 'RepatoQA') $env:APPDATA
$installedDll = Join-Path $deployRoot 'Repato.Revit.dll'
$installedManifest = Join-Path $addinsRoot 'Repato.CreateLevels.TestRunner.addin'
$builtDll = Assert-ChildPath (Join-Path $repoRoot 'bin\Release\net8.0-windows\Repato.Revit.dll') $repoRoot
$isolation = Get-AddinIsolationInventory -PolicyPath (Join-Path $repoRoot 'QA\MachineWideAddins.allowlist.json') `
    -MachineRoot 'C:\ProgramData\Autodesk\Revit\Addins\2025' -UserRoot $addinsRoot -QaSourceRoot (Join-Path $repoRoot 'QA')
$isolationReportPath = Assert-ChildPath (Join-Path $reportsRoot ('isolation-' + [Guid]::NewGuid().ToString('N') + '.json')) $reportsRoot
@{ Phase = $Action; TestId = $testId; Status = $(if ($isolation.Allowed) { 'Allowed' } else { 'Blocked' });
    AddinIsolation = $isolation; RecordedUtc = [DateTimeOffset]::UtcNow.ToString('O') } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $isolationReportPath -Encoding UTF8
if (!$isolation.Allowed) {
    throw "Add-in isolation blocked $Action. Inspect every detected manifest and its decision in $isolationReportPath"
}

if ($Action -eq 'Install') {
    if (!(Test-Path -LiteralPath $builtDll -PathType Leaf)) { throw 'Build the add-in first.' }
    New-Item -ItemType Directory -Path $deployRoot -Force | Out-Null
    foreach ($name in @('Repato.Revit.dll', 'Repato.Revit.deps.json', 'Repato.Revit.pdb')) {
        $source = Join-Path ([IO.Path]::GetDirectoryName($builtDll)) $name
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination (Join-Path $deployRoot $name) -Force }
    }
    Copy-Item -LiteralPath (Join-Path $repoRoot 'QA\Repato.CreateLevels.TestRunner.addin') -Destination $installedManifest -Force
    if ((Get-Sha256 $builtDll) -ine (Get-Sha256 $installedDll)) { throw 'Deployment hash mismatch.' }
    Write-Host "Installed QA-only manifest and build: $installedDll"
    return
}

if (!(Test-Path -LiteralPath $installedManifest) -or (Get-Sha256 $builtDll) -ine (Get-Sha256 $installedDll)) { throw 'Install the current build before running QA.' }
if ((Get-Sha256 $installedManifest) -ine (Get-Sha256 (Join-Path $repoRoot 'QA\Repato.CreateLevels.TestRunner.addin'))) { throw 'Installed QA manifest differs from source.' }
$fixture = Assert-ChildPath (Join-Path $repoRoot 'QA\Fixtures\CreateLevelsEmpty.rvt') (Join-Path $repoRoot 'QA\Fixtures')
$provenance = Get-Content -LiteralPath (Join-Path $repoRoot 'QA\Fixtures\CreateLevelsEmpty.provenance.json') -Raw | ConvertFrom-Json
$fixtureHash = Get-Sha256 $fixture
if ($provenance.fixtureId -cne 'CreateLevelsEmpty' -or $fixtureHash -ine $provenance.sourceSha256) { throw 'Controlled fixture hash mismatch.' }
Report-StaleRequests
$requestId = [Guid]::NewGuid().ToString('N')
$runDirectory = Assert-ChildPath (Join-Path $runsRoot ('create-levels-' + $requestId)) $runsRoot
New-Item -ItemType Directory -Path $runDirectory | Out-Null
$model = Join-Path $runDirectory 'model.rvt'
Copy-Item -LiteralPath $fixture -Destination $model
@{ fixtureId = 'CreateLevelsEmpty'; sourceSha256 = $fixtureHash } | ConvertTo-Json | Set-Content -LiteralPath ($model + '.fixture.json') -Encoding UTF8
$requestPath = Join-Path $runDirectory 'levels.request.json'
@{ requestId = $requestId; testId = $testId; modelPath = $model; assemblySha256 = (Get-Sha256 $installedDll);
    expiresUtc = [DateTimeOffset]::UtcNow.AddSeconds([Math]::Max($TimeoutSeconds, 900) + 300).ToString('O'); addinIsolation = $isolation } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $requestPath -Encoding UTF8
$resultPath = $requestPath + '.result.json'
$previousRequest = $env:REPATO_QA_LEVELS_REQUEST
try {
    $env:REPATO_QA_LEVELS_REQUEST = $requestPath
    $process = Start-Process -FilePath 'E:\revit\Revit 2025\Revit.exe' -WindowStyle Hidden -PassThru
}
finally { $env:REPATO_QA_LEVELS_REQUEST = $previousRequest }
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
try {
    while (!(Test-Path -LiteralPath $resultPath)) {
        if ($process.HasExited) { throw "Revit exited without a completed report. Preserve $runDirectory" }
        if ([DateTime]::UtcNow -ge $deadline) { throw "QA timeout. Revit PID $($process.Id) remains open; inspect dialogs and preserve $runDirectory. No automatic retry or process kill." }
        Start-Sleep -Seconds 1
        $process.Refresh()
    }
    Verify-Result $resultPath
}
catch {
    $controllerReport = Assert-ChildPath (Join-Path $reportsRoot ('controller-' + $requestId + '.json')) $reportsRoot
    @{ TestId = $testId; RequestId = $requestId; Status = 'Incomplete'; Error = $_.Exception.Message;
        ProcessId = $process.Id; ModelPath = $model; AddinIsolation = $isolation; FinishedUtc = [DateTimeOffset]::UtcNow.ToString('O') } |
        ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $controllerReport -Encoding UTF8
    throw
}
Write-Host 'Revit remains open on the disposable copy. Close without saving after reviewing evidence.'
Write-Output $resultPath
