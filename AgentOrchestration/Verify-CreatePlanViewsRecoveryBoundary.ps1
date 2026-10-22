param([switch]$RepairPreparationRevision)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent;$store=Join-Path $repo 'QA/MayaRuns';$id='task-bf61fe7f22d74df7a92599681da5919e'
$module=Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -PassThru -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
$t=Find-RepatoTask (Read-RepatoTaskStore $store) $id;$x=$t.mayaTaraExecution
$prep=& $module {param($x)Test-MayaQaFixturePreparationRecord -QaRoot (Get-MayaQaRoot) -TaskId $x.TaskId -WorkflowId $x.WorkflowId -SourcePath $x.AuthoritativeFixturePath -SourceSha256 $x.AuthoritativeFixtureSha256 -Evidence $x.FixturePreparationEvidence} $x
$w=@($t.deploymentWorkflows|Where-Object workflowId -ceq $x.WorkflowId)[0];$e=$w.qaBuildEvidence
$candidate=Test-MayaQaFrozenCandidate -CandidateDirectory $e.CandidateDirectory -CandidateDllPath $e.ArtifactPath -ExpectedSha256 $e.ArtifactSha256 -ExpectedSourceCommit $e.CandidateSourceCommit -QaWorkflowId $x.QaWorkflowId
foreach($pair in @(@($x.DisposableModelPath,$x.DisposableModelSha256),@($e.RunnerManifestPath,$e.RunnerManifestSha256),@($e.DeployedRunnerManifestPath,$e.DeployedRunnerManifestSha256),@($x.IsolationPolicyPath,$x.IsolationPolicySha256),@($e.ManifestPath,$e.ManifestSha256))){if((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ine $pair[1]){throw 'Boundary file hash mismatch.'}}
$side=Get-Content ($x.DisposableModelPath+'.fixture.json') -Raw|ConvertFrom-Json
if($side.preparedModelSha256 -ine $x.DisposableModelSha256 -or $side.sourceSha256 -ine $x.AuthoritativeFixtureSha256 -or $side.fixturePreparationRequestSha256 -ine $x.FixturePreparationEvidence.RequestSha256 -or $side.fixturePreparationResultSha256 -ine $x.FixturePreparationEvidence.ResultSha256){throw 'Boundary fixture sidecar mismatch.'}
$q=@($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})
if($q.Count -ne 1 -or [DateTimeOffset]::Parse($q[0].expiresUtc) -le [DateTimeOffset]::UtcNow -or [DateTimeOffset]::Parse($t.mayaTaraAttempt.RequestExpiresUtc) -le [DateTimeOffset]::UtcNow){throw 'Boundary approval or attempt expired.'}
$version=(Get-Item 'C:/Program Files/Repato/QaLaunchAgent/Repato.QaLaunchAgent.exe').VersionInfo.ProductVersion
if($version -cne $q[0].runtime.Version -or $x.Stage -cne 'prepared' -or $x.ExecutionStatus -cne 'Prepared' -or $x.ClaimId -or $x.NativeProcessId -or $x.RequestPath -or $x.SideEffectsPerformed){throw 'Boundary runtime or execution identity mismatch.'}
if($RepairPreparationRevision){$t=Repair-MayaQaRecoveredLaunchApprovalRevision -StoreRoot $store -TaskId $id -RequestId $q[0].requestId -ExpectedTaskRevision $t.revision;$q=@($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'pending'})}
[pscustomobject]@{TaskId=$id;TaskRevision=$t.revision;Status=$t.status;PreparedModelValid=$prep;PreparedModelPath=$x.DisposableModelPath;PreparedModelSha256=$x.DisposableModelSha256;FrozenCandidateSha256=$e.ArtifactSha256;FrozenCandidateCommit=$e.CandidateSourceCommit;RuntimeVersion=$version;RuntimeDllSha256=(Get-FileHash 'C:/Program Files/Repato/QaLaunchAgent/Repato.QaLaunchAgent.dll').Hash;AttemptId=$t.mayaTaraAttempt.AttemptId;AttemptExpiresUtc=$t.mayaTaraAttempt.RequestExpiresUtc;ApprovalRequestId=$q[0].requestId;ApprovalExpiresUtc=$q[0].expiresUtc;PreparationRevision=$t.mayaTaraExecution.TaskRevisionAtPrepare;ApprovalRequestedRevision=$q[0].requestedRevision;RevitLaunched=$false}|ConvertTo-Json -Depth 5
