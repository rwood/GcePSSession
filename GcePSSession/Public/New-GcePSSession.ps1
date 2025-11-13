function New-GcePSSession {

    #Requires -Version 6.0

    <#
    
    .SYNOPSIS
    
        Creates a PowerShell remoting session to a GCE VM instance using an IAP tunnel.
    
    .DESCRIPTION
    
        Creates a PowerShell remoting session to a Google Cloud Engine VM instance using
        Identity-Aware Proxy (IAP) tunnel. The function establishes an IAP tunnel in the
        background and creates a PSSession via SSH through the tunnel.
        
        If a GceSshTunnel object is provided via -Tunnel, it will be reused. Otherwise, the
        function will search for existing active tunnels matching the Project, Zone, and
        InstanceName before creating a new tunnel.
        
        The tunnel process is attached to the returned session object. When you remove the
        session using Remove-PSSession, you should also stop the tunnel process by calling
        Remove-GcePSSession (which handles cleanup automatically) or by accessing the TunnelProcess property on the session.
        
        Requires Google Cloud SDK (gcloud CLI) to be installed and configured.
        The user must have appropriate IAP permissions for the target VM instance.
        Requires PowerShell 6+ for SSH remoting support.
    
    .PARAMETER Tunnel
    
        Optional GceSshTunnel object to reuse. If provided, Project, Zone, and InstanceName
        parameters are optional and will be extracted from the tunnel object.
    
    .PARAMETER Project
    
        The GCP project ID that contains the VM instance. Required if Tunnel is not provided.
    
    .PARAMETER Zone
    
        The GCE zone where the VM instance is located. Required if Tunnel is not provided.
    
    .PARAMETER InstanceName
    
        The name of the GCE VM instance. Required if Tunnel is not provided.
    
    .PARAMETER Credential
    
        Optional PSCredential for SSH authentication to the VM.
        If not provided, will use default SSH credentials.
    
    .PARAMETER KeyFilePath
    
        Path to SSH private key file for authentication.
    
    .PARAMETER UserName
    
        Username for SSH authentication. If not provided and Credential is not specified,
        will use the current user's username.
    
    .PARAMETER LocalPort
    
        Local port to use for the IAP tunnel. Defaults to an available port.
    
    .PARAMETER RemotePort
    
        Remote port on the VM (default: 22 for SSH).
    
    .PARAMETER GcloudPath
    
        Path to gcloud CLI executable. Defaults to 'gcloud'.
    
    .PARAMETER ReadyTimeout
    
        Maximum time in seconds to wait for the tunnel to become ready. Defaults to 30 seconds.
    
    .PARAMETER ShowTunnelWindow
    
        When specified, the IAP tunnel process will run in a visible window. Useful for debugging
        tunnel connection issues. By default, the tunnel runs hidden.
    
    .EXAMPLE
    
        $session = New-GcePSSession -Project "my-project" -Zone "us-central1-a" -InstanceName "my-vm"
        Invoke-Command -Session $session -ScriptBlock { Get-Process }
        Remove-GcePSSession -Session $session
    
    .EXAMPLE
    
        $session = New-GcePSSession -Project "my-project" -Zone "us-central1-a" -InstanceName "my-vm" -KeyFilePath "C:\Users\me\.ssh\mykey" -UserName "domain\user"
        Invoke-Command -Session $session -ScriptBlock { Write-Host $env:COMPUTERNAME }
        Remove-GcePSSession -Session $session
    
    .EXAMPLE
    
        $session = New-GcePSSession -Project "my-project" -Zone "us-central1-a" -InstanceName "my-vm" -ShowTunnelWindow
        # Tunnel process will be visible in a separate window for debugging
    
    .EXAMPLE
    
        # Reuse an existing tunnel
        $tunnel = Get-GceSshTunnel -InstanceName "my-vm" | Select-Object -First 1
        $session = New-GcePSSession -Tunnel $tunnel
        # Reuses the existing tunnel instead of creating a new one
    
    .NOTES
    
        The tunnel process continues running in the background. Use Remove-GcePSSession
        to automatically clean up both the session and tunnel, or access the TunnelProcess
        property on the session to manage it manually.
    
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false, ValueFromPipeline=$false, Position=0)]
        [GceSshTunnel]$Tunnel,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$Project,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$Zone,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [Alias('Instance')]
        [string]$InstanceName,
        
        [Parameter(Mandatory=$false)]
        [PSCredential]
        [System.Management.Automation.CredentialAttribute()]$Credential,
        
        [Parameter(Mandatory=$false)]
        [string]$KeyFilePath,
        
        [Parameter(Mandatory=$false)]
        [string]$UserName,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 65535)]
        [int]$LocalPort = 0,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 65535)]
        [int]$RemotePort = 22,
        
        [Parameter(Mandatory=$false)]
        [string]$GcloudPath = 'gcloud',
        
        [Parameter(Mandatory=$false)]
        [int]$ReadyTimeout = 30,
        
        [Parameter(Mandatory=$false)]
        [switch]$ShowTunnelWindow
    )

    $ErrorActionPreference = 'Stop'
    $TunnelObject = $null
    $TunnelInfo = $null
    $Session = $null
    $existingTunnels = $null
    $tunnelWasReused = $false

    try {
        Write-Verbose "$(Get-Date): [GcePSSession]: Starting IAP tunnel setup"

        # Handle Tunnel parameter - extract Project, Zone, InstanceName if provided
        if ($Tunnel) {
            Write-Verbose "$(Get-Date): [GcePSSession]: Using provided tunnel (ID: $($Tunnel.Id))"
            if (-not $Project) { $Project = $Tunnel.Project }
            if (-not $Zone) { $Zone = $Tunnel.Zone }
            if (-not $InstanceName) { $InstanceName = $Tunnel.InstanceName }
            $TunnelObject = $Tunnel
            $tunnelWasReused = $true
        } else {
            # Validate required parameters if Tunnel not provided
            if (-not $Project) {
                throw "Project parameter is required when Tunnel is not provided."
            }
            if (-not $Zone) {
                throw "Zone parameter is required when Tunnel is not provided."
            }
            if (-not $InstanceName) {
                throw "InstanceName parameter is required when Tunnel is not provided."
            }
            
            # Try to find existing active tunnel matching Project, Zone, InstanceName
            Write-Verbose "$(Get-Date): [GcePSSession]: Searching for existing tunnel to $InstanceName in project $Project, zone $Zone"
            $existingTunnels = Get-GceSshTunnel -Project $Project -Zone $Zone -InstanceName $InstanceName -ErrorAction SilentlyContinue
            $activeTunnel = $existingTunnels | Where-Object { $_.GetStatus() -eq 'Active' } | Select-Object -First 1
            
            if ($activeTunnel) {
                Write-Verbose "$(Get-Date): [GcePSSession]: Found existing active tunnel (ID: $($activeTunnel.Id)), reusing it"
                $TunnelObject = $activeTunnel
                $tunnelWasReused = $true
            } else {
                Write-Verbose "$(Get-Date): [GcePSSession]: No existing active tunnel found, creating new tunnel"
                $TunnelObject = $null
                $tunnelWasReused = $false
            }
        }

        # Load default values from GcePSSession.json if parameters are not provided
        $configFilePath = Join-Path $env:USERPROFILE ".GcePSSession.json"
        if (Test-Path $configFilePath) {
            try {
                $config = Get-Content -Path $configFilePath -Raw | ConvertFrom-Json
                Write-Verbose "$(Get-Date): [GcePSSession]: Loaded configuration from $configFilePath"
                
                # Use config values only if parameters were not provided
                if (-not $PSBoundParameters.ContainsKey('KeyFilePath') -and $config.KeyFilePath) {
                    $KeyFilePath = $config.KeyFilePath
                    Write-Verbose "$(Get-Date): [GcePSSession]: Using KeyFilePath from config: $KeyFilePath"
                }
                
                if (-not $PSBoundParameters.ContainsKey('UserName') -and $config.UserName) {
                    $UserName = $config.UserName
                    Write-Verbose "$(Get-Date): [GcePSSession]: Using UserName from config: $UserName"
                }
            } catch {
                Write-Warning "Failed to load configuration from $configFilePath`: $_"
            }
        }

        # Verify PowerShell version (need 6+ for SSH remoting)
        $PSVersion = $PSVersionTable.PSVersion.Major
        if ($PSVersion -lt 6) {
            throw "New-GcePSSession requires PowerShell 6 or higher for SSH remoting support. Current version: $PSVersion"
        }

        # Create new tunnel only if we don't have one to reuse
        if (-not $TunnelObject) {
            Write-Verbose "$(Get-Date): [GcePSSession]: Creating new IAP tunnel"
            # Create IAP tunnel using the new tunnel management function
            $TunnelParams = @{
                Project = $Project
                Zone = $Zone
                InstanceName = $InstanceName
                LocalPort = $LocalPort
                RemotePort = $RemotePort
                GcloudPath = $GcloudPath
                TunnelReadyTimeout = $ReadyTimeout
            }
            
            if ($ShowTunnelWindow) {
                $TunnelParams['ShowTunnelWindow'] = $true
            }
            
            if ($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent) {
                $TunnelParams['Verbose'] = $true
            }
            
            $TunnelObject = New-GceSshTunnel @TunnelParams
        } else {
            Write-Verbose "$(Get-Date): [GcePSSession]: Reusing existing tunnel (ID: $($TunnelObject.Id))"
            # Verify tunnel is still active
            $tunnelStatus = $TunnelObject.GetStatus()
            if ($tunnelStatus -ne 'Active') {
                throw "Provided tunnel is not active (Status: $tunnelStatus). Cannot create PSSession with inactive tunnel."
            }
            
            # Warn if LocalPort was specified but doesn't match existing tunnel
            if ($LocalPort -ne 0 -and $LocalPort -ne $TunnelObject.LocalPort) {
                Write-Warning "LocalPort parameter ($LocalPort) was specified but existing tunnel uses port $($TunnelObject.LocalPort). Using existing tunnel's port."
            }
        }
        
        # Extract tunnel info for backward compatibility
        $TunnelInfo = [PSCustomObject]@{
            TunnelProcess = $TunnelObject.TunnelProcess
            LocalPort = $TunnelObject.LocalPort
            RemotePort = $TunnelObject.RemotePort
            Project = $TunnelObject.Project
            Zone = $TunnelObject.Zone
            InstanceName = $TunnelObject.InstanceName
        }
        
        Write-Verbose "$(Get-Date): [GcePSSession]: Tunnel established, configuring SSH and creating PSSession"

        # Configure SSH to skip host key checking for localhost connections
        $sshConfigPath = "$env:USERPROFILE\.ssh\config"
        $sshConfigDir = Split-Path $sshConfigPath -Parent
        if (-not (Test-Path $sshConfigDir)) {
            New-Item -ItemType Directory -Path $sshConfigDir -Force | Out-Null
        }

        # Function to fix SSH file permissions (required by OpenSSH on Windows)
        function Set-SshFilePermissions {
            param([string]$FilePath)
            
            try {
                # Get current user's identity
                $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
                $userAccount = $currentUser.User
                
                # Get the file's ACL
                $acl = Get-Acl -Path $FilePath -ErrorAction Stop
                
                # Set the owner to current user (if not already)
                try {
                    $acl.SetOwner($userAccount)
                } catch {
                    Write-Verbose "$(Get-Date): [GcePSSession]: Could not set owner (may require elevation): $_"
                }
                
                # Remove all existing access rules and disable inheritance
                $acl.SetAccessRuleProtection($true, $false)  # Disable inheritance, don't copy inherited rules
                $existingRules = $acl.Access | ForEach-Object { $_ }
                foreach ($rule in $existingRules) {
                    try {
                        $acl.RemoveAccessRule($rule) | Out-Null
                    } catch {
                        # Ignore errors removing rules
                    }
                }
                
                # Add full control for current user only
                # Use the user account directly (SecurityIdentifier object)
                $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $userAccount,
                    "FullControl",
                    "Allow"
                )
                $acl.AddAccessRule($accessRule)
                
                # Set the ACL
                Set-Acl -Path $FilePath -AclObject $acl -ErrorAction Stop
                Write-Verbose "$(Get-Date): [GcePSSession]: Fixed permissions on $FilePath"
            } catch {
                Write-Warning "Failed to set permissions on $FilePath`: $_"
            }
        }

        # Fix permissions on .ssh directory if needed
        try {
            Set-SshFilePermissions -FilePath $sshConfigDir
        } catch {
            Write-Verbose "$(Get-Date): [GcePSSession]: Could not fix permissions on .ssh directory: $_"
        }

        # Create a specific Host entry for this port to ensure it's matched
        # PowerShell SSH remoting uses [localhost]:port format
        $portSpecificHost = "[localhost]:$($TunnelInfo.LocalPort)"
        
        # Add or update SSH config entry for localhost with port-specific pattern
        $configEntry = @"
