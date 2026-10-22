$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent;$tara=Get-Content (Join-Path $PSScriptRoot 'Repato.TaraRevitQa.psm1') -Raw;$client=Get-Content (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Raw;$adapter=Get-Content (Join-Path $PSScriptRoot 'Invoke-RepatoQaDeploymentValidation.ps1') -Raw
function A([bool]$x,[string]$m){if(!$x){throw $m}}
A ($tara -match 'Invoke-MayaQaLaunchAgentDeploymentValidation') 'Tara does not use typed protected validation.'
A ($tara -match 'remoteDeployment' -and $tara -match 'Get-Content -LiteralPath \$\(if\(\$remoteDeployment\)') 'Protected read bypass missing.'
A ($adapter -match 'Test-TaraFrozenCandidateQaIsolation') 'Authoritative isolation validator not retained.'
A ($adapter -notmatch 'Start-Process|Invoke-Expression|Copy-Item|Set-Content') 'Validation adapter accepts arbitrary execution or mutation.'
A ($client -match 'validate-qa-deployment' -and $client -match 'validationIdentity') 'Typed client/result validation missing.'
A ($tara -match 'if\(\$remoteDeployment\).*Allowed') 'Forged/failed validation does not gate plan.'
A ($tara -match 'manifestIntegrityPassed' -and $tara -match 'elseif\(\(Get-TaraSha256 \$manifest\)') 'Manifest evidence gate or local-only fallback missing.'
A ($tara -match 'Test-TaraLegacyDeploymentManifestCompatibility') 'Legacy deployment manifest compatibility is not applied at the Tara plan boundary.'
'QA deployment preflight boundary checks passed: protected read moved to RepatoQA, authoritative isolation retained, typed identity/hash binding, no client path/command authority, and fail-closed plan gating.'
