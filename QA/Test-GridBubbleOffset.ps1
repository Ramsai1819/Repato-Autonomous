$ErrorActionPreference='Stop';$c=Get-Content (Join-Path $PSScriptRoot '..\TestRunner\GridBubbleOffsetTestCommand.cs') -Raw
@('grid-bubble-offset-v1','SelectedGridCount','UnselectedGridPolicy','rollback','GridBubbleOffsetEmpty')|%{if($c -notmatch [regex]::Escape($_)){throw "Missing $_"}}
Write-Host '5 Grid Bubble Offset static checks passed'
