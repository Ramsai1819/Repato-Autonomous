$ErrorActionPreference='Stop';$s=Get-Content (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Raw
foreach($n in @('Repato.CreateLevels.TestRunner.addin','Repato.CreateGrids.TestRunner.addin','Repato.GridBubbleVisibility.TestRunner.addin','Repato.GridBubbleOffset.TestRunner.addin','Repato.GridResequence.TestRunner.addin','Repato.CreatePlanViews.TestRunner.addin')){if($s -notmatch [regex]::Escape($n)){throw "Trust allowlist missing $n"}}
if($s -notmatch 'ApprovedUserManifestName.*\$runner\[0\]'){throw 'Tara isolation is not workflow-specific.'}
if($s -notmatch 'RepatoQA\.trust\.json' -or $s -notmatch 'PromptFree'){throw 'QA trust diagnostic/configuration missing.'};Write-Host 'Tara QA trust configuration regression passed.'
