$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('repato-planviews-isolation-'+[guid]::NewGuid().ToString('N'))
try {
    $machine=Join-Path $root 'Machine';$user=Join-Path $root 'User';$qa=Join-Path $root 'QA'
    foreach($d in @($machine,$user,$qa)){New-Item -ItemType Directory -Path $d -Force|Out-Null}
    $source=Join-Path $qa 'Repato.CreatePlanViews.TestRunner.addin';Copy-Item (Join-Path $PSScriptRoot '..\QA\Repato.CreatePlanViews.TestRunner.addin') $source
    $policy=Join-Path $qa 'MachineWideAddins.allowlist.json';@{schemaVersion=1;machineWideRoot=$machine;approvedMachineWideManifests=@()}|ConvertTo-Json|Set-Content $policy
    function Assert-ChildPath([string]$Path,[string]$Parent){$full=[IO.Path]::GetFullPath($Path);if(!$full.StartsWith(([IO.Path]::GetFullPath($Parent).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'outside test root'};$full}
    function Get-Sha256([string]$Path){(Get-FileHash $Path -Algorithm SHA256).Hash}
    . (Join-Path $PSScriptRoot '..\QA\AddinIsolation.ps1')
    $approved=Join-Path $user 'Repato.CreatePlanViews.TestRunner.addin';Copy-Item $source $approved
    $good=Get-AddinIsolationInventory $policy $machine $user $qa 'Repato.CreatePlanViews.TestRunner.addin'
    if(!$good.Allowed){throw 'Create Plan Views runner was not accepted.'}
    $unexpected=Join-Path $user 'unexpected.addin';Set-Content $unexpected '<RevitAddIns />'
    $blocked=Get-AddinIsolationInventory $policy $machine $user $qa 'Repato.CreatePlanViews.TestRunner.addin'
    if($blocked.Allowed -or @($blocked.DetectedAddins|Where-Object Path -eq $unexpected|Where-Object Allowlisted).Count){throw 'Unexpected user-profile manifest was accepted.'}
    Remove-Item $unexpected
    Add-Content $approved 'tampered'
    $mismatch=Get-AddinIsolationInventory $policy $machine $user $qa 'Repato.CreatePlanViews.TestRunner.addin'
    if($mismatch.Allowed -or @($mismatch.DetectedAddins|Where-Object Path -eq $approved|Where-Object Allowlisted).Count){throw 'Hash-mismatched runner was accepted.'}
    $machineManifest=Join-Path $machine 'approved.addin';Set-Content $machineManifest '<RevitAddIns />'
    $machineResult=Get-AddinIsolationInventory $policy $machine $user $qa 'Repato.CreatePlanViews.TestRunner.addin'
    if($machineResult.Allowed){throw 'Unlisted machine-wide manifest was accepted.'}
    Write-Host 'Create Plan Views Tara isolation checks passed: 4'
} finally { if(Test-Path $root){Remove-Item $root -Recurse -Force} }
