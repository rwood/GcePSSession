function Get-GceSshTunnel {

    #Requires -Version 3.0

    <#
    
    .SYNOPSIS
    
        Gets IAP tunnels that are currently registered and active.
    
    .DESCRIPTION
    
        Retrieves IAP tunnel objects that have been created with New-GceSshTunnel
        and are currently registered in the module. This function follows the same
        pattern as Get-PSSession for PowerShell sessions.
        
        The GetStatus() method of each tunnel object dynamically checks the process
        and port status when called.
    
    .PARAMETER Id
    
        Specifies the Process ID (PID) of a specific tunnel to retrieve.
    
    .PARAMETER InstanceName
    
        Filters tunnels by instance name.
    
    .PARAMETER Project
    
        Filters tunnels by GCP project.
    
    .PARAMETER Zone
    
        Filters tunnels by GCE zone.
    
    .PARAMETER Status
    
        Filters tunnels by status (Active, Stopped, Error).
    
    .OUTPUTS
    
        GceSshTunnel object(s) with the following properties:
        - Id: Tunnel ID (Process ID/PID)
        - GetStatus(): Method that returns tunnel status (Active, Stopped, Error)
        - InstanceName: The VM instance name
        - Project: The GCP project
        - Zone: The GCE zone
        - LocalPort: The local port used for the tunnel
        - RemotePort: The remote port
        - TunnelProcess: The Process object for the tunnel
        - Created: Timestamp when the tunnel was created
    
    .EXAMPLE
    
        Get-GceSshTunnel
        
        Gets all registered IAP tunnels.
    
    .EXAMPLE
    
        Get-GceSshTunnel -Id 12345
        
        Gets a specific tunnel by Process ID.
    
    .EXAMPLE
    
        Get-GceSshTunnel -InstanceName "my-vm" -Project "my-project"
        
        Gets tunnels matching specific instance and project.
    
    .EXAMPLE
    
        Get-GceSshTunnel -Status Active
        
        Gets only active tunnels.
    
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [int]$Id,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$InstanceName,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$Project,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$Zone,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Active', 'Stopped', 'Error')]
        [string]$Status
    )

    process {
        # Refresh registry from disk files to ensure we have current state
        # This handles cases where processes exited outside of PowerShell or module was reloaded
        try {
            $diskTunnels = Import-GceSshTunnelFiles
            # Update registry with tunnels from disk (merge, don't replace, to preserve in-memory objects)
            foreach ($tunnelId in $diskTunnels.Keys) {
                if (-not $script:GceIapTunnels.ContainsKey($tunnelId)) {
                    $script:GceIapTunnels[$tunnelId] = $diskTunnels[$tunnelId]
                }
            }
            # Remove tunnels from registry that no longer exist on disk
            $tunnelIdsToRemove = @()
            foreach ($tunnelId in $script:GceIapTunnels.Keys) {
                if (-not $diskTunnels.ContainsKey($tunnelId)) {
                    $tunnelIdsToRemove += $tunnelId
                }
            }
            foreach ($tunnelId in $tunnelIdsToRemove) {
                $script:GceIapTunnels.Remove($tunnelId)
            }
        } catch {
            Write-Warning "Failed to refresh tunnels from disk: $_"
        }
        
        # If no filters specified, return all tunnels
        if (-not $Id -and -not $InstanceName -and -not $Project -and -not $Zone -and -not $Status) {
            $script:GceIapTunnels.Values | ForEach-Object { $_ }
            return
        }

        # Filter tunnels
        $filteredTunnels = $script:GceIapTunnels.Values | Where-Object {
            $match = $true
            
            if ($Id -and $_.Id -ne $Id) {
                $match = $false
            }
            
            if ($InstanceName -and $_.InstanceName -ne $InstanceName) {
                $match = $false
            }
            
            if ($Project -and $_.Project -ne $Project) {
                $match = $false
            }
            
            if ($Zone -and $_.Zone -ne $Zone) {
                $match = $false
            }
            
            if ($Status -and $_.GetStatus() -ne $Status) {
                $match = $false
            }
            
            $match
        }
        
        $filteredTunnels | ForEach-Object { $_ }
    }
}

