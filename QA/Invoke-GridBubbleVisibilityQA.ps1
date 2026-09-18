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
$testId = 'grid-bubble-visibility-v1'
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
    foreach ($request in @(Get-ChildItem -LiteralPath $runsRoot -Filter 'grid-bubble.request.json' -File -Recurse -ErrorAction SilentlyContinue)) {
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
    if ($model -ine $request.modelPath -or $report.FixtureId -cne 'GridBubbleVisibilityEmpty' -or $report.AssemblyIdentity.Sha256 -ine $request.assemblySha256) {
        throw 'Model, fixture, or artifact identity mismatch.'
    }
    $required = @('addin-isolation', 'safety-gate', 'rollback-status') + @($report.Assertions | ForEach-Object Id)
    $failed = @($report.Assertions | Where-Object { $_.Passed -isnot [bool] -or $_.Passed -ne $true })
    if ($receipt.Status -cne 'Passed' -or $report.Status -cne 'Passed' -or $report.RollbackStatus -cne 'RolledBack' -or
        @($report.Errors).Count -ne 0 -or $failed.Count -ne 0) {
        throw "QA failed or incomplete. Inspect $reportPath"
    }
    if ($report.Inputs.SelectedGridCount -ne 2 -or $report.Inputs.UnselectedGridPolicy -cne 'unchanged' -or $report.Inputs.End0Visible -ne $false -or $report.Inputs.End1Visible -ne $true) {
        throw 'Unexpected Grid Bubble inputs.'
    }
    foreach ($id in $required) {
        if (@($report.Assertions | Where-Object { $_.Id -ceq $id -and $_.Passed -eq $true }).Count -ne 1) {
            throw "Missing or duplicated assertion: $id"
        }
    }
    if ((Get-Sha256 $model) -ine $report.FixtureSha256 -or
        (Get-Sha256 (Join-Path $repoRoot 'QA\Fixtures\GridBubbleVisibilityEmpty.rvt')) -ine $report.FixtureSha256) {
        throw 'Fixture or disposable file changed on disk.'
    }
    Write-Host "PASSED: $reportPath (Grid Bubble visibility verified; rollback confirmed)."
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
$installedManifest = Join-Path $addinsRoot 'Repato.GridBubbleVisibility.TestRunner.addin'
$builtDll = Assert-ChildPath (Join-Path $repoRoot 'bin\Release\net8.0-windows\Repato.Revit.dll') $repoRoot
$isolation = @(Get-AddinIsolationInventory -PolicyPath (Join-Path $repoRoot 'QA\MachineWideAddins.allowlist.json') `
    -MachineRoot 'C:\ProgramData\Autodesk\Revit\Addins\2025' -UserRoot $addinsRoot -QaSourceRoot (Join-Path $repoRoot 'QA'))
$isolation = $isolation | Select-Object -Last 1
if ($null -eq $isolation -or $isolation -is [Array] -or $isolation.PSObject.Properties.Name -notcontains 'DetectedAddins' -or $isolation.PSObject.Properties.Name -notcontains 'Errors') { throw 'Isolation inventory command did not return exactly one inventory object.' }
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
    Copy-Item -LiteralPath (Join-Path $repoRoot 'QA\Repato.GridBubbleVisibility.TestRunner.addin') -Destination $installedManifest -Force
    if ((Get-Sha256 $builtDll) -ine (Get-Sha256 $installedDll)) { throw 'Deployment hash mismatch.' }
    Write-Host "Installed QA-only manifest and build: $installedDll"
    return
}

if (!(Test-Path -LiteralPath $installedManifest) -or (Get-Sha256 $builtDll) -ine (Get-Sha256 $installedDll)) { throw 'Install the current build before running QA.' }
if ((Get-Sha256 $installedManifest) -ine (Get-Sha256 (Join-Path $repoRoot 'QA\Repato.GridBubbleVisibility.TestRunner.addin'))) { throw 'Installed QA manifest differs from source.' }
$fixture = Assert-ChildPath (Join-Path $repoRoot 'QA\Fixtures\GridBubbleVisibilityEmpty.rvt') (Join-Path $repoRoot 'QA\Fixtures')
$provenance = Get-Content -LiteralPath (Join-Path $repoRoot 'QA\Fixtures\GridBubbleVisibilityEmpty.provenance.json') -Raw | ConvertFrom-Json
$fixtureHash = Get-Sha256 $fixture
if ($provenance.fixtureId -cne 'GridBubbleVisibilityEmpty' -or $fixtureHash -ine $provenance.sourceSha256) { throw 'Controlled fixture hash mismatch.' }
Report-StaleRequests
$requestId = [Guid]::NewGuid().ToString('N')
$runDirectory = Assert-ChildPath (Join-Path $runsRoot ('grid-bubble-' + $requestId)) $runsRoot
New-Item -ItemType Directory -Path $runDirectory | Out-Null
$model = Join-Path $runDirectory 'model.rvt'
Copy-Item -LiteralPath $fixture -Destination $model
@{ fixtureId = 'GridBubbleVisibilityEmpty'; sourceSha256 = $fixtureHash; requiredGridNames = @('A','B','C','D','1','2','3','4') } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath ($model + '.fixture.json') -Encoding UTF8
$requestPath = Join-Path $runDirectory 'grid-bubble.request.json'
@{ requestId = $requestId; testId = $testId; modelPath = $model; assemblySha256 = (Get-Sha256 $installedDll);
    expiresUtc = [DateTimeOffset]::UtcNow.AddSeconds([Math]::Max($TimeoutSeconds, 900) + 300).ToString('O'); addinIsolation = $isolation } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $requestPath -Encoding UTF8
$resultPath = $requestPath + '.result.json'
$previousRequest = $env:REPATO_QA_GRID_BUBBLE_REQUEST
try {
    $env:REPATO_QA_GRID_BUBBLE_REQUEST = $requestPath
    $process = Start-Process -FilePath 'E:\revit\Revit 2025\Revit.exe' -WindowStyle Hidden -PassThru
}
finally { $env:REPATO_QA_GRID_BUBBLE_REQUEST = $previousRequest }
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

