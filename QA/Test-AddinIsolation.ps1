# Non-Revit regression checks. Every mutation stays in a new TEMP directory.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Invoke-CreateLevelsQA.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($function in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]}, $false)) {
    Invoke-Expression $function.Extent.Text
}
. (Join-Path $PSScriptRoot 'AddinIsolation.ps1')
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('Repato-IsolationChecks-' + [Guid]::NewGuid().ToString('N'))
$machine = Join-Path $scratch 'machine'
$user = Join-Path $scratch 'user'
$qa = Join-Path $scratch 'QA'
foreach ($directory in @($machine,$user,$qa)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
$approvedPath = Join-Path $machine 'Reviewed.addin'
[IO.File]::WriteAllText($approvedPath, '<RevitAddIns/>')
$policyPath = Join-Path $qa 'MachineWideAddins.allowlist.json'
$entry = @{path=$approvedPath; sha256=(Get-Sha256 $approvedPath); reviewReason='Synthetic approval'}
$policy = @{schemaVersion=1; machineWideRoot=$machine; approvedMachineWideManifests=@($entry)}
$policy | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $policyPath -Encoding UTF8
$policyText = Get-Content -LiteralPath $policyPath -Raw
$checks = 0
function Inspect { Get-AddinIsolationInventory -PolicyPath $policyPath -MachineRoot $machine -UserRoot $user -QaSourceRoot $qa }
function Check([string]$Name, [bool]$Condition) {
    if (!$Condition) { throw "FAILED: $Name" }; $script:checks++; Write-Host "PASS: $Name"
}
$result = Inspect
Check 'reviewed exact path and hash accepted (UTF8 BOM policy)' ($result.Allowed -and $result.DetectedAddins.Count -eq 1 -and $result.DetectedAddins[0].Allowlisted)
$unknown = Join-Path $machine 'Unknown.addin'
[IO.File]::WriteAllText($unknown, '<RevitAddIns/>')
$result = Inspect
Check 'unknown machine manifest blocked and recorded' (!$result.Allowed -and $result.DetectedAddins.Count -eq 2 -and @($result.DetectedAddins | Where-Object {!$_.Allowlisted}).Count -eq 1)
# Rename temporary test inputs out of .addin registration; no installed manifests are touched.
Move-Item -LiteralPath $unknown -Destination ($unknown + '.test-disabled')
[IO.File]::WriteAllText($approvedPath, '<changed/>')
Check 'changed approved manifest blocked' (!(Inspect).Allowed)
[IO.File]::WriteAllText($approvedPath, '<RevitAddIns/>')
$userCopy = Join-Path $user 'Reviewed.addin'
Copy-Item -LiteralPath $approvedPath -Destination $userCopy
Check 'approved machine name copied to user profile remains blocked' (!(Inspect).Allowed)
Move-Item -LiteralPath $userCopy -Destination ($userCopy + '.test-disabled')
$qaName = 'Repato.CreateLevels.TestRunner.addin'
$bubbleName = 'Repato.GridBubbleVisibility.TestRunner.addin'
$offsetName = 'Repato.GridBubbleOffset.TestRunner.addin'
$resequenceName = 'Repato.GridResequence.TestRunner.addin'
$welcomeName = 'Repato.WelcomeSmoke.TestRunner.addin'
[IO.File]::WriteAllText((Join-Path $qa $qaName), '<qa/>')
Copy-Item -LiteralPath (Join-Path $qa $qaName) -Destination (Join-Path $user $qaName)
Check 'repository QA bootstrap exact hash accepted' ((Inspect).Allowed)
[IO.File]::WriteAllText((Join-Path $user $qaName), '<not-qa/>')
Check 'QA filename with changed content blocked' (!(Inspect).Allowed)
Copy-Item -LiteralPath (Join-Path $qa $qaName) -Destination (Join-Path $user $qaName) -Force
[IO.File]::WriteAllText((Join-Path $qa $bubbleName), '<bubble-qa/>')
Copy-Item -LiteralPath (Join-Path $qa $bubbleName) -Destination (Join-Path $user $bubbleName)
Check 'Grid Bubble repository manifest exact hash accepted' ((Inspect).Allowed -and @((Inspect).DetectedAddins | Where-Object {$_.Path -like ('*' + $bubbleName) -and $_.Allowlisted}).Count -eq 1)
[IO.File]::WriteAllText((Join-Path $qa $offsetName), '<offset-qa/>')
Copy-Item -LiteralPath (Join-Path $qa $offsetName) -Destination (Join-Path $user $offsetName)
Check 'Grid Bubble Offset repository manifest exact hash accepted' ((Inspect).Allowed -and @((Inspect).DetectedAddins | Where-Object {$_.Path -like ('*' + $offsetName) -and $_.Allowlisted}).Count -eq 1)
[IO.File]::WriteAllText((Join-Path $qa $resequenceName), '<resequence-qa/>')
Copy-Item -LiteralPath (Join-Path $qa $resequenceName) -Destination (Join-Path $user $resequenceName)
Check 'Grid Resequence repository manifest exact hash accepted' ((Inspect).Allowed -and @((Inspect).DetectedAddins | Where-Object {$_.Path -like ('*' + $resequenceName) -and $_.Allowlisted}).Count -eq 1)
[IO.File]::WriteAllText((Join-Path $qa $welcomeName), '<welcome-qa/>')
Copy-Item -LiteralPath (Join-Path $qa $welcomeName) -Destination (Join-Path $user $welcomeName)
Check 'Welcome Smoke repository manifest exact hash accepted' ((Inspect).Allowed -and @((Inspect).DetectedAddins | Where-Object {$_.Path -like ('*' + $welcomeName) -and $_.Allowlisted}).Count -eq 1)
$emptyUser = Join-Path $scratch 'empty-user'
New-Item -ItemType Directory -Path $emptyUser -Force | Out-Null
$emptyMachine = Join-Path $scratch 'empty-machine'; New-Item -ItemType Directory -Path $emptyMachine -Force | Out-Null
$zero = Get-AddinIsolationInventory -PolicyPath $policyPath -MachineRoot $emptyMachine -UserRoot $emptyUser -QaSourceRoot $qa
Check 'zero detected manifests returns an array' ($zero.DetectedAddins -is [Array])
$oneUser = Join-Path $scratch 'one-user'; New-Item -ItemType Directory -Path $oneUser -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $qa $qaName) -Destination (Join-Path $oneUser $qaName)
$one = Get-AddinIsolationInventory -PolicyPath $policyPath -MachineRoot $machine -UserRoot $oneUser -QaSourceRoot $qa
Check 'one detected manifest returns an array' ($one.DetectedAddins -is [Array] -and $one.DetectedAddins.Count -eq 2)
foreach ($case in @('wildcard','duplicate','outside root','bad hash','bad schema','invalid json')) {
    $changed = $policyText | ConvertFrom-Json
    switch ($case) {
        'wildcard' { $changed.approvedMachineWideManifests[0].path = Join-Path $machine '*.addin' }
        'duplicate' { $changed.approvedMachineWideManifests = @($changed.approvedMachineWideManifests[0],$changed.approvedMachineWideManifests[0]) }
        'outside root' { $changed.approvedMachineWideManifests[0].path = Join-Path $user 'Reviewed.addin' }
        'bad hash' { $changed.approvedMachineWideManifests[0].sha256 = 'invalid' }
        'bad schema' { $changed.schemaVersion = 2 }
    }
    if ($case -eq 'invalid json') { '{bad' | Set-Content -LiteralPath $policyPath }
    else { $changed | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $policyPath -Encoding UTF8 }
    $result = Inspect
    Check ($case + ' policy rejected with complete inventory') (!$result.Allowed -and $result.Errors.Count -gt 0 -and $result.DetectedAddins.Count -eq 6)
}
Move-Item -LiteralPath $policyPath -Destination ($policyPath + '.missing')
Check 'missing policy fails closed' (!(Inspect).Allowed)
$policyText | Set-Content -LiteralPath $policyPath -Encoding UTF8
$missing = Get-AddinIsolationInventory -PolicyPath $policyPath -MachineRoot $machine -UserRoot (Join-Path $scratch 'missing-user') -QaSourceRoot $qa
Check 'missing registration directory fails closed' (!$missing.Allowed -and $missing.Errors.Count -gt 0)
Write-Host "$checks PowerShell isolation checks passed. Synthetic files retained in $scratch"
