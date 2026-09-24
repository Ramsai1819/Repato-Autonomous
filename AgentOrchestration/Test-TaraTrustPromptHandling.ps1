$ErrorActionPreference='Stop';$s=Get-Content (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Raw
foreach($t in @('PromptDetected','PromptAction','ApprovedManifest','PromptFree','PromptRecords','Multiple approved QA manifests','Unexpected RepatoQA manifest installed')){if($s -notmatch [regex]::Escape($t)){throw "Trust prompt handling missing $t"}}
Write-Host 'Tara trust prompt handling regression passed.'
