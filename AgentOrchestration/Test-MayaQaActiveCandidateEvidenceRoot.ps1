$ErrorActionPreference='Stop'
$here=$PSScriptRoot
Import-Module (Join-Path $here 'Repato.AgentOrchestration.psm1') -Force
Import-Module (Join-Path $here 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
$taskId='task-active-candidate-root';$qa='create-plan-views-v1';$testId=$qa
$repo=[IO.Path]::GetFullPath((Join-Path $here '..'));$commit=(& git -C $repo rev-parse HEAD).Trim();$primaryRepo=[IO.Path]::GetFullPath((Split-Path -Parent ((& git -C $repo rev-parse --path-format=absolute --git-common-dir).Trim())));$candidateRoot=Join-Path $primaryRepo 'DeploymentCandidates\AgentBuilds';$folderName='SyntheticRootTest-'+[guid]::NewGuid().ToString('N');$inside=Join-Path $candidateRoot $folderName;$outside=Join-Path ([IO.Path]::GetTempPath()) ('candidate-outside-'+[guid]::NewGuid().ToString('N'));$store=Join-Path ([IO.Path]::GetTempPath()) ('candidate-root-store-'+[guid]::NewGuid().ToString('N'))
try {
    $bootstrap=New-MayaQaBootstrap -StoreRoot $store -QaWorkflowId $qa -RunId 'active-root-test' -TaskId $taskId
    $trustedRunner=Join-Path $repo ('QA\Repato.CreatePlanViews.TestRunner.addin');$runnerHash=(Get-FileHash $trustedRunner -Algorithm SHA256).Hash
    function New-CandidateFiles([string]$directory,[string]$sourceCommit) {
        New-Item -ItemType Directory -Path $directory -Force|Out-Null;$dll=Join-Path $directory 'Repato.Revit.dll';$provenance=Join-Path $directory 'release-manifest.json';[IO.File]::WriteAllText($dll,'synthetic frozen artifact');$dllHash=(Get-FileHash $dll -Algorithm SHA256).Hash;([ordered]@{SourceCommit=$sourceCommit;FrozenArtifactSha256=$dllHash}|ConvertTo-Json)|Set-Content -LiteralPath $provenance
        [pscustomobject]@{Directory=$directory;Dll=$dll;Hash=$dllHash;Provenance=$provenance}
    }
    $valid=New-CandidateFiles $inside $commit
    Invoke-RepatoStoreMutation $store {param($d,$preview)
        $t=Find-RepatoTask $d $taskId;$w=@($t.deploymentWorkflows|Where-Object workflowId -ceq $bootstrap.WorkflowId)[0];$w|Add-Member NoteProperty qaBuildStatus 'succeeded' -Force;$w|Add-Member NoteProperty qaBuildRequest ([pscustomobject]@{BuildRequestId='synthetic-build';AuthenticatedBuildSource=[pscustomobject]@{RepositoryRoot=$repo;ExpectedSourceCommit=$commit;ProjectRelativePath='Forma.RevitConnector.csproj'}}) -Force
        $w|Add-Member NoteProperty qaBuildEvidence ([pscustomobject]@{BuildRequestId='synthetic-build';BuildStatus='succeeded';EvidenceSource='FrozenCandidate';SourceCommit=$commit;CandidateSourceCommit=$commit;CandidateDirectory=$valid.Directory;CandidateProvenancePath=$valid.Provenance;ArtifactPath=$valid.Dll;ArtifactSha256=$valid.Hash;RunnerManifestPath=$trustedRunner;RunnerManifestSha256=$runnerHash}) -Force;$d
    }|Out-Null
    $accepted=New-MayaQaPersistedCandidateEvidence -StoreRoot $store -TaskId $taskId -WorkflowId $bootstrap.WorkflowId -QaWorkflowId $qa -TestId $testId
    if([IO.Path]::GetFullPath($accepted.CandidateDirectory) -ine [IO.Path]::GetFullPath($inside) -or $accepted.CandidateDllSha256 -ine $valid.Hash){throw 'Candidate under active repository allowlist was not accepted with exact hashes.'}
    $invalid=New-CandidateFiles $outside $commit
    Invoke-RepatoStoreMutation $store {param($d,$preview)$t=Find-RepatoTask $d $taskId;$w=@($t.deploymentWorkflows|Where-Object workflowId -ceq $bootstrap.WorkflowId)[0];$e=$w.qaBuildEvidence;$e.CandidateDirectory=$invalid.Directory;$e.CandidateProvenancePath=$invalid.Provenance;$e.ArtifactPath=$invalid.Dll;$e.ArtifactSha256=$invalid.Hash;$d}|Out-Null
    $rejected=$false;try{New-MayaQaPersistedCandidateEvidence -StoreRoot $store -TaskId $taskId -WorkflowId $bootstrap.WorkflowId -QaWorkflowId $qa -TestId $testId|Out-Null}catch{$rejected=$_.Exception.Message -match 'outside the approved candidate root'}
    if(!$rejected){throw 'Candidate outside active repository DeploymentCandidates\\AgentBuilds was not rejected.'}
    [pscustomobject]@{Status='PASS';ActiveRepositoryCandidateRoot=$candidateRoot;InRootAccepted=$true;OutOfRootRejected=$rejected;HashesAndProvenanceValidated=$true;StoreMutatedOnlySynthetic=$true}|ConvertTo-Json -Compress
} finally {foreach($path in @($inside,$outside,$store)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue}}}
