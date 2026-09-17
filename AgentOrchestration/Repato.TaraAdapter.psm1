Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue

$script:TaraRepositoryRoot='C:\Repato-Autonomous\Source'
$script:TaraRegistryPath=Join-Path $PSScriptRoot 'TaraCommands.json'
$script:TaraLogsRoot=Join-Path $PSScriptRoot 'Logs'

function Assert-TaraRepositoryPath([string]$Path,[bool]$MustExist=$true){
    if([string]::IsNullOrWhiteSpace($Path)-or$Path-notmatch'^[A-Za-z]:\\'-or$Path.Substring(2).Contains(':')){throw 'Absolute local repository path required.'}
    $full=[IO.Path]::GetFullPath($Path);$root=[IO.Path]::GetFullPath($script:TaraRepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if(!$full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw "Path escapes repository root: $full"}
    if($MustExist-and!(Test-Path -LiteralPath $full -PathType Leaf)){throw "Repository file missing: $full"}
    $full
}

function Get-TaraRegistry {
    $path=Assert-TaraRepositoryPath $script:TaraRegistryPath
    try{$registry=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json}catch{throw "Malformed Tara command registry: $($_.Exception.Message)"}
    if($registry.schemaVersion-ne1-or$registry.repositoryRoot-ine$script:TaraRepositoryRoot-or$registry.scripts-isnot[Array]){throw 'Invalid Tara command registry.'}
    $seen=@{};foreach($relative in $registry.scripts){
        if($relative-notmatch'^(QA|AgentOrchestration)/(Test-[A-Za-z0-9._-]+|Fixtures/Validate-[A-Za-z0-9._-]+)\.ps1$'-or$relative.Contains('..')-or$seen.ContainsKey($relative)){throw 'Unsafe or duplicate registered script.'}
        $full=Assert-TaraRepositoryPath (Join-Path $script:TaraRepositoryRoot $relative.Replace('/','\'))
        $seen[$relative]=$full
    }
    [pscustomobject]@{Path=$path;Sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;Scripts=$seen}
}

function Get-TaraCommandCatalog {
    $registry=Get-TaraRegistry;$catalog=[ordered]@{}
    $catalog['build.release']=[pscustomobject]@{Executable='C:\Program Files\dotnet\dotnet.exe';Arguments=@('build','.\Forma.RevitConnector.csproj','-c','Release','-p:RevitInstallDir=E:\revit\Revit 2025');Stages=@('build-checks');ArtifactPaths=@('bin\Release\net8.0-windows\Repato.Revit.dll');RegistrySha256=$registry.Sha256}
    $catalog['syntax.powershell']=[pscustomobject]@{Executable='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';Arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $script:TaraRepositoryRoot 'AgentOrchestration\Test-PowerShellSyntax.ps1'));Stages=@('build-checks','qa');ArtifactPaths=@();RegistrySha256=$registry.Sha256}
    $catalog['git.diff-check']=[pscustomobject]@{Executable='C:\Program Files\Git\cmd\git.exe';Arguments=@('diff','--check');Stages=@('build-checks','qa');ArtifactPaths=@();RegistrySha256=$registry.Sha256}
    $catalog['git.status']=[pscustomobject]@{Executable='C:\Program Files\Git\cmd\git.exe';Arguments=@('status','--short');Stages=@('build-checks','qa');ArtifactPaths=@();RegistrySha256=$registry.Sha256}
    $catalog['git.log']=[pscustomobject]@{Executable='C:\Program Files\Git\cmd\git.exe';Arguments=@('log','-n','10','--oneline','--decorate');Stages=@('build-checks','qa');ArtifactPaths=@();RegistrySha256=$registry.Sha256}
    $catalog['git.diff']=[pscustomobject]@{Executable='C:\Program Files\Git\cmd\git.exe';Arguments=@('diff','--stat');Stages=@('build-checks','qa');ArtifactPaths=@();RegistrySha256=$registry.Sha256}
    foreach($entry in $registry.Scripts.GetEnumerator()){
        $id='script.'+$entry.Key.Replace('/','.').Replace('.ps1','')
        $stage=if($entry.Key.StartsWith('QA/')){@('qa')}else{@('build-checks')}
        $catalog[$id]=[pscustomobject]@{Executable='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';Arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$entry.Value);Stages=$stage;ArtifactPaths=@();RegistrySha256=$registry.Sha256}
    }
    foreach($definition in $catalog.Values){
        $scriptPath=if(@($definition.Arguments).Count-ge2-and$definition.Arguments[-2]-ceq'-File'){$definition.Arguments[-1]}else{$null}
        $identity=[ordered]@{executable=$definition.Executable;executableSha256=(Get-FileHash -LiteralPath $definition.Executable -Algorithm SHA256).Hash;arguments=[object[]]@($definition.Arguments);registrySha256=$definition.RegistrySha256;scriptSha256=$(if($scriptPath){(Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash}else{$null})}|ConvertTo-Json -Depth 5 -Compress
        $algorithm=[Security.Cryptography.SHA256]::Create();try{$hash=([BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity)))).Replace('-','')}finally{$algorithm.Dispose()}
        $definition|Add-Member -NotePropertyName CommandSha256 -NotePropertyValue $hash
    }
    $catalog
}

