Set-StrictMode -Version Latest
$script:QaModule=Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -PassThru -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue

function Get-RetestBindingHash($Binding){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $Binding -Depth 20 -Compress))))).Replace('-','')}finally{$sha.Dispose()}
}
function Get-MayaQaRetestRuntimeEvidence {
    param([string]$ManifestPath,[string]$ManifestSha256)
    if((Get-FileHash -LiteralPath $ManifestPath).Hash -ine $ManifestSha256){throw 'Retest runtime release manifest hash mismatch.'}
    $manifest=Get-Content -LiteralPath $ManifestPath -Raw|ConvertFrom-Json
    $root='C:\Program Files\Repato\QaLaunchAgent'
    $names=@('Repato.QaLaunchAgent.exe','Repato.QaLaunchAgent.dll','Repato.QaLaunchAgent.deps.json','Repato.QaLaunchAgent.runtimeconfig.json')
    if($manifest.product -cne 'Repato.QaLaunchAgent' -or $manifest.account -cne 'RAMSAI\RepatoQA' -or $manifest.sid -cne 'S-1-5-21-1031246752-3872016183-2454652381-1015' -or @($manifest.files).Count -ne 4 -or @($manifest.files.name|Select-Object -Unique).Count -ne 4 -or @($manifest.files|Where-Object name -cnotin $names).Count){throw 'Retest runtime release identity mismatch.'}
    foreach($file in $manifest.files){if((Get-FileHash -LiteralPath (Join-Path $root $file.name)).Hash -ine $file.sha256){throw 'Retest installed runtime hash mismatch.'}}
    if((Get-Item (Join-Path $root 'Repato.QaLaunchAgent.exe')).VersionInfo.ProductVersion -cne $manifest.productVersion){throw 'Retest runtime version mismatch.'}
    [pscustomobject]@{InstallRoot=$root;Version=$manifest.productVersion;SourceCommit=$manifest.sourceCommit;ReleaseManifestPath=[IO.Path]::GetFullPath($ManifestPath);ReleaseManifestSha256=$ManifestSha256;DllSha256=($manifest.files|Where-Object name -ceq 'Repato.QaLaunchAgent.dll').sha256;ExeSha256=($manifest.files|Where-Object name -ceq 'Repato.QaLaunchAgent.exe').sha256}
}
function New-MayaQaStartupFailureRetest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$FailedAttemptId,[Parameter(Mandatory)][long]$ExpectedTaskRevision,[Parameter(Mandatory)][string]$RuntimeReleaseManifestPath,[Parameter(Mandatory)][string]$RuntimeReleaseManifestSha256,[ValidateRange(120,240)][int]$ValidityMinutes=180,[scriptblock]$RuntimeValidationBoundary)
    $t=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId;$old=$t.mayaTaraExecution
    if([long]$t.revision -ne $ExpectedTaskRevision -or $t.status -cne 'blocked' -or $t.workflowStage -cne 'qa' -or $old.AttemptId -cne $FailedAttemptId -or $old.Stage -cne 'qa-failed' -or $old.ExecutionStatus -cne 'QaFailed' -or $old.FailureCode -cne 'native-qa-failed' -or $old.RollbackStatus -cne 'NotStarted' -or $old.SideEffectsPerformed){throw 'Exact recorded side-effect-free startup failure required for retest.'}
    if(@($t.approvalRequests|Where-Object status -ceq 'pending').Count -or @(Get-Process Revit -ErrorAction SilentlyContinue).Count){throw 'Retest cannot prepare with pending approval or live Revit.'}
    $prior=@($t.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved' -and $_.attemptId -ceq $FailedAttemptId -and $_.runId -ceq $old.RunId -and $_.decidedBy -ceq 'user'})
    if($prior.Count -ne 1){throw 'Exact historical approved failed attempt required.'}
    foreach($pair in @(@($old.ResultPath,$old.ResultSha256),@($old.ReportPath,$old.ReportSha256),@($old.DisposableModelPath,$old.DisposableModelSha256),@($old.ArtifactPath,$old.ArtifactSha256),@($old.RunnerManifestPath,$old.RunnerManifestSha256),@($old.ValidatedRunnerManifestPath,$old.ValidatedRunnerManifestSha256),@($old.IsolationPolicyPath,$old.IsolationPolicySha256))){if((Get-FileHash -LiteralPath $pair[0]).Hash -ine $pair[1]){throw 'Retest historical evidence hash mismatch.'}}
    $report=Get-Content $old.ReportPath -Raw|ConvertFrom-Json;$result=Get-Content $old.ResultPath -Raw|ConvertFrom-Json
    foreach($doc in @($report,$result)){foreach($n in 'TaskId','WorkflowId','TestId','AttemptId','RunId','ClaimId'){if([string]$doc.$n -cne [string]$old.$n){throw 'Retest native failure correlation mismatch.'}};if($doc.RequestId -cne $old.NativeRequestId -or $doc.Status -cne 'Failed'){throw 'Retest failure result identity mismatch.'}}
    if($report.RollbackStatus -cne 'NotStarted' -or @($report.CreatedIds).Count -or @($report.ChangedIds).Count -or @($report.DeletedIds).Count -or $report.Errors[0] -notmatch 'Start a fresh Revit 2025 QA session with no open documents\.' -or $report.AssemblyIdentity.Sha256 -ine $old.ArtifactSha256){throw 'Retest does not have the expected startup failure evidence.'}
    $qa=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../QA'))
    $null=& $script:QaModule {param($q,$x)Test-MayaQaFixturePreparationRecord -QaRoot $q -TaskId $x.TaskId -WorkflowId $x.WorkflowId -SourcePath $x.AuthoritativeFixturePath -SourceSha256 $x.AuthoritativeFixtureSha256 -Evidence $x.FixturePreparationEvidence} $qa $old
    if($old.DisposableModelSha256 -ine $old.FixturePreparationEvidence.PreparedModelSha256){throw 'Retest must preserve the authenticated prepared model.'}
    $w=Get-DeployWorkflow $StoreRoot $TaskId $old.WorkflowId;$e=$w.qaBuildEvidence
    $null=Test-MayaQaFrozenCandidate -CandidateDirectory $e.CandidateDirectory -CandidateDllPath $e.ArtifactPath -ExpectedSha256 $old.ArtifactSha256 -ExpectedSourceCommit $e.CandidateSourceCommit -QaWorkflowId $old.QaWorkflowId
    if(!$e.DeploymentValidation -or !$e.ManifestIntegrityValidation -or !$e.QaIsolation -or $e.ArtifactSha256 -ine $old.ArtifactSha256 -or (Get-FileHash (Join-Path $e.QaAddinRoot 'Repato.Revit.dll')).Hash -ine $old.ArtifactSha256){throw 'Retest frozen deployment integrity mismatch.'}
    $runtime=if($RuntimeValidationBoundary){& $RuntimeValidationBoundary $RuntimeReleaseManifestPath $RuntimeReleaseManifestSha256}else{Get-MayaQaRetestRuntimeEvidence $RuntimeReleaseManifestPath $RuntimeReleaseManifestSha256}
    $attempt=[guid]::NewGuid().ToString('N');$run=[guid]::NewGuid().ToString('N');$root=Join-Path (Join-Path $qa 'TestRuns') ($run+'-startup-retest');$model=Join-Path $root 'model.rvt';$sidecar=$model+'.fixture.json'
    if(Test-Path $root){throw 'Retest runtime already exists.'}
    New-Item $root -ItemType Directory|Out-Null;Copy-Item -LiteralPath $old.DisposableModelPath -Destination $model;Copy-Item -LiteralPath ($old.DisposableModelPath+'.fixture.json') -Destination $sidecar
    if((Get-FileHash $model).Hash -ine $old.DisposableModelSha256){throw 'Retest model copy hash mismatch.'}
    $expiry=[DateTimeOffset]::UtcNow.AddMinutes($ValidityMinutes).ToString('O')
    $binding=[pscustomobject][ordered]@{SchemaVersion='maya-qa-startup-retest-approval-v1';TaskId=$TaskId;WorkflowId=$old.WorkflowId;QaWorkflowId=$old.QaWorkflowId;FailedAttemptId=$FailedAttemptId;PreviousApprovalId=$prior[0].requestId;AttemptId=$attempt;RunId=$run;BuildRequestId=$e.BuildRequestId;CandidateSourceCommit=$e.CandidateSourceCommit;CandidateSha256=$old.ArtifactSha256;CandidatePath=$old.ArtifactPath;CandidateProvenancePath=$e.CandidateProvenancePath;CandidateProvenanceSha256=(Get-FileHash $e.CandidateProvenancePath).Hash;SourceRunnerManifestPath=$old.RunnerManifestPath;SourceRunnerManifestSha256=$old.RunnerManifestSha256;DeployedRunnerManifestPath=$old.ValidatedRunnerManifestPath;DeployedRunnerManifestSha256=$old.ValidatedRunnerManifestSha256;ModelPath=$model;ModelSha256=$old.DisposableModelSha256;SidecarPath=$sidecar;SidecarSha256=(Get-FileHash $sidecar).Hash;AuthoritativeFixturePath=$old.AuthoritativeFixturePath;AuthoritativeFixtureSha256=$old.AuthoritativeFixtureSha256;FixturePreparationEvidence=$old.FixturePreparationEvidence;IsolationPolicyPath=$old.IsolationPolicyPath;IsolationPolicySha256=$old.IsolationPolicySha256;Runtime=$runtime;TrustDecision='HumanOnlyForExactVerifiedAddin';RequiredExecutor='Tara';RevitVersion='2025';AttemptExpiresUtc=$expiry;ResultTimeoutSeconds=7200}
    $q=[pscustomobject][ordered]@{requestId=[guid]::NewGuid().ToString('N');action='qa-run';requiredLevel='user';status='pending';bindingHash=(Get-RetestBindingHash $binding);recoveryBinding=$binding;attemptId=$attempt;runId=$run;runtime=$runtime;candidate=[pscustomobject]@{BuildRequestId=$e.BuildRequestId;SourceCommit=$e.CandidateSourceCommit;ArtifactSha256=$old.ArtifactSha256};previousStatus='in-progress';requestedRevision=[long]0;approvedRevision=$null;requestedUtc=Get-RepatoUtc;expiresUtc=$expiry;decidedUtc=$null;decidedBy=$null;reason='Fresh exact startup retest; prior approval consumed and not reusable.';consumedUtc=$null}
    Invoke-RepatoStoreMutation $StoreRoot {
        param($data,$preview)
        $current=Find-RepatoTask $data $TaskId;$x=$current.mayaTaraExecution
        if([long]$current.revision -ne $ExpectedTaskRevision -or $x.AttemptId -cne $FailedAttemptId -or $x.Stage -cne 'qa-failed' -or @($current.approvalRequests|Where-Object status -ceq 'pending').Count -or (Get-FileHash $x.ReportPath).Hash -ine $old.ReportSha256){throw 'Retest preparation compare-and-swap failed.'}
        $arch=ConvertFrom-Json (ConvertTo-Json $x -Depth 20);$arch|Add-Member NoteProperty ReplacementAttemptId $attempt -Force;$arch|Add-Member NoteProperty ReplacementRunId $run -Force
        $current.mayaTaraExecutionHistory=[object[]]@($current.mayaTaraExecutionHistory)+$arch;$current.mayaTaraAttemptHistory=[object[]]@($current.mayaTaraAttemptHistory)+$current.mayaTaraAttempt
        $previous=@($current.approvalRequests|Where-Object requestId -ceq $prior[0].requestId)[0];$previous.consumedUtc=$old.FailedUtc;$previous|Add-Member NoteProperty consumedAttemptId $FailedAttemptId -Force
        $replacement=ConvertFrom-Json (ConvertTo-Json $x -Depth 20);$replacement.AttemptId=$attempt;$replacement.RunId=$run;$replacement.DisposableRuntimeRoot=$root;$replacement.DisposableModelPath=$model;$replacement.PreparedUtc=Get-RepatoUtc;$replacement.Stage='prepared';$replacement.ExecutionStatus='Prepared';$replacement.ClaimStatus='unclaimed';$replacement.SideEffectsPerformed=$false
        foreach($n in 'ClaimOwner','ClaimId','ClaimedUtc','LaunchingUtc','LaunchedUtc','ExecutingUtc','EvidenceCollectedUtc','RollbackStartedUtc','RollbackVerifiedUtc','VerifiedUtc','CompletedUtc','FailedUtc','NativeProcessId','NativeRequestId','RequestPath','ResultPath','ReportPath','EvidencePath','ReceiptPath','FailureCode','FailureDetails','TaskRevisionAtClaim','ResultSha256','ReportSha256'){if($replacement.PSObject.Properties.Name -contains $n){$replacement.$n=$null}}
        $replacement.RollbackStatus='Required';$replacement.VerificationStatus='Pending';$replacement.CompletionStatus='Pending'
        $current.mayaTaraExecution=$replacement;$current.mayaTaraAttempt=[pscustomobject]@{SchemaVersion='maya-tara-execution-request-v1';TaskId=$TaskId;WorkflowId=$old.WorkflowId;QaWorkflowId=$old.QaWorkflowId;AttemptId=$attempt;RunId=$run;RuntimeRoot=$root;RequestExpiresUtc=$expiry;Stage='prepared';Success=$false;RequestPath=$null}
        $packet=ConvertFrom-Json (ConvertTo-Json $current.mayaTaraQaPacket -Depth 20);$current.mayaTaraQaPacketHistory=[object[]]@($current.mayaTaraQaPacketHistory)+[pscustomobject]@{Packet=$packet;AttemptId=$packet.AttemptId;RunId=$packet.RunId;ArchivedUtc=Get-RepatoUtc}
        $packet.AttemptId=$attempt;$packet.RunId=$run;$packet.ModelPath=$model;$packet.SidecarPath=$sidecar;$packet.DisposableModelSha256=$old.DisposableModelSha256;$packet.FixturePreparationEvidence=$old.FixturePreparationEvidence;$packet.RequestExpiresUtc=$expiry;$current.mayaTaraQaPacket=$packet
        $workflow=@($current.deploymentWorkflows|Where-Object workflowId -ceq $old.WorkflowId)[0];$workflow.qaRunId=$run;$workflow.qaModelPath=$model;$workflow.qaSidecarPath=$sidecar
        $workflow|Add-Member NoteProperty qaDisposableModelSha256 $old.DisposableModelSha256 -Force;$workflow|Add-Member NoteProperty qaApprovalId $q.requestId -Force
        if($workflow.qaHandoff){foreach($n in 'AttemptId','RunId','CoordinatorRunId'){if($workflow.qaHandoff.PSObject.Properties.Name -contains $n){$workflow.qaHandoff.$n=$(if($n -eq 'AttemptId'){$attempt}else{$run})}}}
        $current.approvalRequests=[object[]]@($current.approvalRequests)+$q;$current.status='awaiting-approval';$current.workflowStage='approval';$current.errorDetails=$null
        Add-RepatoHistory $current 'maya-tara-startup-retest-prepared' 'Maya' "failedAttempt=$FailedAttemptId; attempt=$attempt; request=$($q.requestId); preserved prepared fixture; corrected runtime=$($runtime.Version); no launch"
        $q.requestedRevision=[long]$current.revision;$replacement.TaskRevisionAtPrepare=[long]$current.revision
        [pscustomobject]@{TaskRevision=$current.revision;ApprovalRequestId=$q.requestId;AttemptId=$attempt;RunId=$run;ExpiresUtc=$expiry;BindingHash=$q.bindingHash;RevitLaunched=$false}
    }
}

