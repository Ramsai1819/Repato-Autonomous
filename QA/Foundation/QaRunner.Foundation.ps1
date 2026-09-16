# Shared Repato QA controller primitives. Dot-sourcing performs no actions.
Set-StrictMode -Version Latest

function Get-RepatoQaSha256([string]$Path) {
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $algorithm=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-','') }
    finally { $algorithm.Dispose();$stream.Dispose() }
}

function Assert-RepatoQaChildPath([string]$Path,[string]$Parent,[bool]$MustExist=$false) {
    if([string]::IsNullOrWhiteSpace($Path)-or $Path -notmatch '^[A-Za-z]:\\'-or $Path.Substring(2).Contains(':')){throw 'Absolute local path without alternate streams required.'}
    $full=[IO.Path]::GetFullPath($Path);$root=[IO.Path]::GetFullPath($Parent).TrimEnd('\')+'\'
    if(!$full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw "Path escapes approved root: $full"}
    if(([IO.DriveInfo]::new([IO.Path]::GetPathRoot($full))).DriveType-ne[IO.DriveType]::Fixed){throw 'Fixed local drive required.'}
    for($part=$full;$part;$part=[IO.Path]::GetDirectoryName($part)){if((Test-Path -LiteralPath $part)-and((Get-Item -LiteralPath $part -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw "Reparse point rejected: $part"}}
    if($MustExist-and!(Test-Path -LiteralPath $full -PathType Leaf)){throw "Required file missing: $full"}
    $full
}

function Read-RepatoQaFixtureProvenance {
    param([string]$FixturePath,[string]$ProvenancePath,[string]$ExpectedFixtureId,[string[]]$ExpectedGridNames)
    $data=Get-Content -LiteralPath $ProvenancePath -Raw|ConvertFrom-Json
    $hash=Get-RepatoQaSha256 $FixturePath
    if($data.fixtureId-cne$ExpectedFixtureId-or$data.sourceSha256-ine$hash){throw 'Fixture ID or SHA-256 does not match provenance.'}
    if($ExpectedGridNames.Count-and((@($data.requiredGridNames|Sort-Object)-join '|')-cne(@($ExpectedGridNames|Sort-Object)-join '|'))){throw 'Fixture approved-name declaration mismatch.'}
    [pscustomobject]@{FixtureId=$ExpectedFixtureId;Sha256=$hash;RequiredGridNames=[object[]]@($ExpectedGridNames);Provenance=$data}
}

function Write-RepatoQaJsonAtomic([string]$Path,$Value,[int]$Depth=12) {
    $temporary=$Path+'.partial'
    if(Test-Path -LiteralPath $Path){throw "Refusing to overwrite evidence: $Path"}
    $Value|ConvertTo-Json -Depth $Depth|Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $Path
}

function New-RepatoQaRun {
    param([string]$RunsRoot,[string]$ToolSlug,[string]$RequestName,[string]$TestId,[string]$FixturePath,$FixtureIdentity,[string]$AssemblySha256,$AddinIsolation,[int]$TimeoutSeconds=900)
    $requestId=[guid]::NewGuid().ToString('N');$directory=Assert-RepatoQaChildPath (Join-Path $RunsRoot ($ToolSlug+'-'+$requestId)) $RunsRoot
    New-Item -ItemType Directory -Path $directory|Out-Null
    $model=Join-Path $directory 'model.rvt';Copy-Item -LiteralPath $FixturePath -Destination $model
    Write-RepatoQaJsonAtomic ($model+'.fixture.json') @{fixtureId=$FixtureIdentity.FixtureId;sourceSha256=$FixtureIdentity.Sha256;requiredGridNames=$FixtureIdentity.RequiredGridNames}
    $request=Join-Path $directory $RequestName
    Write-RepatoQaJsonAtomic $request @{requestId=$requestId;testId=$TestId;modelPath=$model;assemblySha256=$AssemblySha256;expiresUtc=[DateTimeOffset]::UtcNow.AddSeconds([Math]::Max($TimeoutSeconds,900)+300).ToString('O');addinIsolation=$AddinIsolation}
    [pscustomobject]@{RequestId=$requestId;RunDirectory=$directory;ModelPath=$model;RequestPath=$request;ResultPath=$request+'.result.json'}
}

function Write-RepatoQaDiagnostic([string]$Path,[string]$Phase,[string]$TestId,[string]$Status,$Details) {
    Write-RepatoQaJsonAtomic $Path @{phase=$Phase;testId=$TestId;status=$Status;details=$Details;recordedUtc=[DateTimeOffset]::UtcNow.ToString('O')}
}

function Start-RepatoQaRevit {
    param([string]$RevitExe,[string]$RequestEnvironmentVariable,[string]$RequestPath,[string]$LaunchLogPath,$LaunchDetails,[switch]$Visible)
    "$(Get-Date -Format o) Revit process launch requested; $LaunchDetails"|Set-Content -LiteralPath $LaunchLogPath -Encoding UTF8
    $old=[Environment]::GetEnvironmentVariable($RequestEnvironmentVariable,'Process')
    try {
        [Environment]::SetEnvironmentVariable($RequestEnvironmentVariable,$RequestPath,'Process')
        if($Visible){Start-Process -FilePath $RevitExe -PassThru}
        else{Start-Process -FilePath $RevitExe -WindowStyle Hidden -PassThru}
    }
    finally {[Environment]::SetEnvironmentVariable($RequestEnvironmentVariable,$old,'Process')}
}

function Wait-RepatoQaResult {
    param($Process,[string]$ResultPath,[int]$TimeoutSeconds,[string]$RunDirectory)
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while(!(Test-Path -LiteralPath $ResultPath)){
        if($Process.HasExited){throw "Revit exited without result. Preserved: $RunDirectory"}
        if([DateTime]::UtcNow-ge$deadline){throw "QA timeout. Revit PID $($Process.Id) remains open; preserve $RunDirectory. No automatic retry or process kill."}
        Start-Sleep -Seconds 1;$Process.Refresh()
    }
    $ResultPath
}

function Find-RepatoQaStaleRequests {
    param([string]$RunsRoot,[string]$RequestName)
    @(
        Get-ChildItem -LiteralPath $RunsRoot -Filter $RequestName -File -Recurse -ErrorAction SilentlyContinue|ForEach-Object{
            try{$request=Get-Content $_.FullName -Raw|ConvertFrom-Json;if([DateTimeOffset]::Parse($request.expiresUtc)-lt[DateTimeOffset]::UtcNow){[pscustomobject]@{Status='StaleRequestPreserved';Path=$_.FullName;RequestId=$request.requestId}}}
            catch{[pscustomobject]@{Status='InvalidRequestPreserved';Path=$_.FullName;Error=$_.Exception.Message}}
        }
    )
}
