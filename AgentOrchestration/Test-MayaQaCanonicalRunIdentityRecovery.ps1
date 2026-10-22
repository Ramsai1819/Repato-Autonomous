$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
$passed=0;$total=0;$negative=0;$negativeInvoked=0;$negativeRejected=0;$qaRunInRejected=$false
function Assert-Case([string]$Name,[scriptblock]$Action){$script:total++;&$Action;$script:passed++}
function New-SyntheticLifecycle {
 $root=Join-Path ([IO.Path]::GetTempPath()) ('maya-recovery-'+[guid]::NewGuid().ToString('N'));$store=Join-Path $root 'store';$target=Join-Path $root 'target';$runs=Join-Path $root 'runs';New-Item $target,$runs -ItemType Directory -Force|Out-Null
 $id='RECOVERY-'+[guid]::NewGuid().ToString('N').Substring(0,8);$build='build-'+[guid]::NewGuid().ToString('N');$qa='create-plan-views-v1';$artifact=Join-Path $target 'artifact.bin';$manifest=Join-Path $target 'manifest.addin';$provenance=Join-Path $target 'release-manifest.json';Set-Content $artifact artifact;Set-Content $manifest manifest
 New-RepatoTask $store $id 'Synthetic QA' 'run recovery' 'qa/recovery' maya|Out-Null;Claim-RepatoTask $store $id Neil|Out-Null;Update-RepatoTask $store $id in-progress implementation Neil $null $null|Out-Null;Update-RepatoTask $store $id in-progress build-checks Neil $null $null|Out-Null;Update-RepatoTask $store $id in-progress qa Tara $null $null|Out-Null;Update-RepatoTask $store $id passed qa Tara $null $null|Out-Null
 $plan=New-DeployPlan $store $id $artifact $manifest -TargetRoot $target;$wf=New-DeployWorkflow $store $plan;$null=Request-RepatoTaskApproval $store $id qa-run maya;$null=Resolve-RepatoTaskApproval $store $id approve Maya approved
 $d=Read-RepatoTaskStore $store;$t=Find-RepatoTask $d $id;$approval=@($t.approvalRequests|Where-Object status -eq 'approved')[-1];$aHash=(Get-FileHash $artifact).Hash;$mHash=(Get-FileHash $manifest).Hash;[pscustomobject]@{SourceCommit=('A'*40);FrozenArtifactSha256=$aHash;SupportedQaWorkflows=@($qa)}|ConvertTo-Json|Set-Content $provenance
 $null=Invoke-RepatoStoreMutation $store {param($data,$preview)$t=Find-RepatoTask $data $id;$w=@($t.deploymentWorkflows|Where-Object workflowId -ceq $wf.workflowId)[0];$t.workflowStage='approval';$e=[pscustomobject]@{BuildRequestId=$build;BuildStatus='succeeded';EvidenceSource='FrozenCandidate';SourceCommit=('A'*40);CandidateSourceCommit=('A'*40);ArtifactPath=$artifact;ArtifactSha256=$aHash;ManifestPath=$manifest;ManifestSha256=$mHash;CandidateProvenancePath=$provenance;RunnerManifestPath='synthetic-runner';RunnerManifestSha256=('B'*64);DeploymentValidation=$true;QaIsolation=$true;ManifestIntegrityValidation=$true};$w|Add-Member qaWorkflowId $qa -Force;$w|Add-Member qaBuildRequest ([pscustomobject]@{BuildRequestId=$build}) -Force;$w|Add-Member qaBuildStatus 'succeeded' -Force;$w|Add-Member qaBuildEvidence $e -Force;$h=[pscustomobject]@{HandoffId='handoff-synthetic';TaskId=$id;WorkflowId=$wf.workflowId;BuildRequestId=$build;QaWorkflowId=$qa;NativeTestId=$qa;QaApprovalId=$approval.requestId;HandoffStatus='ready';ArtifactPath=$artifact;ArtifactSha256=$aHash;ManifestPath=$manifest;ManifestSha256=$mHash;RunnerManifestPath='synthetic-runner';RunnerManifestSha256=('B'*64);QaAddinRoot='synthetic-root';Isolation=[pscustomobject]@{Allowed=$true}};$w|Add-Member qaHandoffId $h.HandoffId -Force;$w|Add-Member qaHandoff $h -Force;$w|Add-Member qaApprovalId $approval.requestId -Force;$w|Add-Member qaApprovalStatus 'approved' -Force;$t}
 [pscustomobject]@{Root=$root;Store=$store;Runs=$runs;TaskId=$id;WorkflowId=$wf.workflowId;Build=$build;Qa=$qa}
}
function Get-State($c){$d=Read-RepatoTaskStore $c.Store;$t=Find-RepatoTask $d $c.TaskId;$w=@($t.deploymentWorkflows|Where-Object workflowId -ceq $c.WorkflowId)[0];if(!$t -or !$w){throw 'Synthetic store is not resolvable.'};[pscustomobject]@{Task=$t;Workflow=$w}}
function Invoke-SyntheticMutation($c,[scriptblock]$Mutation){$null=Invoke-RepatoStoreMutation $c.Store {param($data,$preview)$t=Find-RepatoTask $data $c.TaskId;$w=@($t.deploymentWorkflows|Where-Object workflowId -ceq $c.WorkflowId)[0];if(!$t -or !$w){throw 'Mutation target is not resolvable.'};&$Mutation $t $w};Get-State $c}
function Assert-Rejected($Name,$Mutation,$InvocationArgs){$script:negative++;$c=New-SyntheticLifecycle;if($Mutation){$s=Invoke-SyntheticMutation $c $Mutation;if(!$s.Task -or !$s.Workflow){throw "${Name} corrupted synthetic store"}};$beforeState=Get-State $c;$beforeRun=if($beforeState.Workflow.PSObject.Properties.Name -contains 'qaRunId'){[string]$beforeState.Workflow.qaRunId}else{''};$script:negativeInvoked++;$rejected=$false;try{if($InvocationArgs){Repair-MayaQaCanonicalRunIdentity -StoreRoot $c.Store -TaskId $InvocationArgs[0] -WorkflowId $InvocationArgs[1] -QaWorkflowId $InvocationArgs[2] -ExpectedBuildRequestId $InvocationArgs[3] -RuntimeRoot $c.Runs|Out-Null}else{Repair-MayaQaCanonicalRunIdentity -StoreRoot $c.Store -TaskId $c.TaskId -WorkflowId $c.WorkflowId -QaWorkflowId $c.Qa -ExpectedBuildRequestId $c.Build -RuntimeRoot $c.Runs|Out-Null}}catch{$rejected=$true};if(!$rejected){throw "${Name}: production accepted invalid lifecycle"};$after=Get-State $c;$afterRun=if($after.Workflow.PSObject.Properties.Name -contains 'qaRunId'){[string]$after.Workflow.qaRunId}else{''};if($afterRun -ne $beforeRun){$script:qaRunInRejected=$true;throw "${Name}: rejected case created or changed qaRunId"};$script:negativeRejected++;Remove-Item $c.Root -Recurse -Force -ErrorAction SilentlyContinue}
$c=New-SyntheticLifecycle;$s=Get-State $c
Assert-Case 'baseline fixture' {$s.Task.taskId -eq $c.TaskId -and $s.Workflow.workflowId -eq $c.WorkflowId -and $s.Workflow.qaBuildStatus -eq 'succeeded' -and $s.Workflow.qaBuildEvidence.DeploymentValidation -and $s.Workflow.qaHandoffId -and !$s.Workflow.qaRunId}
$before=$s.Task.revision;Repair-MayaQaCanonicalRunIdentity -StoreRoot $c.Store -TaskId $c.TaskId -WorkflowId $c.WorkflowId -QaWorkflowId $c.Qa -ExpectedBuildRequestId $c.Build -RuntimeRoot $c.Runs|Out-Null;$s=Get-State $c
Assert-Case 'positive recovery' {$s.Workflow.qaRunId -match '^MAYA-[A-Fa-f0-9-]{32,40}$' -and $s.Task.revision -gt $before -and $s.Workflow.qaApprovalStatus -eq 'approved' -and $s.Workflow.qaHandoffId}
Assert-Case 'post recovery preparation' {$null=New-MayaQaCanonicalPreparation -StoreRoot $c.Store -TaskId $c.TaskId -WorkflowId $c.WorkflowId -QaWorkflowId $c.Qa;$true}
Assert-Case 'one revision failed preparation continuity' {$c=New-SyntheticLifecycle;Invoke-SyntheticMutation $c {param($t,$w)$a=@($t.approvalRequests|? {$_.status -eq 'approved'})[0];$a.approvedRevision=$t.revision;Add-RepatoHistory $t 'deployment-workflow-mutated' 'Maya' $w.workflowId}|Out-Null;Repair-MayaQaCanonicalRunIdentity -StoreRoot $c.Store -TaskId $c.TaskId -WorkflowId $c.WorkflowId -QaWorkflowId $c.Qa -ExpectedBuildRequestId $c.Build -RuntimeRoot $c.Runs|Out-Null;[bool](Get-State $c).Workflow.qaRunId}
Assert-Rejected 'two revision approval gap' {param($t,$w)$a=@($t.approvalRequests|? {$_.status -eq 'approved'})[0];$a.approvedRevision=$t.revision-2} $null
Assert-Rejected 'one revision without partial handoff' {param($t,$w)$w.PSObject.Properties.Remove('qaHandoff')|Out-Null} $null
Assert-Case 'legacy unavailable accepted' {$c=New-SyntheticLifecycle;Invoke-SyntheticMutation $c {param($t,$w)$w.qaBuildEvidence.ManifestIntegrityValidation='Unavailable'}|Out-Null;Repair-MayaQaCanonicalRunIdentity -StoreRoot $c.Store -TaskId $c.TaskId -WorkflowId $c.WorkflowId -QaWorkflowId $c.Qa -ExpectedBuildRequestId $c.Build -RuntimeRoot $c.Runs|Out-Null;[bool](Get-State $c).Workflow.qaRunId}
Assert-Case 'legacy handoff accepted' {$c=New-SyntheticLifecycle;Invoke-SyntheticMutation $c {param($t,$w)$w.qaHandoff.PSObject.Properties.Remove('WorkflowId')|Out-Null}|Out-Null;Repair-MayaQaCanonicalRunIdentity -StoreRoot $c.Store -TaskId $c.TaskId -WorkflowId $c.WorkflowId -QaWorkflowId $c.Qa -ExpectedBuildRequestId $c.Build -RuntimeRoot $c.Runs|Out-Null;[bool](Get-State $c).Workflow.qaRunId}
Assert-Rejected 'legacy wrong task' {param($t,$w)$w.qaHandoff.PSObject.Properties.Remove('WorkflowId')|Out-Null;$w.qaHandoff.TaskId='wrong'} $null
Assert-Rejected 'legacy wrong handoff linkage' {param($t,$w)$w.qaHandoff.PSObject.Properties.Remove('WorkflowId')|Out-Null;$w.qaHandoffId='wrong'} $null
Assert-Rejected 'legacy wrong approval linkage' {param($t,$w)$w.qaHandoff.PSObject.Properties.Remove('WorkflowId')|Out-Null;$w.qaHandoff.QaApprovalId='wrong'} $null
Assert-Rejected 'legacy wrong build linkage' {param($t,$w)$w.qaHandoff.PSObject.Properties.Remove('WorkflowId')|Out-Null;$w.qaHandoff.BuildRequestId='wrong'} $null
Assert-Rejected 'legacy ambiguous workflow' {param($t,$w)$w.qaHandoff.PSObject.Properties.Remove('WorkflowId')|Out-Null;$w.qaHandoff.QaWorkflowId=''} $null
Assert-Rejected 'empty workflow id' {param($t,$w)$w.qaHandoff.WorkflowId=''} $null
Assert-Rejected 'null workflow id' {param($t,$w)$w.qaHandoff.WorkflowId=$null} $null
Assert-Rejected 'unavailable wrong artifact' {param($t,$w)$w.qaBuildEvidence.ManifestIntegrityValidation='Unavailable';$w.qaBuildEvidence.ArtifactSha256='C'*64} $null
Assert-Rejected 'unavailable wrong manifest' {param($t,$w)$w.qaBuildEvidence.ManifestIntegrityValidation='Unavailable';$w.qaBuildEvidence.ManifestSha256='C'*64} $null
Assert-Rejected 'unavailable wrong source' {param($t,$w)$w.qaBuildEvidence.ManifestIntegrityValidation='Unavailable';$w.qaBuildEvidence.SourceCommit='C'*40} $null
Assert-Rejected 'unavailable wrong runner' {param($t,$w)$w.qaBuildEvidence.ManifestIntegrityValidation='Unavailable';$w.qaBuildEvidence.RunnerManifestSha256='C'*64} $null
Assert-Rejected 'unavailable no staging' {param($t,$w)$w.qaBuildEvidence.ManifestIntegrityValidation='Unavailable';$w.qaBuildEvidence.DeploymentValidation=$false} $null
Assert-Rejected 'unavailable no isolation' {param($t,$w)$w.qaBuildEvidence.ManifestIntegrityValidation='Unavailable';$w.qaBuildEvidence.QaIsolation=$false} $null
Assert-Rejected 'unavailable bad provenance' {param($t,$w)$w.qaBuildEvidence.ManifestIntegrityValidation='Unavailable';$w.qaBuildEvidence.CandidateProvenancePath='missing'} $null
Assert-Rejected 'wrong task id' $null @('wrong',$c.WorkflowId,$c.Qa,$c.Build)
Assert-Rejected 'wrong workflow id' $null @($c.TaskId,'wrong',$c.Qa,$c.Build)
Assert-Rejected 'wrong build id' $null @($c.TaskId,$c.WorkflowId,$c.Qa,'wrong')
Assert-Rejected 'wrong QA id' {param($t,$w)$w.qaWorkflowId='wrong'} $null
Assert-Rejected 'pending approval' {param($t,$w)$w.qaApprovalStatus='pending';$t.approvalRequests[0].status='pending';$t.status='awaiting-approval'} $null
Assert-Rejected 'rejected approval' {param($t,$w)$w.qaApprovalStatus='rejected';$t.approvalRequests[0].status='rejected'} $null
Assert-Rejected 'missing build evidence' {param($t,$w)$w.qaBuildEvidence=$null;$w.qaBuildStatus=$null} $null
Assert-Rejected 'failed build' {param($t,$w)$w.qaBuildStatus='failed'} $null
Assert-Rejected 'candidate source mismatch' {param($t,$w)$w.qaBuildEvidence.SourceCommit='C'*40} $null
Assert-Rejected 'candidate hash mismatch' {param($t,$w)$w.qaBuildEvidence.ArtifactSha256='D'*64} $null
Assert-Rejected 'missing candidate' {param($t,$w)$w.qaBuildEvidence=$null} $null
Assert-Rejected 'missing staging' {param($t,$w)$w.qaBuildEvidence.DeploymentValidation=$false} $null
Assert-Rejected 'failed staging' {param($t,$w)$w.qaBuildEvidence.ManifestIntegrityValidation=$false} $null
Assert-Rejected 'staging identity' {param($t,$w)$w.qaHandoff.TaskId='wrong'} $null
Assert-Rejected 'isolation failed' {param($t,$w)$w.qaBuildEvidence.QaIsolation=$false} $null
Assert-Rejected 'deployment identity' {param($t,$w)$w.qaHandoff.WorkflowId='wrong'} $null
Assert-Rejected 'deployment candidate' {param($t,$w)$w.qaHandoff.ArtifactSha256='E'*64} $null
Assert-Rejected 'Tara packet' {param($t,$w)$t|Add-Member mayaTaraQaPacket ([pscustomobject]@{x=1}) -Force} $null
Assert-Rejected 'Tara attempt' {param($t,$w)$t|Add-Member mayaTaraAttempt ([pscustomobject]@{x=1}) -Force} $null
Assert-Rejected 'Tara execution' {param($t,$w)$t|Add-Member mayaTaraExecution ([pscustomobject]@{x=1}) -Force} $null
Assert-Rejected 'native attempt' {param($t,$w)$t|Add-Member nativeAttemptCount 1 -Force} $null
Assert-Rejected 'completed QA' {param($t,$w)$t.status='completed'} $null
Assert-Rejected 'terminal failed' {param($t,$w)$t.status='failed'} $null
Assert-Rejected 'existing run id' {param($t,$w)$w|Add-Member -NotePropertyName qaRunId -NotePropertyValue 'MAYA-existing' -Force} $null
Assert-Rejected 'handoff id mismatch' {param($t,$w)$w.qaHandoffId='wrong'} $null
Assert-Rejected 'handoff identity mismatch' {param($t,$w)$w.qaHandoff.WorkflowId='wrong'} $null
Assert-Rejected 'approval id mismatch' {param($t,$w)$w.qaApprovalId='wrong'} $null
Assert-Rejected 'approval linkage mismatch' {param($t,$w)$w.qaHandoff.QaApprovalId='wrong'} $null
Write-Output "FocusedCasesPassed=$($passed+$negativeRejected)/$($total+$negative)"
Write-Output "GenuineNegativeCases=$negative;Invoked=$negativeInvoked;Rejected=$negativeRejected;QaRunIdInRejected=$qaRunInRejected"
