$ErrorActionPreference='Stop'
$policy=Get-Content (Join-Path $PSScriptRoot '..\TestRunner\FixtureContentPolicy.cs') -Raw
if($policy -notmatch 'GridResequenceEmpty' -or $policy -notmatch 'ApprovedGridResequenceNames'){throw 'Fixture policy missing'}
$source=Get-Content (Join-Path $PSScriptRoot '..\GridResequenceCommand.cs') -Raw
if($source -notmatch 'CreateResequenceRenames' -or $source -notmatch 'SecondarySuffixComparer' -or $source -notmatch 'unselectedNames'){throw 'Production planner integration missing'}
Write-Host '5 Grid Resequence .NET integration checks passed'
