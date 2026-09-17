$ErrorActionPreference='Stop'
foreach($f in 'Invoke-RepatoNeilAdapter.ps1','Invoke-RepatoTaraAdapter.ps1'){$s=Get-Content (Join-Path $PSScriptRoot $f) -Raw;if($s -notmatch 'JointApprovalId' -or $s -notmatch 'Validate-JointApproval'){throw "$f missing joint validation"}}
$s=Get-Content (Join-Path $PSScriptRoot 'Repato.JointApproval.psm1') -Raw;foreach($x in 'supervisorExecutionId','adapterPlanSha256','adapterRegistrySha256','commandSha256','nonce'){if($s -notmatch $x){throw "contract missing $x"}}
'Joint adapter nonce wiring checks passed.'
