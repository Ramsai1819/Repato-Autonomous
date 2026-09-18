# Supervised QA profile deployment

These commands are documentation only. They do not launch Revit. Review the hashes and obtain explicit user approval before supplying `-ConfirmQaProfileDeployment`.

```powershell
$root = 'C:\Repato-Autonomous\Source'
$dll = Join-Path $root 'bin\Release\net8.0-windows\Repato.Revit.dll'
$manifest = Join-Path $root 'QA\Repato.WelcomeSmoke.TestRunner.addin'
$target = 'C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\RepatoQA'
$dllHash = (Get-FileHash $dll -Algorithm SHA256).Hash
$manifestHash = (Get-FileHash $manifest -Algorithm SHA256).Hash
Import-Module (Join-Path $root 'AgentOrchestration\Repato.QaAddinDeployment.psm1')
Invoke-QaAddinDeployment $dll $manifest -TargetRoot $target -DryRun
Invoke-QaAddinDeployment $dll $manifest -TargetRoot $target -ConfirmQaProfileDeployment
Get-FileHash (Join-Path $target 'Repato.Revit.dll') -Algorithm SHA256
Get-FileHash (Join-Path (Split-Path -Parent $target) ([IO.Path]::GetFileName($manifest))) -Algorithm SHA256
# If verification fails, stop and restore the recorded BackupPaths with Copy-Item, then re-hash both files.
```

Revit 2025 scans the per-user directory `C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025` for `.addin` manifests. The manifest is therefore placed directly in that directory, while `Repato.Revit.dll` remains isolated in its `RepatoQA` subfolder and is referenced by a relative `RepatoQA\Repato.Revit.dll` assembly path. The real target is restricted to the exact RepatoQA profile directory and its one approved manifest location. Machine-wide, Revit-install, network, unrelated user-profile, and external paths are rejected. The confirmed command is intentionally not run automatically.
