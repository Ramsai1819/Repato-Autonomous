$ErrorActionPreference='Stop'
$p=Join-Path $PSScriptRoot '..\TestRunner\GridBubbleVisibilityTestCommand.cs'
if(!(Test-Path $p)){throw 'Runner source missing'}
if((Get-Content $p -Raw) -match 'GridBubbleVisibilityCommand.Execute'){throw 'Production command coupling detected'}
Write-Host '2 .NET QA policy checks passed'
$dll=Join-Path $PSScriptRoot '..\bin\Release\net8.0-windows\Repato.Revit.dll'
if(!(Test-Path $dll)){throw 'Built DLL missing'}
$source=Join-Path $PSScriptRoot '..\TestRunner\GridBubbleVisibilityTestCommand.cs'
if((Get-Content $source -Raw) -notmatch 'TestSafetyGate\.Verify\(d,r,"GridBubbleVisibilityEmpty"\)'){throw 'Source command fixture identity mismatch'}
if((Get-Item $dll).LastWriteTimeUtc -lt (Get-Item $source).LastWriteTimeUtc){throw 'Built DLL predates the command source'}
Write-Host 'compiled command artifact freshness and fixture identity check passed'
