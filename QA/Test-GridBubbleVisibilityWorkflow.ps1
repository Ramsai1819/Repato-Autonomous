$ErrorActionPreference='Stop'
$fixture=Join-Path $PSScriptRoot 'Fixtures\GridBubbleVisibilityEmpty.rvt'; $prov=Get-Content (Join-Path $PSScriptRoot 'Fixtures\GridBubbleVisibilityEmpty.provenance.json') -Raw | ConvertFrom-Json
if(!(Test-Path $fixture)){throw 'Fixture missing'}; if($prov.fixtureId -ne 'GridBubbleVisibilityEmpty'){throw 'Fixture provenance mismatch'}
$addin=Get-Content (Join-Path $PSScriptRoot 'Repato.GridBubbleVisibility.TestRunner.addin') -Raw
if($addin -notmatch 'GridBubbleVisibilityTestCommand'){throw 'Manifest mismatch'}
$controller=Get-Content (Join-Path $PSScriptRoot 'Invoke-GridBubbleVisibilityQA.ps1') -Raw
if($controller -notmatch "grid-bubble-visibility-v1"){throw 'Controller test ID does not match the QA command.'}
$runner=Get-Content (Join-Path $PSScriptRoot '..\TestRunner\GridBubbleVisibilityTestCommand.cs') -Raw
if($runner -notmatch 'FixtureId="GridBubbleVisibilityEmpty"'){throw 'Runner fixture identity mismatch.'}
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Invoke-GridBubbleVisibilityQA.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Grid controller syntax error'}
if($addin -notmatch 'GridBubbleVisibilityQaApplication'){throw 'Application manifest missing'}
Write-Host '3 workflow checks passed (fixture, provenance, QA-only manifest)'
