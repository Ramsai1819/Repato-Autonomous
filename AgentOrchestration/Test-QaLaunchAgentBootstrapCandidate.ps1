$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$module=Import-Module (Join-Path $repo 'QaLaunchAgent\Repato.QaLaunchAgent.Bootstrap.psm1') -Force -PassThru
$candidate=Join-Path $repo 'DeploymentCandidates\AgentReleases\Repato.QaLaunchAgent-1.0.0+48cdcde'
$manifest=Join-Path $candidate 'Repato.QaLaunchAgent.release.json'
$manifestHash=(Get-FileHash $manifest -Algorithm SHA256).Hash
$validated=& $module {param($s,$m,$h) Read-ValidatedManifest $s $m $h} $candidate $manifest $manifestHash
$state=[pscustomobject]@{Task=$null;OldXml=$null;FailSet=$false}
$context=[pscustomobject]@{
  IsAdministrator={};ResolveIdentity={param($a,$s)};PrepareAcl={param($p)}
  GetTask={ $state.Task };ExportTask={param($t) if($t){'old-task-xml'}}
  SetTask={param($spec) if($state.FailSet){throw 'synthetic task failure'};$state.Task=$spec}
  RestoreTask={param($xml) if($xml){$state.Task=[pscustomobject]@{Restored=$true}}else{$state.Task=$null}}
  RemoveTask={$state.Task=$null}
}
$notRunning={ $null }
$running={ [pscustomobject]@{Id=15340;ProcessName='Repato.QaLaunchAgent'} }
$temp=Join-Path ([IO.Path]::GetTempPath()) ('repato-bootstrap-candidate-'+[guid]::NewGuid().ToString('N'))
try {
  $one=& $module {param($v,$c,$t,$p) Invoke-InstallCore $v $c $t -AllowTestRoot -ProcessDetector $p} $validated $context (Join-Path $temp 'install') $notRunning
  if(!$one.Installed){throw 'valid candidate install failed'}
  $two=& $module {param($v,$c,$t,$p) Invoke-InstallCore $v $c $t -AllowTestRoot -ProcessDetector $p} $validated $context (Join-Path $temp 'install') $notRunning
  if(!$two.Installed -or !$two.Updated){throw 'candidate idempotency failed'}
  $state.FailSet=$true
  $rejected=$false;try{& $module {param($v,$c,$t,$p) Invoke-InstallCore $v $c $t -AllowTestRoot -ProcessDetector $p} $validated $context (Join-Path $temp 'install') $notRunning|Out-Null}catch{$rejected=$true}
  if(!$rejected){throw 'synthetic rollback failure was accepted'}
  $guarded=$false;try{& $module {param($v,$c,$t,$p) Invoke-InstallCore $v $c $t -AllowTestRoot -ProcessDetector $p} $validated $context (Join-Path $temp 'running') $running|Out-Null}catch{$guarded=$true}
  if(!$guarded){throw 'synthetic running-agent guard was bypassed'}
  [pscustomobject]@{Test='QaLaunchAgentBootstrapCandidate';CandidateManifestSha256=$manifestHash;SyntheticNotRunning='PASS';SyntheticRunning='PASS';Rollback='PASS'}|ConvertTo-Json -Compress
} finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