Host localhost
    StrictHostKeyChecking no
    UserKnownHostsFile NUL
    CheckHostIP no
    LogLevel ERROR
Host $portSpecificHost
    StrictHostKeyChecking no
    UserKnownHostsFile NUL
    CheckHostIP no
    LogLevel ERROR
"@

        # Check if config already has entries
        if (Test-Path $sshConfigPath) {
            $existingConfig = Get-Content $sshConfigPath -Raw
            # Check if we need to add or update
            if ($existingConfig -notmatch "Host\s+($portSpecificHost|localhost)") {
                Add-Content -Path $sshConfigPath -Value "`n$configEntry"
                Write-Verbose "$(Get-Date): [GcePSSession]: Added SSH config entry for localhost and $portSpecificHost"
                # Fix permissions after modifying the file
                Set-SshFilePermissions -FilePath $sshConfigPath
            } elseif ($existingConfig -notmatch 'UserKnownHostsFile\s+NUL') {
                # Update existing entry if it doesn't have NUL
                Write-Verbose "$(Get-Date): [GcePSSession]: Updating SSH config entry for localhost"
                # Remove old localhost entries and add new ones
                $lines = Get-Content $sshConfigPath
                $newLines = @()
                $inLocalhostBlock = $false
                foreach ($line in $lines) {
                    if ($line -match '^\s*Host\s+(localhost|\[localhost\])') {
                        $inLocalhostBlock = $true
                        continue
                    }
                    if ($inLocalhostBlock -and $line -match '^\s*Host\s+') {
                        $inLocalhostBlock = $false
                    }
                    if (-not $inLocalhostBlock) {
                        $newLines += $line
                    }
                }
                $newLines += $configEntry
                $newLines | Set-Content $sshConfigPath -Encoding UTF8
                # Fix permissions after modifying the file
                Set-SshFilePermissions -FilePath $sshConfigPath
            }
        } else {
            Set-Content -Path $sshConfigPath -Value $configEntry
            Write-Verbose "$(Get-Date): [GcePSSession]: Created SSH config file with localhost entry"
        }

        # Fix permissions on SSH config file (required by OpenSSH on Windows)
        Set-SshFilePermissions -FilePath $sshConfigPath

        # Determine username for SSH
        if ($Credential) {
            $SSHUserName = $Credential.UserName
        } elseif ($UserName) {
            $SSHUserName = $UserName
        } else {
            $SSHUserName = $env:USERNAME
        }

        # Create SSH-based PSSession
        Write-Verbose "$(Get-Date): [GcePSSession]: Creating PSSession via SSH"
        $SessionParams = @{
            HostName = "localhost"
            Port = $TunnelInfo.LocalPort
            UserName = $SSHUserName
            SSHTransport = $true
        }

        if ($KeyFilePath) {
            $SessionParams['KeyFilePath'] = $KeyFilePath
        }

        if ($Credential) {
            $SessionParams['Credential'] = $Credential
        }

        $Session = New-PSSession @SessionParams -ErrorAction Stop

        # Attach tunnel process information to the session
        Add-Member -InputObject $Session -MemberType NoteProperty -Name 'TunnelProcess' -Value $TunnelInfo.TunnelProcess -Force
        Add-Member -InputObject $Session -MemberType NoteProperty -Name 'LocalPort' -Value $TunnelInfo.LocalPort -Force
        Add-Member -InputObject $Session -MemberType NoteProperty -Name 'RemotePort' -Value $TunnelInfo.RemotePort -Force
        Add-Member -InputObject $Session -MemberType NoteProperty -Name 'Project' -Value $TunnelInfo.Project -Force
        Add-Member -InputObject $Session -MemberType NoteProperty -Name 'Zone' -Value $TunnelInfo.Zone -Force
        Add-Member -InputObject $Session -MemberType NoteProperty -Name 'InstanceName' -Value $TunnelInfo.InstanceName -Force
        Add-Member -InputObject $Session -MemberType NoteProperty -Name 'TunnelId' -Value $TunnelObject.Id -Force

        Write-Verbose "$(Get-Date): [GcePSSession]: PSSession created successfully"
        return $Session

    } catch {
        # Cleanup on error
        # Only cleanup tunnel if we created it (not if it was provided or reused)
        if ($TunnelObject -and -not $tunnelWasReused) {
            Write-Verbose "$(Get-Date): [GcePSSession]: Cleaning up newly created tunnel due to error"
            try {
                Remove-GceSshTunnel -Tunnel $TunnelObject -ErrorAction SilentlyContinue
            } catch {
                Write-Warning "Failed to cleanup tunnel: $_"
            }
        } elseif ($TunnelObject -and $tunnelWasReused) {
            Write-Verbose "$(Get-Date): [GcePSSession]: Tunnel was reused, not cleaning up on error"
        } elseif ($TunnelInfo -and $TunnelInfo.TunnelProcess -and -not $TunnelInfo.TunnelProcess.HasExited) {
            Write-Verbose "$(Get-Date): [GcePSSession]: Cleaning up tunnel process due to error"
            $TunnelInfo.TunnelProcess.Kill()
            $TunnelInfo.TunnelProcess.WaitForExit(5000)
        }
        if ($Session) {
            Remove-PSSession -Session $Session -ErrorAction SilentlyContinue
        }
        throw
    }
}

