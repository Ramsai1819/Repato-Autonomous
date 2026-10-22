$ErrorActionPreference='Stop'
$m=Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1'
$s=Get-Content $m -Raw
$body=([regex]::Match($s,'function Invoke-MayaQaLaunchAgentHealth \{(?<body>[\s\S]*?)\r?\n\}')).Groups['body'].Value
if($body -match 'Test-Path|Add-Type|Program Files'){ throw 'Health client still reads protected agent files.' }
if($body -notmatch "operation='health'"){throw 'Health operation missing.'}
if($body -match 'Invoke-MayaQaProcessLauncher|LaunchCoordinator|StoreMutation'){throw 'Health path reaches launch or Store code.'}
'Maya health client ACL regression checks passed: pipe-only, health-only, no protected DLL access'
