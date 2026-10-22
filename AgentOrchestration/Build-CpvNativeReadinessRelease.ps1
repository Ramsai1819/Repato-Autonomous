param([Parameter(Mandatory)][string]$BuildSourceRoot,[Parameter(Mandatory)][string]$SourceCommit,
    [Parameter(Mandatory)][string]$AgentOutputRoot)
$ErrorActionPreference='Stop'
Push-Location -LiteralPath $BuildSourceRoot
try {
    if((git rev-parse HEAD).Trim() -cne $SourceCommit){throw 'Build commit mismatch.'}
    dotnet build '.\Forma.RevitConnector.csproj' -c Release '-p:RevitInstallDir=E:\revit\Revit 2025'
    if($LASTEXITCODE -ne 0){throw 'Product Release build failed.'}
    dotnet build '.\QaLaunchAgent\Repato.QaLaunchAgent.csproj' -c Release ('-p:Version=1.0.23+'+$SourceCommit) -p:UseAppHost=true -o $AgentOutputRoot
    if($LASTEXITCODE -ne 0){throw 'Agent Release build failed.'}
} finally {Pop-Location}
