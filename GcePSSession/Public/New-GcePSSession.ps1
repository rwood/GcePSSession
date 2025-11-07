function New-GcePSSession {

    #Requires -Version 6.0

    <#
    
    .SYNOPSIS
    
        Creates a PowerShell remoting session to a GCE VM instance using an IAP tunnel.
    
    .DESCRIPTION
    
        Creates a PowerShell remoting session to a Google Cloud Engine VM instance using
        Identity-Aware Proxy (IAP) tunnel. The function establishes an IAP tunnel in the
        background and creates a PSSession via SSH through the tunnel.
        
        The tunnel process is attached to the returned session object. When you remove the
        session using Remove-PSSession, you should also stop the tunnel process by calling
        Remove-GcePSSession (which handles cleanup automatically) or by accessing the TunnelProcess property on the session.
        
        Requires Google Cloud SDK (gcloud CLI) to be installed and configured.
        The user must have appropriate IAP permissions for the target VM instance.
        Requires PowerShell 6+ for SSH remoting support.
    
    .PARAMETER Project
    
        The GCP project ID that contains the VM instance.
    
    .PARAMETER Zone
    
        The GCE zone where the VM instance is located.
    
    .PARAMETER InstanceName
    
        The name of the GCE VM instance.
    
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
    
    .PARAMETER TunnelReadyTimeout
    
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
    
    .NOTES
    
        The tunnel process continues running in the background. Use Remove-GcePSSession
        to automatically clean up both the session and tunnel, or access the TunnelProcess
        property on the session to manage it manually.
    
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
        [int]$TunnelReadyTimeout = 30,
        
        [Parameter(Mandatory=$false)]
        [switch]$ShowTunnelWindow
    )

    $ErrorActionPreference = 'Stop'
    $TunnelInfo = $null
    $Session = $null

    try {
        Write-Verbose "$(Get-Date): [GcePSSession]: Starting IAP tunnel setup"

        # Verify PowerShell version (need 6+ for SSH remoting)
        $PSVersion = $PSVersionTable.PSVersion.Major
        if ($PSVersion -lt 6) {
            throw "New-GcePSSession requires PowerShell 6 or higher for SSH remoting support. Current version: $PSVersion"
        }

        # Create IAP tunnel
        $TunnelParams = @{
            Project = $Project
            Zone = $Zone
            InstanceName = $InstanceName
            LocalPort = $LocalPort
            RemotePort = $RemotePort
            GcloudPath = $GcloudPath
            TunnelReadyTimeout = $TunnelReadyTimeout
        }
        
        if ($ShowTunnelWindow) {
            $TunnelParams['ShowTunnelWindow'] = $true
        }
        
        if ($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent) {
            $TunnelParams['Verbose'] = $true
        }
        
        $TunnelInfo = New-GceSshTunnel @TunnelParams
        
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

        Write-Verbose "$(Get-Date): [GcePSSession]: PSSession created successfully"
        return $Session

    } catch {
        # Cleanup on error
        if ($TunnelInfo -and $TunnelInfo.TunnelProcess -and -not $TunnelInfo.TunnelProcess.HasExited) {
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

