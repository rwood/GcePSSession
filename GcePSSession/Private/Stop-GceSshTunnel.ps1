function Stop-GceSshTunnel {

    #Requires -Version 3.0

    <#
    
    .SYNOPSIS
    
        Stops the SSH tunnel process associated with a GCE PSSession.
    
    .DESCRIPTION
    
        Stops the SSH tunnel process that was created for a GCE PSSession.
        This is a private helper function used internally by Remove-GcePSSession.
    
    .PARAMETER Session
    
        The PSSession object returned by New-GcePSSession. The session must have
        a TunnelProcess property attached.
    
    .PARAMETER Force
    
        Forcefully kill the tunnel process if it doesn't respond to termination signals.
    
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [System.Management.Automation.Runspaces.PSSession]$Session,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )

    process {
        if (-not $Session.TunnelProcess) {
            Write-Warning "Session does not have a TunnelProcess property. It may not have been created with New-GcePSSession."
            return
        }

        $TunnelProcess = $Session.TunnelProcess

        if ($TunnelProcess.HasExited) {
            Write-Verbose "Tunnel process has already exited (ExitCode: $($TunnelProcess.ExitCode))"
            return
        }

        try {
            Write-Verbose "Stopping SSH tunnel process (PID: $($TunnelProcess.Id))"
            
            # For console processes, we need to kill them directly
            # Try to send Ctrl+C signal first if possible, otherwise just kill
            $TunnelProcess.Kill()
            $TunnelProcess.WaitForExit(5000)
            
            if (-not $TunnelProcess.HasExited) {
                Write-Warning "Tunnel process did not exit, it may need to be killed manually (PID: $($TunnelProcess.Id))"
            } else {
                Write-Verbose "Tunnel process stopped successfully"
            }
        } catch {
            Write-Warning "Error stopping tunnel process: $_"
            try {
                $TunnelProcess.Kill()
            } catch {
                Write-Warning "Failed to kill tunnel process: $_"
            }
        }
    }
}

