$ErrorActionPreference='Stop';$s=Get-Content (Join-Path $PSScriptRoot '..\TestRunner\GridBubbleOffsetQaApplication.cs') -Raw;$c=Get-Content (Join-Path $PSScriptRoot 'Invoke-GridBubbleOffsetQA.ps1') -Raw
if($s -notmatch 'REPATO_QA_GRID_BUBBLE_OFFSET_REQUEST' -or $c -notmatch 'REPATO_QA_GRID_BUBBLE_OFFSET_REQUEST'){throw 'Startup environment contract mismatch'}
if($s -notmatch 'add-in startup reached|request path detected|command execution started|result path written' -or $c -notmatch 'Revit process launch requested'){throw 'Startup diagnostics missing'}
Write-Host '5 Grid Bubble Offset startup contract checks passed'
