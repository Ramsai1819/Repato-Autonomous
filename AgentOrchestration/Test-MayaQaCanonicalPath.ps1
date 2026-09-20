$ErrorActionPreference = 'Stop'
$module=Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1'
$text=Get-Content $module -Raw
if($text -notmatch [regex]::Escape('..\..\Source\QA')){throw 'Canonical Source QA root is not configured.'}
$bad=$text -match [regex]::Escape('..\QA');if($bad){throw 'AgentWork QA root remains configured.'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\Source\QA\TestRuns'));$agent=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\QA\TestRuns'));if($root -ieq $agent){throw 'Canonical and AgentWork paths unexpectedly match.'}
'Maya QA canonical path checks passed: 3'
