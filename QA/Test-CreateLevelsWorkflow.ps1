# Exercises the actual workflow functions using clearly synthetic data in TEMP.
# Does not load Revit, deploy an add-in, or create evidence in the real QA folders.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Invoke-CreateLevelsQA.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($function in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    Invoke-Expression $function.Extent.Text
}
. (Join-Path $PSScriptRoot 'AddinIsolation.ps1')
$repoRoot = Join-Path ([IO.Path]::GetTempPath()) ('Repato-Levels-WorkflowChecks-' + [Guid]::NewGuid().ToString('N'))
$runsRoot = Join-Path $repoRoot 'QA\TestRuns'
$reportsRoot = Join-Path $repoRoot 'QA\Reports'
$screenshotsRoot = Join-Path $repoRoot 'QA\Screenshots'
$testId = 'create-levels-elevations-v1'
$runId = [Guid]::NewGuid().ToString('N')
$runDirectory = Join-Path $runsRoot 'synthetic-run'
$fixtureDirectory = Join-Path $repoRoot 'QA\Fixtures'
foreach ($directory in @($runDirectory, $reportsRoot, $fixtureDirectory, (Join-Path $screenshotsRoot $runId))) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}
$model = Join-Path $runDirectory 'model.rvt'
[IO.File]::WriteAllText($model, 'SYNTHETIC VERIFIER INPUT; NOT A REVIT MODEL')
Copy-Item -LiteralPath $model -Destination (Join-Path $fixtureDirectory 'CreateLevelsEmpty.rvt')
$hash = Get-Sha256 $model
$requestId = [Guid]::NewGuid().ToString('N')
$requestPath = Join-Path $runDirectory 'levels.request.json'
$receiptPath = $requestPath + '.result.json'
$reportPath = Join-Path $reportsRoot ($runId + '.json')
$names = @('SYNTHETIC_LOW', 'SYNTHETIC_MID', 'SYNTHETIC_HIGH')
$assertionIds = @('addin-isolation','safety-gate','service-commit-observed','created-level-count','total-level-count','exact-created-names',
    'service-result','only-level-additions','no-preexisting-deletions-during-test',
    'baseline-levels-unchanged-during-test','baseline-levels-unchanged-after-rollback','rollback-status',
    'baseline-element-ids-restored','no-test-levels-after-rollback','source-fixture-unchanged','disk-copy-unchanged',
    'screenshot-before','screenshot-created','screenshot-rolled-back')
