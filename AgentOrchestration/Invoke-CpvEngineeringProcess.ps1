[CmdletBinding()]
param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$LogPrefix,[ValidateRange(7200,86400)][int]$TimeoutSeconds=7200,
    [int]$ExpectedExitCode=0)
$ErrorActionPreference='Stop'
$prefix=[IO.Path]::GetFullPath($LogPrefix)
New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($prefix)) -Force|Out-Null
# Arguments are passed directly to a process, never evaluated by a shell.
$quoted=@(foreach($value in $Arguments){if($value.Contains('"')){throw 'Embedded quotes are not supported in engineering arguments.'};'"'+$value+'"'})
$info=New-Object Diagnostics.ProcessStartInfo
$info.FileName=$Executable;$info.Arguments=$quoted -join ' ';$info.WorkingDirectory=Split-Path $PSScriptRoot -Parent
$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
if($Executable -like '*\WindowsPowerShell\v1.0\powershell.exe'){
    # Process.Start bypasses pwsh's native-command adjustment of PSModulePath.
    # Give the 5.1 child its own standard module paths rather than PS7 modules.
    $info.EnvironmentVariables['PSModulePath']=(@(
        (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'),
        (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'),
        (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\Modules')) -join ';')
}
$process=New-Object Diagnostics.Process;$process.StartInfo=$info
try {
    if(!$process.Start()){throw 'Engineering subprocess did not start.'}
    $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
    if(!$process.WaitForExit($TimeoutSeconds*1000)){
        $process.Kill();throw "Engineering subprocess exceeded $TimeoutSeconds seconds."
    }
    $process.WaitForExit()
    [IO.File]::WriteAllText($prefix+'.stdout.log',$stdout.GetAwaiter().GetResult())
    [IO.File]::WriteAllText($prefix+'.stderr.log',$stderr.GetAwaiter().GetResult())
    $result=[pscustomobject]@{Executable=$Executable;Arguments=$Arguments;ExitCode=$process.ExitCode;ExpectedExitCode=$ExpectedExitCode;TimeoutSeconds=$TimeoutSeconds;Stdout=$prefix+'.stdout.log';Stderr=$prefix+'.stderr.log'}
    [IO.File]::WriteAllText($prefix+'.result.json',($result|ConvertTo-Json -Depth 5))
    $result
    if($process.ExitCode -ne $ExpectedExitCode){throw "Engineering subprocess exit $($process.ExitCode); see $prefix.stderr.log"}
} finally {$process.Dispose()}
