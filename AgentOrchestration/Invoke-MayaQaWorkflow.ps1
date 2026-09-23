param(
    [Parameter(Mandatory)]
    [ValidateSet(
        'qa-tara-execute',
        'qa-handoff',
        'qa-report-submit',
        'qa-build-execute',
        'qa-build-request',
        'qa-intake',
        'qa-bootstrap',
        'qa-run-plan',
        'qa-report-verify',
        'qa-complete',
        'qa-receipt',
        'qa-receipt-status',
        'qa-dashboard',
        'qa-overview',
        'qa-status',
        'qa-catalog',
        'qa-catalog-dry-run',
        'qa-help',
        'qa-capabilities'
        ,'qa-request-execute'
    )]
    [string]$Operation,

    [ValidateSet(
        'qa-catalog-dry-run',
        'qa-status',
        'qa-receipt-status',
        'qa-dashboard'
    )]
    [string]$Route,

    [string]$StoreRoot,
    [string]$TaskId,
    [string]$WorkflowId,
    [string]$QaWorkflowId,
    [string]$HandoffId,
    [string]$RunId,
    [string]$ReportPath,
    [string]$UserRequest,
    [string]$SourceBranch,
    [string]$ProjectPath,
    [string]$ModelPath,
    [string]$SidecarPath,
    [string]$ReportDirectory,
    [string]$RevitInstallDir = 'E:\revit\Revit 2025',
    [string]$QaAddinRoot,
    [ValidateRange(1,3600)][int]$TimeoutSeconds = 900,
    [switch]$LocalRun,
    [switch]$IntegrationTest,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue

try {
    $result = switch ($Operation) {
        'qa-request-execute' { Invoke-MayaQaRequest -StoreRoot $StoreRoot -UserRequest $UserRequest -SourceBranch $SourceBranch -ProjectPath $ProjectPath -DryRun:$DryRun }
        'qa-tara-execute' {
            Invoke-MayaQaTaraExecute -StoreRoot $StoreRoot -TaskId $TaskId -WorkflowId $WorkflowId `
                -QaWorkflowId $QaWorkflowId -RunId $RunId -ModelPath $ModelPath -SidecarPath $SidecarPath `
                -ReportDirectory $ReportDirectory -RevitInstallDir $RevitInstallDir -QaAddinRoot $QaAddinRoot `
                -TimeoutSeconds $TimeoutSeconds -DryRun:$DryRun -LocalRun:$LocalRun -IntegrationTest:$IntegrationTest
        }
        'qa-intake' {
            Invoke-MayaQaIntake `
                $TaskId `
                $WorkflowId `
                $QaWorkflowId `
                $UserRequest `
                -DryRun:$DryRun
        }

        'qa-bootstrap' {
            New-MayaQaBootstrap `
                $QaWorkflowId `
                $RunId `
                $StoreRoot `
                $TaskId `
                -DryRun:$DryRun
        }

        'qa-run-plan' {
            New-MayaQaRun `
                $StoreRoot `
                $TaskId `
                $WorkflowId `
                $QaWorkflowId `
                $RunId `
                -DryRun:$DryRun
        }

        'qa-build-request' {
            New-MayaQaBuildRequest `
                -StoreRoot $StoreRoot `
                -TaskId $TaskId `
                -WorkflowId $WorkflowId `
                -QaWorkflowId $QaWorkflowId `
                -UserRequest $UserRequest `
                -SourceBranch $SourceBranch `
                -ProjectPath $ProjectPath `
                -DryRun:$DryRun
        }

        'qa-build-execute' {
            Invoke-MayaQaBuildExecute `
                -StoreRoot $StoreRoot `
                -TaskId $TaskId `
                -WorkflowId $WorkflowId `
                -QaWorkflowId $QaWorkflowId `
                -SourceBranch $SourceBranch `
                -ProjectPath $ProjectPath `
                -DryRun:$DryRun
        }

        'qa-handoff' {
            New-MayaQaHandoff `
                $StoreRoot `
                $TaskId `
                $WorkflowId `
                $QaWorkflowId `
                -DryRun:$DryRun
        }

        'qa-report-submit' {
            Submit-MayaQaReport `
                $StoreRoot `
                $TaskId `
                $WorkflowId `
                $QaWorkflowId `
                $HandoffId `
                $ReportPath `
                -DryRun:$DryRun
        }

        'qa-report-verify' {
            Register-MayaQaReport `
                $StoreRoot `
                $TaskId `
                $WorkflowId `
                $QaWorkflowId `
                $ReportPath `
                -DryRun:$DryRun
        }

        'qa-complete' {
            Complete-MayaQaWorkflow `
                $StoreRoot `
                $TaskId `
                $WorkflowId `
                -DryRun:$DryRun
        }

        'qa-receipt' {
            New-MayaQaReceipt `
                $StoreRoot `
                $TaskId `
                $WorkflowId `
                -DryRun:$DryRun
        }

        'qa-receipt-status' {
            Get-MayaQaReceiptStatus `
                $StoreRoot `
                $TaskId `
                $WorkflowId `
                $QaWorkflowId `
                -DryRun:$DryRun
        }

        'qa-dashboard' {
            Get-MayaQaDashboard `
                $StoreRoot `
                $TaskId `
                $WorkflowId `
                $QaWorkflowId `
                -DryRun:$DryRun
        }

        'qa-overview' {
            Invoke-MayaQaOverview `
                $Route `
                $StoreRoot `
                $TaskId `
                $WorkflowId `
                $QaWorkflowId `
                -DryRun:$DryRun
        }

        'qa-status' {
            Get-MayaQaWorkflowStatus `
                $StoreRoot `
                $TaskId `
                $WorkflowId
        }

        'qa-catalog' {
            Get-MayaQaWorkflowCatalog
        }

        'qa-catalog-dry-run' {
            Get-MayaQaCatalogDryRun `
                $WorkflowId
        }

        'qa-help' {
            [pscustomobject]@{
                Operations = @(
                    'qa-tara-execute',
                    'qa-handoff',
                    'qa-report-submit',
                    'qa-build-execute',
                    'qa-build-request',
                    'qa-intake',
                    'qa-bootstrap',
                    'qa-run-plan',
                    'qa-report-verify',
                    'qa-complete',
                    'qa-receipt',
                    'qa-receipt-status',
                    'qa-dashboard',
                    'qa-overview',
                    'qa-status',
                    'qa-catalog',
                    'qa-catalog-dry-run',
                    'qa-help',
                    'qa-capabilities'
                )
                SupervisedExecutionRequired = $true
                RevitLaunchByCoordinator = $false
                RealDeploymentByCoordinator = $false
                DryRunSupported = $true
                WorkflowIds = @(
                    Get-MayaQaWorkflowCatalog |
                        ForEach-Object WorkflowId
                )
            }
        }

        'qa-capabilities' {
            Get-MayaQaWorkflowCatalog
        }
    }

    if ($Operation -eq 'qa-tara-execute' -and $LocalRun -and !$DryRun) {
        'STARTED'
        'REQUEST_CREATED'
        if ($result.ReportPath) { 'REPORT_FOUND' }
        if ($result.Status -ceq 'Passed') { 'PASSED' } else { 'FAILED' }
        'FINAL_RESULT'
    }
    $result | ConvertTo-Json -Compress -Depth 12
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
