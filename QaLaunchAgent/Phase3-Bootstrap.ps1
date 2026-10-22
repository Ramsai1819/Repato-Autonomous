[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('Show','Install','Verify','Uninstall')][string]$Mode='Show',[string]$SourceRoot=(Join-Path $PSScriptRoot 'bin\Release\net8.0-windows'),[string]$ManifestPath=(Join-Path $PSScriptRoot 'Repato.QaLaunchAgent.release.json'),[string]$ManifestSha256)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.QaLaunchAgent.Bootstrap.psm1') -Force
switch($Mode){
 'Show' { Get-RepatoQaLaunchAgentBootstrapContract }
 'Install' { if(!$ManifestSha256){throw 'Install requires the independently reviewed -ManifestSha256.'}; Install-RepatoQaLaunchAgentBootstrap -SourceRoot $SourceRoot -ManifestPath $ManifestPath -ManifestSha256 $ManifestSha256 -WhatIf:$WhatIfPreference }
 'Verify' { if(!$ManifestSha256){throw 'Verify requires the independently reviewed -ManifestSha256.'}; Test-RepatoQaLaunchAgentBootstrap -ManifestPath $ManifestPath -ManifestSha256 $ManifestSha256 }
 'Uninstall' { Uninstall-RepatoQaLaunchAgentBootstrap -WhatIf:$WhatIfPreference }
}
