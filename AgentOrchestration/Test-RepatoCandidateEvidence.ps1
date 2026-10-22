$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.CandidateEvidence.psm1') -Force
$root=Join-Path ([IO.Path]::GetTempPath()) ('repato-evidence-'+[guid]::NewGuid().ToString('N'));$candidates=Join-Path $root 'candidates';$runnerRoot=Join-Path $root 'runners';New-Item $candidates,$runnerRoot -ItemType Directory -Force|Out-Null
$passed=0;function Check([bool]$ok,[string]$name){if(!$ok){throw "FAILED: $name"};$script:passed++};function Reject([scriptblock]$x,[string]$name){$bad=$false;try{&$x|Out-Null}catch{$bad=$true};Check $bad $name}
try{
  foreach($suffix in 'one','two'){
    $dir=Join-Path $candidates "ReleaseCandidate-$suffix";$null=New-Item $dir -ItemType Directory
    $dll=Join-Path $dir 'Repato.Revit.dll';[IO.File]::WriteAllText($dll,"dll-$suffix");$runner=Join-Path $runnerRoot "runner-$suffix.addin";[IO.File]::WriteAllText($runner,"runner-$suffix")
    $dh=(Get-FileHash $dll).Hash;$rh=(Get-FileHash $runner).Hash;$commit=if($suffix -eq 'one'){('a'*40)}else{('b'*40)};$prov=Join-Path $dir 'release-manifest.json';@{SourceCommit=$commit;FrozenArtifactSha256=$dh}|ConvertTo-Json|Set-Content $prov
    $e=New-RepatoCandidateEvidence 'task' 'workflow' 'qa' 'qa' $commit $dir $dll $dh $dh $runner $rh $prov
    $a=New-RepatoCandidateEvidence 'task' 'workflow' 'qa' 'qa' $commit $dir $dll $dh $dh $runner $rh $prov
    $v=Resolve-RepatoCandidateEvidence $e $a $candidates $runnerRoot 'task' 'workflow' 'qa' 'qa';Check ($v.CandidateDllSha256 -ceq $dh) "valid $suffix evidence accepted";if($suffix -eq 'two'){$second=$true}
  }
  $valid=$e;$auth=$a
  foreach($n in 'TaskId','WorkflowId','QaWorkflowId','TestId'){ $x=$valid.PSObject.Copy();$x.$n='wrong';Reject {Resolve-RepatoCandidateEvidence $x $auth $candidates $runnerRoot 'task' 'workflow' 'qa' 'qa'} "$n mismatch rejected" }
  foreach($n in 'CandidateDllSha256','NeilBuildArtifactSha256','RunnerManifestSha256'){ $x=$valid.PSObject.Copy();$x.$n='0'*64;Reject {Resolve-RepatoCandidateEvidence $x $auth $candidates $runnerRoot 'task' 'workflow' 'qa' 'qa'} "$n mismatch rejected" }
  $x=$valid.PSObject.Copy();$x.CandidateDirectory=Join-Path $root 'escape';Reject {Resolve-RepatoCandidateEvidence $x $auth $candidates $runnerRoot 'task' 'workflow' 'qa' 'qa'} 'candidate root escape rejected'
  $x=$valid.PSObject.Copy();$x.CandidateDllPath=Join-Path $root 'escape.dll';Reject {Resolve-RepatoCandidateEvidence $x $auth $candidates $runnerRoot 'task' 'workflow' 'qa' 'qa'} 'DLL escape rejected'
  $x=$valid.PSObject.Copy();$x.RunnerManifestPath=Join-Path $root 'escape.addin';Reject {Resolve-RepatoCandidateEvidence $x $auth $candidates $runnerRoot 'task' 'workflow' 'qa' 'qa'} 'runner escape rejected'
  $x=$valid.PSObject.Copy();$x.CandidateDllSha256='bad';Reject {Resolve-RepatoCandidateEvidence $x $auth $candidates $runnerRoot 'task' 'workflow' 'qa' 'qa'} 'malformed hash rejected'
  $x=$valid.PSObject.Copy();$x.CandidateSourceCommit='b'*40;Reject {Resolve-RepatoCandidateEvidence $x $auth $candidates $runnerRoot 'task' 'workflow' 'qa' 'qa'} 'provenance mismatch rejected'
  $json=ConvertTo-RepatoCandidateEvidenceJson $valid;Check ((ConvertFrom-RepatoCandidateEvidenceJson $json).SchemaVersion -eq 1) 'JSON round trip accepted'
  [pscustomobject]@{Status='PASS';AssertionsPassed=$passed;AssertionsFailed=0}|ConvertTo-Json -Compress
}finally{Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue}
