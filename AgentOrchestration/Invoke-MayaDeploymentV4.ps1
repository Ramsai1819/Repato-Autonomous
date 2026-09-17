param([Parameter(Mandatory)][ValidateSet('maya-deploy-plan','maya-deploy-request-approval','maya-deploy-approve','maya-deploy-validate','maya-deploy-backup','maya-deploy-apply','maya-deploy-verify','maya-deploy-complete','maya-deploy-rollback','maya-deploy-status')][string]$Operation,[string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$ApprovalId,[string]$ArtifactPath,[string]$ManifestPath,[string]$TargetRoot,[ValidateSet('None','Apply','Verify')][string]$FailureMode='None',[switch]$DryRun)
$ErrorActionPreference='Stop'; $WarningPreference='SilentlyContinue'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue
try {
    $result = switch ($Operation) {
        'maya-deploy-plan' { $p=New-DeployPlan $StoreRoot $TaskId $ArtifactPath $ManifestPath -TargetRoot $TargetRoot -FailureMode $FailureMode -DryRun:$DryRun; $w=New-DeployWorkflow $StoreRoot $p -DryRun:$DryRun; [pscustomobject]@{WorkflowId=$w.workflowId;TaskId=$TaskId;PlanId=$p.planId;PlanHash=(Get-DeployPlanHash $p);TargetRoot=$p.targetRoot;FailureMode=$p.failureMode;Stage=$w.stage} }
        'maya-deploy-request-approval' { Request-DeployWorkflowApproval $StoreRoot $TaskId $WorkflowId -DryRun:$DryRun }
        'maya-deploy-approve' { Approve-DeployWorkflow $StoreRoot $TaskId $WorkflowId -DryRun:$DryRun }
        'maya-deploy-validate' { Validate-DeployWorkflowApproval $StoreRoot $TaskId $WorkflowId $ApprovalId }
        'maya-deploy-backup' { Invoke-DeployWorkflowBackup $StoreRoot $TaskId $WorkflowId $ApprovalId -DryRun:$DryRun }
        'maya-deploy-apply' { Invoke-DeployWorkflowApply $StoreRoot $TaskId $WorkflowId $ApprovalId -DryRun:$DryRun }
        'maya-deploy-verify' { Invoke-DeployWorkflowVerify $StoreRoot $TaskId $WorkflowId $ApprovalId -DryRun:$DryRun }
        'maya-deploy-complete' { Complete-DeployWorkflow $StoreRoot $TaskId $WorkflowId $ApprovalId -DryRun:$DryRun }
        'maya-deploy-rollback' { Invoke-DeployWorkflowRollback $StoreRoot $TaskId $WorkflowId $ApprovalId -DryRun:$DryRun }
        'maya-deploy-status' { Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId }
        default { throw "Unknown operation: $Operation" }
    }
    $result | ConvertTo-Json -Compress -Depth 20
} catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }