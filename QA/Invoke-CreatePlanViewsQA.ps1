param([Parameter(Mandatory)][ValidateSet('Verify')][string]$Action,[Parameter(Mandatory)][string]$ReceiptPath)
$receipt=Get-Content -LiteralPath $ReceiptPath -Raw|ConvertFrom-Json
$report=Get-Content -LiteralPath $receipt.ReportPath -Raw|ConvertFrom-Json
if($receipt.Status -cne 'Passed' -or $report.TestId -cne 'create-plan-views-v1' -or $report.Status -cne 'Passed' -or $report.RollbackStatus -cne 'RolledBack' -or [string]::IsNullOrWhiteSpace($report.FixtureSha256) -or @($report.Errors).Count -ne 0){throw 'Create Plan Views QA report did not pass.'}
try{$finished=[DateTimeOffset]::Parse($report.FinishedUtc)}catch{throw 'Create Plan Views QA report FinishedUtc is invalid.'}
if($finished -eq [DateTimeOffset]::MinValue){throw 'Create Plan Views QA report FinishedUtc is zero.'}
'Create Plan Views synthetic verification passed.'
