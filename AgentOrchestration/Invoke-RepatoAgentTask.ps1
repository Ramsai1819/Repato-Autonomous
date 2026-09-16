[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('create','list','claim','update','attach-report','request-approval','approve','reject','complete')][string]$Operation,
    [string]$TaskId,[string]$Title,[string]$Description,[string]$Agent,[string]$Status,[string]$Stage,[string]$BranchName,
    [string]$LogPath,[string]$ReportPath,[string]$ErrorDetails,[ValidateSet('none','maya','user')][string]$ApprovalLevel='maya',
    [string]$ApprovalAction='completion',[string]$Reason,[string]$StoreRoot=(Join-Path $PSScriptRoot 'Store'),[switch]$DryRun
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.AgentOrchestration.psm1') -Force -WarningAction SilentlyContinue
if($Operation-cne'list' -and [string]::IsNullOrWhiteSpace($TaskId)){throw '-TaskId is required.'}
$result=switch($Operation){
 'create'{New-RepatoTask $StoreRoot $TaskId $Title $Description $BranchName $ApprovalLevel -DryRun:$DryRun}
 'list'{if(!(Test-Path (Join-Path $StoreRoot 'tasks.json'))){Initialize-RepatoTaskStore $StoreRoot -DryRun:$DryRun|Out-Null;if($DryRun){@()}else{Get-RepatoTasks $StoreRoot $TaskId}}else{Get-RepatoTasks $StoreRoot $TaskId}}
 'claim'{Claim-RepatoTask $StoreRoot $TaskId $Agent -DryRun:$DryRun}
 'update'{Update-RepatoTask $StoreRoot $TaskId $Status $Stage $Agent $LogPath $ErrorDetails -DryRun:$DryRun}
 'attach-report'{Add-RepatoTaskReport $StoreRoot $TaskId $ReportPath $(if($Agent){$Agent}else{'Tara'}) -DryRun:$DryRun}
 'request-approval'{Request-RepatoTaskApproval $StoreRoot $TaskId $ApprovalAction $ApprovalLevel -DryRun:$DryRun}
 'approve'{Resolve-RepatoTaskApproval $StoreRoot $TaskId approve $(if($Agent){$Agent}else{'Maya'}) $Reason -DryRun:$DryRun}
 'reject'{Resolve-RepatoTaskApproval $StoreRoot $TaskId reject $(if($Agent){$Agent}else{'Maya'}) $Reason -DryRun:$DryRun}
 'complete'{Complete-RepatoTask $StoreRoot $TaskId -DryRun:$DryRun}
}
$result|ConvertTo-Json -Depth 20
