$ErrorActionPreference='Stop'
$checks=@(
 'Test-CreateGridsCompatibility.ps1','Test-CreateLevelsWorkflow.ps1',
 'Test-GridBubbleVisibility.ps1','Test-GridBubbleVisibilityWorkflow.ps1',
 'Test-GridBubbleOffset.ps1','Test-GridBubbleOffsetWorkflow.ps1','Test-GridBubbleOffsetStartup.ps1',
 'Test-GridResequence.ps1','Test-GridResequenceWorkflow.ps1','Test-GridResequenceStartup.ps1','Test-GridResequenceReportSchema.ps1'
)
foreach($check in $checks){& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $check)|Out-Host;if($LASTEXITCODE-ne 0){throw "$check failed"}}
Write-Host "Five-runner compatibility suite passed ($($checks.Count) component checks)."
