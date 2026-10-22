$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Force -WarningAction SilentlyContinue
$module=Get-Module Repato.TaraRevitQa
$processId=4242
$manifest=Join-Path ([IO.Path]::GetTempPath()) ('repato-prompt-'+[guid]::NewGuid().ToString('N')+'.addin')
$dll=Join-Path ([IO.Path]::GetTempPath()) ('repato-prompt-'+[guid]::NewGuid().ToString('N')+'.dll')
try {
    [IO.File]::WriteAllText($manifest,'<RevitAddIns><AddIn Type="Application"><Name>Repato Create Plan Views QA</Name><FullClassName>Repato.Revit.TestRunner.CreatePlanViewsQaApplication</FullClassName><AddInId>00000000-0000-0000-0000-000000000006</AddInId><VendorId>RPTQ</VendorId></AddIn></RevitAddIns>')
    [IO.File]::WriteAllText($dll,'synthetic unsigned assembly identity')
    $manifestHash=(Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
    $dllHash=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
    $publisherWindow=[pscustomobject]@{
        ProcessId=$processId;Handle=98765;OwnerHandle=1;Title='Revit';ClassName='Afx:TaskDialog'
        Text="The publisher of this add-in could not be verified. $manifest Available choices: Always Load; Load Once; Do Not Load."
        ButtonLabels=@('Always Load','Load Once','Do Not Load');IsVisible=$true;IsEnabled=$true;IsMain=$false;OwnerEnabled=$false
    }
    $windowProvider={param($targetProcessId) @($publisherWindow)}
    $prompt=& $module {param($id,$provider)Get-TaraSecurityPrompt -ProcessId $id -WindowProvider $provider} $processId $windowProvider
    if(!$prompt -or $prompt.Kind -cne 'PublisherVerification' -or $prompt.Title -cne 'Revit' -or $prompt.ProcessId -ne $processId -or @($prompt.ButtonLabels).Count -ne 3){
        throw 'Revit publisher TaskDialog was not detected from its body and controls.'
    }
    $plan=[pscustomobject]@{TrustConfiguration=[pscustomobject]@{PromptRecords=@([pscustomobject]@{ManifestName='Repato.CreatePlanViews.TestRunner.addin';ManifestPath=$manifest;ManifestSha256=$manifestHash;DllPath=$dll;DllSha256=$dllHash})}}
    $provider={ $prompt }.GetNewClosure()
    $rejected=$false
    try{& $module {param($p,$id,$source)Assert-TaraSecurityPromptAbsent $p $source $id} $plan $processId $provider}catch{if($_.Exception.Message -match 'Human trust review required'){$rejected=$true}else{throw}}
    if(!$rejected){throw 'Verified publisher prompt was silently treated as prompt-free.'}
    $evidence=& $module {$script:TaraLastSecurityPrompt}
    if($evidence.Identity.ManifestPath -ine $manifest -or $evidence.Identity.AddInName -cne 'Repato Create Plan Views QA' -or ($evidence.ButtonLabels -join '|') -cne 'Always Load|Load Once|Do Not Load'){
        throw 'Prompt evidence did not retain the exact manifest identity and available choices.'
    }
    $wrongProcess=& $module {param($id,$provider)Get-TaraSecurityPrompt -ProcessId $id -WindowProvider $provider} ($processId+1) $windowProvider
    if($wrongProcess){throw 'A dialog from a different process was attributed to the QA Revit process.'}
    $unknownModal=[pscustomobject]@{ProcessId=$processId;Handle=98766;OwnerHandle=1;Title='Revit';ClassName='#32770';Text='Unknown modal dialog';ButtonLabels=@('OK');IsVisible=$true;IsEnabled=$true;IsMain=$false;OwnerEnabled=$false}
    $unknownProvider={param($targetProcessId) @($unknownModal)}
    $unknown=& $module {param($id,$provider)Get-TaraSecurityPrompt -ProcessId $id -WindowProvider $provider} $processId $unknownProvider
    if(!$unknown -or $unknown.Kind -cne 'UnclassifiedModal'){throw 'An unexpected Revit modal dialog was not failed closed.'}
    $absentProvider={param($targetProcessId) @()}
    $absent=& $module {param($id,$provider)Get-TaraSecurityPrompt -ProcessId $id -WindowProvider $provider} $processId $absentProvider
    if($absent){throw 'An empty window snapshot incorrectly reported a prompt.'}
    $scanFailureProvider={throw 'synthetic window enumeration failure'}
    $scanFailedClosed=$false
    try{& $module {param($p,$id,$provider)Assert-TaraSecurityPromptAbsent $p $provider $id} $plan $processId $scanFailureProvider}catch{if($_.Exception.Message -match 'failed closed'){$scanFailedClosed=$true}else{throw}}
    $scanFailureEvidence=& $module {$script:TaraLastSecurityPrompt}
    if(!$scanFailedClosed -or $scanFailureEvidence.Kind -cne 'DetectionFailure'){throw 'Window-enumeration failure did not fail closed with explicit evidence.'}
    $source=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Raw
    if($source -match 'SendMessage|BM_CLICK|InvokePattern|PromptAction=.*Always Load'){throw 'Security prompt handling contains automated trust interaction.'}
    [pscustomobject]@{Status='PASS';Assertions=7;PublisherDialogDetected=$true;IdentityMatched=$true;ChoicesCaptured=$true;WrongProcessRejected=$true;UnknownModalBlocked=$true;EnumerationFailureBlocked=$true;NoClickAutomation=$true}|ConvertTo-Json -Compress
} finally {
    foreach($path in @($manifest,$dll)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}}
}
