$ErrorActionPreference='Stop';$repo=Split-Path $PSScriptRoot -Parent;$script=Join-Path $PSScriptRoot 'New-QaLaunchAgentRelease.ps1';$commit=(git -C $repo rev-parse HEAD);$tmp=Join-Path ([IO.Path]::GetTempPath()) ('agent-release-'+[guid]::NewGuid().ToString('N'))
function Reject($block){$ok=$false;try{&$block|Out-Null}catch{$ok=$true};if(!$ok){throw 'Expected packaging rejection.'}}
try{
 $source=Join-Path $tmp 'source';$releases=Join-Path $tmp 'releases';New-Item $source,$releases -ItemType Directory|Out-Null
 Copy-Item (Join-Path $repo 'QaLaunchAgent\bin\Release\net8.0-windows\Repato.QaLaunchAgent.*') $source
 $result=& $script -SourceRoot $source -ReleaseRoot $releases -SourceCommit $commit
 if(!(Test-Path $result.ManifestPath) -or (Get-FileHash $result.ManifestPath -Algorithm SHA256).Hash -cne $result.ManifestSha256){throw 'Packaged manifest validation failed.'}
 Reject {&$script -SourceRoot $source -ReleaseRoot $releases -SourceCommit $commit}
 $missing=Join-Path $tmp 'missing';Copy-Item $source $missing -Recurse;Remove-Item (Join-Path $missing 'Repato.QaLaunchAgent.deps.json');Reject {&$script -SourceRoot $missing -ReleaseRoot (Join-Path $tmp 'other') -SourceCommit $commit}
 'QA Launch Agent release packaging checks passed: success, bootstrap/hash validation, existing destination, missing file'
}finally{Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue}
