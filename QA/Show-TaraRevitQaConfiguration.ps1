[CmdletBinding()]
param(
    [string]$QaProfileRoot = 'C:\Users\RepatoQA',
    [string]$RevitInstallDir = 'E:\revit\Revit 2025'
)

$ErrorActionPreference = 'Stop'
# Read-only: this prints configuration, not a readiness or authorization receipt.
$qaRoot = 'C:\Repato-Autonomous\Source\QA'
$registrationRoot = Join-Path $QaProfileRoot 'AppData\Roaming\Autodesk\Revit\Addins\2025'
[ordered]@{
    RequiredWindowsAccount = 'RepatoQA'
    RequiredSession = 'Interactive desktop; logged in and unlocked'
    QaProfileRoot = [IO.Path]::GetFullPath($QaProfileRoot)
    RevitInstallDir = [IO.Path]::GetFullPath($RevitInstallDir)
    RevitExecutable = Join-Path ([IO.Path]::GetFullPath($RevitInstallDir)) 'Revit.exe'
    RevitExecutableExists = Test-Path -LiteralPath (Join-Path $RevitInstallDir 'Revit.exe') -PathType Leaf
    NativeQaRoot = $qaRoot
    FixtureRoot = Join-Path $qaRoot 'Fixtures'
    TestRunsRoot = Join-Path $qaRoot 'TestRuns'
    ReportDirectory = Join-Path $qaRoot 'Reports'
    ScreenshotRoot = Join-Path $qaRoot 'Screenshots'
    QaRegistrationRoot = $registrationRoot
    QaAddinRoot = Join-Path $registrationRoot 'RepatoQA'
    ExpectedDllPath = Join-Path $registrationRoot 'RepatoQA\Repato.Revit.dll'
    MachineRegistrationRoot = 'C:\ProgramData\Autodesk\Revit\Addins\2025'
    AllowlistPath = Join-Path $qaRoot 'MachineWideAddins.allowlist.json'
    RunnerManifests = @('Repato.CreateLevels.TestRunner.addin', 'Repato.GridBubbleVisibility.TestRunner.addin', 'Repato.GridBubbleOffset.TestRunner.addin', 'Repato.GridResequence.TestRunner.addin')
    SupportedQaWorkflowIds = @('create-levels', 'grid-bubble-visibility-v1', 'grid-bubble-offset-v1', 'grid-resequence-v1')
    SuggestedTimeoutSeconds = 900
    ScheduledTaskLogonType = 'InteractiveToken (Run only when user is logged on)'
    ScheduledTaskProgram = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    PerRunValuesFromMaya = @('StoreRoot', 'TaskId', 'WorkflowId', 'QaWorkflowId', 'RunId', 'ModelPath', 'SidecarPath')
    RequiredRealRunSwitch = '-IntegrationTest'
    SideEffectsPerformed = $false
} | ConvertTo-Json -Depth 5
