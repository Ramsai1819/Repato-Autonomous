$script:QaTargetRoot = 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA'
$script:QaManifestRoot = Split-Path -Parent $script:QaTargetRoot
$script:IsolationImplementation = Join-Path $PSScriptRoot '..\QA\AddinIsolation.ps1'

# AddinIsolation.ps1 is a shared internal implementation. These helpers stay
# module-private so its path containment and hashing cannot depend on caller or
# global scope.
function Assert-ChildPath([string]$Path,[string]$Parent) {
    $resolved = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    if ($resolved -ine $root.TrimEnd('\') -and
        !$resolved.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Path escaped approved root.'
    }
    $resolved
}
function Get-Sha256([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
if (!(Test-Path -LiteralPath $script:IsolationImplementation -PathType Leaf)) {
    throw 'Required add-in isolation implementation is missing.'
}
. $script:IsolationImplementation

function Get-TaraQaWorkflowContract {
    param([Parameter(Mandatory)][string]$QaWorkflowId)
    $contracts = @{
        'create-plan-views-v1' = [pscustomobject]@{ TestId='create-plan-views-v1'; Manifest='Repato.CreatePlanViews.TestRunner.addin'; Class='Repato.Revit.TestRunner.CreatePlanViewsQaApplication' }
        'create-levels-elevations-v1' = [pscustomobject]@{ TestId='create-levels'; Manifest='Repato.CreateLevels.TestRunner.addin'; Class='Repato.Revit.TestRunner.CreateLevelsQaApplication' }
        'create-grids-world-axis-v1' = [pscustomobject]@{ TestId='create-grids-world-axis-v1'; Manifest='Repato.CreateGrids.TestRunner.addin'; Class='Repato.Revit.TestRunner.CreateGridsQaApplication' }
        'grid-bubble-visibility-v1' = [pscustomobject]@{ TestId='grid-bubble-visibility-v1'; Manifest='Repato.GridBubbleVisibility.TestRunner.addin'; Class='Repato.Revit.TestRunner.GridBubbleVisibilityQaApplication' }
        'grid-bubble-offset-v1' = [pscustomobject]@{ TestId='grid-bubble-offset-v1'; Manifest='Repato.GridBubbleOffset.TestRunner.addin'; Class='Repato.Revit.TestRunner.GridBubbleOffsetQaApplication' }
        'grid-resequence-v1' = [pscustomobject]@{ TestId='grid-resequence-v1'; Manifest='Repato.GridResequence.TestRunner.addin'; Class='Repato.Revit.TestRunner.GridResequenceQaApplication' }
    }
    if (!$contracts.ContainsKey($QaWorkflowId)) { throw 'QA staging workflow is not supported by the trusted manifest map.' }
    $contracts[$QaWorkflowId]
}

function Test-TaraCandidateRunnerBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CandidateDllPath,
        [Parameter(Mandatory)][string]$TrustedManifestPath,
        [string]$RevitInstallDir = 'E:\revit\Revit 2025'
    )
    if(!(Test-Path -LiteralPath $CandidateDllPath -PathType Leaf) -or !(Test-Path -LiteralPath $TrustedManifestPath -PathType Leaf)) { throw 'Candidate binding inputs are missing.' }
    foreach($api in @('RevitAPI.dll','RevitAPIUI.dll')) { if(!(Test-Path -LiteralPath (Join-Path $RevitInstallDir $api) -PathType Leaf)) { throw "Required Revit API dependency is missing: $api" } }
    try { $manifest=[xml](Get-Content -LiteralPath $TrustedManifestPath -Raw) } catch { throw 'Trusted runner manifest is malformed.' }
    $contract=Get-TaraQaWorkflowContract 'create-plan-views-v1'
    $entries=@($manifest.RevitAddIns.AddIn | Where-Object { $_.Type -ceq 'Application' })
    if($entries.Count -ne 1 -or [string]$entries[0].FullClassName -cne $contract.Class) { throw 'Trusted manifest does not name the exact Create Plan Views application class.' }
    $checker=Join-Path $PSScriptRoot '..\CandidateRunnerBindingCheck\CandidateRunnerBindingCheck.csproj'
    if(!(Test-Path -LiteralPath $checker -PathType Leaf)) { throw 'Metadata-only candidate binding checker is missing.' }
    $buildOutput=@(& dotnet build $checker -c Release --nologo -v:q 2>&1)
    if($LASTEXITCODE -ne 0) { throw ('Candidate binding checker build failed: '+($buildOutput -join ' ')) }
    $checkerDll=Join-Path (Split-Path -Parent $checker) 'bin\Release\net8.0\CandidateRunnerBindingCheck.dll'
    $output=@(& dotnet $checkerDll $CandidateDllPath $TrustedManifestPath $contract.Class '.\RepatoQA\Repato.Revit.dll' 2>&1)
    if($LASTEXITCODE -ne 0) { throw ('Compiled candidate runner binding check failed: '+($output -join ' ')) }
    $check=($output | Where-Object { [string]$_ -match '^\{' } | Select-Object -Last 1)
    if(!$check) { throw 'Compiled candidate runner binding checker returned no evidence.' }
    $evidence=$check | ConvertFrom-Json
    if(!$evidence.Passed -or $evidence.Class -cne $contract.Class -or $evidence.Interface -cne 'Autodesk.Revit.UI.IExternalApplication') { throw 'Compiled candidate runner binding evidence did not satisfy the manifest contract.' }
    [pscustomobject]@{Passed=$true;Class=$evidence.Class;CandidateDll=[IO.Path]::GetFullPath($CandidateDllPath);CandidateSha256=$evidence.CandidateSha256;ManifestPath=[IO.Path]::GetFullPath($TrustedManifestPath);ManifestSha256=(Get-FileHash -LiteralPath $TrustedManifestPath -Algorithm SHA256).Hash;Interface=$evidence.Interface}
}

function Test-TaraFrozenCandidateQaIsolation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CandidateDirectory,
        [Parameter(Mandatory)][string]$ExpectedArtifactSha256,
        [Parameter(Mandatory)][string]$ExpectedSourceCommit,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$TestId,
        [string]$TargetRoot = $script:QaTargetRoot,
        [string]$ManifestRoot = $script:QaManifestRoot,
        [string]$QaSourceRoot = (Join-Path $PSScriptRoot '..\QA'),
        [string]$MachineRoot = 'C:\ProgramData\Autodesk\Revit\Addins\2025',
        [switch]$TestLayout
    )
    $contract = Get-TaraQaWorkflowContract $QaWorkflowId
    if ($TestId -cne $contract.TestId) { throw 'QA isolation TestId is incompatible with the selected workflow.' }
    if ($ExpectedArtifactSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or $ExpectedSourceCommit -notmatch '^[A-Fa-f0-9]{40}$') { throw 'Frozen candidate identity is malformed.' }
    $candidate = [IO.Path]::GetFullPath($CandidateDirectory)
    $qaSource = [IO.Path]::GetFullPath($QaSourceRoot)
    $target = [IO.Path]::GetFullPath($TargetRoot)
    $manifestBase = [IO.Path]::GetFullPath($ManifestRoot)
    $machine = [IO.Path]::GetFullPath($MachineRoot)
    if ($TestLayout) {
        $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        foreach ($path in @($qaSource,$target,$manifestBase,$machine)) {
            if (!$path.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)) { throw 'Synthetic QA isolation roots must be temporary.' }
        }
    } else {
        if ($target -cne $script:QaTargetRoot -or $manifestBase -cne $script:QaManifestRoot) { throw 'Isolation target is not the dedicated RepatoQA Revit 2025 environment.' }
        if ([Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1] -cne 'RepatoQA') { throw 'QA isolation requires the dedicated RepatoQA Windows profile.' }
    }
    $candidateDll = Assert-ChildPath (Join-Path $candidate 'Repato.Revit.dll') $candidate
    $provenancePath = Assert-ChildPath (Join-Path $candidate 'release-manifest.json') $candidate
    $installedDll = Assert-ChildPath (Join-Path $target 'Repato.Revit.dll') $target
    $installedManifest = Assert-ChildPath (Join-Path $manifestBase $contract.Manifest) $manifestBase
    $sourceManifest = Assert-ChildPath (Join-Path $qaSource $contract.Manifest) $qaSource
    $stagingEvidence = Assert-ChildPath (Join-Path $target 'Repato.QaStaging.json') $target
    foreach ($path in @($candidateDll,$provenancePath,$installedDll,$installedManifest,$sourceManifest,$stagingEvidence)) {
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required QA isolation input is missing: $path" }
    }
    if ((Get-Sha256 $candidateDll) -ine $ExpectedArtifactSha256 -or (Get-Sha256 $installedDll) -ine $ExpectedArtifactSha256) { throw 'Installed QA DLL is not bound to the frozen candidate.' }
    $provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
    $evidence = Get-Content -LiteralPath $stagingEvidence -Raw | ConvertFrom-Json
    if ([string]$provenance.SourceCommit -cne $ExpectedSourceCommit -or [string]$provenance.FrozenArtifactSha256 -ine $ExpectedArtifactSha256) { throw 'Frozen candidate provenance mismatch.' }
    if ([string]$evidence.CandidateSourceCommit -cne $ExpectedSourceCommit -or [string]$evidence.CandidateSha256 -ine $ExpectedArtifactSha256 -or [string]$evidence.QaWorkflowId -cne $QaWorkflowId -or [string]$evidence.TestId -cne $TestId) { throw 'Installed QA staging evidence mismatch.' }
    if ((Get-Sha256 $installedManifest) -ine (Get-Sha256 $sourceManifest)) { throw 'Installed QA manifest differs from the trusted workflow manifest.' }
    $xml = [xml](Get-Content -LiteralPath $installedManifest -Raw)
    $apps = @($xml.RevitAddIns.AddIn | Where-Object Type -eq 'Application')
    if ($apps.Count -ne 1 -or [string]$apps[0].FullClassName -cne $contract.Class -or [string]$apps[0].Assembly -cne '.\RepatoQA\Repato.Revit.dll') { throw 'Installed QA workflow manifest contract is incompatible.' }
    $inventory = Get-AddinIsolationInventory -PolicyPath (Join-Path $qaSource 'MachineWideAddins.allowlist.json') -MachineRoot $machine -UserRoot $manifestBase -QaSourceRoot $qaSource -ApprovedUserManifestName $contract.Manifest
    if (!$inventory.Allowed -or @($inventory.Errors).Count) { throw ('Staged QA isolation validation failed: '+(@($inventory.Errors)-join '; ')) }
    [pscustomobject]@{Success=$true;QaWorkflowId=$QaWorkflowId;TestId=$TestId;CandidateSha256=$ExpectedArtifactSha256;InstalledDllPath=$installedDll;InstalledDllSha256=(Get-Sha256 $installedDll);InstalledManifestPath=$installedManifest;InstalledManifestSha256=(Get-Sha256 $installedManifest);Isolation=$inventory;SideEffectsPerformed=$false}
}

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

