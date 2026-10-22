param([string]$SourceRoot=(Join-Path (Split-Path $PSScriptRoot -Parent) 'QaLaunchAgent\bin\Release\net8.0-windows'),[string]$ManifestPath=(Join-Path (Split-Path $PSScriptRoot -Parent) 'QaLaunchAgent\Repato.QaLaunchAgent.release.json'))
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$module=Import-Module (Join-Path $repo 'QaLaunchAgent\Repato.QaLaunchAgent.Bootstrap.psm1') -Force -PassThru
$source=$SourceRoot
$manifest=$ManifestPath
$manifestHash=(Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
$passed=0
function Pass([bool]$condition,[string]$name){if(!$condition){throw "FAILED: $name"};$script:passed++}
function Reject([scriptblock]$body,[string]$name){$rejected=$false;try{& $body|Out-Null}catch{$rejected=$true};Pass $rejected $name}

$validated=& $module {param($s,$m,$h) Read-ValidatedManifest $s $m $h} $source $manifest $manifestHash
Pass ([bool]$validated) 'valid provenance'
Reject {& $module {param($s,$m,$h) Read-ValidatedManifest $s $m ('0'*64)} $source $manifest $manifestHash} 'source manifest hash mismatch rejected'
Reject {Install-RepatoQaLaunchAgentBootstrap -SourceRoot $source -ManifestPath $manifest -ManifestSha256 $manifestHash -Account 'RAMSAI\rsgud'} 'wrong account rejected'
Reject {Install-RepatoQaLaunchAgentBootstrap -SourceRoot $source -ManifestPath $manifest -ManifestSha256 $manifestHash -ExpectedSid 'S-1-5-18'} 'wrong SID rejected'

$temp=Join-Path ([IO.Path]::GetTempPath()) ('repato-bootstrap-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
try {
  $partial=Join-Path $temp 'partial';New-Item -ItemType Directory $partial|Out-Null
  Copy-Item -LiteralPath (Join-Path $source 'Repato.QaLaunchAgent.exe') -Destination $partial
  Reject {& $module {param($s,$m,$h) Read-ValidatedManifest $s $m $h} $partial $manifest $manifestHash} 'partial runtime rejected'
  $bad=Join-Path $temp 'bad';Copy-Item -LiteralPath $source -Destination $bad -Recurse
  Add-Content -LiteralPath (Join-Path $bad 'Repato.QaLaunchAgent.dll') -Value 'tamper'
  Reject {& $module {param($s,$m,$h) Read-ValidatedManifest $s $m $h} $bad $manifest $manifestHash} 'source hash mismatch rejected'
  $versionManifest=Join-Path $temp 'wrong-version.json'
  $versionJson=(Get-Content -LiteralPath $manifest -Raw).Replace([string]$validated.Manifest.productVersion,'9.9.9+wrong')
  Set-Content -LiteralPath $versionManifest -Value $versionJson -NoNewline
  $versionHash=(Get-FileHash -LiteralPath $versionManifest -Algorithm SHA256).Hash
  Reject {& $module {param($s,$m,$h) Read-ValidatedManifest $s $m $h} $source $versionManifest $versionHash} 'mismatched executable DLL release identity rejected'

  $state=[pscustomobject]@{Task=$null;OldXml=$null;FailSet=$false}
  $newContext={param($state)
    [pscustomobject]@{
      IsAdministrator={};ResolveIdentity={param($a,$s)};PrepareAcl={param($p)}
      GetTask={ $state.Task };ExportTask={param($t) if($t){'old-task-xml'}}
      SetTask={param($spec) if($state.FailSet){throw 'synthetic task failure'};$state.Task=$spec}
      RestoreTask={param($xml) if($xml){$state.Task=[pscustomobject]@{Restored=$true}}else{$state.Task=$null}}
      RemoveTask={$state.Task=$null}
    }
  }
  $target=Join-Path $temp 'install'
  $ctx=& $newContext $state
  $one=& $module {param($v,$c,$t) Invoke-InstallCore $v $c $t -AllowTestRoot -ProcessDetector { @() }} $validated $ctx $target
  Pass ($one.Installed -and -not $one.Updated) 'valid fresh install'
  Pass ((Get-FileHash (Join-Path $target 'Repato.QaLaunchAgent.dll') -Algorithm SHA256).Hash -eq $validated.Manifest.files[1].sha256) 'installed runtime integrity'
  $two=& $module {param($v,$c,$t) Invoke-InstallCore $v $c $t -AllowTestRoot -ProcessDetector { @() }} $validated $ctx $target
  Pass ($two.Installed -and $two.Updated) 'idempotent upgrade'
  $state.Task=[pscustomobject]@{Wrong=$true}
  $three=& $module {param($v,$c,$t) Invoke-InstallCore $v $c $t -AllowTestRoot -ProcessDetector { @() }} $validated $ctx $target
  Pass ($three.Task.Principal -eq 'RAMSAI\RepatoQA' -and $three.Task.Arguments -eq '') 'wrong or duplicate task reconciled'
  Set-Content -LiteralPath (Join-Path $target 'marker.txt') -Value 'previous'
  $state.FailSet=$true
  Reject {& $module {param($v,$c,$t) Invoke-InstallCore $v $c $t -AllowTestRoot -ProcessDetector { @() }} $validated $ctx $target} 'failed upgrade rejected'
  Pass (Test-Path (Join-Path $target 'marker.txt')) 'failed upgrade restored previous install'
  Pass ([bool]$state.Task.Restored) 'failed upgrade restored previous task'
  $state.FailSet=$false
  $spec=& $module {New-TaskSpec}
  Pass ($spec.TriggerType -eq 'Logon' -and $spec.TriggerUser -eq 'RAMSAI\RepatoQA') 'RepatoQA-only logon trigger'
  Pass ($spec.Execute -eq 'C:\Program Files\Repato\QaLaunchAgent\Repato.QaLaunchAgent.exe' -and $spec.Arguments -eq '') 'fixed executable and no arguments'
  Pass ($spec.LogonType -eq 'Interactive' -and $spec.RunLevel -eq 'Limited') 'interactive least-privilege principal'
  foreach($mutation in @(
    @{Principal='SYSTEM'},@{TriggerUser='RAMSAI\rsgud'},@{Execute='C:\Temp\agent.exe'},@{Arguments='--anything'},@{TaskName='duplicate'})){
      $copy=$spec|Select-Object *;foreach($k in $mutation.Keys){$copy.$k=$mutation[$k]};Pass (-not (& $module {param($x) Test-TaskSpec $x} $copy)) ('invalid task rejected: '+($mutation.Keys -join ','))
  }
  $uninstallContext=& $newContext $state;& $uninstallContext.RemoveTask;Pass (-not $state.Task) 'uninstall task behavior'
  Reject {& $module {param($v,$c,$t) Invoke-InstallCore $v $c $t} $validated $ctx (Join-Path $temp 'untrusted')} 'untrusted target rejected'
  $nonAdmin=& $newContext $state;$nonAdmin.IsAdministrator={throw 'not elevated'}
  Reject {& $module {param($v,$c,$t) Invoke-InstallCore $v $c $t -AllowTestRoot} $validated $nonAdmin (Join-Path $temp 'nonadmin')} 'non-admin rejected'
} finally {Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
[pscustomobject]@{Test='QaLaunchAgentBootstrap';Passed=$passed;Failed=0;ManifestSha256=$manifestHash}|ConvertTo-Json -Compress
