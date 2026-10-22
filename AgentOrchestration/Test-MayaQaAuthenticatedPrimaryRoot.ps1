$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
$module=Get-Module Repato.MayaQaWorkflow
$expectedRoot=[IO.Path]::GetFullPath('C:\Repato-Autonomous\Source\QA')
$expectedRuns=[IO.Path]::GetFullPath('C:\Repato-Autonomous\Source\QA\TestRuns')
$actual=& $module { [pscustomobject]@{QaRoot=Get-MayaQaRoot;RuntimeRoot=Get-MayaQaRuntimeRoot} }
if([IO.Path]::GetFullPath($actual.QaRoot) -ine $expectedRoot -or [IO.Path]::GetFullPath($actual.RuntimeRoot) -ine $expectedRuns){
    throw 'Maya QA fixture and runtime roots must resolve to the authenticated primary Source repository from an isolated worktree.'
}
if(!(Test-Path -LiteralPath (Join-Path $actual.QaRoot 'Fixtures\CreatePlanViewsEmpty.rvt') -PathType Leaf)){
    throw 'Authenticated primary QA root does not contain the trusted Create Plan Views fixture.'
}
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$head=(& git -C $sourceRoot rev-parse HEAD).Trim()
$historicalCommit=(& git -C $sourceRoot rev-parse 'HEAD~1').Trim()
if($LASTEXITCODE -ne 0 -or $historicalCommit -notmatch '^[0-9a-fA-F]{40}$'){
    throw 'Authenticated source repository does not expose the historical commit test fixture.'
}
$source=[pscustomobject]@{RepositoryRoot=$sourceRoot;ExpectedSourceCommit=$historicalCommit;ProjectRelativePath='Forma.RevitConnector.csproj'}
$strictRejected=$false
try{& $module {param($value) Resolve-MayaQaAuthenticatedBuildSource $value} $source|Out-Null}catch{if($_.Exception.Message -match 'HEAD does not match'){$strictRejected=$true}else{throw}}
$historical=& $module {param($value) Resolve-MayaQaAuthenticatedBuildSource $value -AllowHistoricalCommit} $source
$missing=$false
$badSource=[pscustomobject]@{RepositoryRoot=$sourceRoot;ExpectedSourceCommit=('a'*40);ProjectRelativePath='Forma.RevitConnector.csproj'}
try{& $module {param($value) Resolve-MayaQaAuthenticatedBuildSource $value -AllowHistoricalCommit} $badSource|Out-Null}catch{if($_.Exception.Message -match 'commit is not present'){$missing=$true}else{throw}}
if(!$strictRejected -or $historical.ExpectedSourceCommit -cne $historicalCommit -or !$historical.Isolated -or !$missing){
    throw 'Historical frozen-candidate source validation did not preserve strict build-head validation.'
}
[pscustomobject]@{Status='PASS';QaRoot=$actual.QaRoot;RuntimeRoot=$actual.RuntimeRoot;FixturePresent=$true}|ConvertTo-Json -Compress
