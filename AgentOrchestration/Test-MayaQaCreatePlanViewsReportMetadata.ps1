$ErrorActionPreference='Stop'
$runner=Get-Content (Join-Path $PSScriptRoot '..\TestRunner\CreatePlanViewsQaApplication.cs') -Raw
foreach($marker in @('report.FixtureSha256 =','report.FinishedUtc =','report.DurationMilliseconds','RuntimeModelSha256')){if($runner -notmatch [regex]::Escape($marker)){throw "Native report metadata marker missing: $marker"}}
if($runner.IndexOf('report.FinishedUtc =',[StringComparison]::Ordinal) -gt $runner.IndexOf('report.Write()',[StringComparison]::Ordinal)){throw 'FinishedUtc is not finalized before report write.'}
Write-Host 'Create Plan Views report metadata regression passed: 4'