function Get-TaraPlanHash($Plan){
    $json=[ordered]@{commandId=$Plan.commandId;executable=$Plan.executable;arguments=[object[]]@($Plan.arguments);registrySha256=$Plan.registrySha256;commandSha256=$Plan.commandSha256}|ConvertTo-Json -Depth 6 -Compress
    $algorithm=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','')}finally{$algorithm.Dispose()}
}

function Initialize-TaraRuns($Task){if($Task.PSObject.Properties.Name-notcontains'taraRuns'){$Task|Add-Member -NotePropertyName taraRuns -NotePropertyValue ([object[]]@())}}
function Find-TaraRun($Task,[string]$RunId){Initialize-TaraRuns $Task;$runs=@($Task.taraRuns|Where-Object runId -ceq $RunId);if($runs.Count-ne1){throw "Tara run not found: $RunId"};$runs[0]}

function New-TaraPlan([string]$StoreRoot,[string]$TaskId,[string]$CommandId,[switch]$DryRun){
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;Assert-RepatoTask $task;Initialize-TaraRuns $task
        if($task.assignedAgent-cne'Tara'){throw 'Task must be assigned to Tara.'};if($task.status-cne'in-progress'-and$task.status-cne'passed'){throw 'Task status does not permit Tara execution.'}
        $catalog=Get-TaraCommandCatalog;if(!$catalog.Contains($CommandId)){throw "Unknown Tara command: $CommandId"};$command=$catalog[$CommandId]
        if($task.workflowStage-cnotin$command.Stages){throw "Tara command $CommandId is invalid at stage $($task.workflowStage)."}
        if(@($task.taraRuns|Where-Object status -in @('planned','validated','running')).Count){throw 'An active Tara run already exists for this task.'}
        $run=[pscustomobject][ordered]@{runId=[guid]::NewGuid().ToString('N');mode='Controlled';commandId=$CommandId;status='planned';executable=$command.Executable;arguments=[object[]]@($command.Arguments);allowedStages=[object[]]@($command.Stages);registrySha256=$command.RegistrySha256;commandSha256=$command.CommandSha256;planSha256='';plannedRevision=[long]0;validatedRevision=$null;plannedUtc=Get-RepatoUtc;startedUtc=$null;finishedUtc=$null;durationMilliseconds=$null;exitCode=$null;stdout=$null;stderr=$null;logPath=$null;artifactPaths=[object[]]@();errorDetails=$null};$run.planSha256=Get-TaraPlanHash $run
        if(!$preview){$task.taraRuns=[object[]]@($task.taraRuns)+$run;Add-RepatoHistory $task 'tara-planned' 'Maya' "run=$($run.runId); command=$CommandId; hash=$($run.planSha256)";$run.plannedRevision=[long]$task.revision};$run
    } -DryRun:$DryRun
}

function Test-TaraPlan([string]$StoreRoot,[string]$TaskId,[string]$RunId,[switch]$DryRun){
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;$run=Find-TaraRun $task $RunId
        if($task.assignedAgent-cne'Tara'){throw 'Task must remain assigned to Tara.'};if($run.status-cne'planned'-and$run.status-cne'validated'){throw 'Tara run cannot be validated in its current state.'};if([long]$run.plannedRevision-ne[long]$task.revision-and$run.status-cne'validated'){throw 'Task changed after Tara planning.'}
        $catalog=Get-TaraCommandCatalog;if(!$catalog.Contains($run.commandId)){throw 'Tara command is no longer registered.'};$command=$catalog[$run.commandId]
        if($task.workflowStage-cnotin$command.Stages){throw 'Task workflow stage no longer permits the Tara command.'}
        if($run.executable-cne$command.Executable-or(@($run.arguments)-join"`n")-cne(@($command.Arguments)-join"`n")-or$run.registrySha256-cne$command.RegistrySha256-or$run.commandSha256-cne$command.CommandSha256-or(Get-TaraPlanHash $run)-cne$run.planSha256){throw 'Tara plan identity changed or differs from the registry.'}
        if(!$preview-and$run.status-cne'validated'){$run.status='validated';Add-RepatoHistory $task 'tara-validated' 'Tara' "run=$RunId; hash=$($run.planSha256)";$run.validatedRevision=[long]$task.revision}
        [pscustomobject]@{TaskId=$TaskId;RunId=$RunId;Valid=$true;CommandId=$run.commandId;PlanSha256=$run.planSha256;TaskRevision=$task.revision}
    } -DryRun:$DryRun
}

