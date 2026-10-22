[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$RequestId,
    [Parameter(Mandatory)][ValidatePattern('^task-[0-9a-f]{32}$')][string]$TaskId
)
$ErrorActionPreference='Stop'
if($RequestId -cne '9953e14c15524fe09440d1c7d7353950' -or $TaskId -cne 'task-bf61fe7f22d74df7a92599681da5919e'){
    throw 'This recovery command is restricted to the reviewed CPV failed-preparation request.'
}
Import-Module (Join-Path $PSScriptRoot '../QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1') -Force -WarningAction SilentlyContinue
Recover-RepatoQaLaunchAgentBootstrapInstall -RequestId $RequestId -TaskId $TaskId | ConvertTo-Json -Depth 8
