$ErrorActionPreference='Stop'
$WarningPreference='SilentlyContinue'
$null=Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
$cli=Join-Path $PSScriptRoot 'Invoke-MayaQaWorkflow.ps1'
$ps=(Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source; if(!$ps){$ps=Join-Path $PSHOME 'powershell.exe'}
function Invoke-ChildJson { param([string[]]$Args)
    $o=& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $cli @Args 2>&1; $ec=$LASTEXITCODE
    if($ec -eq 0){$json=@($o|Where-Object {$_ -is [string] -and $_.Trim()}); if($json.Count -ne 1){throw 'CLI did not emit exactly one JSON object.'}; return ($json[0]|ConvertFrom-Json)}
    return [pscustomobject]@{ExitCode=$ec;Error=($o -join [Environment]::NewLine)}
}
$root=Join-Path $env:TEMP ('maya-qa-cli-'+[guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $root|Out-Null
try {
    foreach($id in @('welcome-smoke','create-grids-world-axis-v1','create-levels','grid-bubble-visibility-v1','grid-bubble-offset-v1','grid-resequence-v1')) { if(!(Get-MayaQaWorkflowDefinition $id -ErrorAction SilentlyContinue)){throw "Allowlist missing: $id"} }
    $badArgs=@('-Operation','qa-run-plan','-StoreRoot',(Join-Path $root 'store'),'-TaskId','missing','-WorkflowId','bad-id','-QaWorkflowId','bad-id','-RunId','x','-DryRun'); $old=$ErrorActionPreference; $ErrorActionPreference='Continue'; $null=& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $cli @badArgs 2>$null; $badExit=$LASTEXITCODE; $ErrorActionPreference=$old; if($badExit -eq 0){throw 'Wrong QA workflow ID was accepted.'}
    'Maya QA workflow CLI checks passed: 7'
} finally { if(Test-Path $root){Remove-Item $root -Recurse -Force} }
