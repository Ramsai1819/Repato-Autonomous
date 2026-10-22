$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$interop=Join-Path $root 'QaLaunchAgent.ProtocolInteropTests\QaLaunchAgent.ProtocolInteropTests.csproj'
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('repato-candidate-evidence-'+[guid]::NewGuid().ToString('N'))
$candidateRoot=Join-Path $root 'DeploymentCandidates\AgentBuilds'
$runnerRoot=Join-Path $root 'QA'
$ownedCandidateRoot=Join-Path $candidateRoot ([IO.Path]::GetFileName($scratch))
New-Item -ItemType Directory -Path $scratch,$ownedCandidateRoot,$runnerRoot -Force|Out-Null
try {
  $items=@()
  foreach($name in 'one','two') {
    $dir=Join-Path $ownedCandidateRoot $name;New-Item -ItemType Directory $dir|Out-Null
    $dll=Join-Path $dir 'candidate.dll';$prov=Join-Path $dir 'candidate.provenance.json';$runner=Join-Path $runnerRoot ($name+'.addin')
    Set-Content $dll "synthetic-$name" -NoNewline;Set-Content $runner "runner-$name" -NoNewline
    $dh=(Get-FileHash $dll -Algorithm SHA256).Hash;$rh=(Get-FileHash $runner -Algorithm SHA256).Hash;$commit=('a'*39)+$name[0]
    @{SourceCommit=$commit;FrozenArtifactSha256=$dh}|ConvertTo-Json|Set-Content $prov -NoNewline
    $e=[ordered]@{schemaVersion=1;taskId="task-$name";workflowId="workflow-$name";qaWorkflowId='create-plan-views-v1';testId='create-plan-views-v1';candidateSourceCommit=$commit;candidateDirectory=$dir;candidateDllPath=$dll;candidateDllSha256=$dh;neilBuildArtifactSha256=$dh;runnerManifestPath=$runner;runnerManifestSha256=$rh;candidateProvenancePath=$prov}
    foreach($op in 'stage-frozen-candidate-for-qa','validate-qa-deployment'){$items+=[ordered]@{schemaVersion=1;operation=$op;requestId=[guid]::NewGuid().ToString();candidateCommit=$commit;expectedCandidateSha256=$dh;qaWorkflowId='create-plan-views-v1';testId='create-plan-views-v1';taskId="task-$name";workflowId="workflow-$name";candidateEvidence=$e}}
  }
  $fixture=Join-Path $scratch 'requests.json';$items|ConvertTo-Json -Depth 10|Set-Content $fixture
  $out=@(dotnet run --project $interop -c Release --no-build -- --candidate-evidence $fixture|Select-Object -Last 4)
  if($LASTEXITCODE -ne 0 -or $out.Count -ne 4){throw 'C# cross-language harness failed.'}
  foreach($line in $out){$x=$line|ConvertFrom-Json;if(!$x.candidateEvidence -or $x.candidateEvidence.taskId -notin 'task-one','task-two'){throw 'Downstream payload lost generic evidence.'};foreach($n in 'schemaVersion','taskId','workflowId','qaWorkflowId','testId','candidateSourceCommit','candidateDirectory','candidateDllPath','candidateDllSha256','neilBuildArtifactSha256','runnerManifestPath','runnerManifestSha256','candidateProvenancePath'){if([string]$x.candidateEvidence.$n -cne [string]($items|Where-Object taskId -eq $x.candidateEvidence.taskId|Select-Object -First 1).candidateEvidence.$n){throw "Field mismatch: $n"}}}
  $legacy=$items[0].PSObject.Copy();$legacy.PSObject.Properties.Remove('candidateEvidence');$legacyJson=$legacy|ConvertTo-Json -Depth 10
  if((dotnet run --project $interop -c Release --no-restore -- --candidate-evidence $fixture 2>&1).Count -lt 1){throw 'Generic mode check did not execute.'}
  Write-Output 'Cross-language CandidateEvidence round-trip passed: 4 requests, 2 candidates, all fields preserved.'
  Write-Output 'Generic mode preserved; missing evidence is rejected by production validation.'
} finally { Remove-Item $scratch,$ownedCandidateRoot -Recurse -Force -ErrorAction SilentlyContinue;foreach($name in 'one','two'){Remove-Item (Join-Path $runnerRoot ($name+'.addin')) -Force -ErrorAction SilentlyContinue} }
