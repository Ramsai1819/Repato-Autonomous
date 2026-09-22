Set-StrictMode -Version Latest
$script:Definitions = @{
    'welcome-smoke' = @{ FixtureId='CreateLevelsEmpty'; Source='CreateLevelsEmpty.rvt'; Prep=$null; TestId='welcome-supervised-dialog-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'create-grids-world-axis-v1' = @{ FixtureId='CreateGridsEmptyPlan'; Source='CreateGridsEmptyPlan.rvt'; Prep='Prepare-CreateGridsQaRun.ps1'; TestId='create-grids-world-axis-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
        'create-levels' = @{ FixtureId='CreateLevelsEmpty'; Source='CreateLevelsEmpty.rvt'; Prep='Prepare-CreateLevelsQaRun.ps1'; TestId='create-levels-elevations-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'grid-bubble-visibility-v1' = @{ FixtureId='GridBubbleVisibilityEmpty'; Source='GridBubbleVisibilityEmpty.rvt'; Prep='Prepare-GridBubbleVisibilityQaRun.ps1'; TestId='grid-bubble-visibility-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'grid-bubble-offset-v1' = @{ FixtureId='GridBubbleOffsetEmpty'; Source='GridBubbleOffsetEmpty.rvt'; Prep='Prepare-GridBubbleOffsetQaRun.ps1'; TestId='grid-bubble-offset-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
    'grid-resequence-v1' = @{ FixtureId='GridResequenceEmpty'; Source='GridResequenceEmpty.rvt'; Prep='Prepare-GridResequenceQaRun.ps1'; TestId='grid-resequence-all-directions-v1'; Capabilities=@('prepare-fixture','report-verify','complete') }
}
function Get-MayaQaWorkflowDefinition { param([Parameter(Mandatory)][string]$WorkflowId)
    if (-not $script:Definitions.ContainsKey($WorkflowId)) { throw "Unsupported QA workflow ID: $WorkflowId" }
    [pscustomobject]$script:Definitions[$WorkflowId]
}
function Get-MayaQaWorkflowCatalog {
    @($script:Definitions.GetEnumerator() | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{WorkflowId=$_.Key;FixtureId=$_.Value.FixtureId;TestId=$_.Value.TestId;PreparationScript=$_.Value.Prep;Capabilities=@($_.Value.Capabilities);SupervisedExecutionRequired=$true;RevitLaunchByCoordinator=$false;RealDeploymentByCoordinator=$false;DryRunSupported=$true}
    })
}
function Get-MayaQaCatalogDryRun { param([string]$WorkflowId)
    $items=if($WorkflowId){$null=Get-MayaQaWorkflowDefinition $WorkflowId; @(Get-MayaQaWorkflowCatalog | Where-Object WorkflowId -ceq $WorkflowId)}else{@(Get-MayaQaWorkflowCatalog)}
    $items=@($items); [pscustomobject]@{Workflows=$items;SupportedWorkflowCount=$items.Count;SideEffectsPerformed=$false;RevitLaunchPerformed=$false;DeploymentPerformed=$false;StoreWritePerformed=$false}
}
function Invoke-MayaQaIntake {
    param([Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$UserRequest,[switch]$DryRun)
    if ($TaskId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$') { throw 'Invalid task identity.' }
    if ($WorkflowId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$') { throw 'Invalid workflow identity.' }
    $def = Get-MayaQaWorkflowDefinition $QaWorkflowId
    if ([string]::IsNullOrWhiteSpace($UserRequest)) { throw 'User request is required.' }
    $candidates = @()
    foreach ($candidate in Get-MayaQaWorkflowCatalog) {
        if ($UserRequest -match [regex]::Escape($candidate.WorkflowId)) { $candidates += $candidate; continue }
        if ($UserRequest -match [regex]::Escape($candidate.TestId)) { $candidates += $candidate; continue }
        if ($UserRequest -match [regex]::Escape($candidate.FixtureId)) { $candidates += $candidate }
    }
    if ($candidates.Count -eq 0) { throw 'User request does not identify a supported QA workflow.' }
    $unique = @($candidates | Sort-Object WorkflowId -Unique)
    if ($unique.Count -ne 1 -or $unique[0].WorkflowId -cne $QaWorkflowId) { throw 'User request is ambiguous or does not match QaWorkflowId.' }
    [pscustomobject]@{
        TaskId = $TaskId
        WorkflowId = $WorkflowId
        OriginalUserRequest = $UserRequest
        QaWorkflowId = $unique[0].WorkflowId
        FixtureId = $unique[0].FixtureId
        NativeTestId = $unique[0].TestId
        PreparationScript = $unique[0].PreparationScript
        RequiredApprovalStage = 'Maya approval after Tara QA passed'
        NextAllowedOperation = 'qa-run-plan'
        SideEffectsPerformed = $false
        DryRun = [bool]$DryRun
    }
}function New-MayaQaBuildRequest {
    param(
        [Parameter(Mandatory)]
        [string]$StoreRoot,

        [Parameter(Mandatory)]
        [string]$TaskId,

        [Parameter(Mandatory)]
        [string]$WorkflowId,

        [Parameter(Mandatory)]
        [string]$QaWorkflowId,

        [string]$UserRequest = '',

        [string]$SourceBranch = 'current',

        [string]$ProjectPath = 'Forma.RevitConnector.csproj',

        [switch]$DryRun
    )

    if ([string]::IsNullOrWhiteSpace($SourceBranch)) {
        $SourceBranch = 'current'
    }

    if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
        $ProjectPath = 'Forma.RevitConnector.csproj'
    }

    if ([string]::IsNullOrWhiteSpace($UserRequest)) {
        $UserRequest = "Please run QA workflow $QaWorkflowId"
    }

    $null = Invoke-MayaQaIntake `
        $TaskId `
        $WorkflowId `
        $QaWorkflowId `
        $UserRequest `
        -DryRun:$true

    $requestId = 'build-' + [guid]::NewGuid().ToString('N')
    $requestedArtifact = 'bin\Release\net8.0-windows\Repato.Revit.dll'

    if ($DryRun) {
        return [pscustomobject]@{
            BuildRequestId = $requestId
            TaskId = $TaskId
            WorkflowId = $WorkflowId
            QaWorkflowId = $QaWorkflowId
            BuildStatus = 'requested'
            SourceBranch = $SourceBranch
            ProjectPath = $ProjectPath
            RequestedArtifact = $requestedArtifact
            SideEffectsPerformed = $false
        }
    }

    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId

    if ($workflow.PSObject.Properties.Name -contains 'qaWorkflowId' -and
        $workflow.qaWorkflowId -cne $QaWorkflowId) {
        throw 'Valid QA intake record is missing.'
    }

    if ($workflow.PSObject.Properties.Name -contains 'qaBuildRequestId' -and
        $workflow.qaBuildRequestId) {
        throw 'Build request already exists.'
    }

    $data = Read-RepatoTaskStore $StoreRoot
    $task = Find-RepatoTask $data $TaskId

    $mutation = @(Invoke-RepatoWorkflowMutation `
        $StoreRoot `
        $TaskId `
        $WorkflowId `
        $workflow.workflowRevision `
        $task.revision {

        param($current)

        $current | Add-Member `
            -NotePropertyName qaWorkflowId `
            -NotePropertyValue $QaWorkflowId `
            -Force

        $current | Add-Member `
            -NotePropertyName qaBuildRequestId `
            -NotePropertyValue $requestId `
            -Force

        $current | Add-Member `
            -NotePropertyName qaBuildRequest `
            -NotePropertyValue ([pscustomobject]@{
                BuildRequestId = $requestId
                SourceBranch = $SourceBranch
                ProjectPath = $ProjectPath
                RequestedArtifact = $requestedArtifact
                BuildStatus = 'requested'
                RequestedUtc = (Get-Date).ToUniversalTime().ToString('O')
            }) `
            -Force

        return $current
    })[-1]

    [pscustomobject]@{
        BuildRequestId = $requestId
        TaskId = $TaskId
        WorkflowId = $WorkflowId
        QaWorkflowId = $QaWorkflowId
        BuildStatus = 'requested'
        SourceBranch = $SourceBranch
        ProjectPath = $ProjectPath
        RequestedArtifact = $requestedArtifact
        WorkflowRevision = $mutation.Workflow.workflowRevision
        TaskRevision = $mutation.TaskRevision
        SideEffectsPerformed = $true
    }
}
function Invoke-MayaQaBuildExecute {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[string]$SourceBranch='current',[string]$ProjectPath='Forma.RevitConnector.csproj',[switch]$DryRun)
    if ([string]::IsNullOrWhiteSpace($SourceBranch)) { $SourceBranch = 'current' }
    if ([string]::IsNullOrWhiteSpace($ProjectPath)) { $ProjectPath = 'Forma.RevitConnector.csproj' }
    $def = Get-MayaQaWorkflowDefinition $QaWorkflowId
    if ($DryRun) { return [pscustomobject]@{BuildRequestId=('build-' + [guid]::NewGuid().ToString('N'));TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;BuildStatus='planned';SideEffectsPerformed=$false} }
    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if ($workflow.PSObject.Properties.Name -notcontains 'qaBuildRequest' -or !$workflow.qaBuildRequest) { throw 'Persisted Neil build request is missing.' }
    if ($workflow.PSObject.Properties.Name -contains 'qaWorkflowId' -and $workflow.qaWorkflowId -cne $QaWorkflowId) { throw 'QA workflow identity mismatch.' }
    $normalize = {
        param([string]$Value,[string]$Base)
        if([string]::IsNullOrWhiteSpace($Value)){throw 'Persisted build path is empty.'}
        $clean=$Value.Trim().Trim('"') -replace '\\\\','\'
        if([IO.Path]::IsPathRooted($clean)){[IO.Path]::GetFullPath($clean)}else{[IO.Path]::GetFullPath((Join-Path $Base $clean))}
    }
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $persistedProject = & $normalize ([string]$workflow.qaBuildRequest.ProjectPath) $root
    $requestedProjectInput = & $normalize $ProjectPath $root
    if ($workflow.qaBuildRequest.SourceBranch -cne $SourceBranch -or $persistedProject -ine $requestedProjectInput) { throw 'Build request parameters do not match the persisted request.' }
    $project = [IO.Path]::GetFullPath((Join-Path $root 'Forma.RevitConnector.csproj'))
    if ($persistedProject -ine $project -or !(Test-Path -LiteralPath $persistedProject -PathType Leaf)) { throw 'Normalized project path is missing or outside the approved workspace.' }
    $artifact = [IO.Path]::GetFullPath((Join-Path $root 'bin\Release\net8.0-windows\Repato.Revit.dll'))
    $artifactManifest = [IO.Path]::GetFullPath((Join-Path $root 'Repato.addin'))
    $requestedArtifact = if($workflow.qaBuildRequest.PSObject.Properties.Name -contains 'RequestedArtifact') { & $normalize ([string]$workflow.qaBuildRequest.RequestedArtifact) $root } else { $artifact }
    if($requestedArtifact -ine $artifact){throw 'Normalized requested artifact is outside the approved Release artifact path.'}
    $command = 'dotnet build "' + $project + '" -c Release -p:RevitInstallDir="E:\revit\Revit 2025"'
    if ($DryRun) { return [pscustomobject]@{BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;BuildStatus='planned';Command=$command;Configuration='Release';ArtifactPath=$artifact;SideEffectsPerformed=$false} }
    $started = (Get-Date).ToUniversalTime().ToString('O')
    Push-Location $root
    try { $lines = @(& dotnet build $project -c Release '-p:RevitInstallDir=E:\revit\Revit 2025' 2>&1); $exit = $LASTEXITCODE } finally { Pop-Location }
    $finished = (Get-Date).ToUniversalTime().ToString('O')
    $warningCount = @($lines | Where-Object { $_ -match '(?i)warning' }).Count
    $errorCount = @($lines | Where-Object { $_ -match '(?i)error' }).Count
    $manifestValid=$false
    if(Test-Path -LiteralPath $artifactManifest -PathType Leaf){try{$manifestValid=([xml](Get-Content -LiteralPath $artifactManifest -Raw)).DocumentElement.Name -ceq 'RevitAddIns'}catch{$manifestValid=$false}}
    if ($exit -ne 0 -or !(Test-Path -LiteralPath $artifact -PathType Leaf) -or !$manifestValid) { $status='failed' } else { $status='succeeded' }
    $data = Read-RepatoTaskStore $StoreRoot; $task = Find-RepatoTask $data $TaskId
    $mutation = @(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {
        param($current)
        $current | Add-Member -NotePropertyName qaBuildStatus -NotePropertyValue $status -Force
        $current | Add-Member -NotePropertyName qaBuildEvidence -NotePropertyValue ([pscustomobject]@{BuildRequestId=$current.qaBuildRequest.BuildRequestId;StartedUtc=$started;FinishedUtc=$finished;Command=$command;Configuration='Release';ExitCode=$exit;ArtifactPath=$artifact;ArtifactSha256=$(if(Test-Path $artifact){(Get-FileHash $artifact -Algorithm SHA256).Hash}else{$null});ManifestPath=$artifactManifest;ManifestSha256=$(if(Test-Path $artifactManifest){(Get-FileHash $artifactManifest -Algorithm SHA256).Hash}else{$null});BuildStatus=$status;WarningCount=$warningCount;ErrorCount=$errorCount}) -Force
        return $current
    })[-1]
    if ($status -ne 'succeeded') { throw "Release build failed with exit code $exit." }
    [pscustomobject]@{BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;BuildStatus=$status;Command=$command;Configuration='Release';ExitCode=$exit;ArtifactPath=$artifact;ArtifactSha256=$mutation.Workflow.qaBuildEvidence.ArtifactSha256;ArtifactManifestPath=$artifactManifest;ArtifactManifestSha256=$mutation.Workflow.qaBuildEvidence.ManifestSha256;ManifestPath=$artifactManifest;ManifestSha256=$mutation.Workflow.qaBuildEvidence.ManifestSha256;WarningCount=$warningCount;ErrorCount=$errorCount;WorkflowRevision=$mutation.Workflow.workflowRevision;TaskRevision=$mutation.TaskRevision;SideEffectsPerformed=$true}
}
function New-MayaQaHandoff {
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [switch]$DryRun
    )

    $definition = Get-MayaQaWorkflowDefinition $QaWorkflowId
    if ($DryRun) {
        return [pscustomobject]@{
            HandoffId = 'handoff-' + [guid]::NewGuid().ToString('N')
            TaskId = $TaskId
            WorkflowId = $WorkflowId
            QaWorkflowId = $QaWorkflowId
            HandoffStatus = 'planned'
            SideEffectsPerformed = $false
        }
    }

    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $properties = @($workflow.PSObject.Properties.Name)
    if ($properties -notcontains 'qaBuildRequest' -or $null -eq $workflow.qaBuildRequest) {
        throw 'Completed Neil build request is missing.'
    }
    if ($properties -notcontains 'qaBuildEvidence' -or $properties -notcontains 'qaBuildStatus' -or $workflow.qaBuildStatus -ne 'succeeded') {
        throw 'Successful Neil build execution is required.'
    }
    if ($properties -contains 'qaHandoffId' -and $workflow.qaHandoffId) {
        throw 'Tara QA handoff already exists.'
    }

    $evidence = $workflow.qaBuildEvidence
    foreach ($item in @(
        @('artifact', $evidence.ArtifactPath, $evidence.ArtifactSha256),
        @('manifest', $evidence.ManifestPath, $evidence.ManifestSha256)
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$item[1]) -or !(Test-Path -LiteralPath $item[1] -PathType Leaf)) {
            throw "Built $($item[0]) is missing."
        }
        $actualHash = (Get-FileHash -LiteralPath $item[1] -Algorithm SHA256).Hash
        if ($actualHash -ine [string]$item[2]) {
            throw "Built $($item[0]) hash mismatch."
        }
    }
    $artifactHash = (Get-FileHash -LiteralPath $evidence.ArtifactPath -Algorithm SHA256).Hash
    $manifestHash = (Get-FileHash -LiteralPath $evidence.ManifestPath -Algorithm SHA256).Hash
    $handoffId = 'handoff-' + [guid]::NewGuid().ToString('N')
    $coordinatorRunId = 'qa-run-' + [guid]::NewGuid().ToString('N')
    $data = Read-RepatoTaskStore $StoreRoot
    $task = Find-RepatoTask $data $TaskId
    $mutation = @(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {
        param($current)
        $handoff = [pscustomobject]@{
            HandoffId = $handoffId
            TaskId = $TaskId
            BuildRequestId = $current.qaBuildRequest.BuildRequestId
            ArtifactPath = $evidence.ArtifactPath
            ArtifactSha256 = $artifactHash
            ManifestPath = $evidence.ManifestPath
            ManifestSha256 = $manifestHash
            QaWorkflowId = $QaWorkflowId
            FixtureId = $definition.FixtureId
            NativeTestId = $definition.TestId
            PreparationScript = $definition.Prep
            ModelPath = $(if($current.PSObject.Properties.Name -contains 'qaModelPath'){$current.qaModelPath}else{$null})
            SidecarPath = $(if($current.PSObject.Properties.Name -contains 'qaSidecarPath'){$current.qaSidecarPath}else{$null})
            CoordinatorRunId = $coordinatorRunId
            HandoffStatus = 'ready'
            CreatedUtc = (Get-Date).ToUniversalTime().ToString('O')
        }
        $current | Add-Member -NotePropertyName qaHandoffId -NotePropertyValue $handoffId -Force
        $current | Add-Member -NotePropertyName qaHandoff -NotePropertyValue $handoff -Force
        return $current
    })[-1]
    [pscustomobject]@{
        HandoffId = $handoffId
        TaskId = $TaskId
        WorkflowId = $WorkflowId
        BuildRequestId = $workflow.qaBuildRequest.BuildRequestId
        ArtifactPath = $evidence.ArtifactPath
        ArtifactSha256 = $artifactHash
        ManifestPath = $evidence.ManifestPath
        ManifestSha256 = $manifestHash
        QaWorkflowId = $QaWorkflowId
        FixtureId = $definition.FixtureId
        NativeTestId = $definition.TestId
        PreparationScript = $definition.Prep
        ModelPath = $(if($properties -contains 'qaModelPath'){$workflow.qaModelPath}else{$null})
        SidecarPath = $(if($properties -contains 'qaSidecarPath'){$workflow.qaSidecarPath}else{$null})
        CoordinatorRunId = $coordinatorRunId
        HandoffStatus = 'ready'
        WorkflowRevision = $mutation.Workflow.workflowRevision
        TaskRevision = $mutation.TaskRevision
        SideEffectsPerformed = $true
    }
}
function Get-MayaQaWorkflowStatus { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId)
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId; $qaId=if($w.PSObject.Properties.Name -contains 'qaWorkflowId'){$w.qaWorkflowId}else{$null}; $def=if($qaId){Get-MayaQaWorkflowDefinition $qaId}else{$null}
    [pscustomobject]@{WorkflowId=$WorkflowId;TaskId=$TaskId;QaWorkflowId=$qaId;Stage=$w.stage;DeploymentStatus=$w.status;QaRunId=$(if($w.PSObject.Properties.Name -contains 'qaRunId'){$w.qaRunId}else{$null});QaVerificationStatus=$(if($w.PSObject.Properties.Name -contains 'qaVerificationStatus'){$w.qaVerificationStatus}else{$null});QaCompletionStatus=$(if($w.PSObject.Properties.Name -contains 'qaCompletionStatus'){$w.qaCompletionStatus}else{$null});Capabilities=$(if($def){@($def.Capabilities)}else{@()});SupervisedExecutionRequired=$true;RevitLaunchByCoordinator=$false;RealDeploymentByCoordinator=$false;DryRunSupported=$true}
}
function Get-MayaQaRoot { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\Source\QA')) }
function New-MayaQaBootstrap { param([Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$RunId,[string]$StoreRoot,[string]$TaskId,[switch]$DryRun)
    $def=Get-MayaQaWorkflowDefinition $QaWorkflowId
    if($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'){throw 'Invalid QA run ID.'}
    if(!$StoreRoot){$StoreRoot=Join-Path $env:TEMP ('maya-qa-store-'+[guid]::NewGuid().ToString('N'))}
    $store=[IO.Path]::GetFullPath($StoreRoot);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(!$store.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){throw 'Bootstrap store must be temporary.'}
    if(!$TaskId){$TaskId='maya-qa-'+[guid]::NewGuid().ToString('N').Substring(0,16)}
    if($DryRun){return [pscustomobject]@{StoreRoot=$store;TaskId=$TaskId;WorkflowId=([guid]::NewGuid().ToString('N'));QaWorkflowId=$QaWorkflowId;RunId=$RunId;SideEffectsPerformed=$false}}
    New-RepatoTask $store $TaskId 'Maya QA fixture workflow' "QA workflow $QaWorkflowId" 'qa/maya-qa-workflow' 'maya'|Out-Null
    Claim-RepatoTask $store $TaskId 'Neil'|Out-Null
    Update-RepatoTask $store $TaskId 'in-progress' 'implementation' 'Neil' $null $null|Out-Null
    Update-RepatoTask $store $TaskId 'in-progress' 'build-checks' 'Neil' $null $null|Out-Null
    Update-RepatoTask $store $TaskId 'passed' 'qa' 'Tara' $null $null|Out-Null
    $null=Request-RepatoTaskApproval $store $TaskId 'qa-run' 'maya';$null=Resolve-RepatoTaskApproval $store $TaskId approve 'Maya' 'Tara QA passed; Maya authorized supervised QA run';$qaData=Read-RepatoTaskStore $store;$qaTask=Find-RepatoTask $qaData $TaskId;$qaApproval=@($qaTask.approvalRequests|Where-Object {$_.action -ceq 'qa-run' -and $_.status -ceq 'approved'})[-1];if(!$qaApproval){throw 'QA approval was not persisted.'}
    $target=Join-Path $store 'TargetRoot';New-Item -ItemType Directory -Path $target -Force|Out-Null;$artifact=Join-Path $target 'artifact.bin';$manifest=Join-Path $target 'manifest.addin';Set-Content $artifact 'fixture artifact';Set-Content $manifest 'fixture manifest'
    $plan=New-DeployPlan $store $TaskId $artifact $manifest -TargetRoot $target;$w=New-DeployWorkflow $store $plan;$d=Read-RepatoTaskStore $store;$t=Find-RepatoTask $d $TaskId;$w=@(Invoke-RepatoWorkflowMutation $store $TaskId $w.workflowId $w.workflowRevision $t.revision {param($x)$x|Add-Member -NotePropertyName qaWorkflowId -NotePropertyValue $QaWorkflowId -Force;$x|Add-Member -NotePropertyName qaRunId -NotePropertyValue $RunId -Force;$x|Add-Member -NotePropertyName qaApprovalId -NotePropertyValue $qaApproval.requestId -Force;$x|Add-Member -NotePropertyName qaApprovalStatus -NotePropertyValue 'approved' -Force;return $x})[-1];$w=$w.Workflow
    [pscustomobject]@{StoreRoot=$store;TaskId=$TaskId;WorkflowId=$w.workflowId;QaWorkflowId=$QaWorkflowId;RunId=$RunId;Stage=$w.stage;PlanId=$plan.planId;PlanHash=(Get-DeployPlanHash $plan);SideEffectsPerformed=$true}
}
function Assert-MayaQaPath { param([string]$Path,[string]$Root)
    $p=[IO.Path]::GetFullPath($Path); $r=([IO.Path]::GetFullPath($Root)).TrimEnd('\')+'\'
    if (-not $p.StartsWith($r,[StringComparison]::OrdinalIgnoreCase)) { throw "Path is outside approved QA root: $Path" }; $p
}
function New-MayaQaRun { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$RunId,[switch]$DryRun)
    $def=Get-MayaQaWorkflowDefinition $QaWorkflowId; if ($RunId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'){throw 'Invalid QA run ID.'}
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if ($DryRun) { return [pscustomobject]@{WorkflowId=$WorkflowId;RunId=$RunId;Stage=$w.stage;SideEffectsPerformed=$false} }
    if ($w.PSObject.Properties.Name -notcontains 'qaBuildEvidence' -or $w.PSObject.Properties.Name -notcontains 'qaBuildStatus' -or $w.qaBuildStatus -ne 'succeeded') { throw 'Valid Neil build evidence is required before QA run planning.' }
    foreach($pair in @(@($w.qaBuildEvidence.ArtifactPath,$w.qaBuildEvidence.ArtifactSha256),@($w.qaBuildEvidence.ManifestPath,$w.qaBuildEvidence.ManifestSha256))){if(!(Test-Path -LiteralPath $pair[0] -PathType Leaf) -or (Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ine $pair[1]){throw 'Neil build evidence hash validation failed.'}}
    $qa=Get-MayaQaRoot; $runs=Join-Path $qa 'TestRuns'; if(!(Test-Path -LiteralPath $runs)){New-Item -ItemType Directory -Path $runs -Force|Out-Null}; $run=[IO.Path]::GetFullPath((Join-Path $runs ($WorkflowId+'-'+$RunId))); $runsPrefix=([IO.Path]::GetFullPath($runs)).TrimEnd('\')+'\'; if(!$run.StartsWith($runsPrefix,[StringComparison]::OrdinalIgnoreCase)){throw "Run path escaped QA TestRuns: $run"}
    if (Test-Path -LiteralPath $run) { throw 'QA run directory already exists.' }
    $source=Join-Path (Join-Path $qa 'Fixtures') $def.Source; if (!(Test-Path -LiteralPath $source -PathType Leaf)){throw "Approved fixture missing: $source"}
    New-Item -ItemType Directory -Path $run -Force | Out-Null; $model=Join-Path $run 'model.rvt'; Copy-Item -LiteralPath $source -Destination $model
    $fixtureHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash; $sidecar=Join-Path $run 'model.rvt.fixture.json'
    $side=[ordered]@{fixtureId=$def.FixtureId;sourceSha256=$fixtureHash}; if($QaWorkflowId -eq 'grid-bubble-visibility-v1' -or $QaWorkflowId -eq 'grid-bubble-offset-v1'){$side.requiredGridNames=@('A','B','C','D','1','2','3','4')}; if($QaWorkflowId -eq 'grid-resequence-v1'){$side.requiredGridNames=@('1','2','3','3.2','4','A','A.1','B','C')}
    $side | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $sidecar -Encoding UTF8
    if($WorkflowId -eq 'grid-bubble-visibility-v1'){$check=Get-Content -LiteralPath $sidecar -Raw|ConvertFrom-Json;$expected=@('A','B','C','D','1','2','3','4');if($check.fixtureId -cne 'GridBubbleVisibilityEmpty' -or $check.sourceSha256 -ine $fixtureHash -or (@($check.requiredGridNames)-join '|') -cne ($expected -join '|')){throw 'Grid Bubble Visibility sidecar identity is invalid.'}}    $d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId
    $m=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $w.workflowRevision $t.revision { param($x) foreach($v in @(@('qaWorkflowId',$QaWorkflowId),@('qaRunId',$RunId),@('qaModelPath',$model),@('qaSidecarPath',$sidecar),@('qaFixtureId',$def.FixtureId),@('qaFixtureSha256',$fixtureHash),@('qaTestId',$def.TestId),@('qaReportPath',$null),@('qaReportSha256',$null),@('qaEvidence',$null),@('qaVerificationStatus',$null),@('qaCompletionStatus',$null),@('qaCompletedUtc',$null))){$x|Add-Member -NotePropertyName $v[0] -NotePropertyValue $v[1] -Force}; if($x.PSObject.Properties.Name -contains 'qaHandoff' -and $x.qaHandoff){$x.qaHandoff | Add-Member -NotePropertyName ModelPath -NotePropertyValue $model -Force;$x.qaHandoff | Add-Member -NotePropertyName SidecarPath -NotePropertyValue $sidecar -Force}; return $x })[-1]
    [pscustomobject]@{WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;RunId=$RunId;ModelPath=$model;SidecarPath=$sidecar;FixtureId=$def.FixtureId;FixtureSha256=$fixtureHash;Stage=$m.Workflow.stage;WorkflowRevision=$m.Workflow.workflowRevision;TaskRevision=$m.TaskRevision;SideEffectsPerformed=$true}
}
function Register-MayaQaReport { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$ReportPath,[switch]$DryRun)
    $def=Get-MayaQaWorkflowDefinition $QaWorkflowId; $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if($DryRun){return [pscustomobject]@{WorkflowId=$WorkflowId;Valid=$false;SideEffectsPerformed=$false}}
    $report=Assert-MayaQaPath $ReportPath (Join-Path (Get-MayaQaRoot) 'Reports'); if(!(Test-Path -LiteralPath $report -PathType Leaf)){throw 'QA report does not exist.'}
    $j=Get-Content -LiteralPath $report -Raw|ConvertFrom-Json
    if($j.TestId -cne $def.TestId -or $j.Status -cne 'Passed' -or $j.RollbackStatus -cne 'RolledBack'){throw 'QA report identity/status failed.'}
    if(!$j.Assertions -or @($j.Assertions|Where-Object {$_.Passed -ne $true}).Count){throw 'QA report contains failed assertions.'}
    if([string]::IsNullOrWhiteSpace([string]$j.DocumentPath) -or ([IO.Path]::GetFullPath($j.DocumentPath) -ine [IO.Path]::GetFullPath($w.qaModelPath))){throw 'QA report model identity failed.'}
    if($j.FixtureId -cne $w.qaFixtureId -or $j.FixtureSha256 -ine $w.qaFixtureSha256){throw 'QA report fixture identity failed.'}
    if([string]::IsNullOrWhiteSpace([string]$j.FinishedUtc)){throw 'QA report timestamp is missing.'};try { if(([DateTimeOffset]::Parse($j.FinishedUtc)) -lt ([DateTimeOffset]::Parse($w.startedUtc))){throw 'QA report is stale.'} } catch { if($_.Exception.Message -eq 'QA report is stale.'){throw}; throw 'QA report timestamp is invalid.' }
    $side=Get-Content -LiteralPath $w.qaSidecarPath -Raw|ConvertFrom-Json; if($side.sourceSha256 -ine $w.qaFixtureSha256){throw 'Fixture sidecar hash mismatch.'}
    $rh=(Get-FileHash -LiteralPath $report -Algorithm SHA256).Hash; $d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId
    $m=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $w.workflowRevision $t.revision {param($x)$e=[pscustomobject]@{CoordinatorRunId=$x.qaRunId;NativeRunId=$j.RunId;TestId=$j.TestId;Status=$j.Status;RollbackStatus=$j.RollbackStatus;Assertions=@($j.Assertions).Count;DocumentPath=[IO.Path]::GetFullPath($j.DocumentPath);FixtureId=$j.FixtureId;FixtureSha256=$j.FixtureSha256;VerifiedUtc=(Get-Date).ToUniversalTime().ToString('O')};$x|Add-Member -NotePropertyName qaReportPath -NotePropertyValue $report -Force;$x|Add-Member -NotePropertyName qaReportSha256 -NotePropertyValue $rh -Force;$x|Add-Member -NotePropertyName qaEvidence -NotePropertyValue $e -Force;$x|Add-Member -NotePropertyName qaVerificationStatus -NotePropertyValue 'verified' -Force;return $x})[-1]
    [pscustomobject]@{WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;ReportPath=$report;ReportSha256=$rh;Valid=$true;WorkflowRevision=$m.Workflow.workflowRevision;TaskRevision=$m.TaskRevision;SideEffectsPerformed=$true}
}
function Submit-MayaQaReport {
    param(
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$WorkflowId,
        [Parameter(Mandatory)][string]$QaWorkflowId,
        [Parameter(Mandatory)][string]$HandoffId,
        [Parameter(Mandatory)][string]$ReportPath,
        [switch]$DryRun
    )
    $definition = Get-MayaQaWorkflowDefinition $QaWorkflowId
    if ($DryRun) {
        return [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;HandoffId=$HandoffId;ReportPath=$ReportPath;Valid=$false;SubmissionStatus='planned';SideEffectsPerformed=$false}
    }
    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $properties = @($workflow.PSObject.Properties.Name)
    if ($properties -notcontains 'qaHandoff' -or $properties -notcontains 'qaHandoffId' -or $workflow.qaHandoffId -cne $HandoffId) {
        throw 'Tara QA handoff identity is invalid.'
    }
    if ($workflow.qaHandoff.HandoffStatus -cne 'ready' -or $workflow.qaHandoff.QaWorkflowId -cne $QaWorkflowId -or $workflow.qaHandoff.TaskId -cne $TaskId) {
        throw 'Tara QA handoff is not valid for this workflow.'
    }
    foreach ($item in @(
        @('artifact', $workflow.qaHandoff.ArtifactPath, $workflow.qaHandoff.ArtifactSha256),
        @('manifest', $workflow.qaHandoff.ManifestPath, $workflow.qaHandoff.ManifestSha256)
    )) {
        if (!(Test-Path -LiteralPath $item[1] -PathType Leaf)) { throw "Handoff $($item[0]) is missing." }
        if ((Get-FileHash -LiteralPath $item[1] -Algorithm SHA256).Hash -ine [string]$item[2]) { throw "Handoff $($item[0]) hash mismatch." }
    }
    if ($properties -contains 'qaReportPath' -and $workflow.qaReportPath) {
        throw 'QA report has already been submitted.'
    }
    $reportsRoot = [IO.Path]::GetFullPath((Join-Path (Get-MayaQaRoot) 'Reports')).TrimEnd('\') + '\'
    $resolvedReport = [IO.Path]::GetFullPath($ReportPath)
    if (!$resolvedReport.StartsWith($reportsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Path is outside approved QA root: $ReportPath" }
    if (!(Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { throw 'QA report does not exist.' }
    $result = Register-MayaQaReport $StoreRoot $TaskId $WorkflowId $QaWorkflowId $resolvedReport
    [pscustomobject]@{
        TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;HandoffId=$HandoffId
        ReportPath=$result.ReportPath;ReportSha256=$result.ReportSha256;NativeRunId=$workflow.qaRunId
        Valid=$result.Valid;SubmissionStatus='submitted';WorkflowRevision=$result.WorkflowRevision
        TaskRevision=$result.TaskRevision;SideEffectsPerformed=$true
    }
}
function Complete-MayaQaWorkflow { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[switch]$DryRun)
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    $completion = if($w.PSObject.Properties.Name -contains 'qaCompletionStatus'){[string]$w.qaCompletionStatus}else{$null}
    $verification = if($w.PSObject.Properties.Name -contains 'qaVerificationStatus'){[string]$w.qaVerificationStatus}else{$null}
    if($DryRun){return [pscustomobject]@{WorkflowId=$WorkflowId;QaVerificationStatus=$verification;QaCompletionStatus=$completion;SideEffectsPerformed=$false}}
    if($completion -eq 'completed'){throw 'QA workflow is already completed.'}
    if(($verification -and $verification -ne 'verified') -or !$w.qaEvidence -or $w.qaEvidence.Status -ne 'Passed' -or $w.qaEvidence.RollbackStatus -ne 'RolledBack'){throw 'Verified QA evidence is required.'}
    if(!(Test-Path -LiteralPath $w.qaReportPath -PathType Leaf)){throw 'Verified QA report is missing.'}
    if((Get-FileHash -LiteralPath $w.qaReportPath -Algorithm SHA256).Hash -ine $w.qaReportSha256){throw 'Verified QA report hash changed.'}
    $d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId
    $m=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $w.workflowRevision $t.revision {param($x)$x|Add-Member -NotePropertyName qaVerificationStatus -NotePropertyValue 'verified' -Force;$x|Add-Member -NotePropertyName qaCompletionStatus -NotePropertyValue 'completed' -Force;$x|Add-Member -NotePropertyName qaCompletedUtc -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('O')) -Force;return $x})[-1]
    $updated=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    [pscustomobject]@{WorkflowId=$WorkflowId;QaVerificationStatus=$updated.qaVerificationStatus;QaCompletionStatus=$updated.qaCompletionStatus;CoordinatorRunId=$updated.qaEvidence.CoordinatorRunId;NativeRunId=$updated.qaEvidence.NativeRunId;WorkflowRevision=$m.Workflow.workflowRevision;TaskRevision=$m.TaskRevision;SideEffectsPerformed=$true}
}
function New-MayaQaReceipt { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[switch]$DryRun)
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;if($DryRun){return [pscustomobject]@{WorkflowId=$WorkflowId;SideEffectsPerformed=$false}}
    $qaId=if($w.PSObject.Properties.Name -contains 'qaWorkflowId'){$w.qaWorkflowId}else{$null};if(!$qaId){throw 'QA workflow identity is missing.'};$def=Get-MayaQaWorkflowDefinition $qaId
    if($w.PSObject.Properties.Name -notcontains 'qaCompletionStatus' -or $w.qaCompletionStatus -ne 'completed' -or $w.qaVerificationStatus -ne 'verified'){throw 'QA workflow is incomplete.'}
    if(!$w.qaEvidence -or $w.qaEvidence.Status -ne 'Passed' -or $w.qaEvidence.RollbackStatus -ne 'RolledBack'){throw 'QA evidence is incomplete.'}
    $build=$w.qaBuildEvidence;$tara=if($w.PSObject.Properties.Name -contains 'qaTaraExecutionEvidence'){$w.qaTaraExecutionEvidence}else{[pscustomobject]@{QaRunnerManifestPath=$null;QaRunnerManifestSha256=$null}};$artifactPath=$build.ArtifactPath;$artifactHash=$build.ArtifactSha256;$artifactManifestPath=$build.ManifestPath;$artifactManifestHash=$build.ManifestSha256;$runnerPath=$tara.QaRunnerManifestPath;$runnerHash=$tara.QaRunnerManifestSha256
    $evidencePairs=@(@($artifactPath,$artifactHash),@($artifactManifestPath,$artifactManifestHash),@($w.qaModelPath,$w.qaFixtureSha256),@($w.qaReportPath,$w.qaReportSha256));if($runnerPath){$evidencePairs+=,@($runnerPath,$runnerHash)}
    foreach($pair in $evidencePairs){if(!(Test-Path -LiteralPath $pair[0] -PathType Leaf)){throw "Evidence file is missing: $($pair[0])"};if((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ine $pair[1]){throw "Evidence hash mismatch: $($pair[0])"}}
    $reports=Join-Path (Get-MayaQaRoot) 'Reports';$receiptPath=Join-Path $reports ('maya-qa-receipt-'+$w.qaRunId+'.json');$base=[ordered]@{SchemaVersion='1';TaskId=$TaskId;DeploymentWorkflowId=$WorkflowId;QaWorkflowId=$qaId;QaApprovalId=$(if($w.PSObject.Properties.Name -contains 'qaApprovalId'){$w.qaApprovalId}else{$null});QaApprovalStatus=$(if($w.PSObject.Properties.Name -contains 'qaApprovalStatus'){$w.qaApprovalStatus}else{$null});CoordinatorRunId=$w.qaEvidence.CoordinatorRunId;NativeRunId=$w.qaEvidence.NativeRunId;ArtifactPath=$build.ArtifactPath;ArtifactSha256=$build.ArtifactSha256;ArtifactManifestPath=$artifactManifestPath;ArtifactManifestSha256=$artifactManifestHash;QaRunnerManifestPath=$runnerPath;QaRunnerManifestSha256=$runnerHash;ManifestPath=$build.ManifestPath;ManifestSha256=$build.ManifestSha256;QaModelPath=$w.qaModelPath;FixtureSha256=$w.qaFixtureSha256;QaReportPath=$w.qaReportPath;QaReportSha256=$w.qaReportSha256;ReportStatus=$w.qaEvidence.Status;AssertionCount=$w.qaEvidence.Assertions;RollbackStatus=$w.qaEvidence.RollbackStatus;QaVerificationStatus=$w.qaVerificationStatus;QaCompletionStatus=$w.qaCompletionStatus;CompletionTimestamp=$w.qaCompletedUtc};$json=$base|ConvertTo-Json -Compress -Depth 12;$h=[Security.Cryptography.SHA256]::Create();try{$final=([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}finally{$h.Dispose()};$receipt=[ordered]@{};$base.GetEnumerator()|ForEach-Object{$receipt[$_.Key]=$_.Value};$receipt.FinalReceiptSha256=$final;$serialized=$receipt|ConvertTo-Json -Compress -Depth 12
    $json=$base|ConvertTo-Json -Compress -Depth 12;$h=[Security.Cryptography.SHA256]::Create();try{$final=([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}finally{$h.Dispose()};$receipt=[ordered]@{};$base.GetEnumerator()|ForEach-Object{$receipt[$_.Key]=$_.Value};$receipt.FinalReceiptSha256=$final;$serialized=$receipt|ConvertTo-Json -Compress -Depth 12
    if(Test-Path -LiteralPath $receiptPath){$existing=(Get-Content -LiteralPath $receiptPath -Raw).Trim();if($existing -ne $serialized){throw 'Receipt already exists with different evidence.'};return [pscustomobject]@{ReceiptPath=$receiptPath;FinalReceiptSha256=$final;Duplicate=$true;SideEffectsPerformed=$false}}
    $serialized|Set-Content -LiteralPath $receiptPath -Encoding UTF8;$d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId;$m=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $w.workflowRevision $t.revision {param($x)$x|Add-Member -NotePropertyName qaReceiptPath -NotePropertyValue $receiptPath -Force;$x|Add-Member -NotePropertyName qaReceiptSha256 -NotePropertyValue $final -Force;return $x})[-1]
    [pscustomobject]@{ReceiptPath=$receiptPath;FinalReceiptSha256=$final;Duplicate=$false;WorkflowRevision=$m.Workflow.workflowRevision;TaskRevision=$m.TaskRevision;SideEffectsPerformed=$true}
}
function Get-MayaQaBuildEvidenceStatus {
    param([object]$Workflow)
    if ($Workflow.PSObject.Properties.Name -notcontains 'qaBuildEvidence' -or $Workflow.PSObject.Properties.Name -notcontains 'qaBuildStatus' -or $Workflow.qaBuildStatus -ne 'succeeded') { throw 'Neil build evidence is missing or failed.' }
    $e = $Workflow.qaBuildEvidence
    $checks = @()
    foreach ($pair in @(@('Artifact',$e.ArtifactPath,$e.ArtifactSha256),@('Manifest',$e.ManifestPath,$e.ManifestSha256))) {
        $valid = Test-Path -LiteralPath $pair[1] -PathType Leaf
        if ($valid) { $valid = (Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash -ieq $pair[2] }
        $checks += [pscustomobject]@{Name=$pair[0];Path=$pair[1];ExpectedSha256=$pair[2];Valid=$valid}
        if (-not $valid) { throw "Neil build evidence hash mismatch: $($pair[0])" }
    }
    [pscustomobject]@{BuildStatus=$Workflow.qaBuildStatus;ArtifactPath=$e.ArtifactPath;ArtifactSha256=$e.ArtifactSha256;ManifestPath=$e.ManifestPath;ManifestSha256=$e.ManifestSha256;SourceBranch=$e.SourceBranch;CommitId=$e.CommitId;HashVerification=$checks}
}function Get-MayaQaReceiptStatus { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[switch]$DryRun)
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;if($DryRun){return [pscustomobject]@{TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;SideEffectsPerformed=$false}}
    if($w.PSObject.Properties.Name -notcontains 'qaReceiptPath' -or [string]::IsNullOrWhiteSpace([string]$w.qaReceiptPath)){throw 'QA receipt is missing.'}
    $receiptPath=[IO.Path]::GetFullPath($w.qaReceiptPath);if(!(Test-Path -LiteralPath $receiptPath -PathType Leaf)){throw 'QA receipt is missing.'};$receipt=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
    if($receipt.TaskId -cne $TaskId -or $receipt.DeploymentWorkflowId -cne $WorkflowId -or $receipt.QaWorkflowId -cne $QaWorkflowId){throw 'QA receipt identity mismatch.'}
    $stored=$receipt.FinalReceiptSha256;$copy=[ordered]@{};$receipt.PSObject.Properties|Where-Object Name -ne 'FinalReceiptSha256'|ForEach-Object{$copy[$_.Name]=$_.Value};$json=$copy|ConvertTo-Json -Compress -Depth 12;$h=[Security.Cryptography.SHA256]::Create();try{$computed=([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}finally{$h.Dispose()};if($computed -ine $stored -or ($w.PSObject.Properties.Name -contains 'qaReceiptSha256' -and $w.qaReceiptSha256 -ine $stored)){throw 'QA receipt hash mismatch.'}
    $checks=@();foreach($pair in @(@('Artifact',$receipt.ArtifactPath,$receipt.ArtifactSha256),@('Manifest',$receipt.ManifestPath,$receipt.ManifestSha256),@('Model',$receipt.QaModelPath,$receipt.FixtureSha256),@('Report',$receipt.QaReportPath,$receipt.QaReportSha256))){$ok=Test-Path -LiteralPath $pair[1] -PathType Leaf;if($ok){$ok=(Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash -ieq $pair[2]};$checks+=[pscustomobject]@{Name=$pair[0];Path=$pair[1];ExpectedSha256=$pair[2];Valid=$ok};if(!$ok){throw "$($pair[0]) hash verification failed."}}
    [pscustomobject]@{ReceiptStatus='Valid';TaskId=$receipt.TaskId;WorkflowId=$receipt.DeploymentWorkflowId;QaWorkflowId=$receipt.QaWorkflowId;CoordinatorRunId=$receipt.CoordinatorRunId;NativeRunId=$receipt.NativeRunId;ReportStatus=$receipt.ReportStatus;RollbackStatus=$receipt.RollbackStatus;QaVerificationStatus=$receipt.QaVerificationStatus;QaCompletionStatus=$receipt.QaCompletionStatus;CompletionTimestamp=$receipt.CompletionTimestamp;ReceiptSha256=$stored;ReceiptHashValid=$true;ReferencedHashes=$checks;SideEffectsPerformed=$false}
}
function Get-MayaQaDashboard { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[switch]$DryRun)
    $def=Get-MayaQaWorkflowDefinition $QaWorkflowId;$catalog=Get-MayaQaWorkflowCatalog
    if($DryRun){return [pscustomobject]@{Catalog=$catalog;SelectedWorkflowId=$QaWorkflowId;CapabilityFlags=$def.Capabilities;DeploymentWorkflowStatus='unread';QaApprovalStatus='unread';QaPlanStatus='unread';ReportVerificationStatus='unread';QaCompletionStatus='unread';ReceiptStatus='unread';SideEffectsPerformed=$false}}
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;$plan=Get-DeployWorkflowPlan $StoreRoot $TaskId $WorkflowId;$plan.artifactPath=$w.qaBuildEvidence.ArtifactPath;$plan.artifactSha256=$w.qaBuildEvidence.ArtifactSha256;$plan.manifestPath=$w.qaBuildEvidence.ManifestPath;$plan.manifestSha256=$w.qaBuildEvidence.ManifestSha256
    $hashes=@();foreach($pair in @(@('Artifact',$plan.artifactPath,$plan.artifactSha256),@('Manifest',$plan.manifestPath,$plan.manifestSha256))){$ok=Test-Path -LiteralPath $pair[1] -PathType Leaf;if($ok){$ok=(Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash -ieq $pair[2]};$hashes+=[pscustomobject]@{Name=$pair[0];Path=$pair[1];ExpectedSha256=$pair[2];Valid=$ok};if(!$ok){throw "$($pair[0]) hash verification failed."}}
    $taraEvidence=if($w.PSObject.Properties.Name -contains 'qaTaraExecutionEvidence'){$w.qaTaraExecutionEvidence}else{[pscustomobject]@{QaRunnerManifestPath=$null;QaRunnerManifestSha256=$null}};$runnerOk=$true;if($taraEvidence.QaRunnerManifestPath){$runnerOk=Test-Path -LiteralPath $taraEvidence.QaRunnerManifestPath -PathType Leaf;if($runnerOk){$runnerOk=(Get-FileHash -LiteralPath $taraEvidence.QaRunnerManifestPath -Algorithm SHA256).Hash -ieq $taraEvidence.QaRunnerManifestSha256}};$hashes+=[pscustomobject]@{Name='QaRunnerManifest';Path=$taraEvidence.QaRunnerManifestPath;ExpectedSha256=$taraEvidence.QaRunnerManifestSha256;Valid=$runnerOk};if(!$runnerOk -and $w.qaCompletionStatus -eq 'completed'){throw 'QA runner manifest hash verification failed.'}
    $qaFields=@('qaModelPath','qaFixtureSha256','qaReportPath','qaReportSha256');foreach($n in $qaFields){if($w.PSObject.Properties.Name -notcontains $n){$hashes+=[pscustomobject]@{Name=$n;Valid=$false};continue}}
    if($w.PSObject.Properties.Name -contains 'qaModelPath'){$qaPairs=@(@('Model',$w.qaModelPath,$w.qaFixtureSha256),@('Report',$w.qaReportPath,$w.qaReportSha256));foreach($pair in $qaPairs){$ok=Test-Path -LiteralPath $pair[1] -PathType Leaf;if($ok){$ok=(Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash -ieq $pair[2]};$hashes+=[pscustomobject]@{Name=$pair[0];Path=$pair[1];ExpectedSha256=$pair[2];Valid=$ok};if(!$ok -and $w.qaCompletionStatus -eq 'completed'){throw "$($pair[0]) hash verification failed."}}}
    $receiptStatus='Missing';if($w.PSObject.Properties.Name -contains 'qaReceiptPath' -and $w.qaReceiptPath){$receipt=Get-MayaQaReceiptStatus $StoreRoot $TaskId $WorkflowId $QaWorkflowId;$receiptStatus='Valid'}elseif($w.PSObject.Properties.Name -contains 'qaCompletionStatus' -and $w.qaCompletionStatus -eq 'completed'){throw 'Completed QA workflow is missing its receipt.'}
    [pscustomobject]@{Catalog=$catalog;SelectedWorkflowId=$QaWorkflowId;CapabilityFlags=$def.Capabilities;DeploymentWorkflowStatus=$w.status;QaApprovalStatus=$(if($w.PSObject.Properties.Name -contains 'qaApprovalStatus'){$w.qaApprovalStatus}else{$null});QaPlanStatus=$w.stage;ReportVerificationStatus=$(if($w.PSObject.Properties.Name -contains 'qaVerificationStatus'){$w.qaVerificationStatus}else{$null});QaCompletionStatus=$(if($w.PSObject.Properties.Name -contains 'qaCompletionStatus'){$w.qaCompletionStatus}else{$null});ReceiptStatus=$receiptStatus;CoordinatorRunId=$(if($w.PSObject.Properties.Name -contains 'qaEvidence'){$w.qaEvidence.CoordinatorRunId}else{$null});NativeRunId=$(if($w.PSObject.Properties.Name -contains 'qaEvidence'){$w.qaEvidence.NativeRunId}else{$null});HashVerification=$hashes;CompletionTimestamp=$(if($w.PSObject.Properties.Name -contains 'qaCompletedUtc'){$w.qaCompletedUtc}else{$null});SideEffectsPerformed=$false}
}
function Invoke-MayaQaOverview { param([Parameter(Mandatory)][ValidateSet('qa-catalog-dry-run','qa-status','qa-receipt-status','qa-dashboard')][string]$Route,[string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$QaWorkflowId,[switch]$DryRun)
    $result=switch($Route){'qa-catalog-dry-run'{Get-MayaQaCatalogDryRun $WorkflowId};'qa-status'{Get-MayaQaWorkflowStatus $StoreRoot $TaskId $WorkflowId};'qa-receipt-status'{Get-MayaQaReceiptStatus $StoreRoot $TaskId $WorkflowId $QaWorkflowId -DryRun:$DryRun};'qa-dashboard'{Get-MayaQaDashboard $StoreRoot $TaskId $WorkflowId $QaWorkflowId -DryRun:$DryRun}}
    [pscustomobject]@{Operation=$Route;TimestampUtc=(Get-Date).ToUniversalTime().ToString('O');WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;ResultStatus='ok';SideEffectsPerformed=$false;Result=$result}
}
. (Join-Path $PSScriptRoot 'MayaQa.TaraExecution.ps1')
Export-ModuleMember -Function Invoke-MayaQaTaraExecute,Get-MayaQaWorkflowDefinition,Get-MayaQaWorkflowCatalog,Get-MayaQaCatalogDryRun,Get-MayaQaWorkflowStatus,Invoke-MayaQaIntake,New-MayaQaBuildRequest,Invoke-MayaQaBuildExecute,New-MayaQaHandoff,Submit-MayaQaReport,Get-MayaQaDashboard,Invoke-MayaQaOverview,New-MayaQaBootstrap,New-MayaQaRun,Register-MayaQaReport,Complete-MayaQaWorkflow,New-MayaQaReceipt,Get-MayaQaReceiptStatus
