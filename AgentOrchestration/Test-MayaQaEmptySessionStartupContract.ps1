$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$runner = Get-Content -LiteralPath (Join-Path $repo 'TestRunner\CreatePlanViewsQaApplication.cs') -Raw
$launcher = Get-Content -LiteralPath (Join-Path $repo 'QaLaunchAgent\ProcessBoundary.cs') -Raw
$empty = $runner.IndexOf('app.Application.Documents.Size != 0')
$manifest = $runner.IndexOf('VerifyManifestBinding(manifestPath);', $empty)
$isolation = $runner.IndexOf('AddinIsolationPolicy.RequireAllowed', $empty)
$evidence = $runner.IndexOf('CreatePlanViewsPreparationEvidenceContract.Verify(request, fixture, model);', $empty)
$open = $runner.IndexOf('app.OpenAndActivateDocument(model);', $empty)
$safety = $runner.IndexOf('TestSafetyGate.Verify(document, report, "CreatePlanViewsEmpty");', $open)
if ($empty -lt 0 -or $manifest -le $empty -or $isolation -le $manifest -or $evidence -le $isolation -or $open -le $evidence -or $safety -le $open) {
    throw 'Runner must require an empty session, verify manifest/isolation/authenticated fixture evidence, open the model, and validate the document in that order.'
}
if ([regex]::Matches($runner, 'app\.OpenAndActivateDocument\(model\);').Count -ne 1) {
    throw 'Runner must open the request-bound disposable model exactly once.'
}
if ($launcher -match 'psi\.(ArgumentList\.Add|Arguments\s*=)' -or $launcher -notmatch 'psi\.Environment\[QaLaunchPolicy\.RequestEnvironmentVariable\] = request\.RequestPath;') {
    throw 'Launcher must start an empty session with the canonical request environment binding.'
}
if ($runner -notmatch 'if \(File\.Exists\(receiptPath\)\) throw' -or $runner -notmatch 'request\.ExpiresUtc <= DateTimeOffset\.UtcNow' -or $runner -notmatch 'if \(report\.RollbackStatus != "RolledBack"\) report\.Status = "Failed";') {
    throw 'Startup recovery must preserve duplicate-result, expiry, and rollback failure gates.'
}
Write-Output 'PASS: empty-session launcher/runner startup order and exactly-once model opening contract.'
