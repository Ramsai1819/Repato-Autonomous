$ErrorActionPreference='Stop';Import-Module (Join-Path $PSScriptRoot 'Repato.MayaQaWorkflow.psm1') -Force
$root=Join-Path ([IO.Path]::GetTempPath()) ('maya-source-'+[guid]::NewGuid().ToString('N'));New-Item $root -ItemType Directory|Out-Null
$passed=0;function Check([bool]$ok,[string]$name){if(!$ok){throw "FAILED: $name"};$script:passed++};function Reject([scriptblock]$x){try{&$x|Out-Null;return $false}catch{return $true}}
try{
  Push-Location $root;git init -q;git config user.email test@test;git config user.name test;Set-Content app.cs 'class App {}';Set-Content Test.csproj '<Project Sdk="Microsoft.NET.Sdk" />';git add .;git commit -qm initial;Pop-Location
  $commit=Get-MayaQaTrustedBuildSourceCommit $root (Join-Path $root 'Test.csproj');Check ($commit -match '^[0-9a-f]{40}$') 'trusted HEAD resolved'
  Set-Content (Join-Path $root 'unrelated.txt') x;Check ((Get-MayaQaTrustedBuildSourceCommit $root (Join-Path $root 'Test.csproj')) -ceq $commit) 'unrelated dirty file allowed'
  Set-Content (Join-Path $root 'dirty.cs') 'class Dirty {}';Check (Reject {Get-MayaQaTrustedBuildSourceCommit $root (Join-Path $root 'Test.csproj')}) 'dirty build input rejected'
  Remove-Item (Join-Path $root 'dirty.cs');Set-Content (Join-Path $root 'app.cs') 'class Changed {}';Check (Reject {Get-MayaQaTrustedBuildSourceCommit $root (Join-Path $root 'Test.csproj')}) 'tracked build input rejected'
  Check (Reject {Get-MayaQaTrustedBuildSourceCommit (Join-Path $root 'missing') (Join-Path $root 'Test.csproj')}) 'genuine git failure rejected'
  Check ((Get-MayaQaTrustedBuildSourceCommit (Split-Path $PSScriptRoot -Parent) (Join-Path (Split-Path $PSScriptRoot -Parent) 'Forma.RevitConnector.csproj')) -match '^[0-9a-f]{40}$') 'known unrelated permission warning handled safely'
  [pscustomobject]@{Status='PASS';AssertionsPassed=$passed;AssertionsFailed=0;SourceCommit=$commit}|ConvertTo-Json -Compress
}finally{Pop-Location -ErrorAction SilentlyContinue;Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue}
