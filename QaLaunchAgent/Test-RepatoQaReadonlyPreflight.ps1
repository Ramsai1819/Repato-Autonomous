$ErrorActionPreference = 'Stop'
$source = Get-Content (Join-Path $PSScriptRoot 'LaunchCoordinator.cs') -Raw
$protocol = Get-Content (Join-Path $PSScriptRoot 'Protocol.cs') -Raw
$server = Get-Content (Join-Path $PSScriptRoot 'NamedPipeServer.cs') -Raw
if ($protocol -notmatch 'PreflightOperation = "preflight-readonly"') { throw 'Preflight operation is not fixed.' }
if ($source -notmatch 'FileStream\(path, FileMode\.Open, FileAccess\.Read') { throw 'Read-only file open is missing.' }
if ($source -notmatch 'UnauthorizedAccessException') { throw 'Access-denied classification is missing.' }
if ($source -match 'QaPreflightRequest.*Path|HandlePreflight\([^)]*path') { throw 'Preflight accepts an arbitrary path.' }
if ($server -notmatch 'operation == QaLaunchPolicy\.PreflightOperation') { throw 'Pipe route is missing.' }
if ($source -notmatch 'Repato\.CreatePlanViews\.TestRunner\.addin') { throw 'Canonical runner manifest is not fixed.' }
if ($source -notmatch 'SHA256\.HashData\(stream\)') { throw 'Trusted hash check is missing.' }
if ($source -notmatch 'Directory\.GetParent\(root\)') { throw 'Manifest parent-directory contract is missing.' }
foreach($name in 'runner-manifest-exists','runner-manifest-readable','runner-manifest-integrity','deployed-candidate-dll-exists','deployed-candidate-dll-readable','deployed-candidate-dll-integrity'){if($source -notmatch [regex]::Escape('"'+$name+'"')){throw "Missing preflight check: $name"}}
if ($source -notmatch 'hash-mismatch' -or $source -notmatch 'access-denied' -or $source -notmatch 'io-error') { throw 'Failure classification is incomplete.' }
Write-Output 'RepatoQA read-only preflight synthetic security tests passed: fixed scope, read-only open, error classification, no arbitrary path input, no content return, and no launch route.'
