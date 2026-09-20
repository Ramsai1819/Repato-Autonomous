$ErrorActionPreference = 'Stop'
$application = Get-Content (Join-Path $PSScriptRoot '..\FormaApplication.cs') -Raw
$command = Get-Content (Join-Path $PSScriptRoot '..\CreateLevelsCommand.cs') -Raw
if ($application -notmatch 'RepatoCreateLevels' -or $application -notmatch 'Repato\.Revit\.CreateLevelsCommand' -or $application -notmatch 'panel\.AddItem\(createLevelsButton\)') { throw 'Create Levels is not registered in the production ribbon.' }
if ($command -notmatch 'public sealed class CreateLevelsCommand' -or $command -notmatch 'namespace Repato\.Revit') { throw 'CreateLevelsCommand type or namespace is invalid.' }
if ($application -match 'TestRunner|CreateLevelsTestCommand') { throw 'QA-only command leaked into production ribbon.' }
if ((Get-Content (Join-Path $PSScriptRoot '..\Repato.addin') -Raw) -notmatch 'RepatoApplication') { throw 'Production add-in structure changed.' }
'Production ribbon registration checks passed: 4'
