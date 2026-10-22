[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('Install','Rollback','Verify')][string]$Mode='Verify')
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'bin\Release\net8.0-windows'
$target='C:\Program Files\Repato\QaLaunchAgent'
$files=@('Repato.QaLaunchAgent.exe','Repato.QaLaunchAgent.dll','Repato.QaLaunchAgent.deps.json','Repato.QaLaunchAgent.runtimeconfig.json')
$hashes=@{
 'Repato.QaLaunchAgent.exe'='B4E4C9A454B6C8388213D30A19B0DEF426A66CBBFF4AF4F318821F202CB85FC7'
 'Repato.QaLaunchAgent.dll'='00F64F55D9B98D3F1D493C1746F47A4D21580C3BB2DB4DE54028B6AF93F7EE02'
 'Repato.QaLaunchAgent.deps.json'='757B9F8505AF05922257064161085B07679ACAEC797C42188216553F45FA81B8'
 'Repato.QaLaunchAgent.runtimeconfig.json'='CA1A6B5B185174698E0F5F9AE732AD3D2D3ED5B122ED666F35CC214283E83B7F'
}
if($Mode -eq 'Verify') { foreach($f in $files){$p=Join-Path $source $f;if(!(Test-Path $p)){throw "Missing artifact: $p"};if((Get-FileHash $p -Algorithm SHA256).Hash -cne $hashes[$f]){throw "Source hash mismatch: $f"}}; 'Gate C artifacts verified'; return }
$principal=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Install/Rollback requires an elevated administrator PowerShell.'}
if($Mode -eq 'Install') {
    if(!$PSCmdlet.ShouldProcess($target,'Install Gate C agent artifacts')){return}
    if(Get-Process -Name Repato.QaLaunchAgent -ErrorAction SilentlyContinue){throw 'Refusing replacement while agent is running.'}
    if(Get-ChildItem '\\.\pipe\' -ErrorAction SilentlyContinue | Where-Object Name -like '*Repato*QaLaunch*'){throw 'Refusing replacement while QA pipe is active.'}
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    foreach($f in $files){Copy-Item (Join-Path $source $f) (Join-Path $target $f) -Force}
    $acl=Get-Acl $target; $acl.SetAccessRuleProtection($true,$false)
    foreach($rule in @(
        (New-Object Security.AccessControl.FileSystemAccessRule('SYSTEM','FullControl','ContainerInherit,ObjectInherit','None','Allow')),
        (New-Object Security.AccessControl.FileSystemAccessRule('Administrators','FullControl','ContainerInherit,ObjectInherit','None','Allow')),
        (New-Object Security.AccessControl.FileSystemAccessRule('RepatoQA','ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')))){$acl.AddAccessRule($rule)}
    Set-Acl $target $acl
    foreach($f in $files){$p=Join-Path $target $f;if((Get-FileHash $p -Algorithm SHA256).Hash -cne $hashes[$f]){throw "Installed hash mismatch: $f"}}
    'Gate C artifacts installed and verified; agent not started; startup not registered.'
}
if($Mode -eq 'Rollback') {
    if(!$PSCmdlet.ShouldProcess($target,'Remove Gate C agent artifacts')){return}
    if(Test-Path $target){Remove-Item $target -Recurse -Force}
    'Gate C installation directory removed; no Store, QA, AgentWork, or add-in paths touched.'
}
