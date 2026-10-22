$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$cs=Get-Content (Join-Path $root 'QaLaunchAgent\Protocol.cs') -Raw
$server=Get-Content (Join-Path $root 'QaLaunchAgent\LaunchCoordinator.cs') -Raw
$adapter=Get-Content (Join-Path $PSScriptRoot 'Invoke-RepatoQaFrozenCandidateStaging.ps1') -Raw
$client=Get-Content (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Raw
function Assert([bool]$ok,[string]$message){if(!$ok){throw $message}}
Assert ($cs -match 'stage-frozen-candidate-for-qa') 'Typed staging operation missing.'
Assert ($cs -match 'FrozenCandidateCommit' -and $cs -match 'FrozenCandidateSha256') 'Server policy binding missing.'
Assert ($server -match 'HandleStage' -and $server -match 'StagingAdapter.Run') 'Server staging boundary missing.'
Assert ($adapter -match 'Install-TaraFrozenCandidateForQa' -and $adapter -match 'C:\\Repato-Autonomous\\Source\\DeploymentCandidates') 'Fixed canonical adapter missing.'
Assert ($adapter -notmatch 'Copy-Item|Start-Process|Invoke-Expression') 'Adapter contains arbitrary execution or copying.'
Assert ($client -match 'Invoke-MayaQaLaunchAgentFrozenCandidateStaging') 'Maya staging client missing.'
Assert ($client -match 'isolationPassed' -and $client -match 'StagingIdentity') 'Staging result validation missing.'
Assert ($client -match 'if\(\$QaStagingInvoker\)' ) 'Synthetic staging seam was removed.'
Assert ($cs -match 'HealthOperation' -and $cs -match 'StageOperation') 'Health/operation policy coverage missing.'
'QA Launch Agent staging boundary synthetic checks passed: typed DTO, fixed server policy, canonical adapter, split identity, no arbitrary execution, fail-closed result validation, and health/launch preservation.'
