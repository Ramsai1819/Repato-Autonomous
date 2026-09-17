$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.Deployment.psm1') -Force
$dir=Join-Path $PSScriptRoot 'DeploymentFixtures'
$files='artifact.target','manifest.target'
$snap=@{};foreach($f in $files){$snap[$f]=[IO.File]::ReadAllBytes((Join-Path $dir $f))}
$pass=0
$m=New-DeployPlan '' TEST (Join-Path $dir 'artifact.source') (Join-Path $dir 'manifest.source') 'qa-local-fixture'
$m | Add-Member NoteProperty approvalStatus 'approved'
$m | Add-Member NoteProperty consumed $false
$b=Invoke-Deploy $m deploy-backup
if($b.ArtifactHash -ne (Get-FileHash (Join-Path $dir 'artifact.target.backup') -Algorithm SHA256).Hash){throw 'backup hash'}else{$pass++}
Invoke-Deploy $m deploy-apply|Out-Null
if(-not (Invoke-Deploy $m deploy-verify).Verified){throw 'verify'}else{$pass++}
if(-not (Invoke-Deploy $m deploy-rollback).RolledBack){throw 'rollback'}else{$pass++}
if(-not (Invoke-Deploy $m deploy-rollback).Idempotent){throw 'idempotent'}else{$pass++}
$dry=Invoke-Deploy $m deploy-apply -DryRun;if($dry.SideEffectsPerformed){throw 'dry run'}else{$pass++}
try{$m.targetId='revit';Invoke-Deploy $m deploy-apply;throw 'unexpected target accepted'}catch{$pass++}
try{$m.targetId='qa-local-fixture';$m.approvalStatus='expired';Invoke-Deploy $m deploy-apply;throw 'expired accepted'}catch{$pass++}
try{$m.approvalStatus='approved';$m.consumed=$true;Invoke-Deploy $m deploy-apply;throw 'replay accepted'}catch{$pass++}
try{$m.targetId='..\outside';Invoke-Deploy $m deploy-apply;throw 'path accepted'}catch{$pass++}
'Deployment executor checks passed: ' + $pass
