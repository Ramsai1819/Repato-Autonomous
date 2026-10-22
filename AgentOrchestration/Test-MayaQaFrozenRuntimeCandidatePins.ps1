$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$source = Get-Content -LiteralPath (Join-Path $repo 'QaLaunchAgent\Protocol.cs') -Raw
$commit = [regex]::Match($source, 'FrozenCandidateCommit = "([a-f0-9]{40})"').Groups[1].Value
$hash = [regex]::Match($source, 'FrozenCandidateSha256 = "([A-F0-9]{64})"').Groups[1].Value
$directory = [regex]::Match($source, 'StagingCandidateDirectory = @"([^"]+)"').Groups[1].Value
if ($commit -cne '4f2cbba22ba9f4d6d3176e2d36daf2890bd1849c' -or $hash -cne '8C3F6EF16790247B9949EADED8FF098B4D95598791011C418D003DAAC0680AB5') { throw 'Runtime pins no longer match the preserved approved candidate.' }
$manifest = Get-Content -LiteralPath (Join-Path $directory 'release-manifest.json') -Raw | ConvertFrom-Json
$dll = Join-Path $directory 'Repato.Revit.dll'
if ($manifest.SourceCommit -cne $commit -or $manifest.FrozenArtifactSha256 -cne $hash -or $manifest.NeilArtifactSha256 -cne $hash -or $manifest.CandidateDirectory -cne $directory -or $manifest.CandidateDllPath -cne $dll -or (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash -cne $hash) { throw 'Pinned candidate directory, DLL hash, and immutable provenance disagree.' }
Write-Output 'PASS: fixed runtime candidate pins match preserved DLL and provenance.'
