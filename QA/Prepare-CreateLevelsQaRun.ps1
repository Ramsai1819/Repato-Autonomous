[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$')][string]$RunId)
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'Fixtures\CreateLevelsEmpty.rvt';$runsRoot=Join-Path $PSScriptRoot 'TestRuns';$runRoot=Join-Path $runsRoot ('create-levels-'+$RunId);$model=Join-Path $runRoot 'model.rvt';$sidecar=$model+'.fixture.json'
$prefix=[IO.Path]::GetFullPath($runsRoot).TrimEnd('\')+'\';if(![IO.Path]::GetFullPath($runRoot).StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Run path escaped QA TestRuns.'};if(!(Test-Path -LiteralPath $source -PathType Leaf)){throw 'Approved Create Levels fixture is missing.'};if(Test-Path -LiteralPath $runRoot){throw 'Run directory already exists.'}
New-Item -ItemType Directory -Path $runRoot|Out-Null;Copy-Item -LiteralPath $source -Destination $model;$hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;@{fixtureId='CreateLevelsEmpty';sourceSha256=$hash}|ConvertTo-Json|Set-Content -LiteralPath $sidecar -Encoding UTF8
[pscustomobject]@{RunId=$RunId;ModelPath=$model;SidecarPath=$sidecar;FixtureId='CreateLevelsEmpty';SourceSha256=$hash}|ConvertTo-Json -Compress
