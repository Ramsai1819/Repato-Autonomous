[CmdletBinding()]
param()
$ErrorActionPreference='Stop'

$path=Join-Path $PSScriptRoot 'Install-CpvPreparationAgentCandidate.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw "Installer source does not parse: $($errors[0].Message)"}
$definition=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-CpvRevitProcesses'},$true)
if(!$definition){throw 'Installer is missing Get-CpvRevitProcesses.'}
. ([scriptblock]::Create($definition.Extent.Text))

$script:mode='Absent'
function Get-Process {
    param([string]$Name,[string]$ErrorAction)
    switch($script:mode){
        'Absent' { $record=[Management.Automation.ErrorRecord]::new([InvalidOperationException]::new('No process found'), 'NoProcessFoundForGivenName,Microsoft.PowerShell.Commands.GetProcessCommand', [Management.Automation.ErrorCategory]::ObjectNotFound, $Name); throw $record }
        'Running' { [pscustomobject]@{ProcessName='Revit';Id=42} }
        'Failure' { $record=[Management.Automation.ErrorRecord]::new([UnauthorizedAccessException]::new('Enumeration denied'), 'ProcessEnumerationDenied', [Management.Automation.ErrorCategory]::PermissionDenied, $Name); throw $record }
    }
}

if(@(Get-CpvRevitProcesses).Count -ne 0){throw 'Absent Revit process was not accepted.'}
$script:mode='Running'
if(@(Get-CpvRevitProcesses).Count -ne 1){throw 'Running Revit process was not detected.'}
$script:mode='Failure';$failedClosed=$false
try { Get-CpvRevitProcesses | Out-Null } catch { $failedClosed=$true }
if(!$failedClosed){throw 'Genuine process enumeration failure did not fail closed.'}
'PASS: Revit absent accepted; running detected; enumeration failure rejected.'
