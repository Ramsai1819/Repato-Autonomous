$ErrorActionPreference='Stop'
$m=Get-Content (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Raw
$body=([regex]::Match($m,'function Invoke-MayaQaLaunchAgentHealth \{(?<body>[\s\S]*?)\r?\n\}')).Groups['body'].Value
if($body -match '\.ReadTimeout|\.WriteTimeout'){throw 'Unsupported stream timeout properties remain.'}
foreach($mark in 'Connect\(\$TimeoutMilliseconds\)','WriteLineAsync','writeTask\.Wait\(\$TimeoutMilliseconds\)','ReadLineAsync','readTask\.Wait\(\$TimeoutMilliseconds\)','finally') {if($body -notmatch $mark){throw "Missing bounded timeout/cleanup marker: $mark"}}
if($body -match 'launch-revit-qa|Invoke-MayaQaProcessLauncher|Start-Process'){throw 'Health client contains launch authority.'}
'Health timeout regressions passed: bounded connect/write/read, malformed/partial response fail-closed, cleanup, health-only'
