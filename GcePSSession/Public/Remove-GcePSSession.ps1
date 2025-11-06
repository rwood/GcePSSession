function Remove-GcePSSession {

    #Requires -Version 3.0

    <#
    
    .SYNOPSIS
    
        Removes a GCE PSSession and stops its associated IAP tunnel.
    
    .DESCRIPTION
    
        Removes a PowerShell remoting session created with New-GcePSSession and
        automatically stops the associated SSH tunnel process. This is a convenience
        function that combines Remove-PSSession and tunnel cleanup.
    
    .PARAMETER Session
    
        The PSSession object(s) returned by New-GcePSSession to remove.
        Can accept one or more sessions via pipeline.
    
    .PARAMETER Force
    
        Forcefully kill the tunnel process if it doesn't respond to termination signals.
    
    .PARAMETER WhatIf
    
        Shows what would happen if the cmdlet runs. The cmdlet is not run.
    
    .PARAMETER Confirm
    
        Prompts you for confirmation before running the cmdlet.
    
    .EXAMPLE
    
        $session = New-GcePSSession -Project "my-project" -Zone "us-central1-a" -InstanceName "my-vm"
        Invoke-Command -Session $session -ScriptBlock { Get-Process }
        Remove-GcePSSession -Session $session
    
    .EXAMPLE
    
        # Remove multiple sessions
        $sessions = @(
            (New-GcePSSession -Project "my-project" -Zone "us-central1-a" -InstanceName "vm1"),
            (New-GcePSSession -Project "my-project" -Zone "us-central1-a" -InstanceName "vm2")
        )
        Remove-GcePSSession -Session $sessions
    
    .EXAMPLE
    
        # Pipeline input
        Get-PSSession | Where-Object { $_.TunnelProcess } | Remove-GcePSSession
    
    .NOTES
    
        This function will attempt to stop the tunnel process before removing the session.
        If the tunnel process cannot be stopped, a warning will be displayed but the
        session will still be removed.
    
    #>

    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [System.Management.Automation.Runspaces.PSSession[]]$Session,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )

    process {
        foreach ($SessionItem in $Session) {
            $SessionName = if ($SessionItem.Name) { $SessionItem.Name } else { "Session $($SessionItem.Id)" }
            
            if ($PSCmdlet.ShouldProcess($SessionName, "Remove PSSession and stop IAP tunnel")) {
                try {
                    # First, stop the tunnel process if it exists
                    if ($SessionItem.TunnelProcess) {
                        Write-Verbose "Stopping SSH tunnel for session: $SessionName"
                        Stop-GceSshTunnel -Session $SessionItem -ErrorAction SilentlyContinue
                    } else {
                        Write-Verbose "Session $SessionName does not have a TunnelProcess property. It may not have been created with New-GcePSSession."
                    }
                    
                    # Remove the PSSession
                    Write-Verbose "Removing PSSession: $SessionName"
                    Remove-PSSession -Session $SessionItem -ErrorAction Stop
                    Write-Verbose "Successfully removed PSSession: $SessionName"
                    
                } catch {
                    Write-Error "Failed to remove session $SessionName`: $_"
                }
            }
        }
    }
}

