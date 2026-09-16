[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('Install','Run','Verify')][string]$Action,[string]$ReceiptPath,[ValidateRange(30,900)][int]$TimeoutSeconds=900)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$repoRoot='C:\Repato-Autonomous\Source';$runsRoot=Join-Path $repoRoot 'QA\TestRuns';$reportsRoot=Join-Path $repoRoot 'QA\Reports';$screenshotsRoot=Join-Path $repoRoot 'QA\Screenshots'
$testId='welcome-supervised-dialog-v1';$manifestName='Repato.WelcomeSmoke.TestRunner.addin'
. (Join-Path $PSScriptRoot 'Foundation\QaRunner.Foundation.ps1');. (Join-Path $PSScriptRoot 'AddinIsolation.ps1')

# AddinIsolation.ps1 is shared with the established controllers and intentionally
# uses their helper contract. Map that contract to the reusable foundation.
function Assert-ChildPath([string]$Path,[string]$Parent) {
    Assert-RepatoQaChildPath $Path $Parent
}
function Get-Sha256([string]$Path) {
    Get-RepatoQaSha256 $Path
}

function Invoke-WelcomeIsolationPreflight {
    param(
        [string]$PolicyPath,
        [string]$MachineRoot,
        [string]$UserRoot,
        [string]$QaSourceRoot,
        [string]$DiagnosticPath,
        [string]$Phase = $Action,
        [string]$IsolationTestId = $testId
    )
    $DiagnosticPath = Assert-RepatoQaChildPath $DiagnosticPath $reportsRoot
    $outputs = @()
    $inventory = $null
    $failure = $null
    try {
        $outputs = @(Get-AddinIsolationInventory -PolicyPath $PolicyPath -MachineRoot $MachineRoot `
            -UserRoot $UserRoot -QaSourceRoot $QaSourceRoot)
        if ($outputs.Count -ne 1) { throw "Expected exactly one inventory object; received $($outputs.Count)." }
        $inventory = $outputs[0]
        if ($null -eq $inventory -or $inventory -isnot [pscustomobject]) { throw 'Inventory output is not a PSCustomObject.' }
        foreach ($property in @('PolicyPath','PolicySha256','DetectedAddins','Errors','Allowed')) {
            if ($inventory.PSObject.Properties.Name -notcontains $property) { throw "Inventory is missing property: $property" }
        }
        $inventory.DetectedAddins = [object[]]@($inventory.DetectedAddins)
        $inventory.Errors = [object[]]@($inventory.Errors)
        if ($inventory.Allowed -isnot [bool] -or $inventory.PolicyPath -ine $PolicyPath -or
            $inventory.PolicySha256 -notmatch '^[0-9A-Fa-f]{64}$') {
            throw 'Inventory policy identity or Allowed value is malformed.'
        }
        foreach ($item in $inventory.DetectedAddins) {
            foreach ($property in @('Scope','Path','Sha256','Allowlisted','Reason')) {
                if ($null -eq $item -or $item.PSObject.Properties.Name -notcontains $property) { throw "Manifest record missing $property" }
            }
            if ($item.Allowlisted -isnot [bool] -or $item.Scope -notin @('MachineWide','UserProfile') -or
                $item.Sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw 'Malformed manifest record.' }
        }
        if (!$inventory.Allowed -or $inventory.Errors.Count -ne 0 -or
            @($inventory.DetectedAddins | Where-Object { !$_.Allowlisted }).Count -ne 0) {
            throw 'Add-in inventory is blocked; inspect errors and manifest decisions.'
        }
    }
    catch { $failure = $_.Exception.Message }

    $diagnostic = [ordered]@{
        Phase = $Phase
        TestId = $IsolationTestId
        Status = $(if ($failure) { 'Blocked' } else { 'Allowed' })
        PolicyPath = $(if ($inventory) { $inventory.PolicyPath } else { $PolicyPath })
        PolicySha256 = $(if ($inventory) { $inventory.PolicySha256 } else { '' })
        Allowed = $(if ($inventory) { $inventory.Allowed } else { $false })
        DetectedAddins = [object[]]@($(if ($inventory) { $inventory.DetectedAddins }))
        Errors = [object[]]@($(if ($inventory) { $inventory.Errors }))
        OutputCount = $outputs.Count
        Error = $failure
        RecordedUtc = [DateTimeOffset]::UtcNow.ToString('O')
    }
    Write-RepatoQaJsonAtomic $DiagnosticPath $diagnostic
    if ($failure) { throw "Welcome isolation blocked: $failure Report: $DiagnosticPath" }
    return $inventory
}

function Verify-WelcomeResult([string]$Path){
    $Path=Assert-RepatoQaChildPath $Path $runsRoot $true
    if(!$Path.EndsWith('.request.json.result.json',[StringComparison]::Ordinal)){throw 'Select a Welcome request receipt.'}
    $requestPath=$Path.Substring(0,$Path.Length-'.result.json'.Length);$request=Get-Content $requestPath -Raw|ConvertFrom-Json;$receipt=Get-Content $Path -Raw|ConvertFrom-Json
    $reportPath=Assert-RepatoQaChildPath $receipt.ReportPath $reportsRoot $true;$report=Get-Content $reportPath -Raw|ConvertFrom-Json
    if($receipt.Status-cne'Passed'-or$report.Status-cne'Passed'){throw "Welcome smoke failed. Preserved report: $reportPath; errors: $($report.Errors-join'; ')"}
    Assert-ReportedAddinIsolation $request.addinIsolation $report.AddinIsolation
    if($request.testId-cne$testId-or$report.TestId-cne$testId-or$receipt.RequestId-cne$request.requestId-or$receipt.RunId-cne$report.RunId){throw 'Run identity mismatch.'}
    if($report.FixtureId-cne'CreateLevelsEmpty'-or$report.DocumentPath-ine$request.modelPath-or$report.AssemblyIdentity.Sha256-ine$request.assemblySha256){throw 'Fixture or artifact identity mismatch.'}
    $required=@('addin-isolation','fixture-content-policy','safety-gate','command-result','dialog-observed','dialog-window-title','dialog-title','dialog-message','screenshot-dialog','model-file-unchanged','model-elements-unchanged','rollback-status','baseline-restored')
    foreach($id in $required){if(@($report.Assertions|Where-Object{$_.Id-ceq$id-and$_.Passed-eq$true}).Count-ne1){throw "Missing or failed assertion: $id"}}
    if($report.Inputs.Mode-cne'Supervised UI'-or$report.Inputs.ExpectedTitle-cne'Repato'-or
        $report.Inputs.ExpectedVisibleWindowTitle-cne'Repato Welcome Smoke QA Startup - Repato'-or
        $report.Inputs.ExpectedMessage-cne"Repato is running successfully.`n`nNext: Create Grids."){throw 'Unexpected dialog contract.'}
    if(@($report.Screenshots).Count-ne1-or$report.Screenshots[0].Phase-cne'dialog'){throw 'Dialog screenshot evidence missing.'}
    $image=Assert-RepatoQaChildPath $report.Screenshots[0].Path $screenshotsRoot $true
    if((Get-RepatoQaSha256 $image)-ine$report.Screenshots[0].Sha256){throw 'Screenshot hash mismatch.'}
    if((Get-RepatoQaSha256 $request.modelPath)-ine$report.FixtureSha256-or(Get-RepatoQaSha256 (Join-Path $repoRoot 'QA\Fixtures\CreateLevelsEmpty.rvt'))-ine$report.FixtureSha256){throw 'Disposable model changed.'}
    Write-Host "PASSED supervised Welcome smoke: $reportPath"
}
if($Action-eq'Verify'){if(!$ReceiptPath){throw '-ReceiptPath is required.'};Verify-WelcomeResult $ReceiptPath;return}
if($env:USERNAME-ine'RepatoQA'){throw 'Install and Run require the RepatoQA Windows account.'}
if(Get-Process Revit -ErrorAction SilentlyContinue){throw 'Close Revit before a fresh supervised run.'}
$addinsRoot=Join-Path $env:APPDATA 'Autodesk\Revit\Addins\2025';$deployRoot=Assert-RepatoQaChildPath (Join-Path $addinsRoot 'RepatoQA') $env:APPDATA
$builtDll=Assert-RepatoQaChildPath (Join-Path $repoRoot 'bin\Release\net8.0-windows\Repato.Revit.dll') $repoRoot $true;$installedDll=Join-Path $deployRoot 'Repato.Revit.dll';$installedManifest=Join-Path $addinsRoot $manifestName
$policyPath=Join-Path $repoRoot 'QA\MachineWideAddins.allowlist.json'
$isolationReport=Join-Path $reportsRoot ('isolation-'+[guid]::NewGuid().ToString('N')+'.json')
$isolation=Invoke-WelcomeIsolationPreflight -PolicyPath $policyPath `
    -MachineRoot 'C:\ProgramData\Autodesk\Revit\Addins\2025' -UserRoot $addinsRoot `
    -QaSourceRoot (Join-Path $repoRoot 'QA') -DiagnosticPath $isolationReport
if($Action-eq'Install'){
    New-Item -ItemType Directory -Path $deployRoot -Force|Out-Null
    foreach($name in @('Repato.Revit.dll','Repato.Revit.deps.json','Repato.Revit.pdb')){$source=Join-Path ([IO.Path]::GetDirectoryName($builtDll)) $name;if(Test-Path $source){Copy-Item $source (Join-Path $deployRoot $name) -Force}}
    Copy-Item (Join-Path $repoRoot ('QA\'+$manifestName)) $installedManifest -Force
    if((Get-RepatoQaSha256 $builtDll)-ine(Get-RepatoQaSha256 $installedDll)){throw 'Deployment hash mismatch.'};Write-Host "Installed supervised Welcome QA: $installedDll";return
}
if(!(Test-Path $installedManifest)-or(Get-RepatoQaSha256 $builtDll)-ine(Get-RepatoQaSha256 $installedDll)){throw 'Install current build first.'}
if((Get-RepatoQaSha256 $installedManifest)-ine(Get-RepatoQaSha256 (Join-Path $repoRoot ('QA\'+$manifestName)))){throw 'Installed manifest differs from source.'}
$fixture=Join-Path $repoRoot 'QA\Fixtures\CreateLevelsEmpty.rvt';$identity=Read-RepatoQaFixtureProvenance $fixture (Join-Path $repoRoot 'QA\Fixtures\CreateLevelsEmpty.provenance.json') 'CreateLevelsEmpty' @()
$run=New-RepatoQaRun $runsRoot 'welcome-smoke' 'welcome.request.json' $testId $fixture $identity (Get-RepatoQaSha256 $installedDll) $isolation $TimeoutSeconds
$process=Start-RepatoQaRevit 'E:\revit\Revit 2025\Revit.exe' 'REPATO_QA_WELCOME_REQUEST' $run.RequestPath ($run.RequestPath+'.launch.log') "manifest=$installedManifest; dll=$installedDll; request=$($run.RequestPath); supervised=true" -Visible
try{Wait-RepatoQaResult $process $run.ResultPath $TimeoutSeconds $run.RunDirectory|Out-Null;Verify-WelcomeResult $run.ResultPath}
catch{$controller=Join-Path $reportsRoot ('controller-'+$run.RequestId+'.json');Write-RepatoQaDiagnostic $controller 'Run' $testId 'Incomplete' @{error=$_.Exception.Message;processId=$process.Id;runDirectory=$run.RunDirectory};throw}
Write-Host 'Supervised dialog was dismissed. Revit remains open on the disposable fixture; close without saving.';Write-Output $run.ResultPath
