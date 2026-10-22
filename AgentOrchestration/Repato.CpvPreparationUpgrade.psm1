Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$script:RequestId='9953e14c15524fe09440d1c7d7353950'
$script:TaskId='task-bf61fe7f22d74df7a92599681da5919e'
$script:User='RAMSAI\RepatoQA'
$script:Sid='S-1-5-21-1031246752-3872016183-2454652381-1015'
$script:Failure='preparation-exited-without-result'
$script:FixtureSha256='92CC9E434E2C4DD6720A2AA564E19F4E1A30EB3DA63CEA73CF737F875B9EDD45'
$script:RuntimeFiles=@('Repato.QaLaunchAgent.exe','Repato.QaLaunchAgent.dll','Repato.QaLaunchAgent.deps.json','Repato.QaLaunchAgent.runtimeconfig.json')

function Get-CpvInstalledAgentSid {
    param([Parameter(Mandatory)]$InstalledAgent,[Parameter(Mandatory)][AllowEmptyString()][string]$ProcessSid)
    $sidProperty=$InstalledAgent.PSObject.Properties['Sid']
    $sid=if($sidProperty -and ![string]::IsNullOrWhiteSpace([string]$sidProperty.Value)){[string]$sidProperty.Value}else{$ProcessSid}
    if($ProcessSid -cne $script:Sid -or $sid -cne $script:Sid){throw 'Installed Launch Agent process SID evidence is missing or invalid.'}
    $sid
}

function Get-CpvHealthSid {
    param([Parameter(Mandatory)]$Health)
    $sidProperty=$Health.PSObject.Properties['SID']
    if(!$sidProperty -or [string]::IsNullOrWhiteSpace([string]$sidProperty.Value)){throw 'Authenticated Launch Agent health response has no SID evidence.'}
    [string]$sidProperty.Value
}

function Get-CpvUpgradeInventory([string[]]$Roots) {
    $items=[Collections.Generic.List[object]]::new()
    foreach($root in $Roots){
        $full=[IO.Path]::GetFullPath($root)
        if(!(Test-Path -LiteralPath $full -PathType Container)){throw "Reconciliation evidence directory is missing: $full"}
        foreach($item in Get-ChildItem -LiteralPath $full -Force -Recurse){
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Reparse point in reconciliation evidence: $($item.FullName)"}
            if(!$item.PSIsContainer){$items.Add([pscustomobject]@{path=$item.FullName;sha256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash})}
        }
    }
    @($items|Sort-Object path)
}

function Assert-CpvPreparationUpgradeEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EvidenceRoot,[Parameter(Mandatory)][string]$RuntimeRoot,
        [Parameter(Mandatory)][string]$RequestId,[Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)]$Capabilities,[Parameter(Mandatory)]$Receipt,
        [Parameter(Mandatory)]$InstalledAgent,[Parameter(Mandatory)][AllowEmptyString()][string]$ProcessSid,[Parameter(Mandatory)][string]$ExpectedExecutable,
        [Parameter(Mandatory)][string]$ExpectedInstalledVersion,[Parameter(Mandatory)][string]$CandidateRoot,
        [Parameter(Mandatory)][string]$CandidateManifestPath,[Parameter(Mandatory)][string]$CandidateManifestSha256,
        [Parameter(Mandatory)][object[]]$PriorRuntimeFiles,[Parameter(Mandatory)][bool]$PriorTaskContractValid,
        [Parameter(Mandatory)][bool]$NoRevitProcesses
    )
    if($RequestId -cne $script:RequestId -or $TaskId -cne $script:TaskId){throw 'Only the fixed CPV failed request can use this upgrade exception.'}
    if(!$Capabilities -or $Capabilities.operation -cne 'cpv-preparation-capabilities' -or $Capabilities.supported -ne $true -or
        $Capabilities.user -ine $script:User -or $Capabilities.sid -cne $script:Sid -or $Capabilities.sessionId -le 0){throw 'Authenticated RepatoQA capability evidence is invalid.'}
    if(!$InstalledAgent -or $InstalledAgent.ProcessName -cne 'Repato.QaLaunchAgent' -or
        [IO.Path]::GetFullPath($InstalledAgent.Path) -ine [IO.Path]::GetFullPath($ExpectedExecutable) -or
        $InstalledAgent.ProductVersion -cne $ExpectedInstalledVersion -or $InstalledAgent.Id -le 0 -or !$InstalledAgent.StartTime){throw 'Installed Launch Agent identity differs from the expected prior runtime.'}
    $installedSid=Get-CpvInstalledAgentSid -InstalledAgent $InstalledAgent -ProcessSid $ProcessSid
    if($InstalledAgent.User -ine $script:User -or $installedSid -cne $script:Sid -or
        $InstalledAgent.SessionId -ne $Capabilities.sessionId){throw 'Installed Launch Agent process identity differs from authenticated pipe identity.'}
    if(!$NoRevitProcesses){throw 'Revit process presence or process-state uncertainty blocks the upgrade.'}
    if(!$PriorTaskContractValid -or @($PriorRuntimeFiles).Count -ne $script:RuntimeFiles.Count -or
        @($PriorRuntimeFiles|Where-Object {$_.name -notin $script:RuntimeFiles -or $_.sha256 -notmatch '^[A-Fa-f0-9]{64}'}).Count -or
        @($script:RuntimeFiles|Where-Object {$_ -notin @($PriorRuntimeFiles|ForEach-Object name)}).Count -or
        @($PriorRuntimeFiles.name|Select-Object -Unique).Count -ne $script:RuntimeFiles.Count){throw 'A complete verified rollback source is unavailable.'}
    foreach($entry in $PriorRuntimeFiles){$path=Join-Path (Split-Path $ExpectedExecutable -Parent) $entry.name;if(!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $entry.sha256){throw "Prior runtime rollback hash is invalid: $($entry.name)"}}
    if(!$Receipt -or $Receipt.operation -cne 'prepare-cpv-fixture' -or $Receipt.status -cne 'OutcomeUnknown' -or
        $Receipt.failureCode -cne 'preparation-failed-reconcile-required' -or $Receipt.requestId -cne $RequestId -or
        $Receipt.taskId -cne $TaskId -or $Receipt.user -ine $script:User -or $Receipt.sid -cne $script:Sid -or
        $Receipt.sessionId -le 0 -or $Receipt.cleanupVerified -ne $false -or $Receipt.modelSha256 -or
        $Receipt.resultPath -or $Receipt.resultSha256 -or $Receipt.rollbackStatus -cne 'Unknown')
        {throw 'Authenticated status is not the exact unresolved failed preparation.'}
    $activePath=Join-Path $EvidenceRoot 'active.json';$requestPath=Join-Path $EvidenceRoot ($RequestId+'.request.json')
    $failurePath=Join-Path $EvidenceRoot ($RequestId+'.failure.txt');$receiptPath=Join-Path $EvidenceRoot ($RequestId+'.json')
    foreach($path in @($activePath,$requestPath,$failurePath,$receiptPath)){if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Required reconciliation evidence is missing: $path"}}
    $active=Get-Content -LiteralPath $activePath -Raw|ConvertFrom-Json;$saved=Get-Content -LiteralPath $requestPath -Raw|ConvertFrom-Json
    if($active.requestId -cne $RequestId -or $saved.requestId -cne $RequestId -or $active.taskId -cne $TaskId -or $saved.taskId -cne $TaskId){throw 'Active marker and request identity mismatch.'}
    foreach($name in 'workflowId','attemptId','runId'){if($active.$name -cne $saved.$name){throw "Active marker and request identity mismatch: $name"}}
    if($active.schemaVersion -ne 1 -or $active.operation -cne 'prepare-cpv-fixture' -or
        !(Get-Content -LiteralPath $failurePath -Raw).Contains('InvalidDataException: '+$script:Failure) -or
        $saved.candidateEvidence.CandidateDllSha256 -ine $Receipt.candidateSha256 -or
        $saved.candidateEvidence.RunnerManifestSha256 -ine $Receipt.manifestSha256 -or
        $active.expiresUtc -cne $saved.expiresUtc -or $active.candidateEvidence.CandidateDllSha256 -ine $saved.candidateEvidence.CandidateDllSha256 -or
        $active.candidateEvidence.RunnerManifestSha256 -ine $saved.candidateEvidence.RunnerManifestSha256){throw 'Failure record or candidate binding is inconsistent.'}
    $diskReceipt=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
    foreach($name in 'requestId','taskId','workflowId','attemptId','runId','status','failureCode','candidateSha256','manifestSha256','modelPath','requestPath','modelSha256','resultPath','resultSha256','cleanupVerified','rollbackStatus'){
        if($diskReceipt.$name -cne $Receipt.$name){throw "Stored and authenticated receipt mismatch: $name"}
    }
    $run=Join-Path $RuntimeRoot ('cpv-preparation-'+$active.runId);$model=Join-Path $run 'model.rvt'
    $runnerPath=Join-Path $run ('tara-'+$active.attemptId+'.request.json');$resultPath=$runnerPath+'.preparation.json'
    if([IO.Path]::GetFullPath($Receipt.modelPath) -ine [IO.Path]::GetFullPath($model) -or
        [IO.Path]::GetFullPath($Receipt.requestPath) -ine [IO.Path]::GetFullPath($runnerPath) -or
        !(Test-Path -LiteralPath $model -PathType Leaf) -or !(Test-Path -LiteralPath $runnerPath -PathType Leaf) -or
        (Test-Path -LiteralPath $resultPath) -or (Test-Path -LiteralPath ($model+'.slog')) -or (Test-Path -LiteralPath ($model+'.lck')))
        {throw 'Disposable model, result, or lock evidence is inconsistent.'}
    $runner=Get-Content -LiteralPath $runnerPath -Raw|ConvertFrom-Json
    foreach($pair in @(@('operation','prepare-disposable-create-plan-views-fixture'),@('requestId',$active.attemptId),@('taskId',$TaskId),@('workflowId',$active.workflowId),@('attemptId',$active.attemptId),@('runId',$active.runId))){if($runner.($pair[0]) -cne $pair[1]){throw 'Runner request identity mismatch.'}}
    if([IO.Path]::GetFullPath($runner.modelPath) -ine [IO.Path]::GetFullPath($model) -or
        [IO.Path]::GetFullPath($runner.requestPath) -ine [IO.Path]::GetFullPath($runnerPath) -or
        [IO.Path]::GetFullPath($runner.outputPath) -ine [IO.Path]::GetFullPath($resultPath) -or
        $runner.modelSha256 -ine $script:FixtureSha256 -or
        (Get-FileHash -LiteralPath $model -Algorithm SHA256).Hash -ine $script:FixtureSha256)
        {throw 'Frozen disposable fixture evidence changed.'}
    $sidecar=Get-Content -LiteralPath ($model+'.fixture.json') -Raw|ConvertFrom-Json
    if($sidecar.fixtureId -cne 'CreatePlanViewsEmpty' -or $sidecar.sourceSha256 -ine $script:FixtureSha256){throw 'Disposable fixture sidecar is invalid.'}
    $modelStream=[IO.File]::Open($model,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try{$sha=[Security.Cryptography.SHA256]::Create();try{$actual=([BitConverter]::ToString($sha.ComputeHash($modelStream))).Replace('-','')}finally{$sha.Dispose()}}finally{$modelStream.Dispose()}
    if($actual -ine $script:FixtureSha256){throw 'Disposable model could not be locked or its hash changed.'}
    $manifestFull=[IO.Path]::GetFullPath($CandidateManifestPath);$candidateFull=[IO.Path]::GetFullPath($CandidateRoot).TrimEnd('\')
    if((Get-FileHash -LiteralPath $manifestFull -Algorithm SHA256).Hash -ine $CandidateManifestSha256){throw 'Candidate manifest hash mismatch.'}
    $manifest=Get-Content -LiteralPath $manifestFull -Raw|ConvertFrom-Json
    if(!$CandidateManifestSha256 -or $CandidateManifestSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
        !$manifest.product -or $manifest.product -cne 'Repato.QaLaunchAgent' -or $manifest.account -cne $script:User -or $manifest.sid -cne $script:Sid -or
        $manifest.productVersion -notmatch '^1\.0\.18\+[a-fA-F0-9]{12,40}$' -or $manifest.productVersion -ceq $ExpectedInstalledVersion -or
        @($manifest.files).Count -ne $script:RuntimeFiles.Count -or @($manifest.files.name|Select-Object -Unique).Count -ne $script:RuntimeFiles.Count){throw 'Candidate release contract is invalid.'}
    if(!$manifestFull.StartsWith($candidateFull+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Candidate manifest escaped its release root.'}
    foreach($entry in $manifest.files){
        if($entry.name -notin $script:RuntimeFiles -or $entry.sha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Candidate file manifest is ambiguous.'}
        $path=[IO.Path]::GetFullPath((Join-Path $candidateFull $entry.name))
        if(!$path.StartsWith($candidateFull+'\',[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $entry.sha256){throw "Candidate file hash mismatch: $($entry.name)"}
    }
    [pscustomobject]@{Request=$active;ModelPath=$model;RunDirectory=$run;CandidateVersion=$manifest.productVersion;PriorFiles=@($PriorRuntimeFiles)}
}

function Get-CpvPreparationUpgradeEvidenceSnapshot([string]$EvidenceRoot,[string]$RunDirectory) {
    Get-CpvUpgradeInventory @($EvidenceRoot,$RunDirectory)
}

function Test-CpvPreparationUpgradeEvidenceSnapshot($Before,[string]$EvidenceRoot,[string]$RunDirectory) {
    $after=Get-CpvUpgradeInventory @($EvidenceRoot,$RunDirectory)
    (ConvertTo-Json -InputObject @($Before) -Depth 5 -Compress) -ceq (ConvertTo-Json -InputObject @($after) -Depth 5 -Compress)
}

Export-ModuleMember -Function Assert-CpvPreparationUpgradeEvidence,Get-CpvPreparationUpgradeEvidenceSnapshot,Test-CpvPreparationUpgradeEvidenceSnapshot,Get-CpvHealthSid
