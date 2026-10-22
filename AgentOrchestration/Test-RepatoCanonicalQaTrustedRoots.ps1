$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
$module=Get-Module Repato.AgentOrchestration
$roots=& $module { Get-RepatoCanonicalQaTrustedRoots }
$expectedPrimary=[IO.Path]::GetFullPath('C:\Repato-Autonomous\Source')
$expectedCandidateRoot=[IO.Path]::GetFullPath((Join-Path $expectedPrimary 'DeploymentCandidates\AgentBuilds'))
$expectedQaRoot=[IO.Path]::GetFullPath((Join-Path $expectedPrimary 'QA'))
if([IO.Path]::GetFullPath($roots.PrimaryRepositoryRoot) -ine $expectedPrimary -or
    [IO.Path]::GetFullPath($roots.CandidateRoot) -ine $expectedCandidateRoot -or
    [IO.Path]::GetFullPath($roots.QaRoot) -ine $expectedQaRoot){
    throw 'Approval trusted roots must derive from the primary repository shared by the isolated worktree.'
}
$candidate=Join-Path $expectedCandidateRoot 'ReleaseCandidate-test'
$runner=Join-Path $expectedQaRoot 'Repato.CreatePlanViews.TestRunner.addin'
$candidatePrefixSibling=$expectedCandidateRoot+'-untrusted\ReleaseCandidate-test'
$qaPrefixSibling=$expectedQaRoot+'-untrusted\Repato.CreatePlanViews.TestRunner.addin'
$outside='C:\Repato-Autonomous\outside\Repato.CreatePlanViews.TestRunner.addin'
$checks=@(
    [pscustomobject]@{Name='primary candidate accepted';Path=$candidate;Root=$roots.CandidateRoot;Expected=$true},
    [pscustomobject]@{Name='primary runner accepted';Path=$runner;Root=$roots.QaRoot;Expected=$true},
    [pscustomobject]@{Name='worktree candidate rejected';Path=(Join-Path $roots.WorktreeRoot 'DeploymentCandidates\AgentBuilds\candidate');Root=$roots.CandidateRoot;Expected=$false},
    [pscustomobject]@{Name='worktree runner rejected';Path=(Join-Path $roots.WorktreeRoot 'QA\Repato.CreatePlanViews.TestRunner.addin');Root=$roots.QaRoot;Expected=$false},
    [pscustomobject]@{Name='candidate prefix sibling rejected';Path=$candidatePrefixSibling;Root=$roots.CandidateRoot;Expected=$false},
    [pscustomobject]@{Name='QA prefix sibling rejected';Path=$qaPrefixSibling;Root=$roots.QaRoot;Expected=$false},
    [pscustomobject]@{Name='unrelated root rejected';Path=$outside;Root=$roots.QaRoot;Expected=$false}
)
foreach($check in $checks){
    $actual=& $module {param($path,$root) Test-RepatoPathWithinTrustedRoot -Path $path -Root $root} $check.Path $check.Root
    if([bool]$actual -ne $check.Expected){throw "Trusted-root containment mismatch: $($check.Name)."}
}
$emptyRejected=$false
try{& $module {param($root) Test-RepatoPathWithinTrustedRoot -Path '' -Root $root} $roots.QaRoot|Out-Null}catch{$emptyRejected=$true}
if(!$emptyRejected){throw 'An empty approval path must be rejected.'}
[pscustomobject]@{Status='PASS';Assertions=($checks.Count+2);PrimaryRepositoryRoot=$roots.PrimaryRepositoryRoot;CandidateRoot=$roots.CandidateRoot;QaRoot=$roots.QaRoot;AuthorizedCandidateAccepted=$true;AuthorizedRunnerAccepted=$true;OutsideRootsRejected=$true;PrefixSiblingsRejected=$true}|ConvertTo-Json -Compress
