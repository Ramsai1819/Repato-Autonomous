$ErrorActionPreference='Stop'
$module=Import-Module (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Force -PassThru
$root='C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA'
$runner=Join-Path (Split-Path $root -Parent) 'Repato.CreatePlanViews.TestRunner.addin'
$hash='AF4DBFA78E61524DE7BD3B84178C6B70ED8D29D0A95BA17780826E09BE689D4F'
$candidate='7EC1C819C771DCE4EC4ADCADB93B0245D243F6675EC0F0B070B03303B1F412C2'
$cases=@()
function New-Response {
    [pscustomobject]@{schemaVersion=1;operation='validate-qa-deployment';requestId='synthetic';succeeded=$true;validationIdentity='RAMSAI\RepatoQA';qaWorkflowId='create-plan-views-v1';testId='create-plan-views-v1';candidateSha256='7EC1C819C771DCE4EC4ADCADB93B0245D243F6675EC0F0B070B03303B1F412C2';qaAddinRoot=$root;runnerManifestPath=$runner;runnerManifestSha256=$hash;isolationPassed=$true;manifestIntegrityEvidenceAvailable=$false;manifestIntegrityPassed=$null}
}
function Assert-Case([string]$Name,[scriptblock]$Mutation,[bool]$Expected) {
    $response=New-Response
    & $Mutation $response
    $actual=& $module { param($r,$c,$q,$p,$h) Test-TaraLegacyDeploymentManifestCompatibility $r $c $q $p $h } $response $candidate $root $runner $hash
    if($actual -ne $Expected){throw "$Name expected $Expected but got $actual"}
    $script:cases += [pscustomobject]@{Name=$Name;Passed=$true}
}
Assert-Case 'modern true' {param($r)$r.manifestIntegrityPassed=$true;$r.manifestIntegrityEvidenceAvailable=$true} $true
Assert-Case 'legacy absent' {param($r)$r.PSObject.Properties.Remove('manifestIntegrityPassed');$r.PSObject.Properties.Remove('manifestIntegrityEvidenceAvailable')} $true
Assert-Case 'legacy unavailable' {param($r)$r.manifestIntegrityPassed=$null;$r.manifestIntegrityEvidenceAvailable=$false} $true
Assert-Case 'explicit false' {param($r)$r.manifestIntegrityPassed=$false;$r.manifestIntegrityEvidenceAvailable=$true} $false
Assert-Case 'candidate mismatch' {param($r)$r.candidateSha256='0'*64} $false
Assert-Case 'runner mismatch' {param($r)$r.runnerManifestSha256='0'*64} $false
Assert-Case 'installed path mismatch' {param($r)$r.runnerManifestPath='C:\wrong.addin'} $false
Assert-Case 'QA root mismatch' {param($r)$r.qaAddinRoot='C:\Users\Other\RepatoQA'} $false
Assert-Case 'identity mismatch' {param($r)$r.validationIdentity='RAMSAI\Other'} $false
Assert-Case 'isolation failure' {param($r)$r.isolationPassed=$false} $false
Assert-Case 'deployment failure' {param($r)$r.succeeded=$false} $false
Assert-Case 'missing binding' {param($r)$r.PSObject.Properties.Remove('runnerManifestSha256')} $false
Assert-Case 'explicit failure evidence' {param($r)$r|Add-Member NoteProperty errorCode 'manifest-hash-mismatch' -Force} $false
[pscustomobject]@{FocusedCasesPassed=$cases.Count;FocusedCasesTotal=$cases.Count;NativeRequestSent=$false;RevitLaunched=$false}|ConvertTo-Json -Compress
