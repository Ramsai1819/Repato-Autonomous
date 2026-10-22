$ErrorActionPreference='Stop'
Set-ExecutionPolicy -Scope Process Bypass -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
$workflowModule=Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -PassThru -WarningAction SilentlyContinue

$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$primaryRepo=[IO.Path]::GetFullPath((Split-Path -Parent ((& git -C $repo rev-parse --path-format=absolute --git-common-dir).Trim())))
$sourceCommit=(& git -C $repo rev-parse HEAD).Trim()
$candidate=Join-Path $primaryRepo ('DeploymentCandidates\AgentBuilds\ReleaseCandidate-'+$sourceCommit.Substring(0,12))
$dll=Join-Path $candidate 'Repato.Revit.dll'
$manifest=Join-Path $candidate 'Repato.addin'
$provenance=Join-Path $candidate 'release-manifest.json'
$artifactHash=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash
$manifestHash=(Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
$store=Join-Path ([IO.Path]::GetTempPath()) ('maya-frozen-build-adoption-'+[guid]::NewGuid().ToString('N'))
$taskId='task-frozen-build-adoption-'+[guid]::NewGuid().ToString('N')
$runner=Join-Path $repo 'QA\Repato.CreatePlanViews.TestRunner.addin'
$runnerHash=(Get-FileHash -LiteralPath $runner -Algorithm SHA256).Hash

try {
    $boot=New-MayaQaBootstrap -StoreRoot $store -TaskId $taskId -QaWorkflowId 'create-plan-views-v1' -RunId ('adoption-'+[guid]::NewGuid().ToString('N'))
    $data=Read-RepatoTaskStore $store
    $task=Find-RepatoTask $data $taskId
    $workflow=@($task.deploymentWorkflows|Where-Object workflowId -ceq $boot.WorkflowId)[0]
    $approvalCount=@($task.approvalRequests).Count
    $approvalStatuses=@($task.approvalRequests|ForEach-Object status)
    & $workflowModule {
    param($storeRoot,$id,$wid,$workflowRevision,$taskRevision,$source,$artifact,$artifactSha256,$addinManifest,$addinManifestSha256,$worktreeRoot)
    Invoke-RepatoWorkflowMutation $storeRoot $id $wid $workflowRevision $taskRevision {
        param($w)
        $w|Add-Member NoteProperty qaBuildStatus 'succeeded' -Force
        $w|Add-Member NoteProperty qaBuildRequest ([pscustomobject]@{BuildRequestId='synthetic-release-build';AuthenticatedBuildSource=[pscustomobject]@{RepositoryRoot=$worktreeRoot;ExpectedSourceCommit=$source;ProjectRelativePath='Forma.RevitConnector.csproj'}}) -Force
        $w|Add-Member NoteProperty qaBuildEvidence ([pscustomobject]@{
            BuildRequestId='synthetic-release-build';BuildStatus='succeeded';SourceCommit=$source
            ArtifactPath=$artifact;ArtifactSha256=$artifactSha256
            ManifestPath=$addinManifest;ManifestSha256=$addinManifestSha256
        }) -Force
        return $w
    }|Out-Null
    } $store $taskId $boot.WorkflowId $workflow.workflowRevision $task.revision $sourceCommit (Join-Path $repo 'bin\Release\net8.0-windows\Repato.Revit.dll') $artifactHash $manifest $manifestHash $repo

    $adopted=Invoke-MayaQaFrozenCandidateEvidence -StoreRoot $store -TaskId $taskId -WorkflowId $boot.WorkflowId -QaWorkflowId 'create-plan-views-v1' -CandidateDirectory $candidate -CandidateDllPath $dll -ExpectedSha256 $artifactHash -ExpectedSourceCommit $sourceCommit
    $after=Find-RepatoTask (Read-RepatoTaskStore $store) $taskId
    $bound=@($after.deploymentWorkflows|Where-Object workflowId -ceq $boot.WorkflowId)[0]
    if($adopted.EvidenceSource -cne 'FrozenCandidate' -or $bound.qaBuildEvidence.ArtifactSha256 -cne $artifactHash -or $bound.qaBuildEvidence.ManifestSha256 -cne $manifestHash -or $bound.qaBuildEvidence.RunnerManifestSha256 -cne $runnerHash){throw 'Release build candidate did not persist exact artifact, add-in manifest, and runner manifest bindings.'}
    if(@($after.approvalRequests).Count -ne $approvalCount -or (@($after.approvalRequests|ForEach-Object status) -join ',') -cne ($approvalStatuses -join ',') -or @('mayaTaraAttempt','mayaTaraExecution','mayaTaraQaPacket','mayaTaraExecutionEvidence'|Where-Object {$after.PSObject.Properties.Name -contains $_ -and $after.$_}).Count){throw 'Candidate evidence adoption crossed or damaged the approval boundary.'}

    $badArtifact=$false
    try { Invoke-MayaQaFrozenCandidateEvidence -StoreRoot $store -TaskId $taskId -WorkflowId $boot.WorkflowId -QaWorkflowId 'create-plan-views-v1' -CandidateDirectory $candidate -CandidateDllPath $dll -ExpectedSha256 ('0'*64) -ExpectedSourceCommit $sourceCommit | Out-Null }
    catch { $badArtifact=$_.Exception.Message -match 'SHA-256 mismatch' }
    if(!$badArtifact){throw 'Candidate artifact hash mismatch was not rejected.'}

    $state=Find-RepatoTask (Read-RepatoTaskStore $store) $taskId
    $w=@($state.deploymentWorkflows|Where-Object workflowId -ceq $boot.WorkflowId)[0]
    & $workflowModule {
    param($storeRoot,$id,$wid,$workflowRevision,$taskRevision)
    Invoke-RepatoWorkflowMutation $storeRoot $id $wid $workflowRevision $taskRevision {
        param($x);$x.qaBuildEvidence.ManifestSha256=('0'*64);return $x
    }|Out-Null
    } $store $taskId $boot.WorkflowId $w.workflowRevision $state.revision
    $badManifest=$false
    try { Invoke-MayaQaFrozenCandidateEvidence -StoreRoot $store -TaskId $taskId -WorkflowId $boot.WorkflowId -QaWorkflowId 'create-plan-views-v1' -CandidateDirectory $candidate -CandidateDllPath $dll -ExpectedSha256 $artifactHash -ExpectedSourceCommit $sourceCommit | Out-Null }
    catch { $badManifest=$_.Exception.Message -match 'manifest does not match' }
    if(!$badManifest){throw 'Candidate manifest mismatch against Release build evidence was not rejected.'}

    [pscustomobject]@{Status='PASS';ReleaseArtifactAndManifestBound=$true;TrustedRunnerManifestBound=$true;HashMismatchRejected=$badArtifact;ManifestMismatchRejected=$badManifest;ApprovalBoundaryPreserved=$true;SyntheticStoreOnly=$true}|ConvertTo-Json -Compress
} finally {
    if(Test-Path -LiteralPath $store){Remove-Item -LiteralPath $store -Recurse -Force -ErrorAction SilentlyContinue}
}
