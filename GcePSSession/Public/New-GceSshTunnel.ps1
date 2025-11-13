function New-GceSshTunnel {

    #Requires -Version 3.0

    <#
    
    .SYNOPSIS
    
        Creates an IAP tunnel to a GCE VM instance and registers it for management.
    
    .DESCRIPTION
    
        Creates an Identity-Aware Proxy (IAP) tunnel to a Google Cloud Engine VM instance
        and registers it in the module's tunnel registry. The tunnel can be managed using
        Get-GceSshTunnel and Remove-GceSshTunnel.
        
        This function follows the same pattern as New-PSSession for PowerShell sessions.
    
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
    
    .PARAMETER Id
    
        Optional tunnel ID (Process ID). If not provided, the tunnel process PID will be used as the ID.
    
    .OUTPUTS
    
        GceSshTunnel object with the following properties:
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
    
        $tunnel = New-GceSshTunnel -Project "my-project" -Zone "us-central1-a" -InstanceName "my-vm"
        Get-GceSshTunnel
        Remove-GceSshTunnel -Tunnel $tunnel
        
    .EXAMPLE
    
        Remove-GceSshTunnel -Id 12345
        
        Removes a tunnel by Process ID.
    
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
        [switch]$ShowTunnelWindow,
        
        [Parameter(Mandatory=$false)]
        [int]$Id
    )

    $ErrorActionPreference = 'Stop'
    $TunnelProcess = $null
    $TunnelId = $null
    $ErrorOutputEvent = $null
    $ErrorOutputBuilder = $null

    try {
        Write-Verbose "$(Get-Date): [New-GceSshTunnel]: Creating IAP tunnel to $InstanceName in project $Project, zone $Zone"

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
            Write-Verbose "$(Get-Date): [New-GceSshTunnel]: gcloud is a PowerShell script, will execute via PowerShell"
        }

        Write-Verbose "$(Get-Date): [New-GceSshTunnel]: Using gcloud at: $GcloudExecutable"

        # Find an available local port if not specified
        if ($LocalPort -eq 0) {
            $TcpListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, 0)
            $TcpListener.Start()
            $LocalPort = ($TcpListener.LocalEndpoint).Port
            $TcpListener.Stop()
            Write-Verbose "$(Get-Date): [New-GceSshTunnel]: Selected local port: $LocalPort"
        }

        # Start IAP tunnel in background
        Write-Verbose "$(Get-Date): [New-GceSshTunnel]: Starting IAP tunnel to $InstanceName"
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
                # Properly escape and quote the path for PowerShell command string
                # Use single quotes for the path in PowerShell command string to avoid escaping issues
                $escapedGcloudPath = $GcloudExecutable -replace "'", "''"  # Escape single quotes by doubling them
                $escapedGcloudPath = "'$escapedGcloudPath'"  # Wrap in single quotes
                $escapedArgs = ($TunnelArgs | ForEach-Object { 
                    $arg = $_ -replace "'", "''"  # Escape single quotes
                    "'$arg'"  # Wrap each arg in single quotes
                }) -join ' '
                $commandScript = "try { & $escapedGcloudPath $escapedArgs } catch { Write-Host 'Error: ' + `$_.Exception.Message -ForegroundColor Red; Read-Host 'Press Enter to close this window' }"
                # Escape the command script for the command line argument
                $commandScriptEscaped = $commandScript -replace '"', '`"'
                $TunnelProcessInfo.Arguments = "-NoExit -ExecutionPolicy Bypass -Command `"$commandScriptEscaped`""
            } else {
                # Hidden window - properly quote the file path in arguments
                $TunnelProcessInfo.FileName = 'powershell.exe'
                # Build arguments array - don't quote here, we'll quote when building the string
                $TunnelArgsArray = @(
                    '-NoProfile',
                    '-NonInteractive',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', $GcloudExecutable
                ) + $TunnelArgs
                # Build arguments string, ensuring each argument with spaces is properly quoted
                # For Windows command line, arguments with spaces need to be wrapped in quotes
                # and internal quotes need to be escaped by doubling them
                $argStrings = $TunnelArgsArray | ForEach-Object {
                    if ($_ -match '\s' -or $_ -match '"') {
                        $escaped = $_ -replace '"', '""'  # Escape quotes by doubling
                        "`"$escaped`""  # Wrap in quotes
                    } else {
                        $_
                    }
                }
                $TunnelProcessInfo.Arguments = $argStrings -join ' '
            }
        } else {
            # Execute as regular executable
            # ProcessStartInfo.FileName should be the path without quotes
            # The system will handle paths with spaces automatically
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
        
        # Use Process ID as tunnel ID (guaranteed unique)
        if (-not $Id) {
            $TunnelId = $TunnelProcess.Id
        } else {
            $TunnelId = $Id
            # Verify the provided ID matches the process ID
            if ($TunnelId -ne $TunnelProcess.Id) {
                throw "Provided tunnel ID ($TunnelId) does not match the tunnel process ID ($($TunnelProcess.Id)). Tunnel ID must be the process ID."
            }
        }
        
        # Check if tunnel with this PID already exists
        if ($script:GceIapTunnels.ContainsKey($TunnelId)) {
            Write-Warning "A tunnel with PID $TunnelId already exists. This may indicate a stale entry."
        }
        
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
        Write-Verbose "$(Get-Date): [New-GceSshTunnel]: Waiting for tunnel to be ready on port $LocalPort..."
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
                    Write-Verbose "$(Get-Date): [New-GceSshTunnel]: Tunnel is ready and accepting connections!"
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

        Write-Verbose "$(Get-Date): [New-GceSshTunnel]: Tunnel established successfully"

        # Create tunnel object using the GceSshTunnel class
        $TunnelObject = [GceSshTunnel]::new(
            $TunnelId,
            $InstanceName,
            $Project,
            $Zone,
            $LocalPort,
            $RemotePort,
            $TunnelProcess
        )
        
        # Save tunnel metadata to disk file
        Save-GceSshTunnelFile -Tunnel $TunnelObject
        
        # Register process exit handler to automatically delete file when process exits
        # Note: Event subscription will automatically clean up when process exits
        Register-ObjectEvent -InputObject $TunnelProcess -EventName Exited -Action {
            $tunnelId = $Event.MessageData.TunnelId
            Remove-GceSshTunnelFile -TunnelId $tunnelId
            Write-Verbose "Tunnel file automatically removed (process exited): $tunnelId"
        } -MessageData @{ TunnelId = $TunnelId } -ErrorAction SilentlyContinue | Out-Null
        
        # Register tunnel in module storage
        $script:GceIapTunnels[$TunnelId] = $TunnelObject
        
        Write-Verbose "$(Get-Date): [New-GceSshTunnel]: Tunnel created and registered with ID: $TunnelId"
        
        return $TunnelObject

    } catch {
        # Cleanup on error
        if ($TunnelProcess -and -not $TunnelProcess.HasExited) {
            Write-Verbose "$(Get-Date): [New-GceSshTunnel]: Cleaning up tunnel process due to error"
            try {
                $TunnelProcess.Kill()
                $TunnelProcess.WaitForExit(5000)
            } catch {
                Write-Warning "Failed to cleanup tunnel process: $_"
            }
        }
        if ($ErrorOutputEvent) {
            try {
                Stop-Job -Job $ErrorOutputEvent -ErrorAction SilentlyContinue
                Unregister-Event -SourceIdentifier $ErrorOutputEvent.Name -ErrorAction SilentlyContinue
            } catch { }
        }
        if ($TunnelId) {
            # Remove tunnel file if it was created
            Remove-GceSshTunnelFile -TunnelId $TunnelId
            if ($script:GceIapTunnels.ContainsKey($TunnelId)) {
                $script:GceIapTunnels.Remove($TunnelId)
            }
        }
        throw
    }
}

