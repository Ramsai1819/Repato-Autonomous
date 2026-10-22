& (Join-Path $PSScriptRoot 'Test-MayaQaProductionShapeCanonicalTransaction.ps1');if($LASTEXITCODE -ne 0){exit $LASTEXITCODE};exit 0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force

$canonical = 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.CreatePlanViews.TestRunner.addin'
$obsolete = 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA\Repato.CreatePlanViews.TestRunner.addin'
$manifestHash = 'AF4DBFA78E61524DE7BD3B84178C6B70ED8D29D0A95BA17780826E09BE689D4F'
$candidateHash = '7EC1C819C771DCE4EC4ADCADB93B0245D243F6675EC0F0B070B03303B1F412C2'
$qa = 'create-plan-views-v1'; $events = [System.Collections.Generic.List[string]]::new()
$syntheticStore=Join-Path ([IO.Path]::GetTempPath()) ('maya-manifest-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $syntheticStore -Force|Out-Null;New-RepatoTask $syntheticStore 'synthetic-task' 'Maya QA request' 'Create Plan Views' 'qa/maya-qa-workflow' 'maya'|Out-Null;Invoke-RepatoStoreMutation $syntheticStore {param($d,$p)$t=Find-RepatoTask $d 'synthetic-task';$t|Add-Member NoteProperty mayaTaraAttempt ([pscustomobject]@{TaskId='synthetic-task';WorkflowId='synthetic-workflow';QaWorkflowId=$qa;RunId='synthetic-run';AttemptId='synthetic-attempt';RequestExpiresUtc=([DateTimeOffset]::UtcNow.AddMinutes(30).ToString('O'))}) -Force;$t}|Out-Null
$captured = $null

function New-SyntheticBoundaries {
    param([string]$runnerPath)
    $evidencePath = $runnerPath
    $request = { param($s,$u,$b,$p)
        $events.Add('maya-request')
        [pscustomobject]@{Stage='handoff-ready';TaskId='synthetic-task';WorkflowId='synthetic-workflow';QaWorkflowId=$qa;RunId='synthetic-run';Handoff=[pscustomobject]@{HandoffId='synthetic-handoff';AttemptId='synthetic-attempt';NativeTestId=$qa;ArtifactPath='artifact';ArtifactSha256=('A'*64);ManifestPath='manifest';ManifestSha256=('B'*64);ModelPath='model';ModelSha256=('C'*64);Isolation=[pscustomobject]@{Allowed=$true};RunnerManifestPath=$evidencePath;ValidatedRunnerManifestPath=$evidencePath;RunnerManifestSha256=$manifestHash;CandidateSha256=$candidateHash}}
    }
    $execution = { param($s,$id,$preflight) $events.Add('transaction-preflight'); $global:RepatoSyntheticCaptured=$preflight; [pscustomobject]@{TaskId=$id;WorkflowId='synthetic-workflow';QaWorkflowId=$qa;AttemptId='synthetic-attempt';RunId='synthetic-run'} }
    $claim = { param($s,$id,$owner,$record) $events.Add('claim'); $record | Add-Member NoteProperty ClaimId 'synthetic-claim' -Force; $record }
    $native = { param($s,$id,$claimId) $events.Add('synthetic-send-boundary'); [pscustomobject]@{Success=$true;RequestPayload=[ordered]@{operation='launch-revit-qa';manifestPath=$global:RepatoSyntheticCaptured.RunnerManifest;manifestSha256=$global:RepatoSyntheticCaptured.RunnerManifestSha256;candidateSha256=$candidateHash;qaWorkflowId=$qa;testId=$qa}} }
    [pscustomobject]@{Request=$request.GetNewClosure();Execution=$execution.GetNewClosure();Claim=$claim.GetNewClosure();Native=$native.GetNewClosure()}
}

$b = New-SyntheticBoundaries $canonical
$result = Invoke-MayaQaCanonicalTransaction -StoreRoot $syntheticStore -UserRequest 'synthetic' -RequestInvoker $b.Request -ExecutionRecordInvoker $b.Execution -ClaimInvoker $b.Claim -NativeCoreInvoker $b.Native
$payload = $result.Result.RequestPayload
$captured = $global:RepatoSyntheticCaptured
if($captured.RunnerManifest -cne $canonical -or $payload.manifestPath -cne $canonical){throw 'Canonical manifest path was not preserved end-to-end.'}
if($captured.ValidatedRunnerManifestPath -cne $canonical){throw 'Validated manifest path was not preserved.'}
if($captured.RunnerManifestSha256 -cne $manifestHash -or $payload.manifestSha256 -cne $manifestHash){throw 'Manifest hash binding was not preserved.'}
if($payload.candidateSha256 -cne $candidateHash -or $payload.qaWorkflowId -cne $qa -or $payload.testId -cne $qa){throw 'Candidate or QA identity was not preserved.'}
if(($events -join '|') -cne 'maya-request|transaction-preflight|claim|synthetic-send-boundary'){throw 'Synthetic production boundary ordering failed.'}
if(@($events | Where-Object {$_ -eq 'synthetic-send-boundary'}).Count -ne 1){throw 'Expected exactly one synthetic send boundary.'}

$obsoleteSendCalls = 0
$bad = New-SyntheticBoundaries $obsolete
$bad.Native = { param($s,$id,$claimId) $obsoleteSendCalls++; throw 'send boundary must not be reached for obsolete path' }
$rejected = $false
try { Invoke-MayaQaCanonicalTransaction -StoreRoot $syntheticStore -UserRequest 'synthetic' -RequestInvoker $bad.Request -ExecutionRecordInvoker $bad.Execution -ClaimInvoker $bad.Claim -NativeCoreInvoker $bad.Native | Out-Null } catch { $rejected=$true }
if(!$rejected -or $obsoleteSendCalls -ne 0){throw 'Obsolete path was not rejected before the send boundary.'}

$module = Get-Content (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Raw
if($module -match 'Join-Path \(\[string\]\$r\.qaAddinRoot\) ''Repato\.CreatePlanViews\.TestRunner\.addin'''){throw 'Fallback qaAddinRoot runner derivation remains in production.'}
[pscustomobject]@{SyntheticEndToEnd='PASS';DeploymentValidatedManifestPath=$canonical;MayaProcessedManifestPath=$canonical;HandoffRunnerManifestPath=$canonical;CanonicalPacketRunnerManifestPath=$canonical;TransactionPreflightManifestPath=$captured.RunnerManifest;SerializedLaunchRequestManifestPath=$payload.manifestPath;DeploymentValidatedManifestSha256=$manifestHash;SerializedLaunchRequestManifestSha256=$payload.manifestSha256;SyntheticSendBoundaryCallCount=1;ObsoletePathInjectionRejected=$rejected;MismatchSyntheticSendCallCount=$obsoleteSendCalls;LivePipeRequestSent=$false;RevitLaunched=$false;RealTaskStoreUntouched=$true};Remove-Item $syntheticStore -Recurse -Force -ErrorAction SilentlyContinue
