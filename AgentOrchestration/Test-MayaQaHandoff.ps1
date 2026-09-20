$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
$root=Join-Path ([IO.Path]::GetTempPath()) ('maya-handoff-'+[guid]::NewGuid().ToString('N'));New-Item $root -ItemType Directory|Out-Null
$d=New-MayaQaHandoff $root taskx workflowx create-levels -DryRun
if($d.SideEffectsPerformed -or $d.HandoffStatus -ne 'planned'){throw 'Dry-run mismatch.'}
$bad=$false;try{New-MayaQaHandoff $root taskx workflowx create-plan-views -DryRun|Out-Null}catch{$bad=$true};if(!$bad){throw 'Unsupported workflow accepted.'}
$bad=$false;try{New-MayaQaHandoff $root taskx workflowx create-levels|Out-Null}catch{$bad=$true};if(!$bad){throw 'Missing build accepted.'}
'Maya QA handoff checks passed: 3'
