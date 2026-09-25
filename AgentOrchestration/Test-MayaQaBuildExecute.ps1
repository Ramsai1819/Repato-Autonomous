$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.v4.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
$root = Join-Path ([IO.Path]::GetTempPath()) ('maya-build-exec-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$dry = Invoke-MayaQaBuildExecute $root taskx workflowx create-levels -DryRun
if ($dry.SideEffectsPerformed -or $dry.BuildStatus -ne 'planned') { throw 'Dry-run execution mismatch.' }
$missing = $false; try { Invoke-MayaQaBuildExecute $root taskx workflowx create-levels | Out-Null } catch { $missing = $true }; if (-not $missing) { throw 'Missing build request accepted.' }
$unsupported = $false; try { Invoke-MayaQaBuildExecute $root taskx workflowx create-schedules -DryRun | Out-Null } catch { $unsupported = $true }; if (-not $unsupported) { throw 'Unsupported workflow accepted.' }
'Maya QA build-execute checks passed: 3'
