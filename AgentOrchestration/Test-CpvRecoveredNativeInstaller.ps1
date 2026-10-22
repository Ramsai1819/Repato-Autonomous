[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:assertions=0
function Check($Value,[string]$Message){if(!$Value){throw $Message};$script:assertions++}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action}catch{$failed=$true};Check $failed $Message}
$bootstrap=Import-Module (Join-Path $PSScriptRoot '../QaLaunchAgent/Repato.QaLaunchAgent.Bootstrap.psm1') -Force -PassThru
$candidate='1.0.23+'+('a'*40);$prior='1.0.22+6119aceaab0a34c3e0323089a29f1cefb2c14aaa';$request='c11b311638a54bfc9ebdd1803671ec40'
& $bootstrap {param($v,$p,$r)Assert-CpvRecoveredNativeJournalTransition $v $p $r} $candidate $prior $request
Check $true 'Exact recovered-native transition accepted.'
Reject {& $bootstrap {param($v,$p,$r)Assert-CpvRecoveredNativeJournalTransition $v $p $r} $candidate '1.0.21+3dd4a4bb9b51c040bd8997f403bc1dbd27ff188f' $request} 'Wrong prior must reject.'
Reject {& $bootstrap {param($v,$p,$r)Assert-CpvRecoveredNativeJournalTransition $v $p $r} $candidate $prior '9953e14c15524fe09440d1c7d7353950'} 'Wrong request must reject.'
Reject {& $bootstrap {param($p,$r)Assert-CpvRecoveredNativeJournalTransition '1.0.23+bad' $p $r} $prior $request} 'Malformed candidate must reject.'
Reject {& $bootstrap {param($p,$r)Assert-CpvRecoveredNativeJournalTransition ('1.0.21+'+('a'*40)) $p $r} $prior $request} 'Pinned 1.0.22 prior cannot enter a legacy downgrade transition.'
# Execute actual core only through its explicit-mode precondition. No fixture or production writes are reachable.
$context=[pscustomobject]@{IsAdministrator={};ResolveIdentity={}}
$validated=[pscustomobject]@{Manifest=[pscustomobject]@{productVersion=$candidate}}
$identity=[pscustomobject]@{RequestId=$request;TaskId='task-bf61fe7f22d74df7a92599681da5919e'}
Reject {& $bootstrap {param($v,$c,$i)New-InstallJournalCore $v $c ([IO.Path]::GetTempPath()) $i -AllowTestRoot} $validated $context $identity} '1.0.23 journal creation without explicit mode rejects before mutation.'
$identity|Add-Member RecoveredNativeContinuation $false
Reject {& $bootstrap {param($v,$c,$i)New-InstallJournalCore $v $c ([IO.Path]::GetTempPath()) $i -AllowTestRoot} $validated $context $identity} 'False recovered-native mode rejects before mutation.'
Reject {& $bootstrap {param($v,$c)Invoke-InstallCore $v $c ([IO.Path]::GetTempPath()) -AllowTestRoot -ProcessDetector { @() }} $validated $context} 'Generic 1.0.23 installation without durable guarded journal rejects before mutation.'
$path=Join-Path $PSScriptRoot 'Install-CpvPreparationAgentCandidate.ps1'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
Check (@($errors).Count -eq 0) 'Installer syntax is valid.'
$names=@($ast.ParamBlock.Parameters|ForEach-Object{$_.Name.VariablePath.UserPath})
Check ('RecoveredNativeContinuation' -in $names) 'Installer exposes explicit continuation mode.'
$commands=@($ast.FindAll({param($a)$a -is [Management.Automation.Language.CommandAst]},$true))
$guard=@($commands|Where-Object {$_.GetCommandName() -ceq 'Assert-CpvRecoveredNativeUpgrade'})
Check ($guard.Count -eq 1) 'Exactly one guard call.'
$stops=@($commands|Where-Object {$_.GetCommandName() -ceq 'Stop-RepatoQaLaunchAgentForUpdate'})
Check ($guard[0].Extent.StartOffset -lt $stops[0].Extent.StartOffset) 'Guard precedes any service stop.'
$source=[IO.File]::ReadAllText($path)
Check ($source.Contains('if((Test-Path -LiteralPath $activePath) -or $RecoveredNativeContinuation)')) 'Recovered transition can validate absent marker.'
Check ($source.Contains('-RecoveryReceipt $recoveredReceipt')) 'Guard receives authenticated recovered status.'
Check ($source.Contains('-RecoveredNativeContinuation:$RecoveredNativeContinuation')) 'Journal receives explicit mode.'
Check ($source.Contains("if((`$requestedVersion -match '^1\.0\.23\+') -ne [bool]`$RecoveredNativeContinuation)")) 'Candidate and explicit recovered-native mode are inseparable before active marker selection.'
$preflight=$source.IndexOf('if($PreflightOnly)')
$stop=$source.IndexOf('Stop-RepatoQaLaunchAgentForUpdate')
Check ($preflight -gt 0 -and $preflight -lt $stop) 'Read-only preflight returns before installation boundary.'
Write-Output "PASS: $script:assertions recovered-native installer assertions."