function Resolve-MayaQaStartupRetestApproval {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$RequestId,[Parameter(Mandatory)][long]$ExpectedTaskRevision,[ValidateSet('approve','reject')][string]$Decision='approve',[scriptblock]$RuntimeValidationBoundary)
    $t=Find-RepatoTask (Read-RepatoTaskStore $StoreRoot) $TaskId;$q=@($t.approvalRequests|Where-Object {$_.requestId -ceq $RequestId -and $_.status -ceq 'pending'})
    if($q.Count -ne 1 -or [long]$t.revision -ne $ExpectedTaskRevision -or $t.status -cne 'awaiting-approval'){throw 'Exact current pending retest approval required.'}
    $q=$q[0];$b=$q.recoveryBinding;$x=$t.mayaTaraExecution;$a=$t.mayaTaraAttempt
    if($b.SchemaVersion -cne 'maya-qa-startup-retest-approval-v1' -or $q.bindingHash -cne (Get-RetestBindingHash $b) -or $b.TaskId -cne $TaskId -or $b.AttemptId -cne $x.AttemptId -or $b.RunId -cne $x.RunId -or $x.AttemptId -cne $a.AttemptId -or $x.Stage -cne 'prepared' -or $x.ClaimId -or $x.NativeProcessId -or $x.RequestPath -or $x.SideEffectsPerformed -or [DateTimeOffset]::Parse($q.expiresUtc) -le [DateTimeOffset]::UtcNow -or [DateTimeOffset]::Parse($a.RequestExpiresUtc) -le [DateTimeOffset]::UtcNow){throw 'Retest approval binding or expiry invalid.'}
    foreach($pair in @(@($b.CandidatePath,$b.CandidateSha256),@($b.CandidateProvenancePath,$b.CandidateProvenanceSha256),@($b.ModelPath,$b.ModelSha256),@($b.SidecarPath,$b.SidecarSha256),@($b.SourceRunnerManifestPath,$b.SourceRunnerManifestSha256),@($b.DeployedRunnerManifestPath,$b.DeployedRunnerManifestSha256),@($b.IsolationPolicyPath,$b.IsolationPolicySha256),@($b.AuthoritativeFixturePath,$b.AuthoritativeFixtureSha256))){if((Get-FileHash $pair[0]).Hash -ine $pair[1]){throw 'Retest approval referenced file changed.'}}
    $live=if($RuntimeValidationBoundary){& $RuntimeValidationBoundary $b.Runtime.ReleaseManifestPath $b.Runtime.ReleaseManifestSha256}else{Get-MayaQaRetestRuntimeEvidence $b.Runtime.ReleaseManifestPath $b.Runtime.ReleaseManifestSha256}
    if((ConvertTo-Json $live -Depth 10 -Compress) -cne (ConvertTo-Json $b.Runtime -Depth 10 -Compress)){throw 'Retest approval installed runtime changed.'}
    Invoke-RepatoStoreMutation $StoreRoot {
        param($data,$preview)
        $current=Find-RepatoTask $data $TaskId;$pending=@($current.approvalRequests|Where-Object status -ceq 'pending')
        if([long]$current.revision -ne $ExpectedTaskRevision -or $pending.Count -ne 1 -or $pending[0].requestId -cne $RequestId -or $pending[0].bindingHash -cne $q.bindingHash){throw 'Retest approval compare-and-swap failed.'}
        $p=$pending[0];$p.status=$(if($Decision -ceq 'approve'){'approved'}else{'rejected'});$p.decidedBy='user';$p.decidedUtc=Get-RepatoUtc;$p.reason="User explicitly $Decision request $RequestId."
        $current.status=$(if($Decision -ceq 'approve'){'in-progress'}else{'blocked'});Add-RepatoHistory $current ('approval-'+$Decision) 'user' $p.reason
        if($Decision -ceq 'approve'){$p.approvedRevision=[long]$current.revision}
        $current
    }
}
Export-ModuleMember -Function New-MayaQaStartupFailureRetest,Resolve-MayaQaStartupRetestApproval,Get-MayaQaRetestRuntimeEvidence
