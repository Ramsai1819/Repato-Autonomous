$ErrorActionPreference='Stop'
$m=Get-Content (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Raw
$body=([regex]::Match($m,'function Invoke-MayaQaLaunchAgentHealth \{(?<body>[\s\S]*?)\r?\n\}')).Groups['body'].Value
if($body -notmatch 'StreamWriter\]::new\(\$pipe,\[Text\.Encoding\]::UTF8,1024,\$true\)'){throw 'Writer is not leave-open.'}
if($body -notmatch 'StreamReader\]::new\(\$pipe,\[Text\.Encoding\]::UTF8,\$false,1024,\$true\)'){throw 'Reader is not leave-open.'}
if($body -notmatch 'try \{ if\(\$reader\)\{\$reader\.Dispose\(\)\} \} catch'){throw 'Reader cleanup is not exception-safe.'}
if($body -notmatch 'try \{ if\(\$writer\)\{\$writer\.Dispose\(\)\} \} catch'){throw 'Writer cleanup is not exception-safe.'}
if($body -notmatch 'try \{ if\(\$pipe\)\{\$pipe\.Dispose\(\)\} \} catch'){throw 'Pipe cleanup is not exception-safe.'}
if($body -notmatch 'readTask\.Wait\(\$TimeoutMilliseconds\)'){throw 'Read timeout protection was removed.'}
'Maya health cleanup regressions passed: leave-open streams, idempotent cleanup, timeout preservation'
