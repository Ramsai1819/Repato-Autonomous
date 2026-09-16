$ErrorActionPreference='Stop'
$production=Get-Content (Join-Path $PSScriptRoot '..\GridResequenceCommand.cs') -Raw
$runner=Get-Content (Join-Path $PSScriptRoot '..\TestRunner\GridResequenceTestCommand.cs') -Raw
foreach($token in @('ApplyQaCase','CreateResequenceRenames','Left to Right','Right to Left','Bottom to Top','Top to Bottom','3.2','A.1','REPATO-QA-TEMP')){if($production -notmatch [regex]::Escape($token) -and $runner -notmatch [regex]::Escape($token)){throw "Missing $token"}}
foreach($token in @('vertical-left-to-right','vertical-right-to-left','horizontal-bottom-to-top','horizontal-top-to-bottom','geometry','unselected','special-3-3.2-family-order','all-cases-rolled-back')){if($runner -notmatch [regex]::Escape($token)){throw "Runner missing $token"}}
Write-Host '17 Grid Resequence static checks passed'
