param([Parameter(Mandatory)][ValidateSet('Verify')][string]$Action,[Parameter(Mandatory)][string]$ReceiptPath)
$receipt=Get-Content -LiteralPath $ReceiptPath -Raw|ConvertFrom-Json
if($receipt.Status -cne 'Passed' -or $receipt.Report.TestId -cne 'create-plan-views-v1' -or $receipt.Report.RollbackStatus -cne 'RolledBack'){throw 'Create Plan Views QA report did not pass.'}
'Create Plan Views synthetic verification passed.'
