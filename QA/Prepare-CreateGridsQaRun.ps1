[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$')][string]$RunId)
$ErrorActionPreference='Stop'
$qaRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $PSScriptRoot 'Fixtures\CreateGridsEmptyPlan.rvt'
$runsRoot = Join-Path $PSScriptRoot 'TestRuns'
$runRoot = Join-Path $runsRoot ('create-grids-' + $RunId)
$model = Join-Path $runRoot 'model.rvt'
$sidecar = $model + '.fixture.json'
$fullRuns = [IO.Path]::GetFullPath($runsRoot).TrimEnd('\') + '\'
$fullRun = [IO.Path]::GetFullPath($runRoot)
if (!$fullRun.StartsWith($fullRuns,[StringComparison]::OrdinalIgnoreCase)) { throw 'Run path escaped QA TestRuns.' }
if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Approved Create Grids fixture is missing.' }
if (Test-Path -LiteralPath $runRoot) { throw 'Run directory already exists.' }
New-Item -ItemType Directory -Path $runRoot | Out-Null
Copy-Item -LiteralPath $source -Destination $model
$hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
@{ fixtureId='CreateGridsEmptyPlan'; sourceSha256=$hash } | ConvertTo-Json | Set-Content -LiteralPath $sidecar -Encoding UTF8
[pscustomobject]@{ RunId=$RunId; ModelPath=$model; SidecarPath=$sidecar; FixtureId='CreateGridsEmptyPlan'; SourceSha256=$hash } | ConvertTo-Json -Compress
