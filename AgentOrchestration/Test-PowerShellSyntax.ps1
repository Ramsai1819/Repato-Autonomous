$ErrorActionPreference='Stop'
$root='C:\Repato-Autonomous\Source';$failures=@();$files=@();$pending=[Collections.Generic.Stack[string]]::new();$pending.Push($root)
while($pending.Count){$directory=$pending.Pop();foreach($child in [IO.Directory]::EnumerateDirectories($directory)){if([IO.Path]::GetFileName($child)-notin@('bin','obj','.git','.vs')){$pending.Push($child)}};foreach($pattern in @('*.ps1','*.psm1')){$files+=@([IO.Directory]::EnumerateFiles($directory,$pattern,[IO.SearchOption]::TopDirectoryOnly))}}
$files|ForEach-Object{
    $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($_,[ref]$tokens,[ref]$errors)
    if($errors.Count){$failures+=@($errors|ForEach-Object{"$($_.Extent.File):$($_.Extent.StartLineNumber) $($_.Message)"})}
}
if($failures.Count){$failures|Write-Error;exit 1}
Write-Host 'PowerShell syntax checks passed.'
