$ErrorActionPreference='Stop';$f=Join-Path $PSScriptRoot 'Fixtures\GridBubbleOffsetEmpty.rvt';$p=Get-Content (Join-Path $PSScriptRoot 'Fixtures\GridBubbleOffsetEmpty.provenance.json') -Raw|ConvertFrom-Json
$approved=@('A','B','C','D','1','2','3','4')
if(!(Test-Path $f)){throw 'Fixture missing'};if($p.fixtureId -ne 'GridBubbleOffsetEmpty' -or (@($p.requiredGridNames|Sort-Object)-join '|') -cne (@($approved|Sort-Object)-join '|')){throw 'Fixture identity or exact grid set invalid'}
if((Get-FileHash $f -Algorithm SHA256).Hash -ne $p.sourceSha256){throw 'Fixture hash mismatch'}
$controller=Get-Content (Join-Path $PSScriptRoot 'Invoke-GridBubbleOffsetQA.ps1') -Raw
if($controller -notmatch 'requiredGridNames = \$approvedGridNames' -or $controller -notmatch 'GridBubbleOffsetEmpty'){throw 'Controller does not preserve fixture policy in run sidecar'}
$command=Get-Content (Join-Path $PSScriptRoot '..\TestRunner\GridBubbleOffsetTestCommand.cs') -Raw
if($command -notmatch 'TestSafetyGate\.Verify\(d,r,"GridBubbleOffsetEmpty"\)'){throw 'Offset command does not explicitly request fixture policy'}
Write-Host '5 Grid Bubble Offset workflow checks passed'
