$ErrorActionPreference='Stop';$WarningPreference='SilentlyContinue'
$cli=Join-Path $PSScriptRoot 'Invoke-MayaQaWorkflow.ps1';$ps=(Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source;if(!$ps){$ps=Join-Path $PSHOME 'powershell.exe'}
function Invoke-JsonChild { param([string[]]$Arguments,[switch]$ExpectFailure)
    $old=$ErrorActionPreference;$ErrorActionPreference='Continue';$out=& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $cli @Arguments 2>&1;$ec=$LASTEXITCODE;$ErrorActionPreference=$old
    if($ExpectFailure){if($ec -eq 0){throw 'Expected child failure.'};return [pscustomobject]@{ExitCode=$ec;Output=($out -join "`n")}}
    if($ec -ne 0){throw ($out -join "`n")};$lines=@($out|Where-Object {$_ -is [string] -and $_.Trim()});if($lines.Count -ne 1){throw 'Child did not emit exactly one JSON object.'};$lines[0]|ConvertFrom-Json
}
$root=Join-Path $env:TEMP ('maya-qa-bootstrap-test-'+[guid]::NewGuid().ToString('N'));$store=Join-Path $root 'store';$task='bootstrap-'+[guid]::NewGuid().ToString('N').Substring(0,12);$run='run-'+[guid]::NewGuid().ToString('N').Substring(0,8)
try {
    $args=@('-Operation','qa-bootstrap','-QaWorkflowId','create-levels','-RunId',$run,'-StoreRoot',$store,'-TaskId',$task);$one=Invoke-JsonChild $args
    foreach($n in 'StoreRoot','TaskId','WorkflowId','QaWorkflowId','RunId'){if(!$one.$n){throw "Bootstrap omitted $n."}}
    if($one.QaWorkflowId -ne 'create-levels' -or $one.Stage -ne 'planned'){throw 'Bootstrap identity/stage mismatch.'}
    $duplicate=Invoke-JsonChild $args -ExpectFailure;if($duplicate.ExitCode -eq 0){throw 'Duplicate bootstrap accepted.'}
    $wrong=Invoke-JsonChild @('-Operation','qa-bootstrap','-QaWorkflowId','unsupported','-RunId','wrong','-StoreRoot',(Join-Path $root 'wrong')) -ExpectFailure
    $dry=Invoke-JsonChild @('-Operation','qa-bootstrap','-QaWorkflowId','create-levels','-RunId','dry','-StoreRoot',(Join-Path $root 'dry'),'-DryRun');if($dry.SideEffectsPerformed -or (Test-Path (Join-Path $root 'dry'))){throw 'Bootstrap dry-run wrote state.'}
    'Maya QA bootstrap checks passed: 8'
} finally {if(Test-Path $root){Remove-Item $root -Recurse -Force}}
