function New-GceSshTunnel {

    #Requires -Version 3.0

    <#
    
    .SYNOPSIS
    
        Creates an IAP tunnel to a GCE VM instance for SSH access.
    
    .DESCRIPTION
    
        Creates an Identity-Aware Proxy (IAP) tunnel to a Google Cloud Engine VM instance.
        This is a private helper function used by New-GcePSSession.
    
    .PARAMETER Project
    
        The GCP project ID that contains the VM instance.
    
    .PARAMETER Zone
    
        The GCE zone where the VM instance is located.
    
    .PARAMETER InstanceName
    
        The name of the GCE VM instance.
    
    .PARAMETER LocalPort
    
        Local port to use for the IAP tunnel. Defaults to 0 (auto-select).
    
    .PARAMETER RemotePort
    
        Remote port on the VM (default: 22 for SSH).
    
    .PARAMETER GcloudPath
    
        Path to gcloud CLI executable. Defaults to 'gcloud'.
    
    .PARAMETER TunnelReadyTimeout
    
        Maximum time in seconds to wait for the tunnel to become ready. Defaults to 30 seconds.
    
    .PARAMETER ShowTunnelWindow
    
        When specified, the IAP tunnel process will run in a visible window.
    
    .OUTPUTS
    
        PSCustomObject with the following properties:
        - TunnelProcess: The Process object for the tunnel
        - LocalPort: The local port used for the tunnel
        - RemotePort: The remote port
        - Project: The GCP project
        - Zone: The GCE zone
        - InstanceName: The VM instance name
    
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Project,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Zone,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$InstanceName,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(0, 65535)]
        [int]$LocalPort = 0,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 65535)]
        [int]$RemotePort = 22,
        
        [Parameter(Mandatory=$false)]
        [string]$GcloudPath = 'gcloud',
        
        [Parameter(Mandatory=$false)]
        [int]$TunnelReadyTimeout = 30,
        
        [Parameter(Mandatory=$false)]
        [switch]$ShowTunnelWindow
    )

    $ErrorActionPreference = 'Stop'
    $TunnelProcess = $null
    $ErrorOutputEvent = $null
    $ErrorOutputBuilder = $null

    try {
        Write-Verbose "$(Get-Date): [GceSshTunnel]: Starting IAP tunnel setup"

        # Verify gcloud is available and get the full path
        $gcloudCheck = Get-Command $GcloudPath -ErrorAction SilentlyContinue
        if (-not $gcloudCheck) {
            throw "gcloud CLI not found. Please install Google Cloud SDK and ensure 'gcloud' is in your PATH."
        }

        # Get the actual executable path (handles aliases, functions, etc.)
        $GcloudExecutable = $gcloudCheck.Source
        if (-not $GcloudExecutable) {
            $GcloudExecutable = (Get-Command $GcloudPath -ErrorAction Stop).Source
        }

        # Handle PowerShell script files (.ps1) - need to execute via PowerShell
        $UsePowerShell = $false
        if ($GcloudExecutable -like '*.ps1') {
            $UsePowerShell = $true
            Write-Verbose "$(Get-Date): [GceSshTunnel]: gcloud is a PowerShell script, will execute via PowerShell"
        }

        Write-Verbose "$(Get-Date): [GceSshTunnel]: Using gcloud at: $GcloudExecutable"

        # Find an available local port if not specified
        if ($LocalPort -eq 0) {
            $TcpListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, 0)
            $TcpListener.Start()
            $LocalPort = ($TcpListener.LocalEndpoint).Port
            $TcpListener.Stop()
            Write-Verbose "$(Get-Date): [GceSshTunnel]: Selected local port: $LocalPort"
        }

        # Start IAP tunnel in background
        Write-Verbose "$(Get-Date): [GceSshTunnel]: Starting IAP tunnel to $InstanceName"
        $TunnelArgs = @(
            'compute', 'start-iap-tunnel',
            $InstanceName,
            $RemotePort,
            '--zone', $Zone,
            '--project', $Project,
            '--local-host-port', "localhost:$LocalPort"
        )

        $TunnelProcessInfo = New-Object System.Diagnostics.ProcessStartInfo

        if ($UsePowerShell) {
            # Execute PowerShell script via PowerShell
            if ($ShowTunnelWindow) {
                # For visible window, use pwsh.exe with -NoExit to keep window open for debugging
                $TunnelProcessInfo.FileName = 'pwsh.exe'
                if (-not (Get-Command pwsh.exe -ErrorAction SilentlyContinue)) {
                    $TunnelProcessInfo.FileName = 'powershell.exe'
                }
                # Wrap in try-catch to keep window open on error
                $escapedGcloudPath = $GcloudExecutable -replace '"', '`"'
                $escapedArgs = ($TunnelArgs -join ' ') -replace '"', '`"'
                $commandScript = 'try { & "' + $escapedGcloudPath + '" ' + $escapedArgs + ' } catch { Write-Host "Error: $_" -ForegroundColor Red; Read-Host "Press Enter to close this window" }'
                $TunnelProcessInfo.Arguments = "-NoExit -ExecutionPolicy Bypass -Command $commandScript"
            } else {
                # Hidden window
                $TunnelProcessInfo.FileName = 'powershell.exe'
                $TunnelArgs = @(
                    '-NoProfile',
                    '-NonInteractive',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', $GcloudExecutable
                ) + $TunnelArgs
                $TunnelProcessInfo.Arguments = $TunnelArgs -join ' '
            }
        } else {
            # Execute as regular executable
            $TunnelProcessInfo.FileName = $GcloudExecutable
            $TunnelProcessInfo.Arguments = $TunnelArgs -join ' '
        }

        # Configure process window visibility
        if ($ShowTunnelWindow) {
            $TunnelProcessInfo.UseShellExecute = $true
            $TunnelProcessInfo.CreateNoWindow = $false
            # Cannot redirect streams when UseShellExecute is true
        } else {
            $TunnelProcessInfo.UseShellExecute = $false
            # Only redirect StandardError - we don't need StandardInput/StandardOutput and they can cause blocking
            $TunnelProcessInfo.RedirectStandardError = $true
            $TunnelProcessInfo.CreateNoWindow = $true
        }

        $TunnelProcess = [System.Diagnostics.Process]::Start($TunnelProcessInfo)
        
        # Start reading error stream asynchronously to prevent blocking
        if (-not $ShowTunnelWindow) {
            $ErrorOutputBuilder = New-Object System.Text.StringBuilder
            $ErrorOutputEvent = Register-ObjectEvent -InputObject $TunnelProcess -EventName ErrorDataReceived -Action {
                if ($EventArgs.Data) {
                    [void]$Event.MessageData.AppendLine($EventArgs.Data)
                }
            } -MessageData $ErrorOutputBuilder
            $TunnelProcess.BeginErrorReadLine()
        }

        # Wait for tunnel to establish by testing port connectivity
        Write-Verbose "$(Get-Date): [GceSshTunnel]: Waiting for tunnel to be ready on port $LocalPort..."
        $TunnelReady = $false
        $MaxWaitTime = $TunnelReadyTimeout
        $Attempts = 0
        $MaxAttempts = ($MaxWaitTime * 2)  # Check every 500ms

        while (-not $TunnelReady -and $Attempts -lt $MaxAttempts) {
            $Attempts++
            Start-Sleep -Milliseconds 500

            # Check if process has exited (error)
            if ($TunnelProcess.HasExited) {
                $ErrorOutput = ""
                if (-not $ShowTunnelWindow -and $ErrorOutputEvent) {
                    # Stop reading and get accumulated error output
                    try {
                        Stop-Job -Job $ErrorOutputEvent -ErrorAction SilentlyContinue
                        Unregister-Event -SourceIdentifier $ErrorOutputEvent.Name -ErrorAction SilentlyContinue
                        $ErrorOutput = $ErrorOutputBuilder.ToString()
                    } catch { }
                }
                if ($ErrorOutput) {
                    throw "Failed to start IAP tunnel: $ErrorOutput"
                } else {
                    throw "IAP tunnel process exited unexpectedly. Exit code: $($TunnelProcess.ExitCode)"
                }
            }

            # Try to connect to the port to verify tunnel is ready
            try {
                $TcpClient = New-Object System.Net.Sockets.TcpClient
                $ConnectResult = $TcpClient.BeginConnect("localhost", $LocalPort, $null, $null)
                $WaitResult = $ConnectResult.AsyncWaitHandle.WaitOne(1000, $false)

                if ($WaitResult -and $TcpClient.Connected) {
                    $TunnelReady = $true
                    $TcpClient.Close()
                    Write-Verbose "$(Get-Date): [GceSshTunnel]: Tunnel is ready and accepting connections!"
                } else {
                    $TcpClient.Close()
                }
            } catch {
                # Port not ready yet, continue waiting
                if ($TcpClient) { $TcpClient.Close() }
            }
        }

        if (-not $TunnelReady) {
            $ErrorOutput = ""
            if (-not $TunnelProcess.HasExited -and -not $ShowTunnelWindow -and $ErrorOutputEvent) {
                # Stop reading and get accumulated error output
                try {
                    Stop-Job -Job $ErrorOutputEvent -ErrorAction SilentlyContinue
                    Unregister-Event -SourceIdentifier $ErrorOutputEvent.Name -ErrorAction SilentlyContinue
                    $ErrorOutput = $ErrorOutputBuilder.ToString()
                } catch { }
            }
            $ErrorMsg = "IAP tunnel did not become ready within $MaxWaitTime seconds. "
            if ($ErrorOutput) {
                $ErrorMsg += "Error: $ErrorOutput"
            } elseif ($ShowTunnelWindow) {
                $ErrorMsg += "Check the tunnel window for error details. Verify gcloud authentication and IAP permissions."
            } else {
                $ErrorMsg += "Check gcloud authentication and IAP permissions."
            }
            throw $ErrorMsg
        }
        
        # Clean up error stream reader if tunnel is ready
        if (-not $ShowTunnelWindow -and $ErrorOutputEvent) {
            try {
                Stop-Job -Job $ErrorOutputEvent -ErrorAction SilentlyContinue
                Unregister-Event -SourceIdentifier $ErrorOutputEvent.Name -ErrorAction SilentlyContinue
            } catch { }
        }

        Write-Verbose "$(Get-Date): [GceSshTunnel]: Tunnel established successfully"

        # Return tunnel information object
        return [PSCustomObject]@{
            TunnelProcess = $TunnelProcess
            LocalPort = $LocalPort
            RemotePort = $RemotePort
            Project = $Project
            Zone = $Zone
            InstanceName = $InstanceName
        }

    } catch {
        # Cleanup on error
        if ($TunnelProcess -and -not $TunnelProcess.HasExited) {
            Write-Verbose "$(Get-Date): [GceSshTunnel]: Cleaning up tunnel process due to error"
            $TunnelProcess.Kill()
            $TunnelProcess.WaitForExit(5000)
        }
        if ($ErrorOutputEvent) {
            try {
                Stop-Job -Job $ErrorOutputEvent -ErrorAction SilentlyContinue
                Unregister-Event -SourceIdentifier $ErrorOutputEvent.Name -ErrorAction SilentlyContinue
            } catch { }
        }
        throw
    }
}

