$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Repato.NeilAdapter.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -WarningAction SilentlyContinue
$root=Join-Path ([IO.Path]::GetTempPath()) ('Repato-Neil-'+[guid]::NewGuid().ToString('N'));$checks=0;$repo='C:\Repato-Autonomous\Source';$branch=(Get-Content (Join-Path $repo '.git\HEAD') -Raw).Trim().Replace('ref: refs/heads/','');$fixture=Join-Path $PSScriptRoot 'Fixtures\NeilAdapterTarget.txt'
function Check([string]$Name,[bool]$Condition){if(!$Condition){throw "FAILED: $Name"};$script:checks++;Write-Host "PASS $Name"}
function Reject([string]$Name,[scriptblock]$Action){try{&$Action;throw "FAILED: $Name accepted"}catch{if($_.Exception.Message-like'FAILED:*'){throw};$script:checks++;Write-Host "PASS $Name"}}
function NewTask([string]$Id,[string]$Agent='Neil',[string]$Stage='implementation',[string]$BranchName=$branch){$null=New-RepatoTask $root $Id $Id 'Neil adapter test task' $BranchName maya;$null=Claim-RepatoTask $root $Id $Agent;if($Stage-eq'implementation'){$null=Update-RepatoTask $root $Id in-progress implementation $Agent $null $null}}
function NewValidated([string]$Id,[string]$Action){NewTask $Id;$run=New-NeilPlan $root $Id $Action;$null=Test-NeilPlan $root $Id $run.runId;$run}
function Approve([string]$Id,[string]$RunId,[int]$Minutes=30){$null=Request-NeilApproval $root $Id $RunId $Minutes;$null=Resolve-RepatoTaskApproval $root $Id approve Maya approved}
Initialize-RepatoTaskStore $root|Out-Null

$registry=Get-NeilRegistry
Check 'production source allowlist is explicit' ($registry.ProductionFiles.Count-eq7-and@($registry.ProductionFiles.Keys|Where-Object{$_-notmatch'\.cs$'}).Count-eq0)
Check 'only validation actions enabled' (@($registry.Actions.Values|Where-Object{-not$_.TestOnly}).Count-eq0)
$productionBefore=@{};foreach($path in $registry.ProductionFiles.Values){$productionBefore[$path]=(Get-FileHash $path -Algorithm SHA256).Hash}

NewTask NEIL-UNKNOWN
Reject 'unknown action rejection' {New-NeilPlan $root NEIL-UNKNOWN production.arbitrary|Out-Null}
Reject 'path traversal rejection' {New-NeilPlan $root NEIL-UNKNOWN '../RepatoWelcomeCommand.cs'|Out-Null}
$cli=Join-Path $PSScriptRoot 'Invoke-RepatoNeilAdapter.ps1';$old=$ErrorActionPreference;$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli neil-plan -TaskId NEIL-UNKNOWN -ActionId validation.fixture-marker-forward-v1 -TargetPath '..\RepatoWelcomeCommand.cs' -StoreRoot $root 2>$null|Out-Null;$unsafeExit=$LASTEXITCODE;$ErrorActionPreference=$old
Check 'caller-supplied file rejection' ($unsafeExit-ne0)

NewTask NEIL-AGENT Tara
Reject 'wrong-agent rejection' {New-NeilPlan $root NEIL-AGENT validation.fixture-marker-forward-v1|Out-Null}
NewTask NEIL-STAGE Neil assigned
Reject 'wrong-stage rejection' {New-NeilPlan $root NEIL-STAGE validation.fixture-marker-forward-v1|Out-Null}
NewTask NEIL-BRANCH Neil implementation 'feat/not-the-current-branch'
Reject 'branch mismatch rejection' {New-NeilPlan $root NEIL-BRANCH validation.fixture-marker-forward-v1|Out-Null}

$missing=NewValidated NEIL-MISSING validation.fixture-marker-forward-v1
Reject 'missing approval rejection' {Invoke-NeilApply $root NEIL-MISSING $missing.runId|Out-Null}
$expired=NewValidated NEIL-EXPIRED validation.fixture-marker-forward-v1;$null=Request-NeilApproval $root NEIL-EXPIRED $expired.runId -1
Reject 'expired approval rejection' {Resolve-RepatoTaskApproval $root NEIL-EXPIRED approve Maya late|Out-Null}
$stale=NewValidated NEIL-STALE validation.fixture-marker-forward-v1;Approve NEIL-STALE $stale.runId;$null=Update-RepatoTask $root NEIL-STALE in-progress implementation Neil 'changed.log' $null
Reject 'stale task revision rejection' {Invoke-NeilApply $root NEIL-STALE $stale.runId|Out-Null}

