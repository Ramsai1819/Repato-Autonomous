$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
$module=Get-Module Repato.MayaQaWorkflow
$now=[DateTimeOffset]::UtcNow
$none=@(& $module {param($items) @(Get-MayaQaActiveCanonicalExecutionApprovals -Approvals $items)} @())
$expired=@(& $module {param($items) @(Get-MayaQaActiveCanonicalExecutionApprovals -Approvals $items)} @([pscustomobject]@{action='qa-run';status='approved';consumedUtc=$null;expiresUtc=$now.AddMinutes(-1).ToString('O')}))
$pending=@(& $module {param($items) @(Get-MayaQaActiveCanonicalExecutionApprovals -Approvals $items)} @([pscustomobject]@{action='qa-run';status='pending';consumedUtc=$null;expiresUtc=$now.AddMinutes(5).ToString('O')}))
$consumed=@(& $module {param($items) @(Get-MayaQaActiveCanonicalExecutionApprovals -Approvals $items)} @([pscustomobject]@{action='qa-run';status='approved';consumedUtc=$now.ToString('O');expiresUtc=$now.AddMinutes(5).ToString('O')}))
$noneBlocks=& $module {param($items) Test-MayaQaHasActiveCanonicalExecutionApproval -Approvals $items} @()
$expiredBlocks=& $module {param($items) Test-MayaQaHasActiveCanonicalExecutionApproval -Approvals $items} @([pscustomobject]@{action='qa-run';status='approved';consumedUtc=$null;expiresUtc=$now.AddMinutes(-1).ToString('O')})
$pendingBlocks=& $module {param($items) Test-MayaQaHasActiveCanonicalExecutionApproval -Approvals $items} @([pscustomobject]@{action='qa-run';status='pending';consumedUtc=$null;expiresUtc=$now.AddMinutes(5).ToString('O')})
$invalidRejected=$false
try{& $module {param($items) @(Get-MayaQaActiveCanonicalExecutionApprovals -Approvals $items)} @([pscustomobject]@{action='qa-run';status='pending';consumedUtc=$null;expiresUtc='invalid'})|Out-Null}catch{if($_.Exception.Message -match 'invalid expiry'){$invalidRejected=$true}else{throw}}
if($none.Count -ne 0 -or $expired.Count -ne 0 -or $pending.Count -ne 1 -or $consumed.Count -ne 0 -or $noneBlocks -or $expiredBlocks -or !$pendingBlocks -or !$invalidRejected){
    throw "Canonical active-approval classification failed: none=$($none.Count); expired=$($expired.Count); pending=$($pending.Count); consumed=$($consumed.Count); noneBlocks=$noneBlocks; expiredBlocks=$expiredBlocks; pendingBlocks=$pendingBlocks; invalidRejected=$invalidRejected."
}
[pscustomobject]@{Status='PASS';Assertions=8;ExpiredUnconsumedNotActive=$true;PendingBlocks=$true;ConsumedDoesNotBlock=$true;EmptyListSafe=$true;ExpiredListSafe=$true;InvalidExpiryRejected=$true}|ConvertTo-Json -Compress
