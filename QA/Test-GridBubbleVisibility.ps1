$ErrorActionPreference='Stop'
$c=Get-Content (Join-Path $PSScriptRoot '..\TestRunner\GridBubbleVisibilityTestCommand.cs') -Raw
@('grid-bubble-visibility-v1','ShowBubbleInView','HideBubbleInView','RollbackStatus','selected-','unselected-','rollback-status') | ForEach-Object { if($c -notmatch [regex]::Escape($_)){throw "Missing $_"} }
if($c -notmatch 'GridBubbleVisibilityEmpty'){throw 'Fixture policy not requested'}
Write-Host '8 Grid Bubble Visibility static checks passed'
