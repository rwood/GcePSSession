# Module-level storage for active IAP tunnels (similar to how PowerShell stores PSSessions)
# Key: Tunnel ID (GUID), Value: GceSshTunnel object
# This is populated from disk files on module load and kept in sync with files
$script:GceIapTunnels = @{}

# Load classes first (before functions that use them)
$Classes = @( Get-ChildItem -Path $PSScriptRoot\Classes\*.ps1 -ErrorAction SilentlyContinue )
foreach ($classFile in $Classes) {
    try {
        . $classFile.FullName -ErrorAction Stop
    } catch {
        Write-Warning "Failed to load class $($classFile.Name): $_"
    }
}

#Get public and private function definition files.
$Public = @( Get-ChildItem -Path $PSScriptRoot\public\*.ps1 -Recurse -ErrorAction SilentlyContinue )
$Private = @( Get-ChildItem -Path $PSScriptRoot\private\*.ps1 -Recurse -ErrorAction SilentlyContinue )

# Load private helper functions first (needed for tunnel file management)
foreach ($import in @($Private)) {
    Try {
        . $import.fullname -ErrorAction Stop
    }
    Catch {
        Write-Warning "Failed to import private function $($import.Name): $_"
    }
}

# Load tunnels from disk files on module import (after private functions are loaded)
try {
    if (Get-Command -Name Import-GceSshTunnelFiles -ErrorAction SilentlyContinue) {
        $script:GceIapTunnels = Import-GceSshTunnelFiles
        if ($script:GceIapTunnels.Count -gt 0) {
            Write-Verbose "Loaded $($script:GceIapTunnels.Count) tunnel(s) from disk"
        }
    }
} catch {
    Write-Warning "Failed to load tunnels from disk: $_"
}

#Dot source the public functions (private functions already loaded above)
$LoadedFunctions = @()
Foreach ($import in @($Public)) {
    Try {
        . $import.fullname -ErrorAction Stop
        # Track successfully loaded public functions
        # Extract function name from file (remove .ps1 extension)
        $functionName = [System.IO.Path]::GetFileNameWithoutExtension($import.Name)
        # Verify the function actually exists before adding to export list
        if (Get-Command -Name $functionName -ErrorAction SilentlyContinue) {
            $LoadedFunctions += $functionName
        }
    }
    Catch {
        Write-Warning "Failed to import function $($import.Name): $_"
    }
}

# Export only functions that were successfully loaded
# This ensures functions that fail due to #Requires directives aren't exported
if ($LoadedFunctions.Count -gt 0) {
    Export-ModuleMember -Function $LoadedFunctions
} else {
    Write-Warning "No functions were successfully loaded from the module."
}
