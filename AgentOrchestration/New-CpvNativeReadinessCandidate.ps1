[CmdletBinding()]
param([Parameter(Mandatory)][string]$BuildSourceRoot,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{40}$')][string]$SourceCommit)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$maya=Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -PassThru -WarningAction SilentlyContinue
& $maya {
    param($repo,$source,$commit)
    $id='task-bf61fe7f22d74df7a92599681da5919e';$workflowId='fa2c2f578cbc40cbacac45c96313ca4c';$qa='create-plan-views-v1'
    $source=[IO.Path]::GetFullPath($source)
    $actual=Get-MayaQaTrustedBuildSourceCommit -RepositoryRoot $source -ProjectPath (Join-Path $source 'Forma.RevitConnector.csproj')
    if($actual -cne $commit){throw 'Clean build source commit mismatch.'}
    $production=Join-Path $repo 'QA\MayaRuns\tasks.json';$before=(Get-FileHash $production).Hash
    $data=Read-RepatoTaskStore (Split-Path $production -Parent)
    $task=Find-RepatoTask $data $id
    if($task.revision -ne 127 -or $task.cpvPreparationRecovery.Status -cne 'RecoveredVerified'){throw 'Expected recovered revision127.'}
    $workflow=@($task.deploymentWorkflows|Where-Object workflowId -ceq $workflowId)[0]
    $artifact=Join-Path $source 'bin\Release\net8.0-windows\Repato.Revit.dll';$manifest=Join-Path $source 'Repato.addin'
    $buildId='engineering-native127-'+$commit.Substring(0,12)
    $boundary=[pscustomobject]@{RepositoryRoot=$source;ProjectRelativePath='Forma.RevitConnector.csproj';ExpectedSourceCommit=$commit}
    $workflow.qaBuildRequest|Add-Member NoteProperty AuthenticatedBuildSource $boundary -Force
    $workflow.qaBuildRequest.BuildRequestId=$buildId
    $workflow.qaBuildStatus='succeeded'
    $workflow.qaBuildEvidence=[pscustomobject]@{BuildRequestId=$buildId;SourceCommit=$commit;ArtifactPath=$artifact;ArtifactSha256=(Get-FileHash $artifact).Hash;ManifestPath=$manifest;ManifestSha256=(Get-FileHash $manifest).Hash}
    # Only this isolated snapshot is changed. It is never authoritative task/build evidence.
    $isolated=Join-Path $repo ('QA\Engineering\CPV-NativeEngineering127-20261019\packaging-store-'+$commit.Substring(0,12))
    if(Test-Path $isolated){throw 'Isolated packaging snapshot already exists.'}
    New-Item -ItemType Directory -Path $isolated|Out-Null
    $data|ConvertTo-Json -Depth 60|Set-Content -LiteralPath (Join-Path $isolated 'tasks.json') -Encoding UTF8
    $candidate=New-MayaQaCanonicalCandidate -StoreRoot $isolated -TaskId $id -WorkflowId $workflowId -QaWorkflowId $qa -TestId $qa
    $verified=Test-MayaQaFrozenCandidate -CandidateDirectory $candidate.CandidateDirectory -ExpectedSha256 $candidate.CandidateSha256 -ExpectedSourceCommit $commit -QaWorkflowId $qa
    if((Get-FileHash $production).Hash -cne $before){throw 'Production task store changed during packaging.'}
    [pscustomobject]@{ReviewOnly=$true;TaskRevision=127;ProductionMutation=$false;Candidate=$candidate;Verified=$verified}
} $repo $BuildSourceRoot $SourceCommit
