function Remove-GceSshTunnel {

    #Requires -Version 3.0

    <#
    
    .SYNOPSIS
    
        Removes an IAP tunnel and stops its associated process.
    
    .DESCRIPTION
    
        Removes an IAP tunnel that was created with New-GceSshTunnel, stops the
        associated tunnel process, and unregisters it from the module. This function
        follows the same pattern as Remove-PSSession for PowerShell sessions.
    
    .PARAMETER Tunnel
    
        The GceSshTunnel object(s) to remove. Can accept one or more tunnels via pipeline.
    
    .PARAMETER Id
    
        Specifies the Process ID (PID) of a tunnel to remove.
    
    .PARAMETER InstanceName
    
        Removes tunnels matching the specified instance name.
    
    .PARAMETER Project
    
        Removes tunnels matching the specified project.
    
    .PARAMETER Zone
    
        Removes tunnels matching the specified zone.
    
    .PARAMETER Force
    
        Forcefully kill the tunnel process if it doesn't respond to termination signals.
    
    .PARAMETER WhatIf
    
        Shows what would happen if the cmdlet runs. The cmdlet is not run.
    
    .PARAMETER Confirm
    
        Prompts you for confirmation before running the cmdlet.
    
    .EXAMPLE
    
        $tunnel = New-GceSshTunnel -Project "my-project" -Zone "us-central1-a" -InstanceName "my-vm"
        Remove-GceSshTunnel -Tunnel $tunnel
        
        Creates a tunnel and then removes it.
    
    .EXAMPLE
    
        Remove-GceSshTunnel -Id 12345
        
        Removes a tunnel by Process ID.
    
    .EXAMPLE
    
        Get-GceSshTunnel -InstanceName "my-vm" | Remove-GceSshTunnel
        
        Removes all tunnels for a specific instance via pipeline.
    
    .EXAMPLE
    
        Remove-GceSshTunnel -Project "my-project" -Force
        
        Removes all tunnels for a project, forcefully killing processes.
    
    #>

    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [PSCustomObject[]]$Tunnel,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [int]$Id,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$InstanceName,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$Project,
        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$Zone,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )

    begin {
        $TunnelsToRemove = @()
    }

    process {
        # Collect tunnels to remove
        if ($Tunnel) {
            foreach ($t in $Tunnel) {
                if ($t.Id) {
                    $TunnelsToRemove += $t
                } else {
                    Write-Warning "Tunnel object does not have an Id property. Skipping."
                }
            }
        } elseif ($Id) {
            if ($script:GceIapTunnels.ContainsKey($Id)) {
                $TunnelsToRemove += $script:GceIapTunnels[$Id]
            } else {
                Write-Warning "Tunnel with ID '$Id' not found."
            }
        } else {
            # Filter tunnels by criteria
            $filteredTunnels = Get-GceSshTunnel -InstanceName $InstanceName -Project $Project -Zone $Zone
            $TunnelsToRemove += $filteredTunnels
        }
    }

    end {
        foreach ($tunnel in $TunnelsToRemove) {
            $TunnelId = $tunnel.Id
            $TunnelName = "Tunnel $TunnelId ($($tunnel.InstanceName))"
            
            if ($PSCmdlet.ShouldProcess($TunnelName, "Remove IAP tunnel and stop process")) {
                try {
                    Write-Verbose "Removing tunnel: $TunnelName"
                    
                    # Stop the tunnel process using the class method
                    Write-Verbose "Stopping tunnel process (PID: $($tunnel.TunnelProcess.Id))"
                    $tunnel.Stop($Force)
                    
                    # Remove tunnel file from disk
                    Remove-GceSshTunnelFile -TunnelId $TunnelId
                    
                    # Unregister tunnel from module storage
                    if ($script:GceIapTunnels.ContainsKey($TunnelId)) {
                        $script:GceIapTunnels.Remove($TunnelId)
                        Write-Verbose "Tunnel unregistered successfully"
                    }
                    
                } catch {
                    Write-Error "Failed to remove tunnel $TunnelName`: $_"
                }
            }
        }
    }
}

