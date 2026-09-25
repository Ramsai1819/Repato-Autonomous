# Shared preflight/verification functions. No actions occur when dot-sourced.
# Path overrides exist only for synthetic checks; the Install/Run CLI fixes all roots.
function Get-AddinIsolationInventory {
    param([string]$PolicyPath, [string]$MachineRoot, [string]$UserRoot, [string]$QaSourceRoot, [string]$ApprovedUserManifestName)
    $inventory = [ordered]@{
        PolicyPath = $PolicyPath; PolicySha256 = ''; DetectedAddins = @(); Errors = @(); Allowed = $false
    }
    $approved = @{}
    $qaManifestHashes = @{ 'Repato.CreateGrids.TestRunner.addin' = 'D4A749B573240725B904938ED4260F15AF54314B2D5F8DF0F51B0CC6389AF63D' }
    try {
        $PolicyPath = Assert-ChildPath $PolicyPath $QaSourceRoot
        $inventory.PolicySha256 = Get-Sha256 $PolicyPath
        $policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
        if ($policy.schemaVersion -ne 1 -or $policy.machineWideRoot -ine $MachineRoot -or
            $policy.approvedMachineWideManifests -isnot [Array]) { throw 'Invalid allowlist schema or machine-wide root.' }
        foreach ($entry in $policy.approvedMachineWideManifests) {
            $path = Assert-ChildPath $entry.path $MachineRoot
            if ($entry.path -ine $path -or [IO.Path]::GetDirectoryName($path) -ine $MachineRoot -or
                [IO.Path]::GetExtension($path) -ine '.addin' -or $path -match '[*?\[\]]' -or
                $entry.sha256 -notmatch '^[0-9A-Fa-f]{64}$' -or [string]::IsNullOrWhiteSpace($entry.reviewReason) -or
                $approved.ContainsKey($path)) { throw 'Allowlist entries require unique exact paths, SHA-256, and review reasons.' }
            $approved[$path] = $entry.sha256
        }
    }
    catch { $inventory.Errors += $_.Exception.Message; $approved = @{} }

    foreach ($scope in @('MachineWide','UserProfile')) {
        $directory = if ($scope -eq 'MachineWide') { $MachineRoot } else { $UserRoot }
        try {
            # Validate the directory too; an inaccessible inventory is never an empty approved inventory.
            $null = Assert-ChildPath $directory ([IO.Path]::GetDirectoryName($directory))
            if (!(Test-Path -LiteralPath $directory -ErrorAction Stop)) { throw 'Add-in registration directory is missing.' }
            $files = @(Get-ChildItem -LiteralPath $directory -File -Force -ErrorAction Stop |
                Where-Object { $_.Extension -ieq '.addin' } | Sort-Object FullName)
        }
        catch { $inventory.Errors += "${scope}: $($_.Exception.Message)"; continue }
        foreach ($file in $files) {
            $detected = [ordered]@{ Scope=$scope; Path=$file.FullName; Sha256=''; Allowlisted=$false; Reason='Unlisted manifest' }
            try {
                $path = Assert-ChildPath $file.FullName $directory
                $detected.Sha256 = Get-Sha256 $path
                if ($scope -eq 'MachineWide' -and $approved.ContainsKey($path)) {
                    $detected.Allowlisted = $detected.Sha256 -ieq $approved[$path]
                    $detected.Reason = if ($detected.Allowlisted) { 'Reviewed machine-wide path and manifest SHA-256' } else { 'Manifest changed since review' }
                }
                elseif ($scope -eq 'UserProfile') {
                    # Only the two repository-owned QA bootstrap manifests are eligible.
                    # The machine-wide allowlist can never authorize a user-profile add-in.
                    $eligible = if ([string]::IsNullOrWhiteSpace($ApprovedUserManifestName)) {
                        $file.Name -in @('Repato.CreateLevels.TestRunner.addin','Repato.CreateGrids.TestRunner.addin','Repato.TestRunner.addin','Repato.GridBubbleVisibility.TestRunner.addin','Repato.GridBubbleOffset.TestRunner.addin','Repato.GridResequence.TestRunner.addin','Repato.WelcomeSmoke.TestRunner.addin')
                    } else { $file.Name -ceq $ApprovedUserManifestName }
                    if ($eligible) {
                        $source = Assert-ChildPath (Join-Path $QaSourceRoot $file.Name) $QaSourceRoot
                        $sourceHash = Get-Sha256 $source
                        $detected.Allowlisted = $detected.Sha256 -ieq $sourceHash -and (!$qaManifestHashes.ContainsKey($file.Name) -or $detected.Sha256 -ieq $qaManifestHashes[$file.Name])
                        $detected.Reason = if ($detected.Allowlisted) { 'Repository-owned QA manifest verified against source' } else { 'QA manifest differs from repository source' }
                    }
                    else { $detected.Reason = 'User-profile add-in prohibited' }
                }
            }
            catch { $detected.Reason = $_.Exception.Message }
            $inventory.DetectedAddins += [pscustomobject]$detected
        }
    }
    # Force collection shape at the function boundary; callers must not depend on
    # PowerShell's scalar unrolling for zero or one detected manifests.
    $inventory.DetectedAddins = [object[]]@($inventory.DetectedAddins)
    $inventory.Errors = [object[]]@($inventory.Errors)
    $inventory.Allowed = $inventory.Errors.Count -eq 0 -and @($inventory.DetectedAddins | Where-Object { !$_.Allowlisted }).Count -eq 0
    return [pscustomobject]$inventory
}

