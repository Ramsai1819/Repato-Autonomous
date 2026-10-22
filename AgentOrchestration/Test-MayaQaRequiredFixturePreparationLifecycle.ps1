$ErrorActionPreference='Stop'
$modulePath=Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1'
$source=Get-Content -LiteralPath $modulePath -Raw

$requestStart=$source.IndexOf('function Invoke-MayaQaRequest')
$requestEnd=$source.IndexOf('function Invoke-MayaQaCanonicalTransaction')
if($requestStart -lt 0 -or $requestEnd -le $requestStart){throw 'Invoke-MayaQaRequest source boundary was not found.'}
$requestBody=$source.Substring($requestStart,$requestEnd-$requestStart)
if($requestBody -notmatch '\[string\]\$FixturePreparationResultPath'){
    throw 'Production request entry point does not accept fixture-preparation evidence.'
}
if($requestBody -notmatch 'New-MayaQaRun[^\r\n]+-FixturePreparationResultPath \$FixturePreparationResultPath'){
    throw 'Production request entry point does not forward fixture-preparation evidence to run creation.'
}

$transactionBody=$source.Substring($requestEnd,$source.IndexOf('function Invoke-MayaQaSingleCanonicalAttempt')-$requestEnd)
if($transactionBody -notmatch '\[string\]\$FixturePreparationResultPath' -or $transactionBody -notmatch 'Invoke-MayaQaRequest[^\r\n]+-FixturePreparationResultPath \$FixturePreparationResultPath'){
    throw 'Canonical transaction does not route fixture-preparation evidence into the production request.'
}

$runStart=$source.IndexOf('function New-MayaQaRun')
$runEnd=$source.IndexOf('function Register-MayaQaReport')
if($runStart -lt 0 -or $runEnd -le $runStart){throw 'New-MayaQaRun source boundary was not found.'}
$runBody=$source.Substring($runStart,$runEnd-$runStart)
$guard=$runBody.IndexOf("if(`$QaWorkflowId -ceq 'create-plan-views-v1' -and [string]::IsNullOrWhiteSpace(`$FixturePreparationResultPath))")
$mutation=$runBody.IndexOf('Invoke-RepatoWorkflowMutation')
if($guard -lt 0 -or $mutation -lt 0 -or $guard -gt $mutation){
    throw 'Create Plan Views missing-evidence guard is absent or occurs after persistence.'
}
if($runBody -notmatch "throw 'Create Plan Views QA run requires correlated fixture-preparation evidence before approval or execution preparation\.'"){
    throw 'Create Plan Views missing-evidence rejection is not explicit.'
}

[pscustomobject]@{
    Passed=$true
    ProductionEntryAcceptsEvidence=$true
    EvidenceForwardedToRunCreation=$true
    CanonicalTransactionRoutesEvidence=$true
    MissingEvidenceRejectedBeforePersistence=$true
    RevitLaunched=$false
}|ConvertTo-Json -Compress
