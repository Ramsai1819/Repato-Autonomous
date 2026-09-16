$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$controllerPath = Join-Path $PSScriptRoot 'Invoke-WelcomeSmokeQA.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($controllerPath,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$wanted = @('Assert-ChildPath','Get-Sha256','Invoke-WelcomeIsolationPreflight')
foreach ($function in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) {
    if ($function.Name -in $wanted) { Invoke-Expression $function.Extent.Text }
}
if (@($wanted | Where-Object { !(Get-Command $_ -ErrorAction SilentlyContinue) }).Count) { throw 'Could not load Welcome isolation functions.' }

. (Join-Path $PSScriptRoot 'Foundation\QaRunner.Foundation.ps1')
. (Join-Path $PSScriptRoot 'AddinIsolation.ps1')
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('WelcomeIsolation-' + [guid]::NewGuid().ToString('N'))
$script:reportsRoot = Join-Path $scratch 'reports'
$machine = Join-Path $scratch 'machine'; $user = Join-Path $scratch 'user'; $qa = Join-Path $scratch 'QA'
foreach ($directory in @($reportsRoot,$machine,$user,$qa)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
$reviewed = Join-Path $machine 'Reviewed.addin'; [IO.File]::WriteAllText($reviewed,'<reviewed/>')
$policyPath = Join-Path $qa 'MachineWideAddins.allowlist.json'
@{schemaVersion=1;machineWideRoot=$machine;approvedMachineWideManifests=@(@{path=$reviewed;sha256=(Get-RepatoQaSha256 $reviewed);reviewReason='test'})} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $policyPath -Encoding UTF8
$welcomeName = 'Repato.WelcomeSmoke.TestRunner.addin'
[IO.File]::WriteAllText((Join-Path $qa $welcomeName),'<welcome/>')
Copy-Item -LiteralPath (Join-Path $qa $welcomeName) -Destination (Join-Path $user $welcomeName)
$reportPath = Join-Path $reportsRoot 'allowed.json'
$result = Invoke-WelcomeIsolationPreflight -PolicyPath $policyPath -MachineRoot $machine -UserRoot $user -QaSourceRoot $qa -DiagnosticPath $reportPath -Phase Run -IsolationTestId welcome-supervised-dialog-v1
$record = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
if (!$result.Allowed -or $result.PolicySha256 -notmatch '^[0-9A-F]{64}$' -or $result.DetectedAddins -isnot [Array] -or $result.Errors -isnot [Array]) { throw 'Returned isolation shape is invalid.' }
if (!$record.Allowed -or $record.PolicySha256 -ine $result.PolicySha256 -or @($record.DetectedAddins).Count -ne 2 -or @($record.Errors).Count -ne 0) { throw 'Complete allowed decision was not recorded.' }
$welcome = @($record.DetectedAddins | Where-Object { $_.Path -like ('*' + $welcomeName) })
if ($welcome.Count -ne 1 -or !$welcome[0].Allowlisted -or $welcome[0].Reason -cne 'Repository-owned QA manifest verified against source') { throw 'Welcome manifest did not use repository identity allowlisting.' }

[IO.File]::WriteAllText((Join-Path $user 'Unknown.addin'),'<unknown/>')
$blockedPath = Join-Path $reportsRoot 'blocked.json'
try { $null = Invoke-WelcomeIsolationPreflight -PolicyPath $policyPath -MachineRoot $machine -UserRoot $user -QaSourceRoot $qa -DiagnosticPath $blockedPath -Phase Run -IsolationTestId welcome-supervised-dialog-v1; throw 'Unknown add-in was accepted.' }
catch { if (!(Test-Path -LiteralPath $blockedPath)) { throw } }
$blocked = Get-Content -LiteralPath $blockedPath -Raw | ConvertFrom-Json
if ($blocked.Allowed -or $blocked.Status -cne 'Blocked' -or @($blocked.DetectedAddins | Where-Object { !$_.Allowlisted }).Count -ne 1) { throw 'Blocked decision lacks the unknown manifest evidence.' }
Write-Host 'Welcome controller isolation result-shape checks: 2 passed.'