function Assert-ReportedAddinIsolation {
    param($RequestInventory, $ReportInventory)
    foreach ($inventory in @($RequestInventory, $ReportInventory)) {
        if ($null -eq $inventory) { throw 'Missing add-in inventory object.' }
        if ($inventory.Allowed -isnot [bool] -or !$inventory.Allowed -or @($inventory.Errors).Count -ne 0 -or $null -eq $inventory.DetectedAddins) {
            $details = (@($inventory.Errors) -join '; ')
            throw "Add-in inventory failed. Policy='$($inventory.PolicyPath)' Allowed='$($inventory.Allowed)' Errors='$details' DetectedCount=$(@($inventory.DetectedAddins).Count)."
        }
        $seen = @{}
        foreach ($item in $inventory.DetectedAddins) {
            if ($item.Scope -notin @('MachineWide','UserProfile') -or $item.Allowlisted -isnot [bool] -or !$item.Allowlisted -or
                $item.Sha256 -notmatch '^[0-9A-Fa-f]{64}$' -or $seen.ContainsKey($item.Path)) { throw 'Blocked, malformed, or duplicate add-in record.' }
            $seen[$item.Path] = $true
        }
    }
    $policyPath = Assert-ChildPath $ReportInventory.PolicyPath (Join-Path $repoRoot 'QA')
    if ($policyPath -ine (Join-Path $repoRoot 'QA\MachineWideAddins.allowlist.json') -or
        $RequestInventory.PolicyPath -ine $policyPath -or
        $RequestInventory.PolicySha256 -ine $ReportInventory.PolicySha256 -or
        (Get-Sha256 $policyPath) -ine $ReportInventory.PolicySha256) { throw 'Add-in policy identity changed or differs from the reviewed policy.' }
    $expected = @($RequestInventory.DetectedAddins | ForEach-Object { ($_.Scope + '|' + $_.Path + '|' + $_.Sha256).ToUpperInvariant() } | Sort-Object)
    $actual = @($ReportInventory.DetectedAddins | ForEach-Object { ($_.Scope + '|' + $_.Path + '|' + $_.Sha256).ToUpperInvariant() } | Sort-Object)
    if (($expected -join "`n") -cne ($actual -join "`n")) { throw 'Detected add-ins changed between preflight and execution.' }
}
