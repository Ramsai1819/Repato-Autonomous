$script:QaTargetRoot = 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA'
$script:QaManifestRoot = Split-Path -Parent $script:QaTargetRoot

function Get-QaAddinDeploymentTarget {
    [pscustomobject]@{ TargetId='repatoqa-user-addin'; TargetRoot=$script:QaTargetRoot; ManifestRoot=$script:QaManifestRoot; ManifestPath=(Join-Path $script:QaManifestRoot 'Repato.WelcomeSmoke.TestRunner.addin'); AssemblyPath=(Join-Path $script:QaTargetRoot 'Repato.Revit.dll'); Allowed=$true }
}
function Test-QaAddinTarget {
    param([string]$TargetRoot,[switch]$TestTarget)
    $full=[IO.Path]::GetFullPath($TargetRoot)
    if($TestTarget){$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath());if(!$full.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){throw 'Test target must be temporary.'};return $full}
    if($full -cne $script:QaTargetRoot){throw 'Target is not the approved RepatoQA add-in directory.'};return $full
}
function Invoke-QaAddinDeployment {
    param([string]$ArtifactPath,[string]$ManifestPath,[string]$TargetRoot=$script:QaTargetRoot,[string]$TestTargetRoot,[switch]$ConfirmQaProfileDeployment,[switch]$DryRun)
    $isTest=[bool]$TestTargetRoot;$dllRoot=''
    if($isTest){$dllRoot=Test-QaAddinTarget $TestTargetRoot -TestTarget}else{$dllRoot=Test-QaAddinTarget $TargetRoot}
    if(!(Test-Path -LiteralPath $ArtifactPath -PathType Leaf)-or !(Test-Path -LiteralPath $ManifestPath -PathType Leaf)){throw 'Deployment source is missing.'}
    $artifactSource=[IO.Path]::GetFullPath($ArtifactPath);$manifestSource=[IO.Path]::GetFullPath($ManifestPath)
    $artifactHash=(Get-FileHash $artifactSource -Algorithm SHA256).Hash;$manifestHash=(Get-FileHash $manifestSource -Algorithm SHA256).Hash
    $artifactName='Repato.Revit.dll';$manifestName=[IO.Path]::GetFileName($ManifestPath)
    if($isTest){$artifactName='artifact.target';$manifestName='manifest.target'}
    $artifactDestination=Join-Path $dllRoot $artifactName;$manifestDestination=Join-Path $script:QaManifestRoot $manifestName
    if($isTest){$manifestDestination=Join-Path $dllRoot $manifestName}
    $artifactDestination=[IO.Path]::GetFullPath($artifactDestination);$manifestDestination=[IO.Path]::GetFullPath($manifestDestination)
    if(!$isTest-and $manifestDestination -notlike "$script:QaManifestRoot\*"){throw 'Manifest destination is outside the approved QA discovery root.'}
    $artifactBackup=$artifactDestination+'.backup';$manifestBackup=$manifestDestination+'.backup';$legacyManifest=Join-Path $dllRoot $manifestName;$legacyBackup=$legacyManifest+'.backup';$artifactExists=$false;$manifestExists=$false;$legacyExists=$false;if(!$DryRun){$artifactExists=Test-Path -LiteralPath $artifactDestination -PathType Leaf;$manifestExists=Test-Path -LiteralPath $manifestDestination -PathType Leaf;if(!$isTest -and ([IO.Path]::GetFullPath($legacyManifest) -ne $manifestDestination)){$legacyExists=Test-Path -LiteralPath $legacyManifest -PathType Leaf}};$previouslyAbsent=@()
    if(!$artifactExists){$previouslyAbsent+=$artifactDestination};if(!$manifestExists){$previouslyAbsent+=$manifestDestination}
    if($DryRun){return [pscustomobject]@{TargetRoot=$dllRoot;ArtifactSourcePath=$artifactSource;ArtifactDestinationPath=$artifactDestination;ManifestSourcePath=$manifestSource;ManifestDestinationPath=$manifestDestination;BackupPaths=@($artifactBackup,$manifestBackup);PreviouslyAbsent=$previouslyAbsent;ArtifactSourceSha256=$artifactHash;ManifestSourceSha256=$manifestHash;ConfirmationRequired=(!$isTest);SideEffectsPerformed=$false}}
    if(!$isTest-and !$ConfirmQaProfileDeployment){throw 'Explicit QA profile deployment confirmation is required.'}
    New-Item -ItemType Directory -Path $dllRoot -Force|Out-Null;New-Item -ItemType Directory -Path (Split-Path -Parent $manifestDestination) -Force|Out-Null
    try { if($artifactExists){Copy-Item $artifactDestination ($artifactBackup+'.tmp') -Force;Move-Item ($artifactBackup+'.tmp') $artifactBackup -Force};if($manifestExists){Copy-Item $manifestDestination ($manifestBackup+'.tmp') -Force;Move-Item ($manifestBackup+'.tmp') $manifestBackup -Force};if($legacyExists){Copy-Item $legacyManifest ($legacyBackup+'.tmp') -Force;Move-Item ($legacyBackup+'.tmp') $legacyBackup -Force;Remove-Item $legacyManifest -Force};Copy-Item $artifactSource ($artifactDestination+'.tmp') -Force;Move-Item ($artifactDestination+'.tmp') $artifactDestination -Force;Copy-Item $manifestSource ($manifestDestination+'.tmp') -Force;Move-Item ($manifestDestination+'.tmp') $manifestDestination -Force;if((Get-FileHash $artifactDestination -Algorithm SHA256).Hash-ne $artifactHash-or (Get-FileHash $manifestDestination -Algorithm SHA256).Hash-ne $manifestHash){throw 'Installed hash verification failed.'} } catch { if($artifactExists-and(Test-Path $artifactBackup)){Copy-Item $artifactBackup $artifactDestination -Force}elseif(!$artifactExists-and(Test-Path $artifactDestination)){Remove-Item $artifactDestination -Force};if($manifestExists-and(Test-Path $manifestBackup)){Copy-Item $manifestBackup $manifestDestination -Force}elseif(!$manifestExists-and(Test-Path $manifestDestination)){Remove-Item $manifestDestination -Force};if($legacyExists-and(Test-Path $legacyBackup)){Copy-Item $legacyBackup $legacyManifest -Force};throw }
    $backups=@($(if($artifactExists){$artifactBackup}),$(if($manifestExists){$manifestBackup}),$(if($legacyExists){$legacyBackup}));[pscustomobject]@{TargetRoot=$dllRoot;ArtifactDestinationPath=$artifactDestination;ManifestDestinationPath=$manifestDestination;LegacyManifestPath=$legacyManifest;ArtifactSha256=$artifactHash;ManifestSha256=$manifestHash;BackupPaths=$backups;PreviouslyAbsent=$previouslyAbsent;SideEffectsPerformed=$true}
}
Export-ModuleMember -Function Get-QaAddinDeploymentTarget,Test-QaAddinTarget,Invoke-QaAddinDeployment
