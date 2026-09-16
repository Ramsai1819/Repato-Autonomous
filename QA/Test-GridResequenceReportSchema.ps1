$ErrorActionPreference='Stop';$controller=Get-Content (Join-Path $PSScriptRoot 'Invoke-GridResequenceQA.ps1') -Raw
foreach($id in @('fixture-orientation-counts','vertical-left-to-right-names','vertical-right-to-left-names','horizontal-bottom-to-top-names','horizontal-top-to-bottom-names','special-3-3.2-family-order','all-cases-rolled-back')){if($controller -notmatch [regex]::Escape($id)){throw "Report verifier missing $id"}}
if($controller -notmatch 'RollbackStatus' -or $controller -notmatch 'FixtureSha256' -or $controller -notmatch 'AssemblyIdentity'){throw 'Report identity contract incomplete'}
Write-Host '10 Grid Resequence report-schema checks passed'
