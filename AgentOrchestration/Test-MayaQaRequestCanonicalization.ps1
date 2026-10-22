$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$source=Join-Path $root 'QA\TestRuns\68a8807dded747b58dcd0f51d75496cb-retry\maya-tara-68a8807dded747b58dcd0f51d75496cb.request.json'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('repato-request-'+[guid]::NewGuid().ToString('N')+'.json')
$obj=Get-Content $source -Raw|ConvertFrom-Json;$obj.requestSha256='0'*64
Import-Module (Join-Path $root 'AgentOrchestration\Repato.MayaQaWorkflow.psm1') -Force
$module=Get-Module Repato.MayaQaWorkflow
$mayaHash=&$module {param($x) Get-MayaQaCanonicalRequestSha256 $x} $obj
$canonical=&$module {param($x) ConvertTo-MayaQaCanonicalRequestJson $x} $obj
[IO.File]::WriteAllText($temp,$canonical,[Text.UTF8Encoding]::new($false))
$csharpHash=(dotnet run --project (Join-Path $root 'QaLaunchAgent.ProtocolInteropTests\QaLaunchAgent.ProtocolInteropTests.csproj') -c Release --no-restore -- $temp | Select-Object -Last 1).Trim()
if($mayaHash -cne $csharpHash){throw "Canonical hash mismatch: Maya=$mayaHash Agent=$csharpHash"}
$tampered=$obj.PSObject.Copy();$tampered.taskId='tampered';$tamperedHash=&$module {param($x) Get-MayaQaCanonicalRequestSha256 $x} $tampered;if($tamperedHash -ceq $mayaHash){throw 'Integrity-bound tampering was accepted.'}
$reordered=[ordered]@{};foreach($p in @($obj.PSObject.Properties|Sort-Object Name -Descending)){$reordered[$p.Name]=$p.Value};$reorderedHash=&$module {param($x) Get-MayaQaCanonicalRequestSha256 $x} ([pscustomobject]$reordered);if($reorderedHash -cne $mayaHash){throw 'Property order changed the canonical hash.'}
Remove-Item -LiteralPath $temp -Force
"Request canonicalization regression passed: Maya=$mayaHash; Agent=$csharpHash"
