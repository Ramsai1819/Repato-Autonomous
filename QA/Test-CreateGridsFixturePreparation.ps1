$ErrorActionPreference='Stop'
$runId = [guid]::NewGuid().ToString('N')
$runRoot = Join-Path $PSScriptRoot ('TestRuns\create-grids-' + $runId)
$source = Join-Path $PSScriptRoot 'Fixtures\CreateGridsEmptyPlan.rvt'
$before = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
try {
    $result = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Prepare-CreateGridsQaRun.ps1') -RunId $runId | ConvertFrom-Json
    if ($result.FixtureId -cne 'CreateGridsEmptyPlan') { throw 'Unexpected fixture identity.' }
    if (!(Test-Path -LiteralPath $result.ModelPath -PathType Leaf) -or !(Test-Path -LiteralPath $result.SidecarPath -PathType Leaf)) { throw 'Prepared model or sidecar missing.' }
    $sidecar = Get-Content -LiteralPath $result.SidecarPath -Raw | ConvertFrom-Json
    $actual = (Get-FileHash -LiteralPath $result.ModelPath -Algorithm SHA256).Hash
    if ($sidecar.fixtureId -cne 'CreateGridsEmptyPlan' -or $sidecar.sourceSha256 -ine $before -or $actual -ine $before) { throw 'Sidecar or copy hash mismatch.' }
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ine $before) { throw 'Repository fixture changed.' }
    'Create Grids fixture preparation checks passed: 4'
}
finally { if (Test-Path -LiteralPath $runRoot) { Remove-Item -LiteralPath $runRoot -Recurse -Force } }
