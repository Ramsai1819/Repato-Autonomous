param(
    [string]$SourceRoot=(Join-Path (Split-Path $PSScriptRoot -Parent) 'QaLaunchAgent\bin\Release\net8.0-windows'),
    [string]$ReleaseRoot=(Join-Path (Split-Path $PSScriptRoot -Parent) 'DeploymentCandidates\AgentReleases'),
    [string]$SourceCommit=(git -C (Split-Path $PSScriptRoot -Parent) rev-parse HEAD)
)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$files=@('Repato.QaLaunchAgent.exe','Repato.QaLaunchAgent.dll','Repato.QaLaunchAgent.deps.json','Repato.QaLaunchAgent.runtimeconfig.json')
if($SourceCommit -notmatch '^[a-fA-F0-9]{40}$' -or (git -C $repo cat-file -t $SourceCommit) -cne 'commit'){throw 'SourceCommit is not an existing commit.'}
$source=[IO.Path]::GetFullPath($SourceRoot);$root=[IO.Path]::GetFullPath($ReleaseRoot)
foreach($name in $files){if(!(Test-Path -LiteralPath (Join-Path $source $name) -PathType Leaf)){throw "Required runtime file is missing: $name"}}
$exe=(Get-Item -LiteralPath (Join-Path $source $files[0])).VersionInfo.ProductVersion
$dll=(Get-Item -LiteralPath (Join-Path $source $files[1])).VersionInfo.ProductVersion
if([string]::IsNullOrWhiteSpace($exe) -or $exe -cne $dll -or $exe -notmatch '^\d+\.\d+\.\d+\+[a-fA-F0-9]{12,40}$'){throw 'Executable/DLL build identity is inconsistent.'}
$versionCommit=$exe.Substring($exe.IndexOf('+')+1)
git -C $repo merge-base --is-ancestor $versionCommit $SourceCommit
if($LASTEXITCODE -ne 0){throw 'Build version is not bound to runtime source in SourceCommit history.'}
git -C $repo diff --quiet $SourceCommit -- 'QaLaunchAgent/*.cs' 'QaLaunchAgent/Repato.QaLaunchAgent.csproj'
if($LASTEXITCODE -ne 0){throw 'Runtime source differs from the declared SourceCommit.'}
$destination=Join-Path $root ('Repato.QaLaunchAgent-'+$exe)
if(Test-Path -LiteralPath $destination){throw 'Immutable release destination already exists.'}
$stage=Join-Path $root ('.stage-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $stage -Force|Out-Null
try {
    $entries=@()
    foreach($name in $files){$from=Join-Path $source $name;$before=(Get-FileHash $from -Algorithm SHA256).Hash;Copy-Item -LiteralPath $from -Destination (Join-Path $stage $name);$after=(Get-FileHash $from -Algorithm SHA256).Hash;$packaged=(Get-FileHash (Join-Path $stage $name) -Algorithm SHA256).Hash;if($before -cne $after -or $before -cne $packaged){throw "Runtime file changed while packaging: $name"};$entries+=[ordered]@{name=$name;sha256=$packaged}}
    $manifest=[ordered]@{schemaVersion=1;product='Repato.QaLaunchAgent';productVersion=$exe;sourceCommit=$SourceCommit.ToLowerInvariant();account='RAMSAI\RepatoQA';sid='S-1-5-21-1031246752-3872016183-2454652381-1015';files=$entries}
    $manifestPath=Join-Path $stage 'Repato.QaLaunchAgent.release.json';[IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    $module=Import-Module (Join-Path $repo 'QaLaunchAgent\Repato.QaLaunchAgent.Bootstrap.psm1') -Force -PassThru;$manifestHash=(Get-FileHash $manifestPath -Algorithm SHA256).Hash
    $null=& $module {param($s,$m,$h)Read-ValidatedManifest $s $m $h} $stage $manifestPath $manifestHash
    Move-Item -LiteralPath $stage -Destination $destination
    [pscustomobject]@{Version=$exe;SourceCommit=$SourceCommit.ToLowerInvariant();ReleaseRoot=$destination;ManifestPath=(Join-Path $destination 'Repato.QaLaunchAgent.release.json');ManifestSha256=$manifestHash;Files=$entries}
} catch {if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force};throw}