function Request-TaraApproval([string]$StoreRoot,[string]$TaskId,[string]$RunId,[int]$ExpiryMinutes=30,[switch]$DryRun){
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;$run=Find-TaraRun $task $RunId
        if($run.status-cne'validated'-or[long]$run.validatedRevision-ne[long]$task.revision){throw 'Tara run must be freshly validated before approval.'};if(@($task.approvalRequests|Where-Object status -ceq pending).Count){throw 'Task already has a pending approval.'}
        $request=[pscustomobject]@{requestId=[guid]::NewGuid().ToString('N');action=('tara-run:'+$run.commandId);requiredLevel='maya';status='pending';bindingHash=$run.planSha256;previousStatus=$task.status;requestedRevision=[long]0;approvedRevision=$null;requestedUtc=Get-RepatoUtc;expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes($ExpiryMinutes).ToString('O');decidedUtc=$null;decidedBy=$null;reason=$null;consumedUtc=$null}
        if(!$preview){$task.approvalRequests=[object[]]@($task.approvalRequests)+$request;$task.status='awaiting-approval';Add-RepatoHistory $task 'tara-approval-requested' 'Maya' "run=$RunId; hash=$($run.planSha256)";$request.requestedRevision=[long]$task.revision};$request
    } -DryRun:$DryRun
}

function Assert-TaraApproval($Task,$Run){
    $matches=@($Task.approvalRequests|Where-Object{$_.action-ceq('tara-run:'+$Run.commandId)-and$_.bindingHash-ceq$Run.planSha256-and$_.status-ceq'approved'-and$_.consumedUtc-eq$null})
    if($matches.Count-ne1){throw 'Missing or mismatched Tara execution approval.'};$approval=$matches[0]
    if([DateTimeOffset]::Parse($approval.expiresUtc)-le[DateTimeOffset]::UtcNow-or[long]$approval.approvedRevision-ne[long]$Task.revision){throw 'Tara execution approval expired or task changed after approval.'};$approval
}

