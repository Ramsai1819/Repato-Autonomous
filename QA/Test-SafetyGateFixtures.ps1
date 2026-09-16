$ErrorActionPreference='Stop'; $c=Get-Content (Join-Path $PSScriptRoot '..\TestRunner\TestSafetyGate.cs') -Raw
if($c -notmatch 'grids.Count != 0'){throw 'Empty fixture strict policy missing'}
if($c -notmatch 'Grid Bubble fixture must contain exactly grids A, B, C, D, 1, 2, 3, 4'){throw 'Grid Bubble exact policy missing'}
if($c -notmatch 'RevitLinkType'){throw 'Link rejection missing'}
Write-Host '3 fixture safety policy checks passed'
