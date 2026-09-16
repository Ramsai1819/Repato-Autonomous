$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Foundation\QaRunner.Foundation.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('QaFoundation-'+[guid]::NewGuid().ToString('N'));$runs=Join-Path $root 'runs';New-Item -ItemType Directory $runs|Out-Null
$fixture=Join-Path $root 'fixture.rvt';[IO.File]::WriteAllText($fixture,'fixture')
$hash=Get-RepatoQaSha256 $fixture;$provenance=Join-Path $root 'fixture.json'
@{fixtureId='Fixture';sourceSha256=$hash;requiredGridNames=@('A','1')}|ConvertTo-Json|Set-Content $provenance
$identity=Read-RepatoQaFixtureProvenance $fixture $provenance 'Fixture' @('1','A')
$run=New-RepatoQaRun $runs 'tool' 'tool.request.json' 'test-v1' $fixture $identity ('A'*64) ([pscustomobject]@{Allowed=$true;DetectedAddins=[object[]]@();Errors=[object[]]@()}) 30
if(!(Test-Path $run.ModelPath)-or!(Test-Path $run.RequestPath)-or(Get-RepatoQaSha256 $run.ModelPath)-ne$hash){throw 'Disposable run creation failed'}
$request=Get-Content $run.RequestPath -Raw|ConvertFrom-Json
if($request.requestId-cne$run.RequestId-or$request.testId-cne'test-v1'-or[DateTimeOffset]::Parse($request.expiresUtc)-lt[DateTimeOffset]::UtcNow.AddMinutes(19)){throw 'Fresh request contract failed'}
$blocked=$false;try{Assert-RepatoQaChildPath (Join-Path $runs '..\escape') $runs|Out-Null}catch{$blocked=$true};if(!$blocked){throw 'Path escape accepted'}
$evidence=Join-Path $root 'evidence.json';Write-RepatoQaDiagnostic $evidence 'Run' 'test-v1' 'Failed' @{error='preserved'}
$blocked=$false;try{Write-RepatoQaDiagnostic $evidence 'Run' 'test-v1' 'Failed' @{} }catch{$blocked=$true};if(!$blocked){throw 'Evidence overwrite accepted'}
$staleDir=Join-Path $runs 'stale';New-Item -ItemType Directory $staleDir|Out-Null
@{requestId='old';expiresUtc=[DateTimeOffset]::UtcNow.AddMinutes(-1).ToString('O')}|ConvertTo-Json|Set-Content (Join-Path $staleDir 'tool.request.json')
if(@(Find-RepatoQaStaleRequests $runs 'tool.request.json').Count-ne 1-or!(Test-Path (Join-Path $staleDir 'tool.request.json'))){throw 'Stale request was not preserved'}
$waitSource=(Get-Command Wait-RepatoQaResult).ScriptBlock.ToString();if($waitSource-match 'Kill\(|Stop-Process|taskkill'){throw 'Automatic process kill detected'}
Write-Host '8 shared QA foundation checks passed'
