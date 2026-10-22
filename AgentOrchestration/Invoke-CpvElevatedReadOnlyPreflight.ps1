[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReleaseRoot,[Parameter(Mandatory)][string]$ManifestSha256,
    [ValidateSet('ps51','ps7','both')][string]$Engine='ps51')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $repo
$logs=Join-Path $repo 'QA\Engineering\CPV-Compatibility-20261019'
foreach($selectedEngine in $(if($Engine -ceq 'both'){@('ps51','ps7')}else{@($Engine)})){
$prefix=Join-Path $logs ('elevated-preflight-final-'+$selectedEngine)
$enginePath=if($selectedEngine -ceq 'ps51'){'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'}else{'C:\Program Files\PowerShell\7\pwsh.exe'}
try {
    & (Join-Path $PSScriptRoot 'Invoke-CpvEngineeringProcess.ps1') -Executable $enginePath -Arguments @('-NoProfile','-NonInteractive','-ExecutionPolicy','RemoteSigned','-File',(Join-Path $PSScriptRoot 'Test-CpvCompatibilityDeploymentPreflight.ps1'),'-ReleaseRoot',$ReleaseRoot,'-ManifestSha256',$ManifestSha256,'-EvidencePath',($prefix+'-protected-files.json')) -LogPrefix $prefix -TimeoutSeconds 7200|Out-Null
    [IO.File]::WriteAllText($prefix+'.complete','PASS')
} catch {
    [IO.File]::WriteAllText($prefix+'.complete',($_|Out-String))
    exit 1
}
}
