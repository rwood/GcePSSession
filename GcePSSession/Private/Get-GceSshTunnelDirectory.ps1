# Private helper functions for managing tunnel files

function Get-GceSshTunnelDirectory {
    <#
    .SYNOPSIS
    Gets the directory where tunnel files are stored.
    
    .DESCRIPTION
    Returns the path to the tunnel files directory, creating it if it doesn't exist.
    #>
    $tunnelDir = Join-Path $env:TEMP "GcePSSession\Tunnels"
    if (-not (Test-Path $tunnelDir)) {
        New-Item -ItemType Directory -Path $tunnelDir -Force | Out-Null
    }
    return $tunnelDir
}

function Get-GceSshTunnelFilePath {
    <#
    .SYNOPSIS
    Gets the file path for a tunnel's JSON file.
    
    .PARAMETER TunnelId
    The tunnel ID (Process ID).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [int]$TunnelId
    )
    $tunnelDir = Get-GceSshTunnelDirectory
    return Join-Path $tunnelDir "$TunnelId.json"
}

function Save-GceSshTunnelFile {
    <#
    .SYNOPSIS
    Saves tunnel metadata to a JSON file.
    
    .PARAMETER Tunnel
    The GceSshTunnel object to save.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [GceSshTunnel]$Tunnel
    )
    
    try {
        $filePath = Get-GceSshTunnelFilePath -TunnelId $Tunnel.Id
        $tunnelData = @{
            Id = $Tunnel.Id
            InstanceName = $Tunnel.InstanceName
            Project = $Tunnel.Project
            Zone = $Tunnel.Zone
            LocalPort = $Tunnel.LocalPort
            RemotePort = $Tunnel.RemotePort
            ProcessId = $Tunnel.TunnelProcess.Id
            Created = $Tunnel.Created.ToString("o")  # ISO 8601 format
        }
        
        $tunnelData | ConvertTo-Json -Compress | Set-Content -Path $filePath -Encoding UTF8 -ErrorAction Stop
        Write-Verbose "Saved tunnel file: $filePath"
    } catch {
        Write-Warning "Failed to save tunnel file for $($Tunnel.Id): $_"
    }
}

function Remove-GceSshTunnelFile {
    <#
    .SYNOPSIS
    Removes a tunnel's JSON file.
    
    .PARAMETER TunnelId
    The tunnel ID (Process ID).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [int]$TunnelId
    )
    
    try {
        $filePath = Get-GceSshTunnelFilePath -TunnelId $TunnelId
        if (Test-Path $filePath) {
            Remove-Item -Path $filePath -Force -ErrorAction Stop
            Write-Verbose "Removed tunnel file: $filePath"
        }
    } catch {
        Write-Warning "Failed to remove tunnel file for $TunnelId`: $_"
    }
}

function Import-GceSshTunnelFiles {
    <#
    .SYNOPSIS
    Imports all tunnel files from disk and rebuilds the registry.
    
    .DESCRIPTION
    Scans the tunnel directory, loads all JSON files, verifies processes are still running,
    removes stale files, and returns a hashtable of active tunnels.
    #>
    
    $tunnelDir = Get-GceSshTunnelDirectory
    $tunnels = @{}
    
    if (-not (Test-Path $tunnelDir)) {
        return $tunnels
    }
    
    $tunnelFiles = Get-ChildItem -Path $tunnelDir -Filter "*.json" -ErrorAction SilentlyContinue
    
    foreach ($file in $tunnelFiles) {
        try {
            $tunnelData = Get-Content -Path $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            
            # Verify process still exists
            $process = Get-Process -Id $tunnelData.ProcessId -ErrorAction SilentlyContinue
            if (-not $process) {
                # Process no longer exists, remove stale file
                Write-Verbose "Removing stale tunnel file: $($file.Name) (process $($tunnelData.ProcessId) no longer exists)"
                Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
                continue
            }
            
            # Use ProcessId as the tunnel ID (Id field in JSON may be old GUID format during migration)
            $tunnelId = $tunnelData.ProcessId
            
            # Recreate tunnel object using ProcessId as the ID
            $tunnel = [GceSshTunnel]::new(
                $tunnelId,
                $tunnelData.InstanceName,
                $tunnelData.Project,
                $tunnelData.Zone,
                $tunnelData.LocalPort,
                $tunnelData.RemotePort,
                $process
            )
            
            # Register process exit handler to clean up file
            Register-ObjectEvent -InputObject $process -EventName Exited -Action {
                $tunnelId = $Event.MessageData.TunnelId
                Remove-GceSshTunnelFile -TunnelId $tunnelId
            } -MessageData @{ TunnelId = $tunnelId } | Out-Null
            
            $tunnels[$tunnelId] = $tunnel
            Write-Verbose "Loaded tunnel from file: $($file.Name)"
            
        } catch {
            Write-Warning "Failed to load tunnel file $($file.Name): $_"
            # Remove corrupted file
            try {
                Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
            } catch { }
        }
    }
    
    return $tunnels
}

