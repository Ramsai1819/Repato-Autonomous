$ErrorActionPreference='Stop'
$helperPath=Join-Path $PSScriptRoot 'Repato.QaLaunchAgentInstall.ps1'
. $helperPath
$script:assertions=0
function Assert([bool]$Value,[string]$Message){$script:assertions++;if(!$Value){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$script:assertions++;$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};if(!$failed){throw $Message}}

$script:timestamp=[datetime]::Now
$script:processId=42
$script:process=[pscustomobject]@{Id=42;ProcessName='Repato.QaLaunchAgent';Path='C:\Program Files\Repato\QaLaunchAgent\Repato.QaLaunchAgent.exe';StartTime=$script:timestamp;SessionId=4;Handle=[IntPtr]::Zero}
$script:cim=[pscustomobject]@{ProcessId=42;ExecutablePath=$script:process.Path;SessionId=4;CreationDate=$script:timestamp}
$script:owner=[pscustomobject]@{ReturnValue=0;Domain='RAMSAI';User='RepatoQA'}
function Get-Process {param([int]$Id,[string]$ErrorAction)if($Id -ne $script:processId){return $null};$script:process}
function Get-CimInstance {param([string]$ClassName,[string]$Filter,[string]$ErrorAction)if($script:ambiguous){@($script:cim,$script:cim)}else{@($script:cim)}}
function Invoke-CimMethod {param($InputObject,[string]$MethodName,[string]$ErrorAction)$script:owner}

$typed=ConvertFrom-RepatoCimProcessStartTime $script:timestamp
Assert ($typed -ceq $script:timestamp) 'Typed DateTime was altered.'
$dmtf=[Management.ManagementDateTimeConverter]::ToDmtfDateTime($script:timestamp)
$parsed=ConvertFrom-RepatoCimProcessStartTime $dmtf
Assert ([Math]::Abs(($parsed-$script:timestamp).TotalMilliseconds) -lt 1) 'Valid DMTF timestamp did not round-trip.'
Reject {ConvertFrom-RepatoCimProcessStartTime 'not-a-dmtf-timestamp'} 'Malformed DMTF timestamp was accepted.'
Reject {ConvertFrom-RepatoCimProcessStartTime '20261340123456.123456+000'} 'Invalid calendar DMTF timestamp was accepted.'
Reject {ConvertFrom-RepatoCimProcessStartTime $null} 'Null timestamp was accepted.'
Reject {ConvertFrom-RepatoCimProcessStartTime ([pscustomobject]@{Ticks=1})} 'Unsupported timestamp type was accepted.'

$identity=Get-RepatoQaLaunchAgentProcessIdentity -ProcessId 42
Assert ($identity.ProcessId -eq 42 -and $identity.OwnerSid -ceq 'S-1-5-21-1031246752-3872016183-2454652381-1015' -and $identity.SessionId -eq 4) 'Valid process identity fields were not preserved.'
$script:cim.CreationDate=$dmtf
$identity=Get-RepatoQaLaunchAgentProcessIdentity -ProcessId 42
Assert ($identity.ProcessId -eq 42) 'Valid DMTF timestamp failed through process identity lookup.'
$script:cim.CreationDate='invalid';Reject {Get-RepatoQaLaunchAgentProcessIdentity -ProcessId 42} 'Invalid process timestamp was accepted.'
$script:cim.CreationDate=$null;Reject {Get-RepatoQaLaunchAgentProcessIdentity -ProcessId 42} 'Null process timestamp was accepted.'

$script:cim.CreationDate=$script:timestamp;$script:cim.ProcessId=43;Reject {Get-RepatoQaLaunchAgentProcessIdentity -ProcessId 42} 'Mismatched CIM process ID was accepted.';$script:cim.ProcessId=42
$script:ambiguous=$true;Reject {Get-RepatoQaLaunchAgentProcessIdentity -ProcessId 42} 'Ambiguous CIM process identity was accepted.';$script:ambiguous=$false
$script:cim.ExecutablePath='C:\Other\Repato.QaLaunchAgent.exe';Reject {Get-RepatoQaLaunchAgentProcessIdentity -ProcessId 42} 'Mismatched executable path was accepted.';$script:cim.ExecutablePath=$script:process.Path
$script:cim.SessionId=9;Reject {Get-RepatoQaLaunchAgentProcessIdentity -ProcessId 42} 'Mismatched process session was accepted.';$script:cim.SessionId=4
$script:process.StartTime=$script:timestamp.AddSeconds(1);Reject {Get-RepatoQaLaunchAgentProcessIdentity -ProcessId 42} 'Mismatched process start time was accepted.'
'PASS: '+$script:assertions+' isolated process identity timestamp assertions; live process/task/revit untouched.'
