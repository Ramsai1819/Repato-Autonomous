$ErrorActionPreference='Stop'
$module=Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1'
Import-Module $module -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('repato-frozen-'+[guid]::NewGuid().ToString('N'))
$candidate=Join-Path $scratch 'candidate';New-Item $candidate -ItemType Directory -Force|Out-Null
$dll=Join-Path $candidate 'Repato.Revit.dll';[IO.File]::WriteAllBytes($dll,[Text.Encoding]::UTF8.GetBytes('synthetic frozen dll bytes'))
$addin=Join-Path $candidate 'Repato.addin';Set-Content -LiteralPath $addin '<RevitAddIns></RevitAddIns>' -Encoding UTF8
$hash=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash;$commit='1234567890abcdef1234567890abcdef12345678'
@{CandidateType='SyntheticReleaseCandidate';SourceCommit=$commit;FrozenArtifactSha256=$hash;SupportedQaWorkflows=@('create-plan-views-v1')}|ConvertTo-Json|Set-Content (Join-Path $candidate 'release-manifest.json') -Encoding UTF8
$passed=0
function Check([bool]$Condition,[string]$Name){if(!$Condition){throw "FAILED: $Name"};$script:passed++}
function Reject([scriptblock]$Action,[string]$Name){$rejected=$false;try{&$Action|Out-Null}catch{$rejected=$true};Check $rejected $Name}
try{
  $v=Test-MayaQaFrozenCandidate $candidate '' $hash $commit 'create-plan-views-v1'
  Check ($v.ArtifactSha256 -ceq $hash) 'calculated hash accepted'
  Check ($v.SourceCommit -ceq $commit) 'provenance accepted'
  Check ($v.QaWorkflowId -ceq 'create-plan-views-v1') 'workflow compatibility accepted'
  Check ($v.ManifestSha256 -ceq (Get-FileHash $addin).Hash) 'manifest evidence calculated'
  Reject {Test-MayaQaFrozenCandidate $candidate '' ('0'*64) $commit 'create-plan-views-v1'} 'wrong hash rejected'
  $moved=$dll+'.missing';Move-Item $dll $moved;Reject {Test-MayaQaFrozenCandidate $candidate '' $hash $commit 'create-plan-views-v1'} 'missing DLL rejected';Move-Item $moved $dll
  Reject {Test-MayaQaFrozenCandidate $candidate '' $hash ('f'*40) 'create-plan-views-v1'} 'source commit mismatch rejected'
  Reject {Test-MayaQaFrozenCandidate $candidate '' $hash $commit 'grid-resequence-v1'} 'incompatible workflow rejected'
  $outside=Join-Path $scratch 'outside.dll';Copy-Item $dll $outside;Reject {Test-MayaQaFrozenCandidate $candidate $outside $hash $commit 'create-plan-views-v1'} 'DLL path escape rejected'
  $missingStore=Join-Path $scratch 'must-not-exist';Reject {Invoke-MayaQaFrozenCandidateEvidence $missingStore 'task' 'workflow' 'create-plan-views-v1' $candidate '' ('0'*64) $commit} 'validation fails before state';Check (!(Test-Path $missingStore)) 'no state created on validation failure'
  $source=Get-Content $module -Raw
  Check ($source -match "ArtifactMode='Build'" -and $source -match "ArtifactMode -ceq 'FrozenCandidate'" -and $source -match 'Invoke-MayaQaBuildExecute') 'default build and explicit frozen paths preserved'
  $store=Join-Path $scratch 'controller-store'
  Reject {Invoke-MayaQaRequest -StoreRoot $store -UserRequest 'Create floor plan views for Levels 0, 1, and 2 at 1:100 using the architectural template, named by level' -ArtifactMode FrozenCandidate -CandidateDirectory $candidate -ExpectedCandidateSha256 $hash -ExpectedCandidateSourceCommit $commit} 'legacy frozen flow without source-bound build evidence rejected'
  [pscustomobject]@{Status='PASS';AssertionsPassed=$passed;AssertionsFailed=0;VerifiedArtifactSha256=$v.ArtifactSha256;BuildSkipped=$true;StateCreatedOnFailure=$false}|ConvertTo-Json -Compress
}finally{Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue}