foreach ($name in $names) { $assertionIds += 'elevation-' + $name }
$screenshots = @(foreach ($phase in @('before','created','rolled-back')) {
    $path = Join-Path (Join-Path $screenshotsRoot $runId) ($phase + '.png')
    [IO.File]::WriteAllBytes($path, [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII='))
    @{ Phase = $phase; Path = $path; Sha256 = (Get-Sha256 $path) }
})
$policyPath = Join-Path $repoRoot 'QA\MachineWideAddins.allowlist.json'
'{"schemaVersion":1,"approvedMachineWideManifests":[]}' | Set-Content -LiteralPath $policyPath -Encoding UTF8
$inventory = @{PolicyPath=$policyPath; PolicySha256=(Get-Sha256 $policyPath); DetectedAddins=@(); Errors=@(); Allowed=$true}
$report = @{ RunId=$runId; TestId=$testId; Status='Passed'; RollbackStatus='RolledBack'; FixtureId='CreateLevelsEmpty'; AddinIsolation=$inventory;
    DocumentPath=$model; FixtureSha256=$hash; AssemblyIdentity=@{Sha256=$hash}; CreatedIds=@('101','102','103');
    Inputs=@{Names=$names; ElevationsMm=@(-1200,3450,7800); ElevationReference='Project'; ToleranceMm=0.1};
    Errors=@(); Screenshots=$screenshots; Assertions=@($assertionIds | ForEach-Object { @{Id=$_; Passed=$true} }) }
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8
@{requestId=$requestId; testId=$testId; modelPath=$model; assemblySha256=$hash; addinIsolation=$inventory} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $requestPath -Encoding UTF8
@{RequestId=$requestId; RunId=$runId; ReportPath=$reportPath; Status='Passed'} | ConvertTo-Json | Set-Content -LiteralPath $receiptPath -Encoding UTF8
$baselineJson = Get-Content -LiteralPath $reportPath -Raw
$passed = 0
${staleDir} = Join-Path $runsRoot 'stale-preserved'
New-Item -ItemType Directory -Path $staleDir -Force | Out-Null
$stalePath = Join-Path $staleDir 'levels.request.json'
@{requestId='stale-regression';expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(-5).ToString('O')} | ConvertTo-Json | Set-Content -LiteralPath $stalePath -Encoding UTF8
Report-StaleRequests
$staleReportPath = Join-Path $reportsRoot 'stale-request-stale-preserved.json'
if (!(Test-Path -LiteralPath $stalePath) -or !(Test-Path -LiteralPath $staleReportPath) -or (Get-Content -LiteralPath $stalePath -Raw) -notmatch 'stale-regression') { throw 'Expired request was not preserved and reported.' }
$passed++; Write-Host 'PASS: stale request preserved and reported'
Verify-Result $receiptPath
$passed++

function Expect-Rejection([string]$Label, [scriptblock]$Operation) {
    $rejected = $false
    try { & $Operation } catch { $rejected = $true }
    if (!$rejected) { throw "CHECK FAILED: $Label was accepted" }
    $script:passed++
    Write-Host "Rejected as expected: $Label"
}
Expect-Rejection 'sibling directory prefix' { Assert-ChildPath ($runsRoot + '-outside\model.rvt') $runsRoot }
Expect-Rejection 'directory traversal' { Assert-ChildPath (Join-Path $runsRoot '..\outside.rvt') $runsRoot }
Expect-Rejection 'UNC target' { Assert-ChildPath '\\server\share\model.rvt' $runsRoot }
Expect-Rejection 'alternate data stream' { Assert-ChildPath ($model + ':stream') $runsRoot }
foreach ($case in @('unknown test','failed assertion','missing rollback','wrong elevations','missing screenshot','wrong screenshot hash','wrong artifact','stale run','wrong model','missing inventory','blocked inventory','wrong policy hash','changed inventory')) {
    $changed = $baselineJson | ConvertFrom-Json
    switch ($case) {
        'unknown test' { $changed.TestId = 'unknown' }
        'failed assertion' { $changed.Assertions[0].Passed = $false }
        'missing rollback' { $changed.RollbackStatus = 'Required' }
        'wrong elevations' { $changed.Inputs.ElevationsMm = @(0,1,2) }
        'missing screenshot' { $changed.Screenshots = @($changed.Screenshots[0]) }
        'wrong screenshot hash' { $changed.Screenshots[0].Sha256 = ('0' * 64) }
        'wrong artifact' { $changed.AssemblyIdentity.Sha256 = ('0' * 64) }
        'stale run' { $changed.RunId = [Guid]::NewGuid().ToString('N') }
        'wrong model' { $changed.DocumentPath = Join-Path $runsRoot 'other.rvt' }
        'missing inventory' { $changed.AddinIsolation = $null }
        'blocked inventory' { $changed.AddinIsolation.Allowed = $false }
        'wrong policy hash' { $changed.AddinIsolation.PolicySha256 = ('0' * 64) }
        'changed inventory' { $changed.AddinIsolation.DetectedAddins = @(@{Scope='MachineWide';Path='C:\unexpected.addin';Sha256=$hash;Allowlisted=$true;Reason='Synthetic'}) }
    }
    $changed | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Expect-Rejection $case { Verify-Result $receiptPath }
}
Write-Host "$passed workflow checks passed. Synthetic data retained only in $repoRoot"
