$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force -WarningAction SilentlyContinue
$primary=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'));$approved='C:\Repato-Autonomous\Worktrees';$name='contract-'+[guid]::NewGuid().ToString('N');$worktree=Join-Path $approved $name;$commit=(& git -C $primary rev-parse HEAD).Trim();$passed=0
function Check([bool]$ok,[string]$name){if(!$ok){throw "FAILED: $name"};$script:passed++}
function Reject([scriptblock]$action,[string]$name){$ok=$false;try{&$action|Out-Null}catch{$ok=$true};Check $ok $name}
try{
  New-Item -ItemType Directory -Path $approved -Force|Out-Null
  & git -C $primary worktree add --detach $worktree $commit|Out-Null
  $source=[pscustomobject]@{RepositoryRoot=$worktree;ExpectedSourceCommit=$commit;ProjectRelativePath='Forma.RevitConnector.csproj'}
  $resolved=Resolve-MayaQaAuthenticatedBuildSource $source
  Check ($resolved.RepositoryRoot -ieq $worktree) 'approved worktree accepted'
  Check ($resolved.ExpectedSourceCommit -ceq $commit) 'HEAD-derived commit returned'
  Check ($resolved.ProjectPath -ieq (Join-Path $worktree 'Forma.RevitConnector.csproj')) 'project contained in worktree'
  Check ((Get-MayaQaTrustedBuildSourceCommit $resolved.RepositoryRoot $resolved.ProjectPath) -ceq $commit) 'trusted cleanliness and HEAD binding'
  $primaryResolved=Resolve-MayaQaAuthenticatedBuildSource $null;Check ($primaryResolved.RepositoryRoot -ieq $primary) 'primary behavior preserved'
  Reject {Resolve-MayaQaAuthenticatedBuildSource ([pscustomobject]@{RepositoryRoot=(Join-Path ([IO.Path]::GetTempPath()) 'outside');ExpectedSourceCommit=$commit;ProjectRelativePath='Forma.RevitConnector.csproj'})} 'external root rejected'
  $other=Join-Path ([IO.Path]::GetTempPath()) ('other-'+[guid]::NewGuid().ToString('N'));New-Item $other -ItemType Directory|Out-Null;& git -C $other init -q; & git -C $other config user.email test@test; & git -C $other config user.name test;Set-Content (Join-Path $other 'Forma.RevitConnector.csproj') '<Project />';& git -C $other add .;& git -C $other commit -qm init
  Reject {Resolve-MayaQaAuthenticatedBuildSource ([pscustomobject]@{RepositoryRoot=$other;ExpectedSourceCommit=$commit;ProjectRelativePath='Forma.RevitConnector.csproj'})} 'other repository rejected'
  Reject {Resolve-MayaQaAuthenticatedBuildSource ([pscustomobject]@{RepositoryRoot=$worktree;ExpectedSourceCommit=('0'*40);ProjectRelativePath='Forma.RevitConnector.csproj'})} 'HEAD mismatch rejected'
  Reject {Resolve-MayaQaAuthenticatedBuildSource ([pscustomobject]@{RepositoryRoot=$worktree;ExpectedSourceCommit='not-a-sha';ProjectRelativePath='Forma.RevitConnector.csproj'})} 'invalid commit rejected'
  Set-Content (Join-Path $worktree 'dirty.cs') 'class Dirty {}';Reject {Resolve-MayaQaAuthenticatedBuildSource $source;Get-MayaQaTrustedBuildSourceCommit $worktree (Join-Path $worktree 'Forma.RevitConnector.csproj')} 'dirty input rejected';Remove-Item (Join-Path $worktree 'dirty.cs') -Force
  Reject {Resolve-MayaQaAuthenticatedBuildSource ([pscustomobject]@{RepositoryRoot=$worktree;ExpectedSourceCommit=$commit;ProjectRelativePath='..\Forma.RevitConnector.csproj'})} 'project traversal rejected'
  Reject {Resolve-MayaQaAuthenticatedBuildSource ([pscustomobject]@{RepositoryRoot=$worktree;ExpectedSourceCommit=$commit;ProjectRelativePath='C:\external\Forma.RevitConnector.csproj'})} 'absolute project path rejected'
  [pscustomobject]@{Status='PASS';AssertionsPassed=$passed;AssertionsFailed=0;PrimaryCommit=$commit;WorktreeCreatedForSyntheticTest=$true;BuildPerformed=$false}|ConvertTo-Json -Compress
}finally{
  if(Test-Path -LiteralPath $worktree){& git -C $primary worktree remove --force $worktree 2>$null|Out-Null}
  if($other -and (Test-Path $other)){Remove-Item $other -Recurse -Force -ErrorAction SilentlyContinue}
}
