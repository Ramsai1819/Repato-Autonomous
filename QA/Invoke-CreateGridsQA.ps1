[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Install','Run','Verify')][string]$Action,[string]$ReceiptPath)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
if($Action -ne 'Verify'){ throw 'Create Grids unattended installation is performed by the Tara bridge; use Verify for evidence.' }
if([string]::IsNullOrWhiteSpace($ReceiptPath)){ throw '-ReceiptPath is required for Verify.' }
$receipt=Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json
$report=Get-Content -LiteralPath $receipt.ReportPath -Raw | ConvertFrom-Json
if($receipt.Status -cne 'Passed' -or $report.Status -cne 'Passed' -or $report.TestId -cne 'create-grids-world-axis-v1' -or $report.RollbackStatus -cne 'RolledBack'){ throw 'Create Grids QA report did not pass.' }
$failed=@($report.Assertions|Where-Object { $_.Passed -ne $true })
if($failed.Count -gt 0 -or @($report.Errors).Count -gt 0){ throw 'Create Grids QA contains failed assertions or errors.' }
foreach($id in @('grid-count','exact-names','service-commit-observed','rollback-status')){if(@($report.Assertions|Where-Object {$_.Id -ceq $id -and $_.Passed -eq $true}).Count -ne 1){throw "Missing assertion: $id"}}
Write-Host "PASSED: $($receipt.ReportPath) (eight grids, spacing and rollback verified)."
