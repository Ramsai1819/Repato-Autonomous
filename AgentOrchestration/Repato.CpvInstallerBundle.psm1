Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$script:BundleKind='Repato.QaLaunchAgent.CpvInstallerBundle'
$script:RuntimeVersion='1.0.18+4b0066247088'
$script:RollbackVersion='1.0.17+4b0066247088'
$script:FixtureSha256='92CC9E434E2C4DD6720A2AA564E19F4E1A30EB3DA63CEA73CF737F875B9EDD45'
$script:RuntimeFiles=@('Repato.QaLaunchAgent.exe','Repato.QaLaunchAgent.dll','Repato.QaLaunchAgent.deps.json','Repato.QaLaunchAgent.runtimeconfig.json')
$script:SourceFiles=@(
    'AgentOrchestration/Install-CpvPreparationAgentCandidate.ps1',
    'AgentOrchestration/Repato.QaLaunchAgentInstall.ps1',
    'AgentOrchestration/Invoke-CpvPreparationRecovery.ps1',
    'AgentOrchestration/Recover-CpvPreparationAgentInstall.ps1',
    'AgentOrchestration/Repato.CpvPreparationRecovery.psm1',
    'AgentOrchestration/Repato.CpvPreparationUpgrade.psm1',
    'AgentOrchestration/Repato.MayaQaWorkflow.psm1',
    'AgentOrchestration/Repato.AgentOrchestration.psm1',
    'AgentOrchestration/Repato.Deployment.v4.psm1',
    'AgentOrchestration/MayaQa.TaraExecution.ps1',
    'AgentOrchestration/Repato.CandidateEvidence.psm1',
    'AgentOrchestration/DeploymentTargets.json',
    'QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1'
)
$script:ToolFiles=@(
    'AgentOrchestration/Repato.CpvInstallerBundle.psm1',
    'AgentOrchestration/New-CpvInstallerBundle.ps1',
    'AgentOrchestration/Test-CpvInstallerBundle.ps1'
)
$script:PlatformDependencies=@(
    'Windows PowerShell 5.1',
    'Microsoft.PowerShell.Management',
    'Microsoft.PowerShell.Security',
    'CimCmdlets',
    'ScheduledTasks',
    'Windows Task Scheduler',
    'Named Pipe client APIs'
)

function Get-CpvBundleSha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
}

function Invoke-CpvBundleGit([string]$RepositoryRoot,[string[]]$Arguments) {
    $output=& git -C $RepositoryRoot @Arguments
    if($LASTEXITCODE -ne 0){throw "Git provenance check failed: git $($Arguments -join ' ')"}
    (($output|Out-String).Trim())
}

