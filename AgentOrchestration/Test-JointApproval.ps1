$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot 'Repato.JointApproval.psm1') -Force
if(-not (Get-Command Validate-JointApproval -ErrorAction SilentlyContinue)){throw 'Joint contract not exported'}
$src=Get-Content (Join-Path $PSScriptRoot 'Repato.JointApproval.psm1') -Raw
foreach($name in 'taskId','supervisorExecutionId','adapterId','operationId','taskRevision','planSha256','adapterRegistrySha256','commandSha256','expiresUtc','nonce'){if($src -notmatch $name){throw "Missing approval binding: $name"}}
if($src -notmatch 'Real joint process execution is disabled'){throw 'Dry-run safety gate missing'}
'Joint approval contract checks passed.'