NewTask NEIL-PLAN;$changed=New-NeilPlan $root NEIL-PLAN validation.fixture-marker-forward-v1;$queuePath=Join-Path $root 'tasks.json';$queue=Get-Content $queuePath -Raw|ConvertFrom-Json;(($queue.tasks|Where-Object taskId -ceq 'NEIL-PLAN').neilRuns|Where-Object runId -ceq $changed.runId).afterSha256='0'*64;$queue|ConvertTo-Json -Depth 30|Set-Content $queuePath -Encoding UTF8
Reject 'changed plan rejection' {Test-NeilPlan $root NEIL-PLAN $changed.runId|Out-Null}
$mismatch=NewValidated NEIL-MISMATCH validation.fixture-marker-forward-v1;Approve NEIL-MISMATCH $mismatch.runId;$queue=Get-Content $queuePath -Raw|ConvertFrom-Json;(($queue.tasks|Where-Object taskId -ceq 'NEIL-MISMATCH').approvalRequests|Where-Object status -ceq 'approved').bindingHash='0'*64;$queue|ConvertTo-Json -Depth 30|Set-Content $queuePath -Encoding UTF8
Reject 'mismatched approval rejection' {Invoke-NeilApply $root NEIL-MISMATCH $mismatch.runId|Out-Null}

$dry=NewValidated NEIL-DRY validation.fixture-marker-forward-v1;Approve NEIL-DRY $dry.runId;$fileBefore=(Get-FileHash $fixture -Algorithm SHA256).Hash;$storeBefore=(Get-FileHash $queuePath -Algorithm SHA256).Hash;$logsBefore=@(Get-ChildItem (Join-Path $PSScriptRoot 'Logs') -File -ErrorAction SilentlyContinue).Count;$preview=Invoke-NeilApply $root NEIL-DRY $dry.runId -DryRun;$fileAfter=(Get-FileHash $fixture -Algorithm SHA256).Hash;$storeAfter=(Get-FileHash $queuePath -Algorithm SHA256).Hash;$logsAfter=@(Get-ChildItem (Join-Path $PSScriptRoot 'Logs') -File -ErrorAction SilentlyContinue).Count
Check 'dry-run has no side effects' (!$preview.SideEffectsPerformed-and$fileBefore-eq$fileAfter-and$storeBefore-eq$storeAfter-and$logsBefore-eq$logsAfter)
Check 'dry-run exact diff' ($preview.Diff-match'(?m)^-state=before$'-and$preview.Diff-match'(?m)^\+state=after$'-and$preview.ChangedFiles.Count-eq1)

$forward=NewValidated NEIL-FORWARD validation.fixture-marker-forward-v1;Approve NEIL-FORWARD $forward.runId;$applied=Invoke-NeilApply $root NEIL-FORWARD $forward.runId
Check 'approved atomic edit and log' ($applied.status-eq'passed'-and(Get-Content $fixture -Raw).Trim()-ceq'state=after'-and(Test-Path $applied.logPath)-and$applied.beforeSha256-cne$applied.afterSha256-and$applied.afterLastWriteUtc)
Reject 'duplicate execution rejection' {Invoke-NeilApply $root NEIL-FORWARD $forward.runId|Out-Null}
$reset=NewValidated NEIL-RESET validation.fixture-marker-reset-v1;Approve NEIL-RESET $reset.runId;$restored=Invoke-NeilApply $root NEIL-RESET $reset.runId
Check 'approved reset restores fixture' ($restored.status-eq'passed'-and(Get-Content $fixture -Raw).Trim()-ceq'state=before')

$failed=NewValidated NEIL-FAIL validation.fixture-marker-forward-v1;$failed=Fail-NeilRun $root NEIL-FAIL $failed.runId 'implementation preparation failed';$failedTask=(Get-RepatoTasks $root NEIL-FAIL)[0]
Check 'failed task preservation' ($failed.status-eq'failed'-and$failedTask.status-eq'failed'-and$failedTask.errorDetails-eq'implementation preparation failed')
$concurrent=NewValidated NEIL-CONCURRENT validation.fixture-marker-forward-v1;Approve NEIL-CONCURRENT $concurrent.runId;$held=[IO.File]::Open((Join-Path $root 'store.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);try{Reject 'concurrent execution protection' {Invoke-NeilApply $root NEIL-CONCURRENT $concurrent.runId|Out-Null}}finally{$held.Dispose()}
$malformed=Join-Path $root malformed;Initialize-RepatoTaskStore $malformed|Out-Null;[IO.File]::WriteAllText((Join-Path $malformed 'tasks.json'),'{bad');Reject 'malformed task data rejection' {New-NeilPlan $malformed BAD-001 validation.fixture-marker-forward-v1|Out-Null}

$productionChanged=@();foreach($path in $registry.ProductionFiles.Values){if((Get-FileHash $path -Algorithm SHA256).Hash-cne$productionBefore[$path]){$productionChanged+=$path}}
Check 'production files remain byte-for-byte unchanged' ($productionChanged.Count-eq0)
Write-Host "$checks Neil adapter checks passed; synthetic store: $root"
