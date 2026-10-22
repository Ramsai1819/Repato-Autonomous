[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Repato.QaLaunchAgentInstall.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('cpv-bootstrap-resolution-'+[guid]::NewGuid().ToString('N'))
$one=Join-Path $temp 'one';$two=Join-Path $temp 'two';New-Item -ItemType Directory -Path $one,$two -Force|Out-Null
$expectedOne=Join-Path $one 'Repato.QaLaunchAgent.Bootstrap.psm1'
$expectedTwo=Join-Path $two 'Repato.QaLaunchAgent.Bootstrap.psm1'
$wrongPath=Join-Path $one 'Wrong.Bootstrap.psm1'
[IO.File]::WriteAllText($expectedOne,'function Get-TestBootstrapMarker { "one" }')
[IO.File]::WriteAllText($expectedTwo,'function Get-TestBootstrapMarker { "two" }')
[IO.File]::WriteAllText($wrongPath,'function Get-TestBootstrapMarker { "wrong" }')
$assertions=0
function Check([bool]$Condition,[string]$Name){$script:assertions++;if(!$Condition){throw "FAILED: $Name"}}
function Reject([scriptblock]$Action,[string]$Name){$script:assertions++;try{&$Action;throw 'Unexpected acceptance'}catch{if($_.Exception.Message -eq 'Unexpected acceptance'){throw};if($_.Exception.Message -notmatch 'trusted Launch Agent bootstrap module'){throw}}}
try {
    $single=Resolve-RepatoQaLaunchAgentBootstrapModule -ModulePath $expectedOne
    Check ($single.Name -ceq 'Repato.QaLaunchAgent.Bootstrap' -and [IO.Path]::GetFullPath($single.Path) -ieq [IO.Path]::GetFullPath($expectedOne)) 'single trusted module resolves by exact path'
    $duplicate=Import-Module -Name $expectedTwo -Force -PassThru -ErrorAction Stop
    $sameName=@(Get-Module -Name 'Repato.QaLaunchAgent.Bootstrap')
    Check ($sameName.Count -ge 2) 'test establishes duplicate same-name module instances'
    $resolvedAmongDuplicates=Resolve-RepatoQaLaunchAgentBootstrapModule -ModulePath $expectedOne
    Check ([IO.Path]::GetFullPath($resolvedAmongDuplicates.Path) -ieq [IO.Path]::GetFullPath($expectedOne)) 'trusted path resolves correctly while duplicate names are loaded'
    Reject {Resolve-RepatoQaLaunchAgentBootstrapModule -ModulePath $expectedOne -ImportProvider {param($path) @($single,$duplicate)}} 'duplicate module results rejected'
    $wrong=Import-Module -Name $wrongPath -Force -PassThru -ErrorAction Stop
    Reject {Resolve-RepatoQaLaunchAgentBootstrapModule -ModulePath $expectedOne -ImportProvider {param($path) $wrong}} 'wrong module identity rejected'
    Reject {Resolve-RepatoQaLaunchAgentBootstrapModule -ModulePath $expectedOne -ImportProvider {param($path) $null}} 'missing module rejected'

    $installer=Get-Content (Join-Path $PSScriptRoot 'Install-CpvPreparationAgentCandidate.ps1') -Raw
    Check (!$installer.Contains('Get-Module Repato.QaLaunchAgent.Bootstrap') -and !$installer.Contains('(Get-Module Repato.QaLaunchAgent.Bootstrap)')) 'guarded install and recovery contain no name-based module lookup'
    Check ($installer.Contains('& $bootstrap {param($lease,$context) Invoke-InstallJournalRecoveryCore') -and $installer.Contains('-BootstrapModule $bootstrap')) 'rollback and task-stop paths use the validated module instance'
    $resolveAt=$installer.IndexOf('$bootstrap=Resolve-RepatoQaLaunchAgentBootstrapModule')
    $preflightAt=$installer.IndexOf('$priorTaskEvidence=Get-RepatoQaLaunchAgentTaskEvidence -BootstrapModule $bootstrap')
    $journalAt=$installer.IndexOf('New-RepatoQaLaunchAgentBootstrapInstallJournal')
    $stopAt=$installer.IndexOf('Stop-RepatoQaLaunchAgentForUpdate -ExpectedAgentPid $agents[0].Id')
    $installAt=$installer.IndexOf('Install-RepatoQaLaunchAgentBootstrap -SourceRoot')
    Check ($resolveAt -ge 0 -and $preflightAt -gt $resolveAt -and $journalAt -gt $preflightAt -and $stopAt -gt $journalAt -and $installAt -gt $stopAt) 'actual guarded control-flow order keeps module/preflight checks before journal, stop, and replacement'
    'PASS: '+$assertions+' bootstrap module-resolution assertions; installer operations invoked=false; Revit launched=false.'
} finally {
    Remove-Module -Name 'Wrong.Bootstrap' -Force -ErrorAction SilentlyContinue
    Get-Module -Name 'Repato.QaLaunchAgent.Bootstrap'|Where-Object {$_.Path -like ($temp+'*')}|Remove-Module -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
