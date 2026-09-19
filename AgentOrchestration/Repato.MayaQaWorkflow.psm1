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
function Get-MayaQaWorkflowStatus { param([Parameter(Mandatory)][string]$StoreRoot,[Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$WorkflowId)
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
    $target=Join-Path $store 'TargetRoot';New-Item -ItemType Directory -Path $target -Force|Out-Null;$artifact=Join-Path $target 'artifact.bin';$manifest=Join-Path $target 'manifest.addin';Set-Content $artifact 'fixture artifact';Set-Content $manifest 'fixture manifest'
    $plan=New-DeployPlan $store $TaskId $artifact $manifest -TargetRoot $target;$w=New-DeployWorkflow $store $plan
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
Export-ModuleMember -Function Get-MayaQaWorkflowDefinition,Get-MayaQaWorkflowCatalog,Get-MayaQaCatalogDryRun,Get-MayaQaWorkflowStatus,New-MayaQaBootstrap,New-MayaQaRun,Register-MayaQaReport,Complete-MayaQaWorkflow