function Get-TaraPreview([string]$StoreRoot,[string]$TaskId,[string]$RunId){
    $paths=Get-RepatoStorePaths $StoreRoot;$lock=$null;try{$lock=[IO.File]::Open($paths.Lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$data=Read-RepatoTaskStore $StoreRoot;$task=Find-RepatoTask $data $TaskId;$run=Find-TaraRun $task $RunId;if($run.status-cne'validated'){throw 'Tara run is not validated.'};$null=Assert-TaraApproval $task $run;[pscustomobject]@{TaskId=$TaskId;RunId=$RunId;Mode='DryRun';CommandId=$run.commandId;Executable=$run.executable;Arguments=$run.arguments;PlanSha256=$run.planSha256;TaskRevision=$task.revision;WouldExecute=($run.executable+' '+(@($run.arguments|ForEach-Object{if($_-match'\s'){ '"'+$_+'"' }else{$_}})-join' '));SideEffectsPerformed=$false;ApprovalCheckedUtc=Get-RepatoUtc}}finally{if($lock){$lock.Dispose()}}
}

function ConvertTo-TaraArgumentString([string[]]$Arguments){(@($Arguments|ForEach-Object{'"'+$_.Replace('"','\"')+'"'})-join' ')}

function Invoke-TaraRun([string]$StoreRoot,[string]$TaskId,[string]$RunId,[switch]$DryRun){
    if($DryRun){return Get-TaraPreview $StoreRoot $TaskId $RunId}
    $start=Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;$run=Find-TaraRun $task $RunId
        if($task.assignedAgent-cne'Tara'-or$run.status-cne'validated'){throw 'Tara run is not executable.'}
        $catalog=Get-TaraCommandCatalog;if(!$catalog.Contains($run.commandId)){throw 'Tara command is no longer registered.'};$command=$catalog[$run.commandId]
        if($task.workflowStage-cnotin$command.Stages-or$run.executable-cne$command.Executable-or(@($run.arguments)-join"`n")-cne(@($command.Arguments)-join"`n")-or$run.registrySha256-cne$command.RegistrySha256-or$run.commandSha256-cne$command.CommandSha256-or(Get-TaraPlanHash $run)-cne$run.planSha256){throw 'Tara execution identity, registry, or workflow stage changed.'};$approval=Assert-TaraApproval $task $run
        $approval.consumedUtc=Get-RepatoUtc;$run.status='running';$run.startedUtc=Get-RepatoUtc;Add-RepatoHistory $task 'tara-started' 'Tara' "run=$RunId; command=$($run.commandId)";[pscustomobject]@{Executable=$run.executable;Arguments=[string[]]@($run.arguments);CommandId=$run.commandId;CommandSha256=$run.commandSha256;StartedUtc=$run.startedUtc}
    }
    $stdout='';$stderr='';$exitCode=-1;$errorText=$null;$watch=[Diagnostics.Stopwatch]::StartNew()
    try{$info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$start.Executable;$info.Arguments=ConvertTo-TaraArgumentString $start.Arguments;$info.WorkingDirectory=$script:TaraRepositoryRoot;$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$process=[Diagnostics.Process]::Start($info);$stdoutTask=$process.StandardOutput.ReadToEndAsync();$stderrTask=$process.StandardError.ReadToEndAsync();$process.WaitForExit();$stdout=$stdoutTask.Result;$stderr=$stderrTask.Result;$exitCode=$process.ExitCode}catch{$errorText=$_.Exception.ToString();$stderr=if($stderr){$stderr+"`n"+$errorText}else{$errorText}}finally{$watch.Stop()}
    $finished=Get-RepatoUtc;New-Item -ItemType Directory -Path $script:TaraLogsRoot -Force|Out-Null;$logPath=Join-Path $script:TaraLogsRoot ($TaskId+'-'+$RunId+'.json')
    $artifacts=@();if($start.CommandId-ceq'build.release'){$dll=Join-Path $script:TaraRepositoryRoot 'bin\Release\net8.0-windows\Repato.Revit.dll';if(Test-Path -LiteralPath $dll){$artifacts+=[pscustomobject]@{Path=$dll;Sha256=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash}}}
    $record=[ordered]@{schemaVersion=1;taskId=$TaskId;runId=$RunId;commandId=$start.CommandId;commandSha256=$start.CommandSha256;executable=$start.Executable;arguments=$start.Arguments;startedUtc=$start.StartedUtc;finishedUtc=$finished;durationMilliseconds=$watch.Elapsed.TotalMilliseconds;exitCode=$exitCode;stdout=$stdout;stderr=$stderr;artifacts=$artifacts;errorDetails=$errorText};Write-RepatoJsonAtomic $logPath $record
    Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;$run=Find-TaraRun $task $RunId;if($run.status-cne'running'){throw 'Tara run state changed during execution.'};$run.status=$(if($exitCode-eq0){'passed'}else{'failed'});$run.finishedUtc=$finished;$run.durationMilliseconds=$watch.Elapsed.TotalMilliseconds;$run.exitCode=$exitCode;$run.stdout=$stdout;$run.stderr=$stderr;$run.logPath=$logPath;$run.artifactPaths=[object[]]@($artifacts|ForEach-Object Path);$run.errorDetails=$errorText;$task.logs=[object[]]@($task.logs)+$logPath;$task.reportPaths=[object[]]@($task.reportPaths)+[object[]]@($run.artifactPaths);if($exitCode-ne0){$task.status='failed';$task.finishedUtc=$finished;$task.errorDetails=if($errorText){$errorText}else{"Command exited $exitCode"}}elseif($task.workflowStage-ceq'qa'){$task.status='passed'};Add-RepatoHistory $task ('tara-'+$run.status) 'Tara' "run=$RunId; exit=$exitCode; log=$logPath";$run}
}

function Fail-TaraRun([string]$StoreRoot,[string]$TaskId,[string]$RunId,[string]$ErrorDetails,[switch]$DryRun){
    if([string]::IsNullOrWhiteSpace($ErrorDetails)){throw 'Failure details are required.'};Invoke-RepatoStoreMutation $StoreRoot {param($data,$preview)$task=Find-RepatoTask $data $TaskId;$run=Find-TaraRun $task $RunId;if($run.status-in@('passed','failed')){throw 'Tara run is terminal.'};if(!$preview){$run.status='failed';$run.finishedUtc=Get-RepatoUtc;$run.errorDetails=$ErrorDetails;$task.status='failed';$task.finishedUtc=$run.finishedUtc;$task.errorDetails=$ErrorDetails;Add-RepatoHistory $task 'tara-failed' 'Tara' "run=$RunId; $ErrorDetails"};$run} -DryRun:$DryRun
}

Export-ModuleMember -Function New-TaraPlan,Test-TaraPlan,Request-TaraApproval,Get-TaraPreview,Invoke-TaraRun,Fail-TaraRun,Get-TaraCommandCatalog
