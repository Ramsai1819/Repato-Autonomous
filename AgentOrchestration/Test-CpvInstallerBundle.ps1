[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$RuntimeReleaseRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$RuntimeManifestSha256,
    [Parameter(Mandatory)][string]$RollbackReleaseRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$RollbackManifestSha256,
    [Parameter(Mandatory)][string]$FixedFixturePath,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$ToolCommit
)
$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $PSScriptRoot 'Repato.CpvInstallerBundle.psm1') -Force -PassThru
$script:assertions=0
function Assert([bool]$Value,[string]$Message){$script:assertions++;if(!$Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$script:assertions++;$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};if(!$failed){throw $Message}}
    $sourceCommit=(git -C $SourceRoot rev-parse HEAD).Trim();if($LASTEXITCODE -ne 0){throw 'Source checkout is unavailable.'}
    if($ToolCommit -cne (git -C (Split-Path $PSScriptRoot -Parent) rev-parse HEAD).Trim()){throw 'ToolCommit must identify the clean committed bundle tooling checkout.'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('cpv-installer-bundle-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
try {
    $out=Join-Path $temp 'bundles'
    $result=New-RepatoCpvInstallerBundle -SourceRoot $SourceRoot -SourceCommit $sourceCommit -RuntimeReleaseRoot $RuntimeReleaseRoot -RuntimeManifestSha256 $RuntimeManifestSha256 -RollbackReleaseRoot $RollbackReleaseRoot -RollbackManifestSha256 $RollbackManifestSha256 -FixedFixturePath $FixedFixturePath -ToolCommit $ToolCommit -BundleParent $out
    $valid=Test-RepatoCpvInstallerBundle -BundleRoot $result.BundleRoot -ExpectedManifestSha256 $result.ManifestSha256 -ExpectedSourceCommit $sourceCommit -ExpectedRuntimeManifestSha256 $RuntimeManifestSha256 -ExpectedRollbackManifestSha256 $RollbackManifestSha256 -ExpectedToolCommit $ToolCommit
    Assert ($valid.Valid -and $valid.SourceCommit -ceq $sourceCommit -and $valid.RuntimeVersion -ceq '1.0.18+4b0066247088' -and $valid.RollbackVersion -ceq '1.0.17+4b0066247088') 'Valid bundle identity did not round-trip.'
    Reject {Test-RepatoCpvInstallerBundle -BundleRoot $result.BundleRoot -ExpectedManifestSha256 $result.ManifestSha256 -ExpectedSourceCommit ('0'*40) -ExpectedRuntimeManifestSha256 $RuntimeManifestSha256 -ExpectedRollbackManifestSha256 $RollbackManifestSha256 -ExpectedToolCommit $ToolCommit} 'Wrong source commit was accepted.'
    Reject {Test-RepatoCpvInstallerBundle -BundleRoot $result.BundleRoot -ExpectedManifestSha256 $result.ManifestSha256 -ExpectedSourceCommit $sourceCommit -ExpectedRuntimeManifestSha256 $RuntimeManifestSha256 -ExpectedRollbackManifestSha256 ('0'*64) -ExpectedToolCommit $ToolCommit} 'Wrong rollback provenance was accepted.'
    Reject {Test-RepatoCpvInstallerBundle -BundleRoot $result.BundleRoot -ExpectedManifestSha256 $result.ManifestSha256 -ExpectedSourceCommit $sourceCommit -ExpectedRuntimeManifestSha256 $RuntimeManifestSha256 -ExpectedRollbackManifestSha256 $RollbackManifestSha256 -ExpectedToolCommit ('0'*40)} 'Wrong tooling commit was accepted.'
    $tamper=Join-Path $result.BundleRoot 'AgentOrchestration/Repato.QaLaunchAgentInstall.ps1';$original=[IO.File]::ReadAllBytes($tamper);[IO.File]::WriteAllText($tamper,'tampered')
    Reject {Test-RepatoCpvInstallerBundle -BundleRoot $result.BundleRoot -ExpectedManifestSha256 $result.ManifestSha256 -ExpectedSourceCommit $sourceCommit -ExpectedRuntimeManifestSha256 $RuntimeManifestSha256 -ExpectedRollbackManifestSha256 $RollbackManifestSha256 -ExpectedToolCommit $ToolCommit} 'Tampered bundle file was accepted.'
    [IO.File]::WriteAllBytes($tamper,$original)
    $missing=Join-Path $result.BundleRoot 'AgentOrchestration/Recover-CpvPreparationAgentInstall.ps1';$saved=[IO.File]::ReadAllBytes($missing);Remove-Item -LiteralPath $missing -Force
    Reject {Test-RepatoCpvInstallerBundle -BundleRoot $result.BundleRoot -ExpectedManifestSha256 $result.ManifestSha256 -ExpectedSourceCommit $sourceCommit -ExpectedRuntimeManifestSha256 $RuntimeManifestSha256 -ExpectedRollbackManifestSha256 $RollbackManifestSha256 -ExpectedToolCommit $ToolCommit} 'Missing bundle file was accepted.'
    [IO.File]::WriteAllBytes($missing,$saved)
    Reject {New-RepatoCpvInstallerBundle -SourceRoot $SourceRoot -SourceCommit ('0'*40) -RuntimeReleaseRoot $RuntimeReleaseRoot -RuntimeManifestSha256 $RuntimeManifestSha256 -RollbackReleaseRoot $RollbackReleaseRoot -RollbackManifestSha256 $RollbackManifestSha256 -FixedFixturePath $FixedFixturePath -ToolCommit $ToolCommit -BundleParent $out} 'Wrong source commit was packaged.'
    Reject {New-RepatoCpvInstallerBundle -SourceRoot $SourceRoot -SourceCommit $sourceCommit -RuntimeReleaseRoot $RuntimeReleaseRoot -RuntimeManifestSha256 $RuntimeManifestSha256 -RollbackReleaseRoot $RollbackReleaseRoot -RollbackManifestSha256 ('0'*64) -FixedFixturePath $FixedFixturePath -ToolCommit $ToolCommit -BundleParent $out} 'Wrong rollback release was packaged.'
    Reject {New-RepatoCpvInstallerBundle -SourceRoot $SourceRoot -SourceCommit $sourceCommit -RuntimeReleaseRoot $RuntimeReleaseRoot -RuntimeManifestSha256 $RuntimeManifestSha256 -RollbackReleaseRoot $RollbackReleaseRoot -RollbackManifestSha256 $RollbackManifestSha256 -FixedFixturePath $FixedFixturePath -ToolCommit $ToolCommit -BundleParent $out} 'Duplicate immutable bundle destination was accepted.'
    foreach($file in @('New-CpvInstallerBundle.ps1','Repato.CpvInstallerBundle.psm1')){$text=Get-Content -LiteralPath (Join-Path $PSScriptRoot $file) -Raw;foreach($forbidden in @('Start-Process','Start-ScheduledTask','Stop-ScheduledTask','Stop-Process','Invoke-CpvPreparationTransport','Revit.exe')){Assert (!$text.Contains($forbidden)) "Bundle tooling contains a live-operation reference: $forbidden"}}
    [pscustomobject]@{Test='CpvInstallerBundle';Assertions=$script:assertions;ValidBundle='PASS';MissingFileRejected='PASS';TamperingRejected='PASS';WrongSourceCommitRejected='PASS';WrongRollbackProvenanceRejected='PASS';DuplicateBundleRejected='PASS';LiveOperations='NotInvoked';BundleManifestSha256=$result.ManifestSha256}|ConvertTo-Json -Compress
} finally {
    $resolved=[IO.Path]::GetFullPath($temp);$tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(!$resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase) -or !$resolved.Contains('cpv-installer-bundle-test-')){throw 'Refusing to remove an unowned test directory.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
