$ErrorActionPreference = 'Stop'
$command = Get-Content (Join-Path $PSScriptRoot '..\CreateLevelsCommand.cs') -Raw
$creator = Get-Content (Join-Path $PSScriptRoot '..\LevelCreator.cs') -Raw
if ($command -notmatch 'AcceptsReturn\s*=\s*true' -or $command -notmatch 'AcceptsTab\s*=\s*true' -or $command -notmatch 'WpfTextBox') { throw 'Create Levels textbox does not accept tabs.' }
if ($creator -notmatch "Split\('\\t',\s*2" -or $creator -notmatch "Split\('\|',\s*2") { throw 'Create Levels parser separators are incorrect.' }
foreach ($sample in @("BASEMENT -1`t-1000", "Level 1`t3600", "Level 2`t-250")) { $parts=$sample.Split("`t",2); if($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])){throw "Input rejected: $sample"}; [double]$value=0; if(-not [double]::TryParse($parts[1],[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$value)){throw "Elevation rejected: $sample"} }
if ($creator -notmatch 'Use one level per line') { throw 'User-friendly invalid input message missing.' }
'Create Levels input checks passed: 5'
