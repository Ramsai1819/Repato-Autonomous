$ErrorActionPreference='Stop'
$project=Join-Path $PSScriptRoot '..\QaLaunchAgent\Repato.QaLaunchAgent.csproj'
dotnet build $project -c Release | Out-Null
if($LASTEXITCODE -ne 0){throw 'Protocol v2 build failed.'}
$required=@('LaunchSchemaVersion = 2','QaLaunchResponseV2','CorrelationId','child.Sid','request.Operation','request.TaskId','request.AttemptId')
$source=(Get-ChildItem (Join-Path $PSScriptRoot '..\QaLaunchAgent') -Filter '*.cs'|ForEach-Object {Get-Content $_.FullName -Raw}) -join "`n"
foreach($mark in $required){if($source -notmatch [regex]::Escape($mark)){throw "Missing protocol v2 marker: $mark"}}
foreach($mark in @('!string.IsNullOrWhiteSpace(r.TaskId)','!string.IsNullOrWhiteSpace(r.AttemptId)','IsSha256(r.RequestSha256)','result.Sid.Equals(options.ExpectedUserSid, StringComparison.OrdinalIgnoreCase)','ClientAccount = ExpectedUser','ClientSid = ExpectedUserSid','new SecurityIdentifier(options.ClientSid)')){if($source -notmatch [regex]::Escape($mark)){throw "Missing fail-closed validation marker: $mark"}}
'RepatoQA launch protocol v2 synthetic checks passed: explicit schema, operation, SID, correlation, canonical identity response'
