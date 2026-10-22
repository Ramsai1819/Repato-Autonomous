param([string]$OutputRoot='QA\SyntheticBuilds\CpvNative127')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $repo
foreach($project in @('TestRunner.ContractTests\TestRunner.ContractTests.csproj','QaLaunchAgent.ProtocolInteropTests\QaLaunchAgent.ProtocolInteropTests.csproj')) {
    $name=[IO.Path]::GetFileNameWithoutExtension($project)
    $output=Join-Path $repo (Join-Path $OutputRoot $name)
    & dotnet build $project -c Release -p:UseAppHost=false -o $output
    if($LASTEXITCODE -ne 0){throw "Contract build failed: $name"}
    & dotnet (Join-Path $output ($name+'.dll'))
    if($LASTEXITCODE -ne 0){throw "Contract execution failed: $name"}
}
