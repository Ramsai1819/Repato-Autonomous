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
$testId = 'grid-resequence-all-directions-v1'
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
    foreach ($request in @(Get-ChildItem -LiteralPath $runsRoot -Filter 'grid-resequence.request.json' -File -Recurse -ErrorAction SilentlyContinue)) {
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

function Invoke-OffsetIsolationPreflight {
    param([string]$PolicyPath, [string]$MachineRoot, [string]$UserRoot, [string]$QaSourceRoot, [string]$DiagnosticPath)
    $DiagnosticPath = Assert-ChildPath $DiagnosticPath $reportsRoot
    $outputs = @()
    $inventory = $null
    $failure = $null
    try {
        $outputs = @(Get-AddinIsolationInventory -PolicyPath $PolicyPath -MachineRoot $MachineRoot -UserRoot $UserRoot -QaSourceRoot $QaSourceRoot)
        if ($outputs.Count -ne 1) { throw "Expected exactly one inventory object; received $($outputs.Count)." }
        $inventory = $outputs[0]
        if ($null -eq $inventory -or $inventory -isnot [pscustomobject]) { throw 'Inventory output is not a PSCustomObject.' }
        foreach ($property in @('DetectedAddins', 'Errors', 'Allowed', 'PolicyPath', 'PolicySha256')) {
            if ($inventory.PSObject.Properties.Name -notcontains $property) { throw "Inventory is missing property: $property" }
        }
        if ($inventory.DetectedAddins -isnot [Array] -or $inventory.Errors -isnot [Array] -or $inventory.Allowed -isnot [bool]) {
            throw 'Inventory requires array-valued DetectedAddins and Errors and a Boolean Allowed.'
        }
        if (!$inventory.Allowed -or $inventory.Errors.Count -ne 0) { throw 'Add-in inventory is blocked; inspect its errors and manifest decisions.' }
        foreach ($item in $inventory.DetectedAddins) {
            if ($null -eq $item) { throw 'Null manifest record.' }
            foreach ($property in @('Scope', 'Path', 'Sha256', 'Allowlisted', 'Reason')) {
                if ($item.PSObject.Properties.Name -notcontains $property) { throw "Manifest record missing $property" }
            }
            if ($item.Allowlisted -isnot [bool] -or !$item.Allowlisted -or $item.Scope -notin @('MachineWide','UserProfile') -or
                $item.Sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw 'Blocked or malformed manifest record.' }
        }
    } catch { $failure = $_.Exception.Message }
    $shape = @($outputs | ForEach-Object {
        if ($null -eq $_) { @{ Type = '<null>'; Properties = @() } }
        else { @{ Type = $_.GetType().FullName; Properties = @($_.PSObject.Properties.Name) } }
    })
    @{ Phase = $Action; TestId = $testId; Status = $(if ($failure) { 'Blocked' } else { 'Allowed' });
        OutputCount = $outputs.Count; OutputShape = $shape; Error = $failure; AddinIsolation = $inventory;
        RecordedUtc = [DateTimeOffset]::UtcNow.ToString('O') } |
        ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $DiagnosticPath -Encoding UTF8
    if ($failure) { throw "Offset isolation blocked: $failure Report: $DiagnosticPath" }
    return $inventory
}

function Verify-Result([string]$Path) {
    $Path = Assert-ChildPath $Path $runsRoot
    if (!$Path.EndsWith('.request.json.result.json', [StringComparison]::Ordinal)) { throw 'Select a levels request receipt.' }
    $requestPath = $Path.Substring(0, $Path.Length - '.result.json'.Length)
    $request = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
    $receipt = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $reportPath = Assert-ChildPath $receipt.ReportPath $reportsRoot
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    if ($receipt.Status -cne 'Passed' -or $report.Status -cne 'Passed') {
        throw "Offset QA failed. Preserved report: $reportPath; receipt: $Path; native errors: $($report.Errors -join '; ')"
    }
    Assert-ReportedAddinIsolation $request.addinIsolation $report.AddinIsolation
    if ($request.testId -cne $testId -or $report.TestId -cne $testId -or $receipt.RequestId -cne $request.requestId -or $receipt.RunId -cne $report.RunId) {
        throw 'Run identity mismatch.'
    }
    $model = Assert-ChildPath $report.DocumentPath $runsRoot
    if ($model -ine $request.modelPath -or $report.FixtureId -cne 'GridResequenceEmpty' -or $report.AssemblyIdentity.Sha256 -ine $request.assemblySha256) {
        throw 'Model, fixture, or artifact identity mismatch.'
    }
    $required = @('addin-isolation', 'safety-gate', 'fixture-content-policy', 'fixture-orientation-counts',
        'vertical-left-to-right-names', 'vertical-left-to-right-geometry', 'vertical-left-to-right-unselected', 'vertical-left-to-right-secondary-A.1', 'vertical-left-to-right-rollback',
        'vertical-right-to-left-names', 'vertical-right-to-left-geometry', 'vertical-right-to-left-unselected', 'vertical-right-to-left-secondary-A.1', 'vertical-right-to-left-rollback',
        'horizontal-bottom-to-top-names', 'horizontal-bottom-to-top-geometry', 'horizontal-bottom-to-top-unselected', 'horizontal-bottom-to-top-decimal-3.2', 'horizontal-bottom-to-top-rollback',
        'horizontal-top-to-bottom-names', 'horizontal-top-to-bottom-geometry', 'horizontal-top-to-bottom-unselected', 'horizontal-top-to-bottom-decimal-3.2', 'horizontal-top-to-bottom-rollback',
        'special-3-3.2-family-order', 'all-cases-rolled-back')
    $failed = @($report.Assertions | Where-Object { $_.Passed -isnot [bool] -or $_.Passed -ne $true })
    if ($receipt.Status -cne 'Passed' -or $report.Status -cne 'Passed' -or $report.RollbackStatus -cne 'RolledBack' -or
        @($report.Errors).Count -ne 0 -or $failed.Count -ne 0) {
        throw "QA failed or incomplete. Inspect $reportPath"
    }
    if ($report.Inputs.VerticalStart -cne 'A' -or $report.Inputs.HorizontalStart -ne 1 -or
        ($report.Inputs.VerticalDirections -join '|') -cne 'Left to Right|Right to Left' -or
        ($report.Inputs.HorizontalDirections -join '|') -cne 'Bottom to Top|Top to Bottom') {
        throw 'Unexpected Grid Resequence inputs.'
    }
    foreach ($id in $required) {
        if (@($report.Assertions | Where-Object { $_.Id -ceq $id -and $_.Passed -eq $true }).Count -ne 1) {
            throw "Missing or duplicated assertion: $id"
        }
    }
    if ((Get-Sha256 $model) -ine $report.FixtureSha256 -or
        (Get-Sha256 (Join-Path $repoRoot 'QA\Fixtures\GridResequenceEmpty.rvt')) -ine $report.FixtureSha256) {
        throw 'Fixture or disposable file changed on disk.'
    }
    Write-Host "PASSED: $reportPath (Grid Resequence verified; rollback confirmed)."
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
$installedManifest = Join-Path $addinsRoot 'Repato.GridResequence.TestRunner.addin'
$builtDll = Assert-ChildPath (Join-Path $repoRoot 'bin\Release\net8.0-windows\Repato.Revit.dll') $repoRoot
$isolationReportPath = Assert-ChildPath (Join-Path $reportsRoot ('isolation-' + [Guid]::NewGuid().ToString('N') + '.json')) $reportsRoot
$isolation = Invoke-OffsetIsolationPreflight -PolicyPath (Join-Path $repoRoot 'QA\MachineWideAddins.allowlist.json') `
    -MachineRoot 'C:\ProgramData\Autodesk\Revit\Addins\2025' -UserRoot $addinsRoot -QaSourceRoot (Join-Path $repoRoot 'QA') -DiagnosticPath $isolationReportPath

if ($Action -eq 'Install') {
    if (!(Test-Path -LiteralPath $builtDll -PathType Leaf)) { throw 'Build the add-in first.' }
    New-Item -ItemType Directory -Path $deployRoot -Force | Out-Null
    foreach ($name in @('Repato.Revit.dll', 'Repato.Revit.deps.json', 'Repato.Revit.pdb')) {
        $source = Join-Path ([IO.Path]::GetDirectoryName($builtDll)) $name
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination (Join-Path $deployRoot $name) -Force }
    }
    Copy-Item -LiteralPath (Join-Path $repoRoot 'QA\Repato.GridResequence.TestRunner.addin') -Destination $installedManifest -Force
    if ((Get-Sha256 $builtDll) -ine (Get-Sha256 $installedDll)) { throw 'Deployment hash mismatch.' }
    Write-Host "Installed QA-only manifest and build: $installedDll"
    return
}

if (!(Test-Path -LiteralPath $installedManifest) -or (Get-Sha256 $builtDll) -ine (Get-Sha256 $installedDll)) { throw 'Install the current build before running QA.' }
if ((Get-Sha256 $installedManifest) -ine (Get-Sha256 (Join-Path $repoRoot 'QA\Repato.GridResequence.TestRunner.addin'))) { throw 'Installed QA manifest differs from source.' }
$fixture = Assert-ChildPath (Join-Path $repoRoot 'QA\Fixtures\GridResequenceEmpty.rvt') (Join-Path $repoRoot 'QA\Fixtures')
$provenance = Get-Content -LiteralPath (Join-Path $repoRoot 'QA\Fixtures\GridResequenceEmpty.provenance.json') -Raw | ConvertFrom-Json
$fixtureHash = Get-Sha256 $fixture
$approvedGridNames = @('1','2','3','3.2','4','A','A.1','B','C')
if ($provenance.fixtureId -cne 'GridResequenceEmpty' -or $fixtureHash -ine $provenance.sourceSha256 -or
    (@($provenance.requiredGridNames | Sort-Object) -join '|') -cne (@($approvedGridNames | Sort-Object) -join '|')) {
    throw 'Controlled fixture identity, hash, or approved grid declaration mismatch.'
}
Report-StaleRequests
$requestId = [Guid]::NewGuid().ToString('N')
$runDirectory = Assert-ChildPath (Join-Path $runsRoot ('grid-resequence-' + $requestId)) $runsRoot
New-Item -ItemType Directory -Path $runDirectory | Out-Null
$model = Join-Path $runDirectory 'model.rvt'
Copy-Item -LiteralPath $fixture -Destination $model
@{ fixtureId = 'GridResequenceEmpty'; sourceSha256 = $fixtureHash; requiredGridNames = $approvedGridNames } |
    ConvertTo-Json | Set-Content -LiteralPath ($model + '.fixture.json') -Encoding UTF8
$requestPath = Join-Path $runDirectory 'grid-resequence.request.json'
@{ requestId = $requestId; testId = $testId; modelPath = $model; assemblySha256 = (Get-Sha256 $installedDll);
    expiresUtc = [DateTimeOffset]::UtcNow.AddSeconds([Math]::Max($TimeoutSeconds, 900) + 300).ToString('O'); addinIsolation = $isolation } |
    ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $requestPath -Encoding UTF8
$resultPath = $requestPath + '.result.json'
$previousRequest = $env:REPATO_QA_GRID_RESEQUENCE_REQUEST
try {
    $env:REPATO_QA_GRID_RESEQUENCE_REQUEST = $requestPath
    $launchLog = $requestPath + '.launch.log'
    "$(Get-Date -Format o) Revit process launch requested; manifest=$installedManifest; dll=$installedDll; request=$requestPath; testId=$testId" | Set-Content -LiteralPath $launchLog -Encoding UTF8
    $process = Start-Process -FilePath 'E:\revit\Revit 2025\Revit.exe' -WindowStyle Hidden -PassThru
}
finally { $env:REPATO_QA_GRID_RESEQUENCE_REQUEST = $previousRequest }
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



