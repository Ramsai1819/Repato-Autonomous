$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
$module=Get-Module Repato.MayaQaWorkflow
$count=0
try {
    function Check($condition,$reason){if(!$condition){throw "FAILED: $reason"}; $script:count++}
    function Reject($action,$reason){$ok=$false;try{& $action|Out-Null}catch{$ok=$true};if(!$ok){throw "FAILED: $reason"}; $script:count++}

    $isoNow=[DateTimeOffset]::UtcNow.ToString('O')
    $renormalized=& $module {param($v)Get-MayaQaNormalizedUtc -Value $v -Context 'synthetic ISO'} $isoNow
    Check ($renormalized.ToString('O') -ceq $isoNow) 'ISO round-trip formatting is preserved.'
    $legacyExpected=[DateTimeOffset]::new([datetime]'2026-10-20T12:55:48',[TimeZoneInfo]::Local.GetUtcOffset([datetime]'2026-10-20T12:55:48')).ToUniversalTime()
    $legacy=& $module {param($v)Get-MayaQaNormalizedUtc -Value $v -Context 'legacy agent start time'} '10/20/2026 12:55:48'
    Check ($legacy.ToString('O') -ceq $legacyExpected.ToString('O')) 'legacy agent-format start time resolves to the recorded local-instant UTC value.'
    Check ($legacy -lt [DateTimeOffset]::UtcNow -and $legacy.ToLocalTime().Hour -eq 12) 'legacy local conversion did not shift day or hour.'
    $dayFirstFormat=([datetime]'2026-10-17T12:00:00').ToString([cultureinfo]::CurrentCulture)
    $dayFirst=& $module {param($v)Get-MayaQaNormalizedUtc -Value $v -Context 'day-first current culture'} $dayFirstFormat
    Check ($dayFirst.Date -ceq ([datetime]'2026-10-17T12:00:00').Date) 'day-first format never swaps day and month.'
    $stringIso=(& $module {param($v)ConvertTo-MayaQaNormalizedUtcString -Value $v -Context 'synthetic conversion'} '2026-10-20T07:25:48.0000000Z')
    Check ($stringIso -cmatch '\+00:00$') 'normalized timing conversion returns an ISO-8601 UTC-offset string.'
    Check ($stringIso -ceq '2026-10-20T07:25:48.0000000+00:00') 'UTC normalization preserves the exact UTC instant.'
    Check (& $module {param($v)Get-MayaQaNormalizedUtc -Value $v -Context 'whitespace tolerant'} ' 2026-10-20T07:25:48Z ').Equals([DateTimeOffset]'2026-10-20T07:25:48Z') 'padded ISO input is tolerated.'
    Reject {& $module {param($v)Get-MayaQaNormalizedUtc -Value $v -Context 'unparseable'} 'not-a-timestamp'} 'unparseable timestamps are rejected.'
    Reject {& $module {param($v)Get-MayaQaNormalizedUtc -Value $v -Context 'blank'} '   '} 'blank timestamps are rejected.'

    "Maya normalized UTC gates: $count assertions passed"
} finally {
    Get-Command Get-MayaQaRoot -ErrorAction SilentlyContinue|Out-Null
}
