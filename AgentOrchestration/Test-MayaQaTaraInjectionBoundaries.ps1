$ErrorActionPreference='Stop'
$tara=Get-Content (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Raw
$maya=Get-Content (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Raw
if($tara -notmatch '\[scriptblock\]\$SessionValidationInvoker'){throw 'Session validation boundary is missing.'}
if($tara -notlike '*if(!$DryRun){if($SessionValidationInvoker){& $SessionValidationInvoker}else{Assert-TaraInteractiveSession}}*'){throw 'Session production default is missing.'}
if($maya -notmatch '\[scriptblock\]\$PlanPreflightInvoker'){throw 'Tara plan preflight boundary is missing.'}
if($maya -notmatch 'if\(\$PlanPreflightInvoker\)\{& \$PlanPreflightInvoker'){throw 'Plan injection is missing.'}
if($maya -notlike '*New-TaraRevitQaPlan*SessionValidationInvoker $SessionValidationInvoker*'){throw 'Plan production default is missing.'}
$execution=Get-Content (Join-Path $PSScriptRoot 'MayaQa.TaraExecution.ps1') -Raw
if($execution -notmatch '\[ValidateRange\(1,86400\)\]\[int\]\$TimeoutSeconds\s*=\s*900'){throw 'Tara controller timeout does not accept the full one-day execution window.'}
if($maya -notmatch '\[ValidateRange\(1,86400\)\]\[int\]\$TimeoutSeconds=7200' -or $execution -notmatch 'Resume-MayaQaCanonicalExecution[^\r\n]*-TimeoutSeconds \$TimeoutSeconds'){throw 'Canonical result wait must accept and forward a configurable timeout of at least 7200 seconds.'}
'Focused Tara boundary and timeout-contract checks passed: 6'
