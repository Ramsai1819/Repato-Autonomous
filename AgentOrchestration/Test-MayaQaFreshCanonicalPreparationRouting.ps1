$ErrorActionPreference='Stop'
$source=Get-Content (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Raw
if($source -notmatch 'Invoke-MayaQaCanonicalFrozenCandidateStagingValidation'){throw 'Fresh canonical route is missing the canonical staging boundary.'}
$start=$source.IndexOf('function Invoke-MayaQaRequest');$end=$source.IndexOf('function Invoke-MayaQaCanonicalTransaction');$body=$source.Substring($start,$end-$start)
if($body -notmatch 'Invoke-MayaQaCanonicalFrozenCandidateStagingValidation'){throw 'Fresh production entry point does not call canonical staging.'}
if($body -match 'if\(\$ValidateExistingDeployment -or \$StageFrozenCandidateForQa\)\)\{\$deploymentEvidence=if\(\$DeploymentValidationInvoker\)'){throw 'Fresh route still contains direct deployment validation.'}
if($body -notmatch 'Request-RepatoTaskApproval \$StoreRoot \$taskId ''qa-run'' ''maya'''){throw 'Fresh route does not establish approval lifecycle.'}
[pscustomobject]@{FreshEntryPoint='Invoke-MayaQaRequest';CanonicalBoundary='Invoke-MayaQaCanonicalFrozenCandidateStagingValidation';DirectValidationBypass=$false;ApprovalLifecycle='single-pending-qa-run';RealStoreTouched=$false;LivePipeRequestSent=$false}|ConvertTo-Json -Compress
