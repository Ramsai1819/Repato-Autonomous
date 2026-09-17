Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -WarningAction SilentlyContinue
$script:DeployRegistry=Join-Path $PSScriptRoot 'DeploymentTargets.json'
function Invoke-RepatoWorkflowMutation {
 param([string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[long]$ExpectedWorkflowRevision,[long]$ExpectedTaskRevision,[scriptblock]$Transform,[switch]$DryRun)
 if(-not $Transform -and -not $DryRun){throw 'Workflow transform is required.'}
 if($DryRun){return [pscustomobject]@{SideEffectsPerformed=$false}}
 Invoke-RepatoStoreMutation $StoreRoot { param($d,$p)
  $task=Find-RepatoTask $d $TaskId; $workflow=@($task.deploymentWorkflows|Where-Object workflowId -ceq $WorkflowId)
  if($workflow.Count -ne 1){throw 'Workflow not found or duplicate.'}; $workflow=$workflow[0]
  if([long]$task.revision -ne $ExpectedTaskRevision -or [long]$workflow.workflowRevision -ne $ExpectedWorkflowRevision){throw 'Stale workflow revision.'}
  & $Transform $workflow
  $task.deploymentWorkflows = [object[]]@($task.deploymentWorkflows | ForEach-Object { if($_.workflowId -ceq $WorkflowId){$workflow}else{$_} })
  Add-RepatoHistory $task 'deployment-workflow-mutated' 'Maya' $WorkflowId
  $workflow.taskRevision=[long]$task.revision; $workflow.workflowRevision=[long]($ExpectedWorkflowRevision+1)
  [pscustomobject]@{Workflow=$workflow;TaskRevision=$task.revision;WorkflowRevision=$workflow.workflowRevision}
 }
}
function Get-DeployPlanHash { param([object]$Plan) $o=[ordered]@{taskId=$Plan.taskId;planId=$Plan.planId;artifactPath=$Plan.artifactPath;artifactSha256=$Plan.artifactSha256;manifestPath=$Plan.manifestPath;manifestSha256=$Plan.manifestSha256;targetId=$Plan.targetId;targetRoot=$Plan.targetRoot;failureMode=$Plan.failureMode};$j=$o|ConvertTo-Json -Compress;$h=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($j)))).Replace('-','')}finally{$h.Dispose()}}
function New-DeployPlan { param([string]$StoreRoot,[string]$TaskId,[string]$ArtifactPath,[string]$ManifestPath,[string]$TargetId='qa-local-fixture',[string]$TargetRoot,[switch]$DryRun) $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$t=(Get-Content $script:DeployRegistry -Raw|ConvertFrom-Json).targets|? targetId -ceq $TargetId;if(!$t -or $t.revit){throw 'Deployment target is not registered.'};$tr=if($TargetRoot){[IO.Path]::GetFullPath($TargetRoot)}else{[IO.Path]::GetFullPath((Join-Path $root $t.path))};if($TargetRoot -and !$tr.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){throw 'TargetRoot must be temporary.'};foreach($x in $ArtifactPath,$ManifestPath){$f=[IO.Path]::GetFullPath($x);if(!(Test-Path -LiteralPath $f)){throw 'Missing source file.'};if($TargetRoot -and !$f.StartsWith($tr,[StringComparison]::OrdinalIgnoreCase)){throw 'Source escapes TargetRoot.'};if(!$TargetRoot -and !$f.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Source escapes repository.'}};$a=(Get-FileHash $ArtifactPath -Algorithm SHA256).Hash;$m=(Get-FileHash $ManifestPath -Algorithm SHA256).Hash;[pscustomobject]@{schemaVersion=1;planId=$a.Substring(0,32);taskId=$TaskId;artifactPath=$ArtifactPath;artifactSha256=$a;manifestPath=$ManifestPath;manifestSha256=$m;targetId=$TargetId;targetRoot=$tr;failureMode=$FailureMode;targetPath=$t.path;registrySha256=(Get-FileHash $script:DeployRegistry -Algorithm SHA256).Hash;mode=$(if($DryRun){'DryRun'}else{'Controlled'});sideEffectsPerformed=$false}}
function New-DeployWorkflow { param([string]$StoreRoot,[object]$Plan,[switch]$DryRun) if($DryRun){return [pscustomobject]@{stage='planned';status='dry-run';sideEffectsPerformed=$false}};Invoke-RepatoStoreMutation $StoreRoot {param($d,$p)$t=Find-RepatoTask $d $Plan.taskId;if($t.PSObject.Properties.Name -notcontains 'deploymentWorkflows'){$t|Add-Member NoteProperty deploymentWorkflows @()};$w=[pscustomobject]@{workflowId=[guid]::NewGuid().ToString('N');taskId=$Plan.taskId;planId=$Plan.planId;planSha256=(Get-DeployPlanHash $Plan);targetRoot=$Plan.targetRoot;failureMode=$Plan.failureMode;artifactPath=$Plan.artifactPath;artifactSha256=$Plan.artifactSha256;manifestPath=$Plan.manifestPath;manifestSha256=$Plan.manifestSha256;targetId=$Plan.targetId;registrySha256=$Plan.registrySha256;stage='planned';status='planned';approvalId=$null;approvalStatus=$null;nonceConsumed=$false;consumedNonce=$null;consumedUtc=$null;approvedTaskRevision=$null;backupPaths=@();backupHashes=@();appliedHashes=@();originalError=$null;rollbackResult=$null;restoredHashes=@();verificationStatus=$null;expectedHashes=@();actualHashes=@();completionEvidence=$null;completedUtc=$null;taskRevision=$t.revision;workflowRevision=0;startedUtc=(Get-Date).ToUniversalTime().ToString('O');finishedUtc=$null;history=@()};$t.deploymentWorkflows=[object[]]@($t.deploymentWorkflows)+$w;Add-RepatoHistory $t 'deployment-workflow-planned' 'Maya' $w.workflowId;$w}}
function Get-DeployWorkflow {param([string]$StoreRoot,[string]$TaskId,[string]$WorkflowId)$d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId;$w=@($t.deploymentWorkflows|? workflowId -ceq $WorkflowId);if($w.Count -ne 1){throw 'Workflow not found or duplicate.'};$w[0]}
function Get-DeployWorkflowPlan {param([string]$StoreRoot,[string]$TaskId,[string]$WorkflowId)$w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;$p=[pscustomobject]@{schemaVersion=1;planId=$w.planId;taskId=$w.taskId;artifactPath=$w.artifactPath;artifactSha256=$w.artifactSha256;manifestPath=$w.manifestPath;manifestSha256=$w.manifestSha256;targetId=$w.targetId;targetRoot=$w.targetRoot;failureMode=$w.failureMode};if((Get-DeployPlanHash $p)-ne$w.planSha256){throw 'Persisted plan hash mismatch.'};$p}
function Request-DeployWorkflowApproval { param([string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[switch]$DryRun) $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;if($w.stage -ne 'planned'){throw 'Workflow is not planned.'};if($DryRun){return [pscustomobject]@{stage='approval-pending';sideEffectsPerformed=$false}};$d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId;$null=Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $w.workflowRevision $t.revision {param($x)$x.stage='approval-pending';$x.status='approval-pending'};$p=Get-DeployWorkflowPlan $StoreRoot $TaskId $WorkflowId;Request-RepatoTaskApproval $StoreRoot $TaskId ('deployment:'+ $p.planId) 'maya' 30 }
function Approve-DeployWorkflow { param([string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$Actor='Maya',[string]$Reason='approved',[switch]$DryRun) $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;if($DryRun){return [pscustomobject]@{stage='approved';sideEffectsPerformed=$false}};$null=Resolve-RepatoTaskApproval $StoreRoot $TaskId approve $Actor $Reason;$d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId;$q=@($t.approvalRequests|Where-Object{$_.action -like 'deployment:*' -and $_.status -eq 'approved'})[-1];$w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $w.workflowRevision $t.revision {param($x)$x.stage='approved';$x.status='approved';$x.approvalId=$q.requestId;$x.taskRevision=$q.approvedRevision}).Workflow }
function Validate-DeployWorkflowApproval { param([string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$ApprovalId) $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;$d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId;$q=@($t.approvalRequests|Where-Object requestId -ceq $ApprovalId);if($q.Count -ne 1 -or $q[0].status -ne 'approved'){throw 'Workflow approval is missing or not approved.'};$q[0] }
function Validate-DeployWorkflowConsumedApproval { param([string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$ApprovalId) $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;$d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId;$q=@($t.approvalRequests|Where-Object requestId -ceq $ApprovalId)[0];if(!$q -or $q.status -ne 'consumed' -or !$w.nonceConsumed){throw 'Consumed deployment approval invalid.'};$q }
function Consume-DeployWorkflowApproval { param([string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$ApprovalId) $null=Validate-DeployWorkflowApproval $StoreRoot $TaskId $WorkflowId $ApprovalId;Consume-DeployApproval $StoreRoot $TaskId $ApprovalId }function Invoke-DeployWorkflowBackup {
 param([string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$ApprovalId,[switch]$DryRun)
 $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
 if($workflow.stage -ne 'approved'){throw 'Workflow must be approved before backup.'}
 $plan=Get-DeployWorkflowPlan $StoreRoot $TaskId $WorkflowId
 if($DryRun){return [pscustomobject]@{stage='backed-up';sideEffectsPerformed=$false}}
 $null=Validate-DeployWorkflowApproval $StoreRoot $TaskId $WorkflowId $ApprovalId
 $consumed=Consume-DeployWorkflowApproval $StoreRoot $TaskId $WorkflowId $ApprovalId
 $dir=$plan.targetRoot; if([string]::IsNullOrWhiteSpace($dir)){throw 'TargetRoot required.'}
 $artifact=Join-Path $dir 'artifact.target'; $manifest=Join-Path $dir 'manifest.target'
 $artifactBackup=$artifact+'.backup'; $manifestBackup=$manifest+'.backup'
 Copy-Item $artifact ($artifactBackup+'.tmp') -Force; Move-Item ($artifactBackup+'.tmp') $artifactBackup -Force
 Copy-Item $manifest ($manifestBackup+'.tmp') -Force; Move-Item ($manifestBackup+'.tmp') $manifestBackup -Force
 $data=Read-RepatoTaskStore $StoreRoot; $task=Find-RepatoTask $data $TaskId; $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
 $backupHashes=@((Get-FileHash $artifactBackup -Algorithm SHA256).Hash,(Get-FileHash $manifestBackup -Algorithm SHA256).Hash)
 $result=Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision { param($current)
  $current.stage='backed-up'; $current.status='backed-up'; $current.approvalId=$ApprovalId; $current.approvalStatus='consumed'
  $current.consumedNonce=$consumed.Nonce; $current.nonceConsumed=$true; $current.consumedUtc=$consumed.consumedUtc; $current.approvedTaskRevision=$consumed.approvedRevision
  $current.backupPaths=@($artifactBackup,$manifestBackup); $current.backupHashes=$backupHashes; return $current
 }
 $updated=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
 if($updated.stage -ne 'backed-up'){throw ('Backup stage was not persisted. Actual stage: {0}; revision: {1}' -f $updated.stage,$updated.workflowRevision)}
 return $updated
}function Invoke-DeployWorkflowApply { param([string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$ApprovalId,[switch]$DryRun)
 $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;if($w.stage -ne 'backed-up'){throw 'Workflow must be backed-up before apply.'};$p=Get-DeployWorkflowPlan $StoreRoot $TaskId $WorkflowId;if($DryRun){return [pscustomobject]@{stage='applied';sideEffectsPerformed=$false}};$null=Validate-DeployWorkflowConsumedApproval $StoreRoot $TaskId $WorkflowId $ApprovalId;if($p.failureMode -eq 'Apply'){Invoke-DeployAutomaticRollback $StoreRoot $TaskId $WorkflowId $ApprovalId 'Injected Apply failure';throw 'Injected Apply failure.'};$dir=$p.targetRoot;$a=Join-Path $dir 'artifact.target';$m=Join-Path $dir 'manifest.target';if(!$w.backupPaths -or !(Test-Path $w.backupPaths[0]) -or !(Test-Path $w.backupPaths[1])){throw 'Backup required before apply.'};Copy-Item $p.artifactPath ($a+'.tmp') -Force;Move-Item ($a+'.tmp') $a -Force;Copy-Item $p.manifestPath ($m+'.tmp') -Force;Move-Item ($m+'.tmp') $m -Force;$ah=(Get-FileHash $a -Algorithm SHA256).Hash;$mh=(Get-FileHash $m -Algorithm SHA256).Hash;if($ah -ne $p.artifactSha256 -or $mh -ne $p.manifestSha256){throw 'Applied hash verification failed.'};$d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId;$w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $w.workflowRevision $t.revision {param($x)$x.stage='applied';$x.status='applied';$x.appliedHashes=@($ah,$mh)}).Workflow
}
function Invoke-DeployWorkflowVerify {
 param([string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$ApprovalId,[switch]$DryRun)
 $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
 if($workflow.stage -ne 'applied'){throw 'Workflow must be applied before verification.'}
 $plan=Get-DeployWorkflowPlan $StoreRoot $TaskId $WorkflowId
 if($DryRun){return [pscustomobject]@{stage='verified';sideEffectsPerformed=$false}}
 $null=Validate-DeployWorkflowConsumedApproval $StoreRoot $TaskId $WorkflowId $ApprovalId
 if($plan.failureMode -eq 'Verify'){Invoke-DeployAutomaticRollback $StoreRoot $TaskId $WorkflowId $ApprovalId 'Injected Verify failure';throw 'Injected Verify failure.'}
 $dir=$plan.targetRoot
 $artifact=Join-Path $dir 'artifact.target'; $manifest=Join-Path $dir 'manifest.target'
 $actualArtifact=(Get-FileHash $artifact -Algorithm SHA256).Hash; $actualManifest=(Get-FileHash $manifest -Algorithm SHA256).Hash
 if($actualArtifact -ne $plan.artifactSha256 -or $actualManifest -ne $plan.manifestSha256){throw 'Verification hash mismatch.'}
 $data=Read-RepatoTaskStore $StoreRoot; $task=Find-RepatoTask $data $TaskId; $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
 $result=Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision { param($current)
   $current.stage='verified'; $current.status='verified'; $current.verificationStatus='passed'; $current.expectedHashes=@($plan.artifactSha256,$plan.manifestSha256); $current.actualHashes=@($actualArtifact,$actualManifest); return $current
 }
 $updated=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
 if($updated.stage -ne 'verified'){throw ('Verification stage was not persisted. Actual stage: {0}; revision: {1}' -f $updated.stage,$updated.workflowRevision)}
 return $updated
}
function Complete-DeployWorkflow {
 param([string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$ApprovalId,[switch]$DryRun)
 $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
 if($workflow.stage -ne 'verified'){throw 'Workflow must be verified before completion.'}
 $plan=Get-DeployWorkflowPlan $StoreRoot $TaskId $WorkflowId
 if($DryRun){return [pscustomobject]@{stage='completed';sideEffectsPerformed=$false}}
 $null=Validate-DeployWorkflowConsumedApproval $StoreRoot $TaskId $WorkflowId $ApprovalId
 $data=Read-RepatoTaskStore $StoreRoot; $task=Find-RepatoTask $data $TaskId; $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
 $result=Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision { param($current)
   $current.stage='completed'; $current.status='completed'; $current.completedUtc=(Get-Date).ToUniversalTime().ToString('O'); $current.completionEvidence='verification-passed'; return $current
 }
 $updated=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
 if($updated.stage -ne 'completed'){throw ('Completion stage was not persisted. Actual stage: {0}; revision: {1}' -f $updated.stage,$updated.workflowRevision)}
 return $updated
}
function Invoke-DeployAutomaticRollback {
 param([string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$ApprovalId,[string]$OriginalError='deployment failure',[switch]$DryRun)
 $workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
 if($DryRun){return [pscustomobject]@{stage='failed';sideEffectsPerformed=$false}}
 if($workflow.stage -notin @('backed-up','applied','rollback-pending','failed')){throw 'Rollback requires a backed-up or applied workflow.'}
 if(!$workflow.backupPaths -or $workflow.backupPaths.Count -ne 2){throw 'Valid backups are required for rollback.'}
 $data=Read-RepatoTaskStore $StoreRoot; $task=Find-RepatoTask $data $TaskId
 if($workflow.stage -ne 'rollback-pending'){
   $r=Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {param($x)$x.stage='rollback-pending';$x.status='rollback-pending';$x.originalError=$OriginalError;return $x};$workflow=$r.Workflow
 }
 $artifact=Join-Path $workflow.targetRoot 'artifact.target';$manifest=Join-Path $workflow.targetRoot 'manifest.target'
 Copy-Item $workflow.backupPaths[0] ($artifact+'.tmp') -Force;Move-Item ($artifact+'.tmp') $artifact -Force
 Copy-Item $workflow.backupPaths[1] ($manifest+'.tmp') -Force;Move-Item ($manifest+'.tmp') $manifest -Force
 $ah=(Get-FileHash $artifact -Algorithm SHA256).Hash;$mh=(Get-FileHash $manifest -Algorithm SHA256).Hash
 $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
 $r=Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {param($x)$x.stage='rolled-back';$x.status='rolled-back';$x.rollbackResult='restored';$x.restoredHashes=@($ah,$mh);return $x};$workflow=$r.Workflow
 $data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$workflow=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
 $r=Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {param($x)$x.stage='failed';$x.status='failed';$x.finishedUtc=(Get-Date).ToUniversalTime().ToString('O');return $x};Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
}
function Invoke-DeployWorkflowRollback { param([string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$ApprovalId,[switch]$DryRun) Invoke-DeployAutomaticRollback $StoreRoot $TaskId $WorkflowId $ApprovalId 'manual rollback' -DryRun:$DryRun }
function Invoke-DeployWithRollback { param([scriptblock]$Operation,[string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$ApprovalId,[switch]$DryRun) try { & $Operation } catch { Invoke-DeployAutomaticRollback $StoreRoot $TaskId $WorkflowId $ApprovalId $_.Exception.Message; throw } }
Export-ModuleMember -Function Invoke-RepatoWorkflowMutation,Get-DeployPlanHash,New-DeployPlan,New-DeployWorkflow,Get-DeployWorkflow,Get-DeployWorkflowPlan,Request-DeployWorkflowApproval,Approve-DeployWorkflow,Validate-DeployWorkflowApproval,Validate-DeployWorkflowConsumedApproval,Consume-DeployWorkflowApproval,Invoke-DeployWorkflowBackup,Invoke-DeployWorkflowApply,Invoke-DeployWorkflowVerify,Complete-DeployWorkflow,Invoke-DeployAutomaticRollback,Invoke-DeployWorkflowRollback,Invoke-DeployWithRollback


function Consume-DeployApproval { param([string]$StoreRoot,[string]$TaskId,[string]$ApprovalId) Invoke-RepatoStoreMutation $StoreRoot { param($d,$p) $t=Find-RepatoTask $d $TaskId; $q=@($t.approvalRequests|Where-Object requestId -ceq $ApprovalId); if($q.Count -ne 1 -or $q[0].status -ne 'approved'){throw 'Approval missing or already consumed.'}; $q[0].status='consumed'; $q[0]|Add-Member NoteProperty Nonce ([guid]::NewGuid().ToString('N')) -Force; $q[0]|Add-Member NoteProperty consumedUtc (Get-Date).ToUniversalTime().ToString('O') -Force; $q[0] } }