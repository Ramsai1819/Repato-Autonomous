$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$protocol=Get-Content (Join-Path $root 'QaLaunchAgent\Protocol.cs') -Raw
$commit='e2b5bcf889657b82cc10fd46909d145cd27ff2e0'
$sha='56B6E70E42FBFEAF8DA502E53C31C5CC1DAE1CA6A56A7CD3AC258CA573C5D9F5'
$candidate=Join-Path $root ('DeploymentCandidates\AgentBuilds\ReleaseCandidate-'+$commit.Substring(0,12))
$dll=Join-Path $candidate 'Repato.Revit.dll'
$provenance=Get-Content (Join-Path $candidate 'release-manifest.json') -Raw|ConvertFrom-Json
if($protocol -notmatch ('FrozenCandidateCommit = "'+[regex]::Escape($commit)+'"') -or
   $protocol -notmatch ('FrozenCandidateSha256 = "'+$sha+'"') -or
   !$protocol.Contains('StagingCandidateDirectory = @"'+$candidate+'"')){
    throw 'Launch Agent policy is not pinned to the approved repaired candidate.'
}
if(!(Test-Path -LiteralPath $dll -PathType Leaf) -or (Get-FileHash $dll -Algorithm SHA256).Hash -cne $sha -or
   [string]$provenance.SourceCommit -cne $commit -or [string]$provenance.FrozenArtifactSha256 -cne $sha){
    throw 'Pinned candidate files or provenance do not match the approved identity.'
}
if($protocol -match 'b13b3b855ed939925f8812dffa49cad7268161b7|3C0AA7F9A7601418D625FA74E2393486F8FB5449A444D65B9A439D3A469F830B|fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3|7EC1C819C771DCE4EC4ADCADB93B0245D243F6675EC0F0B070B03303B1F412C2|f20358361886572532ccfceef17385ab1d792e39|8D547954D8F86684EA3EDDA47DE8520B87718D3A2581FE11AD2435DB8F2A5D10|8f27384219dc8116889f7ccd33801f68f9174dd9|42AE699214A77E347ED2E5B3A95A995415E192A62A1B395093BC540F5261FC18'){
    throw 'Launch Agent policy still contains the superseded frozen candidate pin.'
}
'Launch Agent candidate pin tests passed: exact source commit, candidate hash/path, release provenance, and superseded pin rejection.'
