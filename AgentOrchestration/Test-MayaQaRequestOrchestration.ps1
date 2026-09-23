$ErrorActionPreference='Stop';Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
$r=Invoke-MayaQaRequest -StoreRoot ([IO.Path]::GetTempPath()) -UserRequest 'Create eight grids on the world axis.' -DryRun
if(!$r.Success -or $r.QaWorkflowId -cne 'create-grids-world-axis-v1' -or !$r.Stages -or $r.SideEffectsPerformed){throw 'Successful request dry-run contract failed.'}
$failed=$false;try{Invoke-MayaQaRequest -StoreRoot ([IO.Path]::GetTempPath()) -UserRequest 'Do unsupported QA' -DryRun|Out-Null}catch{$failed=$_.Exception.Message -match 'does not identify a supported QA workflow'}
if(!$failed){throw 'Unsupported request was accepted.'};Write-Host 'Maya request orchestration checks passed: 2'
