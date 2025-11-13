# PowerShell class for GCE SSH Tunnel objects
# This class represents an IAP tunnel to a GCE VM instance

class GceSshTunnel {
    # Properties
    [int]$Id  # Tunnel ID is the Process ID (PID)
    [string]$InstanceName
    [string]$Project
    [string]$Zone
    [int]$LocalPort
    [int]$RemotePort
    [System.Diagnostics.Process]$TunnelProcess
    [DateTime]$Created
    
    # Status method that checks process and port status dynamically
    [string] GetStatus() {
        try {
            # Check if process exists and is running
            if ($null -eq $this.TunnelProcess) {
                return 'Error'
            }
            
            # Refresh process object
            try {
                $process = Get-Process -Id $this.TunnelProcess.Id -ErrorAction SilentlyContinue
                if (-not $process) {
                    return 'Stopped'
                }
            } catch {
                # Process check failed - check if it has exited
                if ($this.TunnelProcess.HasExited) {
                    return 'Stopped'
                }
                return 'Error'
            }
            
            # Process is running, now check if port is open
            $TcpClient = $null
            try {
                $TcpClient = New-Object System.Net.Sockets.TcpClient
                $ConnectResult = $TcpClient.BeginConnect("localhost", $this.LocalPort, $null, $null)
                $WaitResult = $ConnectResult.AsyncWaitHandle.WaitOne(1000, $false)
                
                if ($WaitResult -and $TcpClient.Connected) {
                    $TcpClient.Close()
                    return 'Active'
                } else {
                    $TcpClient.Close()
                    return 'Error'
                }
            } catch {
                # Port check failed
                if ($null -ne $TcpClient) { 
                    try { $TcpClient.Close() } catch { }
                }
                return 'Error'
            }
        } catch {
            return 'Error'
        }
    }
    
    # Constructor
    GceSshTunnel(
        [int]$Id,
        [string]$InstanceName,
        [string]$Project,
        [string]$Zone,
        [int]$LocalPort,
        [int]$RemotePort,
        [System.Diagnostics.Process]$TunnelProcess
    ) {
        $this.Id = $Id
        $this.InstanceName = $InstanceName
        $this.Project = $Project
        $this.Zone = $Zone
        $this.LocalPort = $LocalPort
        $this.RemotePort = $RemotePort
        $this.TunnelProcess = $TunnelProcess
        $this.Created = Get-Date
    }
    
    # Method to stop the tunnel process
    [void] Stop([bool]$Force = $false) {
        if ($null -eq $this.TunnelProcess) {
            return
        }
        
        if ($this.TunnelProcess.HasExited) {
            return
        }
        
        try {
            $this.TunnelProcess.Kill()
            $this.TunnelProcess.WaitForExit(5000)
            
            if (-not $this.TunnelProcess.HasExited -and $Force) {
                $this.TunnelProcess.Kill()
                $this.TunnelProcess.WaitForExit(2000)
            }
        } catch {
            if ($Force) {
                try {
                    $this.TunnelProcess.Kill()
                } catch {
                    # Ignore errors when force killing
                }
            }
        }
    }
    
    # Override ToString for better display
    [string] ToString() {
        return "GceSshTunnel [Id=$($this.Id), Instance=$($this.InstanceName), Status=$($this.GetStatus()), Port=$($this.LocalPort)]"
    }
}

