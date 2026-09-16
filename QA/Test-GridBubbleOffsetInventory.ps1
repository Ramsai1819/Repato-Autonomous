# Exercise the controller's actual preflight function and call site without starting Revit.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Invoke-GridBubbleOffsetQA.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($f in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) { Invoke-Expression $f.Extent.Text }
. (Join-Path $PSScriptRoot 'AddinIsolation.ps1')
$collector = ${function:Get-AddinIsolationInventory}
$repoRoot=Join-Path ([IO.Path]::GetTempPath()) ('OffsetInventory-'+[guid]::NewGuid().ToString('N'))
$reportsRoot=Join-Path $repoRoot 'QA\Reports'; $runsRoot=Join-Path $repoRoot 'QA\TestRuns'
$machine=Join-Path $repoRoot 'machine'; $addinsRoot=Join-Path $repoRoot 'user'
foreach ($dir in @($reportsRoot,$runsRoot,$machine,$addinsRoot)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$Action='Run'
$assignment=$ast.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$testId'},$true)
Invoke-Expression $assignment.Extent.Text
$source=Get-Content (Join-Path $PSScriptRoot '..\TestRunner\GridBubbleOffsetTestCommand.cs') -Raw
if ($source -notmatch ('SupportedTestId\s*=\s*"'+[regex]::Escape($testId)+'"')) { throw 'Controller/native test ID mismatch' }
$call=$ast.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$isolation' -and $n.Extent.Text.Contains('Invoke-OffsetIsolationPreflight')},$true)
if (!$call) { throw 'Controller preflight call missing' }
$invoke=$call.Extent.Text.Replace("'C:\ProgramData\Autodesk\Revit\Addins\2025'", '$machine')
@{schemaVersion=1;machineWideRoot=$machine;approvedMachineWideManifests=@()} | ConvertTo-Json | Set-Content (Join-Path $repoRoot 'QA\MachineWideAddins.allowlist.json') -Encoding UTF8
$checks=1
foreach ($count in 0..2) {
    if ($count -gt 0) {
        $name=@('Repato.GridBubbleOffset.TestRunner.addin','Repato.GridBubbleVisibility.TestRunner.addin')[$count-1]
        Copy-Item (Join-Path $PSScriptRoot $name) (Join-Path $repoRoot ('QA\'+$name))
        Copy-Item (Join-Path $PSScriptRoot $name) (Join-Path $addinsRoot $name)
    }
    $isolationReportPath=Join-Path $reportsRoot "count-$count.json"
    Invoke-Expression $invoke
    $roundtrip=$isolation | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    if (@($isolation).Count -ne 1 -or $isolation.DetectedAddins -isnot [Array] -or $isolation.Errors -isnot [Array] -or
        $roundtrip.DetectedAddins.Count -ne $count -or $roundtrip.Errors.Count -ne 0 -or !$roundtrip.Allowed) { throw "Wrong inventory shape for $count" }
    $checks++; Write-Host "PASS actual Offset preflight with $count manifests"
}
$valid=$isolation
foreach ($case in @('empty-output','extra-output','missing-property','scalar-array','blocked','collector-error')) {
    $script:scenario=$case; $script:validInventory=$valid
    function Get-AddinIsolationInventory {
        switch ($script:scenario) {
            'empty-output' { return }
            'extra-output' { 'unexpected output'; $script:validInventory }
            'missing-property' { [pscustomobject]@{Allowed=$true} }
            'scalar-array' { [pscustomobject]@{Allowed=$true;DetectedAddins='invalid';Errors=@();PolicyPath='x';PolicySha256='x'} }
            'blocked' { [pscustomobject]@{Allowed=$false;DetectedAddins=@();Errors=@('inaccessible manifest');PolicyPath='x';PolicySha256='x'} }
            'collector-error' { throw 'synthetic read failure' }
        }
    }
    $isolationReportPath=Join-Path $reportsRoot "$case.json"
    $rejected=$false
    try { Invoke-Expression $invoke } catch { $rejected=$_.Exception.Message.Contains($isolationReportPath) }
    $diagnostic=Get-Content $isolationReportPath -Raw | ConvertFrom-Json
    if (!$rejected -or $diagnostic.Status -ne 'Blocked' -or !$diagnostic.Error) { throw "Did not fail closed: $case" }
    $checks++; Write-Host "PASS blocked diagnostic: $case"
}
${function:Get-AddinIsolationInventory}=$collector
# A native failure before inventory collection must retain its real error and report.
$requestPath=Join-Path $runsRoot 'grid-bubble-offset.request.json'
$reportPath=Join-Path $reportsRoot 'native-failure.json'
'{}' | Set-Content $requestPath
@{Status='Failed';Errors=@('Unknown test ID.');AddinIsolation=$null} | ConvertTo-Json | Set-Content $reportPath
@{Status='Failed';ReportPath=$reportPath} | ConvertTo-Json | Set-Content ($requestPath+'.result.json')
$hash=(Get-FileHash $reportPath).Hash
$rejected=$false
try { Verify-Result ($requestPath+'.result.json') } catch { $rejected=$_.Exception.Message.Contains('Unknown test ID.') -and $_.Exception.Message.Contains($reportPath) }
if (!$rejected -or (Get-FileHash $reportPath).Hash -ne $hash) { throw 'Native failure was masked or changed' }
$checks++
Write-Host "$checks Offset inventory invocation checks passed; evidence: $reportsRoot"
