$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('repato-glob-'+[guid]::NewGuid().ToString('N'))
New-Item $sandbox -ItemType Directory | Out-Null
try {
    Copy-Item (Join-Path $repo 'Forma.RevitConnector.csproj') $sandbox
    foreach($path in 'Production.cs','DeploymentCandidates/AgentBuilds/obj/Release/AssemblyInfo.cs','DeploymentCandidates/AgentReleases/copied.cs','DeploymentBackups/backup.cs','.worktrees/nested/source.cs','.release-worktree-test/source.cs','.diagnostic-publish/source.cs') {
        $target=Join-Path $sandbox $path
        New-Item (Split-Path $target -Parent) -ItemType Directory -Force | Out-Null
        Set-Content $target '// synthetic glob input'
    }
    $raw=& dotnet msbuild (Join-Path $sandbox 'Forma.RevitConnector.csproj') -getItem:Compile
    if($LASTEXITCODE -ne 0){throw 'MSBuild evaluation failed.'}
    $items=($raw -join "`n"|ConvertFrom-Json).Items.Compile
    if(@($items).Count -ne 1 -or $items[0].Identity -cne 'Production.cs'){throw ('Artifact source leaked into Compile: '+($items.Identity -join ', '))}
    'Build artifact exclusion regression passed: production retained, six artifact/worktree inputs excluded.'
} finally {
    $resolved=[IO.Path]::GetFullPath($sandbox)
    if(!$resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe test cleanup path.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
