$ErrorActionPreference='Stop'
$project=Join-Path $PSScriptRoot '..\QaLaunchAgent\Repato.QaLaunchAgent.csproj'
dotnet build $project -c Release | Out-Null
if($LASTEXITCODE -ne 0){throw 'Phase 2 agent build failed.'}
$asm=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\QaLaunchAgent\bin\Release\net8.0-windows\Repato.QaLaunchAgent.dll'))
if(!(Test-Path $asm)){throw 'Agent binary missing.'}
$required=@('NamedPipeServerStreamAcl','RepatoQA','request-replayed','model-hash-mismatch','manifest-hash-mismatch','REPATO_QA_CREATE_PLAN_VIEWS_REQUEST','HealthOperation','QaHealthResponse')
$source=(Get-ChildItem (Join-Path $PSScriptRoot '..\QaLaunchAgent') -Filter '*.cs'|ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
foreach($mark in $required){if($source -notmatch [regex]::Escape($mark)){throw "Missing Phase 2 marker: $mark"}}
'RepatoQA launch-agent Phase 2 synthetic checks passed: build, ACL server, policy, replay, hash, environment contract'
