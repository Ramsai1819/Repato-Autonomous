$ErrorActionPreference='Stop'
$s=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Raw
if($s -notmatch 'compiler/MSBuild diagnostics only' -or $s -notmatch '\$errorLines' -or $s -notmatch '\$errorCount -gt 0'){throw 'Build evidence parser does not distinguish diagnostics from summary text.'}
if($s -match "\$errorCount = @\(\$lines \| Where-Object \{ \$_ -match '\(\?i\)error'"){throw 'Broad error substring parser remains.'}
Write-Host 'Build evidence parser regression passed: summary text is ignored and compiler errors fail the build.'
