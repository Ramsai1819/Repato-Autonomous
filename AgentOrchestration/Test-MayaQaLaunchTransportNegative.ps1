$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
$module=Get-Module Repato.MayaQaWorkflow
$root=Join-Path $env:TEMP ('maya-v2-negative-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root|Out-Null
try {
  $path=Join-Path $root 'request.json';Set-Content $path '{}'
  $request=[pscustomobject]@{schemaVersion=2;operation='launch-revit-qa';requestId='11111111-1111-1111-1111-111111111111';taskId='task-1';workflowId='workflow-1';qaWorkflowId='create-plan-views-v1';testId='create-plan-views-v1';attemptId='22222222-2222-2222-2222-222222222222';runId='qa-run-ec774245da5341549b5d8c8a90d062b8';requestPath=$path}
  $base=[pscustomobject]@{schemaVersion=2;operation='launch-revit-qa';requestId=$request.requestId;correlationId=$request.requestId;accepted=$true;pid=4242;user='RAMSAI\RepatoQA';sid='S-1-5-21-1031246752-3872016183-2454652381-1015';sessionId=16;launchUtc=[DateTimeOffset]::UtcNow.ToString('O');imagePath='E:\revit\Revit 2025\Revit.exe';requestPath=$path;taskId=$request.taskId;workflowId=$request.workflowId;qaWorkflowId=$request.qaWorkflowId;testId=$request.testId;attemptId=$request.attemptId;runId=$request.runId;failureCode=$null}
  function Assert-Rejected($name,[scriptblock]$provider){$ok=$false;try{& $module {param($r,$p) Invoke-MayaQaLaunchAgentRequest -Request $r -Executable 'E:\revit\Revit 2025\Revit.exe' -ResponseProvider $p -ExpectedSessionId 16} -r $request -p $provider|Out-Null}catch{$ok=$true};if(!$ok){throw "Expected rejection did not occur: $name"}}
  $accepted=& $module {param($r,$p) Invoke-MayaQaLaunchAgentRequest -Request $r -Executable 'E:\revit\Revit 2025\Revit.exe' -ResponseProvider $p -ExpectedSessionId 16} -r $request -p {param($r)$base};if($accepted.Pid -ne 4242){throw 'Valid response was not accepted.'}
  $currentSession=(Get-Process -Id $PID).SessionId;$fallbackResponse=$base.PSObject.Copy();$fallbackResponse.sessionId=$currentSession;$fallbackAccepted=& $module {param($r,$p) Invoke-MayaQaLaunchAgentRequest -Request $r -Executable 'E:\revit\Revit 2025\Revit.exe' -ResponseProvider $p} -r $request -p {param($r)$fallbackResponse};if($fallbackAccepted.Pid -ne 4242){throw 'Current RepatoQA session fallback was not accepted.'}
  foreach($name in 'requestId','correlationId','runId','attemptId','user','sid','sessionId','imagePath','pid'){$bad=$base.PSObject.Copy();if($name -eq 'requestId'){$bad.requestId='bad'}elseif($name -eq 'correlationId'){$bad.correlationId='bad'}elseif($name -eq 'runId'){$bad.runId='bad'}elseif($name -eq 'attemptId'){$bad.attemptId='bad'}elseif($name -eq 'user'){$bad.user='RAMSAI\rsgud'}elseif($name -eq 'sid'){$bad.sid='S-1-bad'}elseif($name -eq 'sessionId'){$bad.sessionId=99}elseif($name -eq 'imagePath'){$bad.imagePath='C:\bad.exe'}else{$bad.pid=0};Assert-Rejected $name {param($r)$bad}}
  $rejected=$base.PSObject.Copy();$rejected.accepted=$false;$rejected.failureCode='request-invalid';Assert-Rejected 'accepted-false' {param($r)$rejected}
  Assert-Rejected 'transport-unavailable' {param($r)throw 'pipe unavailable'}
  Assert-Rejected 'malformed-response' {param($r)'not-json'}
  $injected=& $module {Invoke-MayaQaProcessLauncher -Executable 'ignored.exe' -Arguments '' -Launcher {param($e,$a)[pscustomobject]@{Pid=99;StartedUtc=[DateTimeOffset]::UtcNow.ToString('O')}} -LaunchRequest $null};if($injected.Pid -ne 99){throw 'Injected launcher seam failed.'}
  Assert-Rejected 'launcher-unparseable-start-time' {Invoke-MayaQaProcessLauncher -Executable 'ignored.exe' -Arguments '' -Launcher {param($e,$a)[pscustomobject]@{Pid=99;StartedUtc='not-a-timestamp'}} -LaunchRequest $null}
  $source=Get-Content (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Raw
  if($source -notmatch '(?s)\$requestId=\[guid\]::NewGuid\(\)\.ToString\(''N''\).*?requestId=\$requestId.*?NativeRequestId \$requestId'){throw 'Canonical transport request ID is not independently generated and durably bound before transmission.'}
  if($source -notmatch '\$plan=if\(\$PlanPreflightInvoker\)\{.*\}else\{New-TaraRevitQaPlan'){throw 'Canonical native preflight does not invoke the default plan builder when no test seam is supplied.'}
  if($source -match 'Start-Process'){throw 'Direct Start-Process fallback remains.'}
  foreach($mark in 'ExecutionStatus=''LaunchOutcomeUnknown''','FailureCode=''native-launch-outcome-unknown''','Duplicate native launch rejected.','if($x.Stage -cne ''launching'' -or $x.NativeProcessId)'){if($source -notmatch [regex]::Escape($mark)){throw "Missing canonical fail-closed marker: $mark"}}
  'Maya v2 focused negative transport checks passed: 17'
} finally {if(Test-Path $root){Remove-Item $root -Recurse -Force}}
