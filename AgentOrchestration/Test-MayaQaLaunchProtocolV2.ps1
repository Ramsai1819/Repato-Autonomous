$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$interop=Join-Path $root 'QaLaunchAgent.ProtocolInteropTests\QaLaunchAgent.ProtocolInteropTests.csproj'
dotnet build (Join-Path $root 'QaLaunchAgent\Repato.QaLaunchAgent.csproj') -c Release|Out-Null
dotnet run --project $interop -c Release
$source=Get-Content (Join-Path $root 'AgentOrchestration\Repato.MayaQaWorkflow.psm1') -Raw
foreach($mark in @('schemaVersion=2',"operation='launch-revit-qa'",'NamedPipeClientStream','Launch response correlation mismatch','Launch response is missing or oversized','Accepted launch identity is invalid','Launch response validation must run as RAMSAI\RepatoQA.','if($Launcher)')){if($source -notmatch [regex]::Escape($mark)){throw "Missing Maya v2 transport marker: $mark"}}
if($source -match 'Start-Process'){throw 'Production Maya module still contains direct Start-Process fallback.'}
'Maya v2/C# interoperability and no-fallback synthetic checks passed.'
