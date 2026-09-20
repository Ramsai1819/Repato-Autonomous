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
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[Parameter(Mandatory)][string]$UserRequest,[switch]$DryRun)
    $null = Invoke-MayaQaIntake $TaskId $WorkflowId $QaWorkflowId $UserRequest -DryRun:$true
    $requestId = 'build-' + [guid]::NewGuid().ToString('N')
    if ($DryRun) { return [pscustomobject]@{BuildRequestId=$requestId;TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;BuildStatus='requested';SourceBranch='current';ProjectPath='Forma.RevitConnector.csproj';RequestedArtifact='bin\Release\net8.0-windows\Repato.Revit.dll';SideEffectsPerformed=$false} }
    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if ($workflow.PSObject.Properties.Name -contains 'qaWorkflowId' -and $workflow.qaWorkflowId -cne $QaWorkflowId) { throw 'Valid QA intake record is missing.' }
    if ($workflow.PSObject.Properties.Name -contains 'qaBuildRequestId' -and $workflow.qaBuildRequestId) { throw 'Build request already exists.' }
    $data = Read-RepatoTaskStore $StoreRoot
    $task = Find-RepatoTask $data $TaskId
    $mutation = @(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {
        param($current)
        $current | Add-Member -NotePropertyName qaWorkflowId -NotePropertyValue $QaWorkflowId -Force
        $current | Add-Member -NotePropertyName qaBuildRequestId -NotePropertyValue $requestId -Force
        $current | Add-Member -NotePropertyName qaBuildRequest -NotePropertyValue ([pscustomobject]@{BuildRequestId=$requestId;SourceBranch='current';ProjectPath='Forma.RevitConnector.csproj';RequestedArtifact='bin\Release\net8.0-windows\Repato.Revit.dll';BuildStatus='requested';RequestedUtc=(Get-Date).ToUniversalTime().ToString('O')}) -Force
        return $current
    })[-1]
    [pscustomobject]@{BuildRequestId=$requestId;TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;BuildStatus='requested';SourceBranch='current';ProjectPath='Forma.RevitConnector.csproj';RequestedArtifact='bin\Release\net8.0-windows\Repato.Revit.dll';WorkflowRevision=$mutation.Workflow.workflowRevision;TaskRevision=$mutation.TaskRevision;SideEffectsPerformed=$true}
}function Invoke-MayaQaBuildExecute {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[switch]$DryRun)
    $def = Get-MayaQaWorkflowDefinition $QaWorkflowId
    if ($DryRun) { return [pscustomobject]@{BuildRequestId=('build-' + [guid]::NewGuid().ToString('N'));TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;BuildStatus='planned';SideEffectsPerformed=$false} }
    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if ($workflow.PSObject.Properties.Name -notcontains 'qaBuildRequest' -or !$workflow.qaBuildRequest) { throw 'Persisted Neil build request is missing.' }
    if ($workflow.PSObject.Properties.Name -contains 'qaWorkflowId' -and $workflow.qaWorkflowId -cne $QaWorkflowId) { throw 'QA workflow identity mismatch.' }
    if ($workflow.PSObject.Properties.Name -contains 'qaBuildStatus' -and $workflow.qaBuildStatus -eq 'succeeded') { throw 'Build request has already executed.' }
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $project = [IO.Path]::GetFullPath((Join-Path $root 'Forma.RevitConnector.csproj'))
    if ($project -ine [IO.Path]::GetFullPath((Join-Path $root 'Forma.RevitConnector.csproj'))) { throw 'Project path is outside approved workspace.' }
    $artifact = [IO.Path]::GetFullPath((Join-Path $root 'bin\Release\net8.0-windows\Repato.Revit.dll'))
    $command = 'dotnet build "' + $project + '" -c Release -p:RevitInstallDir="E:\revit\Revit 2025"'
    if ($DryRun) { return [pscustomobject]@{BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;BuildStatus='planned';Command=$command;Configuration='Release';ArtifactPath=$artifact;SideEffectsPerformed=$false} }
    $started = (Get-Date).ToUniversalTime().ToString('O')
    Push-Location $root
    try { $lines = @(& dotnet build $project -c Release '-p:RevitInstallDir=E:\revit\Revit 2025' 2>&1); $exit = $LASTEXITCODE } finally { Pop-Location }
    $finished = (Get-Date).ToUniversalTime().ToString('O')
    $warningCount = @($lines | Where-Object { $_ -match '(?i)warning' }).Count
    $errorCount = @($lines | Where-Object { $_ -match '(?i)error' }).Count
    if ($exit -ne 0 -or !(Test-Path -LiteralPath $artifact -PathType Leaf)) { $status='failed' } else { $status='succeeded' }
    $data = Read-RepatoTaskStore $StoreRoot; $task = Find-RepatoTask $data $TaskId
    $mutation = @(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {
        param($current)
        $current | Add-Member -NotePropertyName qaBuildStatus -NotePropertyValue $status -Force
        $current | Add-Member -NotePropertyName qaBuildEvidence -NotePropertyValue ([pscustomobject]@{BuildRequestId=$current.qaBuildRequest.BuildRequestId;StartedUtc=$started;FinishedUtc=$finished;Command=$command;Configuration='Release';ExitCode=$exit;ArtifactPath=$artifact;ArtifactSha256=$(if(Test-Path $artifact){(Get-FileHash $artifact -Algorithm SHA256).Hash}else{$null});WarningCount=$warningCount;ErrorCount=$errorCount}) -Force
        return $current
    })[-1]
    if ($status -ne 'succeeded') { throw "Release build failed with exit code $exit." }
    [pscustomobject]@{BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;BuildStatus=$status;Command=$command;Configuration='Release';ExitCode=$exit;ArtifactPath=$artifact;ArtifactSha256=$mutation.Workflow.qaBuildEvidence.ArtifactSha256;WarningCount=$warningCount;ErrorCount=$errorCount;WorkflowRevision=$mutation.Workflow.workflowRevision;TaskRevision=$mutation.TaskRevision;SideEffectsPerformed=$true}
}function New-MayaQaHandoff {
    param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[switch]$DryRun)
    $def = Get-MayaQaWorkflowDefinition $QaWorkflowId
    if ($DryRun) { return [pscustomobject]@{HandoffId=('handoff-' + [guid]::NewGuid().ToString('N'));TaskId=$TaskId;WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;HandoffStatus='planned';SideEffectsPerformed=$false} }
    $workflow = Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId
    if ($workflow.PSObject.Properties.Name -notcontains 'qaBuildRequest' -or !$workflow.qaBuildRequest) { throw 'Completed Neil build request is missing.' }
    if ($workflow.PSObject.Properties.Name -notcontains 'qaBuildEvidence' -or $workflow.qaBuildStatus -ne 'succeeded') { throw 'Successful Neil build execution is required.' }
    if ($workflow.PSObject.Properties.Name -contains 'qaHandoffId' -and $workflow.qaHandoffId) { throw 'Tara QA handoff already exists.' }
    $evidence = $workflow.qaBuildEvidence
    if (!(Test-Path -LiteralPath $evidence.ArtifactPath -PathType Leaf)) { throw 'Built artifact is missing.' }
    $actual = (Get-FileHash -LiteralPath $evidence.ArtifactPath -Algorithm SHA256).Hash
    if ($actual -ine $evidence.ArtifactSha256) { throw 'Built artifact hash mismatch.' }
    $handoffId = 'handoff-' + [guid]::NewGuid().ToString('N')
    $coordinatorRunId = 'qa-run-' + [guid]::NewGuid().ToString('N')
    $data = Read-RepatoTaskStore $StoreRoot; $task = Find-RepatoTask $data $TaskId
    $mutation = @(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $workflow.workflowRevision $task.revision {
        param($current)
        $current | Add-Member -NotePropertyName qaHandoffId -NotePropertyValue $handoffId -Force
        $current | Add-Member -NotePropertyName qaHandoff -NotePropertyValue ([pscustomobject]@{HandoffId=$handoffId;TaskId=$TaskId;BuildRequestId=$current.qaBuildRequest.BuildRequestId;ArtifactPath=$evidence.ArtifactPath;ArtifactSha256=$actual;QaWorkflowId=$QaWorkflowId;FixtureId=$def.FixtureId;NativeTestId=$def.TestId;PreparationScript=$def.Prep;CoordinatorRunId=$coordinatorRunId;HandoffStatus='ready';CreatedUtc=(Get-Date).ToUniversalTime().ToString('O')}) -Force
        return $current
    })[-1]
    [pscustomobject]@{HandoffId=$handoffId;TaskId=$TaskId;WorkflowId=$WorkflowId;BuildRequestId=$workflow.qaBuildRequest.BuildRequestId;ArtifactPath=$evidence.ArtifactPath;ArtifactSha256=$actual;QaWorkflowId=$QaWorkflowId;FixtureId=$def.FixtureId;NativeTestId=$def.TestId;PreparationScript=$def.Prep;CoordinatorRunId=$coordinatorRunId;HandoffStatus='ready';WorkflowRevision=$mutation.Workflow.workflowRevision;TaskRevision=$mutation.TaskRevision;SideEffectsPerformed=$true}
}function Get-MayaQaWorkflowStatus { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId)
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId; $qaId=if($w.PSObject.Properties.Name -contains 'qaWorkflowId'){$w.qaWorkflowId}else{$null}; $def=if($qaId){Get-MayaQaWorkflowDefinition $qaId}else{$null}
    [pscustomobject]@{WorkflowId=$WorkflowId;TaskId=$TaskId;QaWorkflowId=$qaId;Stage=$w.stage;DeploymentStatus=$w.status;QaRunId=$(if($w.PSObject.Properties.Name -contains 'qaRunId'){$w.qaRunId}else{$null});QaVerificationStatus=$(if($w.PSObject.Properties.Name -contains 'qaVerificationStatus'){$w.qaVerificationStatus}else{$null});QaCompletionStatus=$(if($w.PSObject.Properties.Name -contains 'qaCompletionStatus'){$w.qaCompletionStatus}else{$null});Capabilities=$(if($def){@($def.Capabilities)}else{@()});SupervisedExecutionRequired=$true;RevitLaunchByCoordinator=$false;RealDeploymentByCoordinator=$false;DryRunSupported=$true}
}
function Get-MayaQaRoot { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\QA')) }
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
    $plan=New-DeployPlan $store $TaskId $artifact $manifest -TargetRoot $target;$w=New-DeployWorkflow $store $plan;$d=Read-RepatoTaskStore $store;$t=Find-RepatoTask $d $TaskId;$w=@(Invoke-RepatoWorkflowMutation $store $TaskId $w.workflowId $w.workflowRevision $t.revision {param($x)$x|Add-Member -NotePropertyName qaApprovalId -NotePropertyValue $qaApproval.requestId -Force;$x|Add-Member -NotePropertyName qaApprovalStatus -NotePropertyValue 'approved' -Force;return $x})[-1];$w=$w.Workflow
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
    $qa=Get-MayaQaRoot; $runs=Join-Path $qa 'TestRuns'; if(!(Test-Path -LiteralPath $runs)){New-Item -ItemType Directory -Path $runs -Force|Out-Null}; $run=[IO.Path]::GetFullPath((Join-Path $runs ($WorkflowId+'-'+$RunId))); $runsPrefix=([IO.Path]::GetFullPath($runs)).TrimEnd('\')+'\'; if(!$run.StartsWith($runsPrefix,[StringComparison]::OrdinalIgnoreCase)){throw "Run path escaped QA TestRuns: $run"}
    if (Test-Path -LiteralPath $run) { throw 'QA run directory already exists.' }
    $source=Join-Path (Join-Path $qa 'Fixtures') $def.Source; if (!(Test-Path -LiteralPath $source -PathType Leaf)){throw "Approved fixture missing: $source"}
    New-Item -ItemType Directory -Path $run -Force | Out-Null; $model=Join-Path $run 'model.rvt'; Copy-Item -LiteralPath $source -Destination $model
    $fixtureHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash; $sidecar=Join-Path $run 'model.rvt.fixture.json'
    $side=@{fixtureId=$def.FixtureId;sourceSha256=$fixtureHash}; if($WorkflowId -like 'grid-bubble-*'){$side.requiredGridNames=@('A','B','C','D','1','2','3','4')}; if($WorkflowId -eq 'grid-resequence-v1'){$side.requiredGridNames=@('1','2','3','3.2','4','A','A.1','B','C')}
    $side | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $sidecar -Encoding UTF8
    $d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId
    $m=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $w.workflowRevision $t.revision { param($x) foreach($v in @(@('qaWorkflowId',$QaWorkflowId),@('qaRunId',$RunId),@('qaModelPath',$model),@('qaSidecarPath',$sidecar),@('qaFixtureId',$def.FixtureId),@('qaFixtureSha256',$fixtureHash),@('qaTestId',$def.TestId),@('qaReportPath',$null),@('qaReportSha256',$null),@('qaEvidence',$null),@('qaVerificationStatus',$null),@('qaCompletionStatus',$null),@('qaCompletedUtc',$null))){$x|Add-Member -NotePropertyName $v[0] -NotePropertyValue $v[1] -Force}; return $x })[-1]
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
    $plan=Get-DeployWorkflowPlan $StoreRoot $TaskId $WorkflowId;foreach($pair in @(@($plan.artifactPath,$plan.artifactSha256),@($plan.manifestPath,$plan.manifestSha256),@($w.qaModelPath,$w.qaFixtureSha256),@($w.qaReportPath,$w.qaReportSha256))){if(!(Test-Path -LiteralPath $pair[0] -PathType Leaf)){throw "Evidence file is missing: $($pair[0])"};if((Get-FileHash -LiteralPath $pair[0] -Algorithm SHA256).Hash -ine $pair[1]){throw "Evidence hash mismatch: $($pair[0])"}}
    $reports=Join-Path (Get-MayaQaRoot) 'Reports';$receiptPath=Join-Path $reports ('maya-qa-receipt-'+$w.qaRunId+'.json');$base=[ordered]@{SchemaVersion='1';TaskId=$TaskId;DeploymentWorkflowId=$WorkflowId;QaWorkflowId=$qaId;QaApprovalId=$(if($w.PSObject.Properties.Name -contains 'qaApprovalId'){$w.qaApprovalId}else{$null});QaApprovalStatus=$(if($w.PSObject.Properties.Name -contains 'qaApprovalStatus'){$w.qaApprovalStatus}else{$null});CoordinatorRunId=$w.qaEvidence.CoordinatorRunId;NativeRunId=$w.qaEvidence.NativeRunId;ArtifactPath=$plan.artifactPath;ArtifactSha256=$plan.artifactSha256;ManifestPath=$plan.manifestPath;ManifestSha256=$plan.manifestSha256;QaModelPath=$w.qaModelPath;FixtureSha256=$w.qaFixtureSha256;QaReportPath=$w.qaReportPath;QaReportSha256=$w.qaReportSha256;ReportStatus=$w.qaEvidence.Status;AssertionCount=$w.qaEvidence.Assertions;RollbackStatus=$w.qaEvidence.RollbackStatus;QaVerificationStatus=$w.qaVerificationStatus;QaCompletionStatus=$w.qaCompletionStatus;CompletionTimestamp=$w.qaCompletedUtc};$json=$base|ConvertTo-Json -Compress -Depth 12;$h=[Security.Cryptography.SHA256]::Create();try{$final=([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}finally{$h.Dispose()};$receipt=[ordered]@{};$base.GetEnumerator()|ForEach-Object{$receipt[$_.Key]=$_.Value};$receipt.FinalReceiptSha256=$final;$serialized=$receipt|ConvertTo-Json -Compress -Depth 12
    if(Test-Path -LiteralPath $receiptPath){$existing=(Get-Content -LiteralPath $receiptPath -Raw).Trim();if($existing -ne $serialized){throw 'Receipt already exists with different evidence.'};return [pscustomobject]@{ReceiptPath=$receiptPath;FinalReceiptSha256=$final;Duplicate=$true;SideEffectsPerformed=$false}}
    $serialized|Set-Content -LiteralPath $receiptPath -Encoding UTF8;$d=Read-RepatoTaskStore $StoreRoot;$t=Find-RepatoTask $d $TaskId;$m=@(Invoke-RepatoWorkflowMutation $StoreRoot $TaskId $WorkflowId $w.workflowRevision $t.revision {param($x)$x|Add-Member -NotePropertyName qaReceiptPath -NotePropertyValue $receiptPath -Force;$x|Add-Member -NotePropertyName qaReceiptSha256 -NotePropertyValue $final -Force;return $x})[-1]
    [pscustomobject]@{ReceiptPath=$receiptPath;FinalReceiptSha256=$final;Duplicate=$false;WorkflowRevision=$m.Workflow.workflowRevision;TaskRevision=$m.TaskRevision;SideEffectsPerformed=$true}
}
function Get-MayaQaReceiptStatus { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId,[Parameter(Mandatory)][string]$QaWorkflowId,[switch]$DryRun)
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
    $w=Get-DeployWorkflow $StoreRoot $TaskId $WorkflowId;$plan=Get-DeployWorkflowPlan $StoreRoot $TaskId $WorkflowId
    $hashes=@();foreach($pair in @(@('Artifact',$plan.artifactPath,$plan.artifactSha256),@('Manifest',$plan.manifestPath,$plan.manifestSha256))){$ok=Test-Path -LiteralPath $pair[1] -PathType Leaf;if($ok){$ok=(Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash -ieq $pair[2]};$hashes+=[pscustomobject]@{Name=$pair[0];Path=$pair[1];ExpectedSha256=$pair[2];Valid=$ok};if(!$ok){throw "$($pair[0]) hash verification failed."}}
    $qaFields=@('qaModelPath','qaFixtureSha256','qaReportPath','qaReportSha256');foreach($n in $qaFields){if($w.PSObject.Properties.Name -notcontains $n){$hashes+=[pscustomobject]@{Name=$n;Valid=$false};continue}}
    if($w.PSObject.Properties.Name -contains 'qaModelPath'){$qaPairs=@(@('Model',$w.qaModelPath,$w.qaFixtureSha256),@('Report',$w.qaReportPath,$w.qaReportSha256));foreach($pair in $qaPairs){$ok=Test-Path -LiteralPath $pair[1] -PathType Leaf;if($ok){$ok=(Get-FileHash -LiteralPath $pair[1] -Algorithm SHA256).Hash -ieq $pair[2]};$hashes+=[pscustomobject]@{Name=$pair[0];Path=$pair[1];ExpectedSha256=$pair[2];Valid=$ok};if(!$ok -and $w.qaCompletionStatus -eq 'completed'){throw "$($pair[0]) hash verification failed."}}}
    $receiptStatus='Missing';if($w.PSObject.Properties.Name -contains 'qaReceiptPath' -and $w.qaReceiptPath){$receipt=Get-MayaQaReceiptStatus $StoreRoot $TaskId $WorkflowId $QaWorkflowId;$receiptStatus='Valid'}elseif($w.PSObject.Properties.Name -contains 'qaCompletionStatus' -and $w.qaCompletionStatus -eq 'completed'){throw 'Completed QA workflow is missing its receipt.'}
    [pscustomobject]@{Catalog=$catalog;SelectedWorkflowId=$QaWorkflowId;CapabilityFlags=$def.Capabilities;DeploymentWorkflowStatus=$w.status;QaApprovalStatus=$(if($w.PSObject.Properties.Name -contains 'qaApprovalStatus'){$w.qaApprovalStatus}else{$null});QaPlanStatus=$w.stage;ReportVerificationStatus=$(if($w.PSObject.Properties.Name -contains 'qaVerificationStatus'){$w.qaVerificationStatus}else{$null});QaCompletionStatus=$(if($w.PSObject.Properties.Name -contains 'qaCompletionStatus'){$w.qaCompletionStatus}else{$null});ReceiptStatus=$receiptStatus;CoordinatorRunId=$(if($w.PSObject.Properties.Name -contains 'qaEvidence'){$w.qaEvidence.CoordinatorRunId}else{$null});NativeRunId=$(if($w.PSObject.Properties.Name -contains 'qaEvidence'){$w.qaEvidence.NativeRunId}else{$null});HashVerification=$hashes;CompletionTimestamp=$(if($w.PSObject.Properties.Name -contains 'qaCompletedUtc'){$w.qaCompletedUtc}else{$null});SideEffectsPerformed=$false}
}
function Invoke-MayaQaOverview { param([Parameter(Mandatory)][ValidateSet('qa-catalog-dry-run','qa-status','qa-receipt-status','qa-dashboard')][string]$Route,[string]$StoreRoot,[string]$TaskId,[string]$WorkflowId,[string]$QaWorkflowId,[switch]$DryRun)
    $result=switch($Route){'qa-catalog-dry-run'{Get-MayaQaCatalogDryRun $WorkflowId};'qa-status'{Get-MayaQaWorkflowStatus $StoreRoot $TaskId $WorkflowId};'qa-receipt-status'{Get-MayaQaReceiptStatus $StoreRoot $TaskId $WorkflowId $QaWorkflowId -DryRun:$DryRun};'qa-dashboard'{Get-MayaQaDashboard $StoreRoot $TaskId $WorkflowId $QaWorkflowId -DryRun:$DryRun}}
    [pscustomobject]@{Operation=$Route;TimestampUtc=(Get-Date).ToUniversalTime().ToString('O');WorkflowId=$WorkflowId;QaWorkflowId=$QaWorkflowId;ResultStatus='ok';SideEffectsPerformed=$false;Result=$result}
}
Export-ModuleMember -Function Get-MayaQaWorkflowDefinition,Get-MayaQaWorkflowCatalog,Get-MayaQaCatalogDryRun,Get-MayaQaWorkflowStatus,Invoke-MayaQaIntake,New-MayaQaBuildRequest,Invoke-MayaQaBuildExecute,New-MayaQaHandoff,Get-MayaQaDashboard,Invoke-MayaQaOverview,New-MayaQaBootstrap,New-MayaQaRun,Register-MayaQaReport,Complete-MayaQaWorkflow,New-MayaQaReceipt,Get-MayaQaReceiptStatus
