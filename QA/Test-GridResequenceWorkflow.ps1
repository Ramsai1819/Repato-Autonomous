$ErrorActionPreference='Stop'
$fixture=Join-Path $PSScriptRoot 'Fixtures\GridResequenceEmpty.rvt';$provenance=Get-Content (Join-Path $PSScriptRoot 'Fixtures\GridResequenceEmpty.provenance.json') -Raw|ConvertFrom-Json
$names=@('1','2','3','3.2','4','A','A.1','B','C')
if(!(Test-Path $fixture)){throw 'Fixture missing'}
if($provenance.fixtureId -cne 'GridResequenceEmpty' -or (Get-FileHash $fixture -Algorithm SHA256).Hash -ine $provenance.sourceSha256){throw 'Fixture identity mismatch'}
if((@($provenance.requiredGridNames|Sort-Object)-join '|') -cne (@($names|Sort-Object)-join '|')){throw 'Approved names mismatch'}
if(($provenance.layout.verticalLeftToRight-join '|') -cne 'B|A.1|C|A' -or ($provenance.layout.horizontalBottomToTop-join '|') -cne '2|3.2|1|4|3'){throw 'Fixture layout mismatch'}
$controller=Get-Content (Join-Path $PSScriptRoot 'Invoke-GridResequenceQA.ps1') -Raw;$command=Get-Content (Join-Path $PSScriptRoot '..\TestRunner\GridResequenceTestCommand.cs') -Raw
if($controller -notmatch 'grid-resequence-all-directions-v1' -or $command -notmatch 'grid-resequence-all-directions-v1'){throw 'Test ID mismatch'}
if($command -notmatch 'TestSafetyGate\.Verify\(document, report, "GridResequenceEmpty"\)'){throw 'Fixture policy not requested'}
Write-Host '6 Grid Resequence workflow checks passed'
