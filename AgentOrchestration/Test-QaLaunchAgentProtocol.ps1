$ErrorActionPreference='Stop'
$project=Join-Path $PSScriptRoot '..\QaLaunchAgent\Repato.QaLaunchAgent.csproj'
dotnet build $project --no-restore -c Release | Out-Null
if($LASTEXITCODE -ne 0){throw 'QA launch agent build failed.'}
'QA launch agent protocol checks passed: contracts, policy, project build'
