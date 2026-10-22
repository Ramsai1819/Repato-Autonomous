$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Force -PassThru -WarningAction SilentlyContinue
$root=Join-Path ([IO.Path]::GetTempPath()) ('repato-trust-'+[guid]::NewGuid().ToString('N'));New-Item $root -ItemType Directory|Out-Null
try {
    $path=Join-Path $root 'Repato.CreatePlanViews.TestRunner.addin';Copy-Item (Join-Path $PSScriptRoot '../QA/Repato.CreatePlanViews.TestRunner.addin') $path
    $dll=Join-Path $root 'RepatoQA/Repato.Revit.dll';New-Item (Split-Path $dll -Parent) -ItemType Directory|Out-Null;Set-Content $dll 'synthetic assembly'
    $hash=(Get-FileHash $path).Hash;$dh=(Get-FileHash $dll).Hash
    $e=& $module {param($p,$h,$d)Test-TaraStablePlanViewsManifest $p $h $d} $path $hash $dll
    if($e.PersistentTrustVerified -or $e.SecurityDecision -cne 'HumanOnly'){throw 'Manifest evidence fabricated trust.'}
    foreach($case in @('identity','location')){
        if($case -eq 'identity'){$text=(Get-Content $path -Raw).Replace('00000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000007');Set-Content $path $text}
        $failed=$false;try{& $module {param($p,$h,$d)Test-TaraStablePlanViewsManifest $p $h $d} $path ((Get-FileHash $path).Hash) $(if($case -eq 'location'){Join-Path $root 'other.dll'}else{$dll})|Out-Null}catch{$failed=$true};if(!$failed){throw 'Changed identity/location accepted.'}
        Copy-Item (Join-Path $PSScriptRoot '../QA/Repato.CreatePlanViews.TestRunner.addin') $path -Force
    }
    $plan=[pscustomobject]@{TrustConfiguration=[pscustomobject]@{PromptRecords=@([pscustomobject]@{ManifestPath=$path;ManifestSha256=$hash;DllPath=$dll;DllSha256=$dh})}}
    foreach($text in @($dll,'unknown unrelated add-in')){
        try{& $module {param($p,$t)Handle-TaraTrustPrompt $p $null $null { [pscustomobject]@{Title='Security - Unsigned Add-In';Text=$t} }} $plan $text|Out-Null;throw 'Security prompt accepted.'}catch{if($_.Exception.Message -notmatch 'Human trust review required'){throw}}
    }
    $r=& $module {param($p)Handle-TaraTrustPrompt $p $null $null {$null}} $plan
    if($r.PromptAction -cne 'None' -or $r.ManualApprovalEvidence){throw 'Absent prompt became authorization.'}
    $source=Get-Content (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Raw
    if($source -match 'SendMessage|InvokePattern|BM_CLICK|0x00F5|PromptAction=.*Always Load'){throw 'Security click automation remains.'}
    'Human-only trust PASS: stable identity/location, changed identity rejection, known/unknown prompt stop, no fabricated approval, no security clicking.'
} finally {if(![IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe cleanup.'};Remove-Item -LiteralPath $root -Recurse -Force}
