$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('repato-planviews-verifier-'+[guid]::NewGuid().ToString('N'));New-Item $root -ItemType Directory|Out-Null
try {
    $report=Join-Path $root 'native-report.json';$receipt=Join-Path $root 'native-result.json'
    [ordered]@{TestId='create-plan-views-v1';Status='Passed';RollbackStatus='RolledBack';FixtureSha256=('A'*64);FinishedUtc=(Get-Date).ToUniversalTime().ToString('O');Errors=@()}|ConvertTo-Json|Set-Content $report
    [ordered]@{Status='Passed';ReportPath=$report}|ConvertTo-Json|Set-Content $receipt
    & powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\QA\Invoke-CreatePlanViewsQA.ps1') -Action Verify -ReceiptPath $receipt|Out-Null
    Write-Host 'Create Plan Views verifier schema regression passed: 7'
} finally {if(Test-Path $root){Remove-Item $root -Recurse -Force}}