function Assert-CpvInstallerSource {
    param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$SourceCommit)
    if($SourceCommit -notmatch '^[a-fA-F0-9]{40}$'){throw 'Installer source commit must be a full SHA-1.'}
    $root=[IO.Path]::GetFullPath($SourceRoot)
    if(!(Test-Path -LiteralPath (Join-Path $root '.git'))){throw 'Installer source must be a clean Git checkout.'}
    $head=Invoke-CpvBundleGit $root @('rev-parse','HEAD')
    if($head -cne $SourceCommit.ToLowerInvariant()){throw 'Clean checkout HEAD differs from the requested source commit.'}
    $status=Invoke-CpvBundleGit $root @('status','--porcelain','--untracked-files=all')
    if($status){throw 'Installer source checkout is not clean.'}
    foreach($relative in $script:SourceFiles){
        $path=Join-Path $root ($relative.Replace('/','\'))
        if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Committed installer dependency is missing: $relative"}
        $blob=Invoke-CpvBundleGit $root @('rev-parse',"$($SourceCommit.ToLowerInvariant()):$relative")
        $actual=Invoke-CpvBundleGit $root @('hash-object','--',$path)
        if($actual -cne $blob){throw "Installer dependency differs from committed source: $relative"}
    }
    $recoverySource=Get-Content -LiteralPath (Join-Path $root 'AgentOrchestration/Repato.CpvPreparationUpgrade.psm1') -Raw
    if(!$recoverySource.Contains("`$script:FixtureSha256='$($script:FixtureSha256)'")){throw 'Committed recovery source does not pin the fixed CPV fixture hash.'}
    $root
}

function Assert-CpvInstallerTool {
    $root=[IO.Path]::GetFullPath((Split-Path (Split-Path $PSCommandPath -Parent) -Parent))
    $head=Invoke-CpvBundleGit $root @('rev-parse','HEAD')
    if($head -notmatch '^[a-f0-9]{40}$'){throw 'Installer bundle tooling is not in a Git checkout.'}
    if(Invoke-CpvBundleGit $root @('status','--porcelain','--untracked-files=all')){throw 'Installer bundle tooling checkout is not clean.'}
    foreach($relative in $script:ToolFiles){
        $path=Join-Path $root ($relative.Replace('/','\'))
        if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Committed bundle tool is missing: $relative"}
        $blob=Invoke-CpvBundleGit $root @('rev-parse',"${head}:$relative")
        if((Invoke-CpvBundleGit $root @('hash-object','--',$path)) -cne $blob){throw "Bundle tool differs from its committed source: $relative"}
    }
    [pscustomobject]@{Root=$root;Commit=$head}
}

function Get-CpvValidatedRuntimeRelease {
    param([Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$ReleaseRoot,[Parameter(Mandatory)][string]$ManifestSha256,[Parameter(Mandatory)][string]$ExpectedVersion)
    $root=[IO.Path]::GetFullPath($ReleaseRoot);$manifestPath=Join-Path $root 'Repato.QaLaunchAgent.release.json'
    if(!(Test-Path -LiteralPath $manifestPath -PathType Leaf) -or (Get-CpvBundleSha256 $manifestPath) -cne $ManifestSha256.ToUpperInvariant()){throw 'Runtime release manifest is missing or its SHA-256 differs.'}
    $bootstrap=Import-Module (Join-Path $SourceRoot 'QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1') -Force -PassThru -WarningAction SilentlyContinue
    $validated=& $bootstrap {param($source,$path,$hash)Read-ValidatedManifest $source $path $hash} $root $manifestPath $ManifestSha256
    $manifest=$validated.Manifest
    if($manifest.product -cne 'Repato.QaLaunchAgent' -or $manifest.productVersion -cne $ExpectedVersion -or $manifest.sourceCommit -notmatch '^[a-fA-F0-9]{40}$'){throw "Runtime release identity is invalid; expected $ExpectedVersion."}
    $entries=@($manifest.files)
    if($entries.Count -ne $script:RuntimeFiles.Count -or @($entries.name|Select-Object -Unique).Count -ne $script:RuntimeFiles.Count -or @($entries|Where-Object {$_.name -notin $script:RuntimeFiles -or $_.sha256 -notmatch '^[a-fA-F0-9]{64}$'}).Count){throw 'Runtime release file inventory is invalid.'}
    $actual=@(Get-ChildItem -LiteralPath $root -File -Force -Recurse -ErrorAction Stop|ForEach-Object {$_.FullName.Substring($root.TrimEnd('\').Length+1).Replace('\','/')})
    $expected=@($script:RuntimeFiles)+@('Repato.QaLaunchAgent.release.json')
    if((@($actual|Sort-Object) -join "`n") -cne (@($expected|Sort-Object) -join "`n")){throw 'Runtime release contains missing or extra files.'}
    [pscustomobject]@{Root=$root;Manifest=$manifest;ManifestPath=$manifestPath;ManifestSha256=$ManifestSha256.ToUpperInvariant()}
}

function Get-CpvBundlePayloadFiles([string]$Root) {
    $base=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    $items=@(Get-ChildItem -LiteralPath $base -Force -Recurse -ErrorAction Stop)
    if(@($items|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){throw 'Bundle contains a reparse point.'}
    @($items|Where-Object {-not $_.PSIsContainer}|ForEach-Object {$_.FullName.Substring($base.Length+1).Replace('\','/')})
}

function Test-RepatoCpvInstallerBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BundleRoot,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedManifestSha256,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$ExpectedSourceCommit,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedRuntimeManifestSha256,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedRollbackManifestSha256,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$ExpectedToolCommit
    )
    $root=[IO.Path]::GetFullPath($BundleRoot);$manifestPath=Join-Path $root 'Repato.CpvInstallerBundle.manifest.json'
    if(!(Test-Path -LiteralPath $manifestPath -PathType Leaf) -or (Get-CpvBundleSha256 $manifestPath) -cne $ExpectedManifestSha256.ToUpperInvariant()){throw 'Bundle manifest is missing or its SHA-256 differs.'}
    try{$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json -ErrorAction Stop}catch{throw 'Bundle manifest JSON is invalid.'}
    if($manifest.schemaVersion -ne 1 -or $manifest.kind -cne $script:BundleKind -or $manifest.sourceCommit -cne $ExpectedSourceCommit.ToLowerInvariant()){throw 'Bundle schema, kind, or source commit does not match.'}
    if($manifest.bundleTool.sourceCommit -cne $ExpectedToolCommit.ToLowerInvariant()){throw 'Bundle tooling source commit does not match.'}
    if($manifest.runtimeRelease.productVersion -cne $script:RuntimeVersion -or $manifest.runtimeRelease.manifestSha256 -cne $ExpectedRuntimeManifestSha256.ToUpperInvariant() -or
       $manifest.rollbackRelease.productVersion -cne $script:RollbackVersion -or $manifest.rollbackRelease.manifestSha256 -cne $ExpectedRollbackManifestSha256.ToUpperInvariant()){throw 'Runtime or rollback release provenance does not match.'}
    $entries=@($manifest.files);$paths=@($entries|ForEach-Object {[string]$_.path});$pathSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($path in $paths){if(!$path -or $path.Contains('\') -or $path.Contains(':') -or $path.StartsWith('/') -or @($path.Split('/')|Where-Object {$_ -in @('','.','..')}).Count -or !$pathSet.Add($path)){throw 'Bundle file inventory is malformed, duplicated, or contains an unsafe path.'}}
    if(!$entries.Count -or @($entries|Where-Object {$_.sha256 -notmatch '^[a-fA-F0-9]{64}'}).Count){throw 'Bundle file inventory has a missing or malformed SHA-256.'}
    $actual=@(Get-CpvBundlePayloadFiles $root|Where-Object {$_ -cne 'Repato.CpvInstallerBundle.manifest.json'})
    if((@($actual|Sort-Object) -join "`n") -cne (@($paths|Sort-Object) -join "`n")){throw 'Bundle is missing declared files or contains undeclared files.'}
    foreach($entry in $entries){$path=Join-Path $root ($entry.path.Replace('/','\'));if((Get-CpvBundleSha256 $path) -cne $entry.sha256.ToUpperInvariant()){throw "Bundle file hash mismatch: $($entry.path)"}}
    foreach($relative in $script:SourceFiles){
        $entry=@($entries|Where-Object {$_.path -ceq $relative})
        if($entry.Count -ne 1 -or $entry[0].kind -cne 'Source' -or $entry[0].sourceCommit -cne $manifest.sourceCommit){throw "Committed installer source is absent or misbound: $relative"}
    }
    if(@($entries|Where-Object {$_.kind -ceq 'Source'}).Count -ne $script:SourceFiles.Count){throw 'Bundle contains an unexpected source file.'}
    foreach($relative in $script:ToolFiles){$entry=@($entries|Where-Object {$_.path -ceq ('Tooling/'+$relative)});if($entry.Count -ne 1 -or $entry[0].kind -cne 'BundleTool' -or $entry[0].sourceCommit -cne $manifest.bundleTool.sourceCommit){throw "Committed bundle tooling is absent or misbound: $relative"}}
    if(@($entries|Where-Object {$_.kind -ceq 'BundleTool'}).Count -ne $script:ToolFiles.Count){throw 'Bundle contains unexpected tooling files.'}
    $moduleEntry=@($entries|Where-Object {$_.path -ceq $manifest.bundleTool.path});if($moduleEntry.Count -ne 1 -or $manifest.bundleTool.path -cne 'Tooling/AgentOrchestration/Repato.CpvInstallerBundle.psm1' -or $moduleEntry[0].sha256 -cne $manifest.bundleTool.sha256){throw 'Bundle manifest tooling module identity is inconsistent.'}
    $fixture=@($entries|Where-Object {$_.path -ceq 'QA/Fixtures/CreatePlanViewsEmpty.rvt'})
    if($fixture.Count -ne 1 -or $fixture[0].kind -cne 'PinnedFixture' -or $fixture[0].sha256 -ine $script:FixtureSha256 -or $fixture[0].boundBySourceCommit -cne $manifest.sourceCommit -or $fixture[0].boundBySourcePath -cne 'AgentOrchestration/Repato.CpvPreparationUpgrade.psm1' -or
       $manifest.fixedFixture.path -cne $fixture[0].path -or $manifest.fixedFixture.sha256 -ine $script:FixtureSha256 -or $manifest.fixedFixture.boundBySourceCommit -cne $manifest.sourceCommit -or $manifest.fixedFixture.boundBySourcePath -cne $fixture[0].boundBySourcePath){throw 'Fixed fixture is not bound to the committed recovery source.'}
    $bootstrap=Import-Module (Join-Path $root 'QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1') -Force -PassThru -WarningAction SilentlyContinue
    foreach($release in @($manifest.runtimeRelease,$manifest.rollbackRelease)){
        $requiredRoot=if($release.productVersion -ceq $script:RuntimeVersion){'Runtime/Repato.QaLaunchAgent-'+$script:RuntimeVersion}else{'Rollback/Repato.QaLaunchAgent-'+$script:RollbackVersion}
        if($release.path -cne $requiredRoot){throw 'Embedded release path differs from its fixed product identity.'}
        $releaseRoot=[IO.Path]::GetFullPath((Join-Path $root ([string]$release.path)))
        $releaseManifest=Join-Path $releaseRoot 'Repato.QaLaunchAgent.release.json'
        if((Get-CpvBundleSha256 $releaseManifest) -cne $release.manifestSha256){throw 'Embedded runtime release manifest hash mismatch.'}
        $validated=& $bootstrap {param($source,$path,$hash)Read-ValidatedManifest $source $path $hash} $releaseRoot $releaseManifest $release.manifestSha256
        if($validated.Manifest.productVersion -cne $release.productVersion -or $validated.Manifest.sourceCommit -cne $release.sourceCommit){throw 'Embedded runtime release identity mismatch.'}
        $expectedNames=@($script:RuntimeFiles)+@('Repato.QaLaunchAgent.release.json')
        $embeddedEntries=@($entries|Where-Object {$_.path.StartsWith($release.path+'/',[StringComparison]::OrdinalIgnoreCase)})
        $expectedPaths=@($expectedNames|ForEach-Object {$release.path+'/'+$_})
        if((@($embeddedEntries.path|Sort-Object) -join "`n") -cne (@($expectedPaths|Sort-Object) -join "`n") -or @($embeddedEntries|Where-Object {$_.kind -cne $(if($release.productVersion -ceq $script:RuntimeVersion){'RuntimeRelease'}else{'RollbackRelease'}) -or $_.sourceCommit -cne $release.sourceCommit}).Count){throw 'Embedded release file inventory or source binding is invalid.'}
    }
    [pscustomobject]@{Valid=$true;SourceCommit=$manifest.sourceCommit;RuntimeVersion=$manifest.runtimeRelease.productVersion;RuntimeManifestSha256=$manifest.runtimeRelease.manifestSha256;RollbackVersion=$manifest.rollbackRelease.productVersion;RollbackManifestSha256=$manifest.rollbackRelease.manifestSha256;ManifestSha256=(Get-CpvBundleSha256 $manifestPath);FileCount=$entries.Count}
}

function New-RepatoCpvInstallerBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$SourceCommit,
        [Parameter(Mandatory)][string]$RuntimeReleaseRoot,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$RuntimeManifestSha256,
        [Parameter(Mandatory)][string]$RollbackReleaseRoot,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$RollbackManifestSha256,
        [Parameter(Mandatory)][string]$FixedFixturePath,
        [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$ToolCommit,
        [Parameter(Mandatory)][string]$BundleParent
    )
    $tool=Assert-CpvInstallerTool
    if($ToolCommit -cne $tool.Commit){throw 'Requested bundle tool commit differs from the committed tooling checkout.'}
    $source=Assert-CpvInstallerSource $SourceRoot $SourceCommit
    $runtime=Get-CpvValidatedRuntimeRelease $source $RuntimeReleaseRoot $RuntimeManifestSha256 $script:RuntimeVersion
    $rollback=Get-CpvValidatedRuntimeRelease $source $RollbackReleaseRoot $RollbackManifestSha256 $script:RollbackVersion
    $fixture=[IO.Path]::GetFullPath($FixedFixturePath)
    if(!(Test-Path -LiteralPath $fixture -PathType Leaf) -or ((Get-Item -LiteralPath $fixture -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-CpvBundleSha256 $fixture) -cne $script:FixtureSha256){throw 'Fixed CPV fixture is missing, redirected, or does not match its committed pinned hash.'}
    $parent=[IO.Path]::GetFullPath($BundleParent);New-Item -ItemType Directory -Path $parent -Force|Out-Null
    $short=$SourceCommit.Substring(0,12).ToLowerInvariant();$destination=Join-Path $parent "Repato.CpvInstallerBundle-$short"
    if(Test-Path -LiteralPath $destination){throw 'Immutable installer bundle destination already exists.'}
    $stage=Join-Path $parent ('.stage-cpv-bundle-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $stage|Out-Null
    try {
        $entries=[Collections.Generic.List[object]]::new()
        foreach($relative in $script:SourceFiles){
            $from=Join-Path $source ($relative.Replace('/','\'));$to=Join-Path $stage ($relative.Replace('/','\'));New-Item -ItemType Directory -Path (Split-Path $to -Parent) -Force|Out-Null
            $hash=Get-CpvBundleSha256 $from;Copy-Item -LiteralPath $from -Destination $to -Force
            if((Get-CpvBundleSha256 $from) -cne $hash -or (Get-CpvBundleSha256 $to) -cne $hash){throw "Installer dependency changed while packaging: $relative"}
            $entries.Add([ordered]@{path=$relative;sha256=$hash;kind='Source';sourceCommit=$SourceCommit.ToLowerInvariant()})
        }
        foreach($relative in $script:ToolFiles){
            $from=Join-Path $tool.Root ($relative.Replace('/','\'));$relativeOut='Tooling/'+$relative;$to=Join-Path $stage ($relativeOut.Replace('/','\'));New-Item -ItemType Directory -Path (Split-Path $to -Parent) -Force|Out-Null
            $hash=Get-CpvBundleSha256 $from;Copy-Item -LiteralPath $from -Destination $to -Force
            if((Get-CpvBundleSha256 $from) -cne $hash -or (Get-CpvBundleSha256 $to) -cne $hash){throw "Bundle tool changed while packaging: $relative"}
            $entries.Add([ordered]@{path=$relativeOut;sha256=$hash;kind='BundleTool';sourceCommit=$ToolCommit.ToLowerInvariant()})
        }
        $fixtureRelative='QA/Fixtures/CreatePlanViewsEmpty.rvt';$fixtureOut=Join-Path $stage ($fixtureRelative.Replace('/','\'));New-Item -ItemType Directory -Path (Split-Path $fixtureOut -Parent) -Force|Out-Null;Copy-Item -LiteralPath $fixture -Destination $fixtureOut -Force
        $entries.Add([ordered]@{path=$fixtureRelative;sha256=(Get-CpvBundleSha256 $fixtureOut);kind='PinnedFixture';boundBySourceCommit=$SourceCommit.ToLowerInvariant();boundBySourcePath='AgentOrchestration/Repato.CpvPreparationUpgrade.psm1'})
        $embedded=@(
            @{Name='runtime';Release=$runtime;RelativeRoot=('Runtime/'+(Split-Path $runtime.Root -Leaf))},
            @{Name='rollback';Release=$rollback;RelativeRoot=('Rollback/'+(Split-Path $rollback.Root -Leaf))}
        )
        $releaseRecords=@{}
        foreach($item in $embedded){
            $targetRoot=Join-Path $stage ($item.RelativeRoot.Replace('/','\'));New-Item -ItemType Directory -Path $targetRoot -Force|Out-Null
            foreach($file in Get-ChildItem -LiteralPath $item.Release.Root -File -Force -Recurse){
                $relative=$file.FullName.Substring($item.Release.Root.TrimEnd('\').Length+1).Replace('\','/')
                $target=Join-Path $targetRoot ($relative.Replace('/','\'));New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force|Out-Null
                $before=Get-CpvBundleSha256 $file.FullName;Copy-Item -LiteralPath $file.FullName -Destination $target -Force
                if((Get-CpvBundleSha256 $file.FullName) -cne $before -or (Get-CpvBundleSha256 $target) -cne $before){throw "Release file changed while bundling: $relative"}
                $entries.Add([ordered]@{path=($item.RelativeRoot+'/'+$relative);sha256=$before;kind=$(if($item.Name -ceq 'runtime'){'RuntimeRelease'}else{'RollbackRelease'});sourceCommit=$item.Release.Manifest.sourceCommit.ToLowerInvariant()})
            }
            $releaseRecords[$item.Name]=[ordered]@{path=$item.RelativeRoot;productVersion=$item.Release.Manifest.productVersion;sourceCommit=$item.Release.Manifest.sourceCommit.ToLowerInvariant();manifestSha256=$item.Release.ManifestSha256}
        }
        $entries=@($entries|Sort-Object path)
        $modulePath=$PSCommandPath
        $manifest=[ordered]@{
            schemaVersion=1;kind=$script:BundleKind;bundleId=('cpv-installer-'+$short);sourceCommit=$SourceCommit.ToLowerInvariant();createdUtc=[DateTimeOffset]::UtcNow.ToString('O')
            runtimeRelease=$releaseRecords.runtime;rollbackRelease=$releaseRecords.rollback
            fixedFixture=[ordered]@{path=$fixtureRelative;sha256=$script:FixtureSha256;boundBySourceCommit=$SourceCommit.ToLowerInvariant();boundBySourcePath='AgentOrchestration/Repato.CpvPreparationUpgrade.psm1'}
            platformDependencies=$script:PlatformDependencies
            bundleTool=[ordered]@{sourceCommit=$ToolCommit.ToLowerInvariant();path='Tooling/AgentOrchestration/Repato.CpvInstallerBundle.psm1';sha256=(Get-CpvBundleSha256 $modulePath)}
            files=$entries
        }
        $manifestPath=Join-Path $stage 'Repato.CpvInstallerBundle.manifest.json'
        [IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
        $manifestHash=Get-CpvBundleSha256 $manifestPath
        $validation=Test-RepatoCpvInstallerBundle -BundleRoot $stage -ExpectedManifestSha256 $manifestHash -ExpectedSourceCommit $SourceCommit -ExpectedRuntimeManifestSha256 $RuntimeManifestSha256 -ExpectedRollbackManifestSha256 $RollbackManifestSha256 -ExpectedToolCommit $ToolCommit
        if(!$validation.Valid){throw 'New installer bundle failed self-validation.'}
        [IO.Directory]::Move($stage,$destination)
        [pscustomobject]@{BundleRoot=$destination;ManifestPath=(Join-Path $destination 'Repato.CpvInstallerBundle.manifest.json');ManifestSha256=$manifestHash;SourceCommit=$SourceCommit.ToLowerInvariant();RuntimeVersion=$runtime.Manifest.productVersion;RuntimeManifestSha256=$runtime.ManifestSha256;RollbackVersion=$rollback.Manifest.productVersion;RollbackManifestSha256=$rollback.ManifestSha256;FileCount=$entries.Count}
    } catch {
        if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue}
        throw
    }
}

Export-ModuleMember -Function New-RepatoCpvInstallerBundle,Test-RepatoCpvInstallerBundle
