param([string]$StoreRoot=(Join-Path $PSScriptRoot '..\QA\MayaRuns'),[string]$TaskId='task-41cfec12ef3e406990d36c9997cf6591',[string]$WorkflowId='78b5a11ab95e4cac86dcf45a1cb9cfdc',[string]$AttemptId='3adc98af191a46b6bce2bc985137e2c7')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaRunnerRepair.psm1') -Force -WarningAction SilentlyContinue
$before=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $before $TaskId
$dry=New-MayaQaRunnerRepairBuildRequest -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -FailedAttemptId $AttemptId -DryRun
if($dry.StoreMutationPerformed -or $dry.CandidateBuilt -or $dry.DeploymentPerformed -or $dry.QaAttemptCreated -or !$dry.CandidateEvidencePreserved){throw 'Dry-run side-effect contract failed.'}
try { New-MayaQaRunnerRepairBuildRequest -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId -FailedAttemptId 'wrong-attempt' -DryRun | Out-Null; throw 'Wrong attempt identity was accepted.' } catch { if($_.Exception.Message -like 'Wrong attempt identity*'){throw} }
$after=Read-RepatoTaskStore $StoreRoot;$same=(Find-RepatoTask $after $TaskId)
if([long]$same.revision -ne [long]$task.revision -or $same.mayaTaraExecution.Stage -cne 'runner-startup-failed' -or $same.mayaTaraAttempt.AttemptId -cne $AttemptId){throw 'Dry-run changed task state.'}
[pscustomobject]@{Status='PASS';Assertions=3;BuildRequestId=$dry.ReplacementBuildRequestId;SourceCommit=$dry.SourceCommit;StoreMutationPerformed=$false;CandidateBuilt=$false;DeploymentPerformed=$false;QaAttemptCreated=$false}|ConvertTo-Json -Compress