function Install-TaraFrozenCandidateForQa {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CandidateDirectory,
        [Parameter(Mandatory)][string]$ExpectedArtifactSha256,
        [Parameter(Mandatory)][string]$ExpectedSourceCommit,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$TestId,
        [ValidateSet('2025')][string]$RevitVersion = '2025',
        [string]$TargetRoot = $script:QaTargetRoot,
        [string]$ManifestRoot = $script:QaManifestRoot,
        [string]$QaSourceRoot = (Join-Path $PSScriptRoot '..\QA'),
        [string]$MachineRoot = 'C:\ProgramData\Autodesk\Revit\Addins\2025',
        [string]$TestTargetRoot,
        [string]$TestManifestRoot,
        [string]$TestMachineRoot,
        [ValidateSet('None','AfterPayloadValidation','AfterDllCommit')][string]$FailureMode = 'None',
        [switch]$DryRun
    )
    $contract=Get-TaraQaWorkflowContract $QaWorkflowId
    if($TestId -cne $contract.TestId){throw 'QA staging TestId is incompatible with the selected workflow.'}
    if($ExpectedArtifactSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or $ExpectedSourceCommit -notmatch '^[A-Fa-f0-9]{40}$'){throw 'Frozen candidate identity is malformed.'}
    $candidate=[IO.Path]::GetFullPath($CandidateDirectory)
    $dll=Join-Path $candidate 'Repato.Revit.dll';$provenancePath=Join-Path $candidate 'release-manifest.json'
    if(!(Test-Path $candidate -PathType Container)-or !(Test-Path $dll -PathType Leaf)-or !(Test-Path $provenancePath -PathType Leaf)){throw 'Frozen candidate payload is missing.'}
    $candidateHash=(Get-FileHash $dll -Algorithm SHA256).Hash
    if($candidateHash -ine $ExpectedArtifactSha256){throw 'Frozen candidate DLL SHA-256 mismatch.'}
    try{$provenance=Get-Content $provenancePath -Raw|ConvertFrom-Json}catch{throw 'Frozen candidate provenance is malformed.'}
    if([string]$provenance.SourceCommit -cne $ExpectedSourceCommit -or [string]$provenance.FrozenArtifactSha256 -ine $candidateHash){throw 'Frozen candidate provenance mismatch.'}
    if(@($provenance.SupportedQaWorkflows|Where-Object{[string]$_ -ceq $QaWorkflowId}).Count -ne 1){throw 'Frozen candidate does not support the requested QA workflow.'}
    $qaSource=[IO.Path]::GetFullPath($QaSourceRoot);$sourceManifest=Join-Path $qaSource $contract.Manifest
    if(!(Test-Path $sourceManifest -PathType Leaf)){throw 'Trusted QA workflow manifest is missing.'}
    try{$xml=[xml](Get-Content $sourceManifest -Raw)}catch{throw 'Trusted QA workflow manifest is malformed.'}
    $apps=@($xml.RevitAddIns.AddIn|Where-Object Type -eq 'Application')
    if($apps.Count -ne 1 -or [string]$apps[0].FullClassName -cne $contract.Class -or [string]$apps[0].Assembly -cne '.\RepatoQA\Repato.Revit.dll'){throw 'Trusted QA workflow manifest contract is incompatible.'}
      $binding=Test-TaraCandidateRunnerBinding -CandidateDllPath $dll -TrustedManifestPath $sourceManifest
    $testMode=![string]::IsNullOrWhiteSpace($TestTargetRoot)
    if($testMode){
        $target=[IO.Path]::GetFullPath($TestTargetRoot);$manifestBase=[IO.Path]::GetFullPath($TestManifestRoot);$machine=[IO.Path]::GetFullPath($TestMachineRoot)
        $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
        foreach($p in @($target,$manifestBase,$machine,$qaSource)){if(!$p.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){throw 'Synthetic QA staging roots must be temporary.'}}
    }else{
        $target=[IO.Path]::GetFullPath($TargetRoot);$manifestBase=[IO.Path]::GetFullPath($ManifestRoot);$machine=[IO.Path]::GetFullPath($MachineRoot)
        if($target -cne $script:QaTargetRoot -or $manifestBase -cne $script:QaManifestRoot -or $RevitVersion -cne '2025'){throw 'Target is not the dedicated RepatoQA Revit 2025 environment.'}
        $windowsUser=[Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1]
        if($windowsUser -cne 'RepatoQA'){throw 'QA-only staging requires the dedicated RepatoQA Windows profile.'}
    }
    $dllDestination=Join-Path $target 'Repato.Revit.dll';$manifestDestination=Join-Path $manifestBase $contract.Manifest;$evidenceDestination=Join-Path $target 'Repato.QaStaging.json'
    $sourceManifestHash=(Get-FileHash $sourceManifest -Algorithm SHA256).Hash
    if($DryRun){return [pscustomobject]@{Success=$true;Mode='DryRun';QaWorkflowId=$QaWorkflowId;TestId=$TestId;TargetRoot=$target;ManifestPath=$manifestDestination;CandidateSourceCommit=$ExpectedSourceCommit;CandidateSha256=$candidateHash;BuildInvoked=$false;SideEffectsPerformed=$false}}
    $stageRoot=Join-Path ([IO.Path]::GetTempPath()) ('repato-qa-stage-'+[guid]::NewGuid().ToString('N'))
    $dllExisted=Test-Path $dllDestination -PathType Leaf;$manifestExisted=Test-Path $manifestDestination -PathType Leaf;$evidenceExisted=Test-Path $evidenceDestination -PathType Leaf
    New-Item $stageRoot -ItemType Directory|Out-Null
    try{
        $stagedDll=Join-Path $stageRoot 'Repato.Revit.dll';$stagedManifest=Join-Path $stageRoot $contract.Manifest;$stagedEvidence=Join-Path $stageRoot 'Repato.QaStaging.json'
        Copy-Item $dll $stagedDll;Copy-Item $sourceManifest $stagedManifest
        if((Get-FileHash $stagedDll).Hash -ine $candidateHash -or (Get-FileHash $stagedManifest).Hash -ine $sourceManifestHash){throw 'QA staging payload validation failed.'}
        [ordered]@{SchemaVersion='repato-qa-staging-v1';CandidateSourceCommit=$ExpectedSourceCommit;CandidateSha256=$candidateHash;QaWorkflowId=$QaWorkflowId;TestId=$TestId;RevitVersion=$RevitVersion;ManifestName=$contract.Manifest;ManifestSha256=$sourceManifestHash;StagedUtc=[DateTimeOffset]::UtcNow.ToString('O')}|ConvertTo-Json -Depth 5|Set-Content $stagedEvidence -Encoding UTF8
        if($FailureMode -ceq 'AfterPayloadValidation'){throw 'Synthetic failure after payload validation.'}
        New-Item $target -ItemType Directory -Force|Out-Null;New-Item $manifestBase -ItemType Directory -Force|Out-Null
        if($dllExisted){Copy-Item $dllDestination (Join-Path $stageRoot 'previous.dll')}
        if($manifestExisted){Copy-Item $manifestDestination (Join-Path $stageRoot 'previous.addin')}
        if($evidenceExisted){Copy-Item $evidenceDestination (Join-Path $stageRoot 'previous-evidence.json')}
        Copy-Item $stagedDll ($dllDestination+'.staging') -Force;Move-Item ($dllDestination+'.staging') $dllDestination -Force
        if($FailureMode -ceq 'AfterDllCommit'){throw 'Synthetic failure after DLL commit.'}
        Copy-Item $stagedManifest ($manifestDestination+'.staging') -Force;Move-Item ($manifestDestination+'.staging') $manifestDestination -Force
        Copy-Item $stagedEvidence ($evidenceDestination+'.staging') -Force;Move-Item ($evidenceDestination+'.staging') $evidenceDestination -Force
        if((Get-FileHash $dllDestination).Hash -ine $candidateHash -or (Get-FileHash $manifestDestination).Hash -ine $sourceManifestHash){throw 'Installed QA payload hash validation failed.'}
        $installedEvidence=Get-Content $evidenceDestination -Raw|ConvertFrom-Json
        if($installedEvidence.CandidateSourceCommit -cne $ExpectedSourceCommit -or $installedEvidence.CandidateSha256 -ine $candidateHash -or $installedEvidence.QaWorkflowId -cne $QaWorkflowId -or $installedEvidence.TestId -cne $TestId){throw 'Installed QA staging evidence validation failed.'}
        $validation=Test-TaraFrozenCandidateQaIsolation -CandidateDirectory $candidate -ExpectedArtifactSha256 $ExpectedArtifactSha256 -ExpectedSourceCommit $ExpectedSourceCommit -QaWorkflowId $QaWorkflowId -TestId $TestId -TargetRoot $target -ManifestRoot $manifestBase -QaSourceRoot $qaSource -MachineRoot $machine -TestLayout:$testMode
        $isolation=$validation.Isolation
        [pscustomobject]@{Success=$true;Mode='Installed';QaWorkflowId=$QaWorkflowId;TestId=$TestId;TargetRoot=$target;InstalledDllPath=$dllDestination;InstalledDllSha256=(Get-FileHash $dllDestination).Hash;InstalledManifestPath=$manifestDestination;InstalledManifestSha256=(Get-FileHash $manifestDestination).Hash;StagingEvidencePath=$evidenceDestination;StagingEvidenceSha256=(Get-FileHash $evidenceDestination).Hash;CandidateSourceCommit=$ExpectedSourceCommit;CandidateSha256=$candidateHash;ProvenancePath=$provenancePath;Isolation=$isolation;BuildInvoked=$false;SideEffectsPerformed=$true}
    }catch{
        if($dllExisted -and (Test-Path (Join-Path $stageRoot 'previous.dll'))){Copy-Item (Join-Path $stageRoot 'previous.dll') $dllDestination -Force}elseif(!$dllExisted -and (Test-Path $dllDestination)){Remove-Item $dllDestination -Force}
        if($manifestExisted -and (Test-Path (Join-Path $stageRoot 'previous.addin'))){Copy-Item (Join-Path $stageRoot 'previous.addin') $manifestDestination -Force}elseif(!$manifestExisted -and (Test-Path $manifestDestination)){Remove-Item $manifestDestination -Force}
        if($evidenceExisted -and (Test-Path (Join-Path $stageRoot 'previous-evidence.json'))){Copy-Item (Join-Path $stageRoot 'previous-evidence.json') $evidenceDestination -Force}elseif(!$evidenceExisted -and (Test-Path $evidenceDestination)){Remove-Item $evidenceDestination -Force}
        Remove-Item ($dllDestination+'.staging'),($manifestDestination+'.staging'),($evidenceDestination+'.staging') -Force -ErrorAction SilentlyContinue
        throw
    }finally{Remove-Item $stageRoot -Recurse -Force -ErrorAction SilentlyContinue}
}
Export-ModuleMember -Function Get-QaAddinDeploymentTarget,Test-QaAddinTarget,Invoke-QaAddinDeployment,Install-TaraFrozenCandidateForQa,Test-TaraFrozenCandidateQaIsolation,Test-TaraCandidateRunnerBinding
