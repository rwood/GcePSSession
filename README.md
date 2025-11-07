# GcePSSession

PowerShell remoting sessions for Google Cloud Engine (GCE) VM instances using Identity-Aware Proxy (IAP) Tunnel.

## Overview

GcePSSession is a PowerShell module that enables secure PowerShell remoting to Google Cloud Engine Windows VM instances without requiring direct network access or VPN connections. It leverages Google Cloud's Identity-Aware Proxy (IAP) to create secure SSH tunnels and establish PowerShell remoting sessions.

## Features

- **Secure Remote Access**: Connect to GCE Windows VMs using IAP tunnels without exposing SSH ports publicly
- **PowerShell Remoting**: Full PowerShell remoting support via SSH transport (PowerShell 6+)
- **Session Management**: Easy creation and cleanup of remoting sessions with automatic tunnel management
- **Windows SSH Setup**: Automated installation and configuration of SSH server on Windows VMs
- **Credential Support**: Flexible authentication options including SSH keys and credentials

## Requirements

### Prerequisites

- **PowerShell 3.0+** (for most functions)
- **PowerShell 6.0+** (required for `New-GcePSSession` - SSH remoting support)
- **Google Cloud SDK** (gcloud CLI) installed and configured
- **GCP IAP Permissions**: Your account must have appropriate IAP permissions for target VM instances
- **Windows VM**: Target VM must have SSH server installed and configured (use `Install-GceWindowsSsh.ps1` script for setup)

### Google Cloud Setup

1. Install [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)
2. Authenticate with gcloud:
   ```powershell
   gcloud auth login
   gcloud auth application-default login
   ```
3. Ensure IAP is enabled for your project and you have the necessary permissions:
   - `roles/iap.tunnelResourceAccessor` role or equivalent
   - Compute Engine instance access

## Installation

### From PowerShell Gallery

```powershell
Install-Module -Name GcePSSession -Scope CurrentUser
```

### Manual Installation

1. Clone or download this repository
2. Copy the `GcePSSession` folder to your PowerShell modules directory:
   ```powershell
   # User modules directory
   $modulePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
   Copy-Item -Path ".\GcePSSession" -Destination $modulePath -Recurse
   ```
3. Import the module:
   ```powershell
   Import-Module GcePSSession
   ```

## Usage

### Quick Start

```powershell
# Import the module
Import-Module GcePSSession

# Create a PowerShell remoting session
$session = New-GcePSSession -Project "my-project" -Zone "us-central1-a" -InstanceName "my-windows-vm"

# Execute commands on the remote VM
Invoke-Command -Session $session -ScriptBlock {
    Get-Process
    $env:COMPUTERNAME
}

# Clean up session and tunnel
Remove-GcePSSession -Session $session
```

### Setting Up SSH on Windows VMs

Before you can connect to a Windows VM, you need to install and configure SSH. Download and run the `Install-GceWindowsSsh.ps1` script on the Windows VM:

```powershell
# Download the script (or copy it to the VM)
# Then run it on the Windows VM (requires Administrator privileges)
.\Install-GceWindowsSsh.ps1

# Or specify a custom PowerShell path
.\Install-GceWindowsSsh.ps1 -PowerShellPath "C:\Program Files\PowerShell\8\pwsh.exe"

# Skip package installation if packages are already installed
.\Install-GceWindowsSsh.ps1 -SkipInstallCheck
```

This script:
- Installs Google Compute Engine Windows components
- Installs Google Compute Engine SSH server
- Configures SSH to use PowerShell as the default shell
- Enables password and public key authentication
- Restarts the SSH service

### Creating Sessions

#### Basic Session

```powershell
$session = New-GcePSSession `
    -Project "my-project" `
    -Zone "us-central1-a" `
    -InstanceName "my-vm"
```

#### With SSH Key Authentication

```powershell
$session = New-GcePSSession `
    -Project "my-project" `
    -Zone "us-central1-a" `
    -InstanceName "my-vm" `
    -KeyFilePath "C:\Users\me\.ssh\id_rsa" `
    -UserName "domain\user"
```

#### With Credential Object

```powershell
$cred = Get-Credential
$session = New-GcePSSession `
    -Project "my-project" `
    -Zone "us-central1-a" `
    -InstanceName "my-vm" `
    -Credential $cred
```

#### Debugging Tunnel Issues

```powershell
# Show tunnel window for debugging
$session = New-GcePSSession `
    -Project "my-project" `
    -Zone "us-central1-a" `
    -InstanceName "my-vm" `
    -ShowTunnelWindow
```

#### Using Sessions (Persistent Connection)

```powershell
# Create session
$session = New-GcePSSession `
    -Project "my-project" `
    -Zone "us-central1-a" `
    -InstanceName "my-vm"

# Execute multiple commands
Invoke-Command -Session $session -ScriptBlock {
    Get-Service | Where-Object Status -eq "Running"
}

Invoke-Command -Session $session -ScriptBlock {
    Get-EventLog -LogName Application -Newest 10
}

# Copy files (if needed)
Copy-Item -ToSession $session -Path "C:\Local\file.txt" -Destination "C:\Remote\file.txt"

# Clean up
Remove-GcePSSession -Session $session
```

### Session Management

```powershell
# Create multiple sessions
$sessions = @(
    (New-GcePSSession -Project "my-project" -Zone "us-central1-a" -InstanceName "vm1"),
    (New-GcePSSession -Project "my-project" -Zone "us-central1-a" -InstanceName "vm2"),
    (New-GcePSSession -Project "my-project" -Zone "us-central1-b" -InstanceName "vm3")
)

# Execute on all sessions
Invoke-Command -Session $sessions -ScriptBlock {
    Write-Host "Connected to: $env:COMPUTERNAME"
}

# Remove all sessions (automatically cleans up tunnels)
Remove-GcePSSession -Session $sessions

# Or remove via pipeline
Get-PSSession | Where-Object { $_.TunnelProcess } | Remove-GcePSSession
```

### Advanced Usage

#### Custom Port Configuration

```powershell
$session = New-GcePSSession `
    -Project "my-project" `
    -Zone "us-central1-a" `
    -InstanceName "my-vm" `
    -LocalPort 2222 `
    -RemotePort 22
```

#### Custom gcloud Path

```powershell
$session = New-GcePSSession `
    -Project "my-project" `
    -Zone "us-central1-a" `
    -InstanceName "my-vm" `
    -GcloudPath "C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"
```

#### Using Variables in Remote Scripts

```powershell
$localVar = "Hello from local"
$session = New-GcePSSession `
    -Project "my-project" `
    -Zone "us-central1-a" `
    -InstanceName "my-vm"

Invoke-Command -Session $session -ScriptBlock {
    Write-Host "Local variable value: $using:localVar"
}
```

## Functions

### Public Functions

#### `New-GcePSSession`

Creates a PowerShell remoting session to a GCE VM instance using an IAP tunnel.

**Parameters:**
- `Project` (Mandatory): GCP project ID
- `Zone` (Mandatory): GCE zone
- `InstanceName` (Mandatory): VM instance name
- `Credential`: PSCredential for SSH authentication
- `KeyFilePath`: Path to SSH private key file
- `UserName`: Username for SSH authentication
- `LocalPort`: Local port for tunnel (default: auto-select)
- `RemotePort`: Remote port on VM (default: 22)
- `GcloudPath`: Path to gcloud CLI (default: 'gcloud')
- `TunnelReadyTimeout`: Max wait time for tunnel (default: 30 seconds)
- `ShowTunnelWindow`: Show tunnel process window for debugging

**Returns:** PSSession object with attached tunnel information

#### `Remove-GcePSSession`

Removes a GCE PSSession and stops its associated IAP tunnel.

**Parameters:**
- `Session` (Mandatory): PSSession object(s) to remove
- `Force`: Forcefully kill tunnel process
- `WhatIf`: Preview changes
- `Confirm`: Prompt for confirmation

### Standalone Scripts

#### `Install-GceWindowsSsh.ps1`

A standalone script that installs and configures SSH server on Windows VM in Google Cloud with PowerShell as the default shell. This script can be downloaded and run directly on Windows VMs without requiring the module to be installed.

**Usage:**
```powershell
.\Install-GceWindowsSsh.ps1
.\Install-GceWindowsSsh.ps1 -PowerShellPath "C:\Program Files\PowerShell\8\pwsh.exe"
.\Install-GceWindowsSsh.ps1 -SkipInstallCheck
```

**Parameters:**
- `PowerShellPath`: Path to PowerShell 7+ executable (default: "C:\Program Files\PowerShell\7\pwsh.exe")
- `SkipInstallCheck`: Skip checking/installing GCE packages

**Requirements:**
- Administrator privileges
- PowerShell 7+ (pwsh.exe) installed
- googet package manager (typically available on GCE Windows images)

## Troubleshooting

### Tunnel Connection Issues

1. **Verify gcloud authentication:**
   ```powershell
   gcloud auth list
   gcloud config get-value project
   ```

2. **Check IAP permissions:**
   ```powershell
   gcloud projects get-iam-policy YOUR_PROJECT_ID
   ```

3. **Test IAP tunnel manually:**
   ```powershell
   gcloud compute start-iap-tunnel INSTANCE_NAME 22 --zone=ZONE --project=PROJECT_ID
   ```

4. **Use ShowTunnelWindow for debugging:**
   ```powershell
   $session = New-GcePSSession -Project "..." -Zone "..." -InstanceName "..." -ShowTunnelWindow
   ```

### SSH Connection Issues

1. **Verify SSH server is running on the VM:**
   ```powershell
   # On the VM
   Get-Service sshd
   ```

2. **Check SSH configuration:**
   ```powershell
   # On the VM
   Get-Content C:\ProgramData\ssh\sshd_config
   ```

3. **Verify PowerShell is set as default shell:**
   ```powershell
   # On the VM
   Get-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell
   ```

### Common Errors

- **"gcloud CLI not found"**: Install Google Cloud SDK and ensure `gcloud` is in your PATH
- **"IAP tunnel did not become ready"**: Check IAP permissions and gcloud authentication
- **"PowerShell 6+ required"**: Install PowerShell 7+ for SSH remoting support
- **"SSH connection failed"**: Verify SSH server is installed and configured on the VM

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.

## Author

**Roger Wood**


## Links

- [Project Repository](https://github.com/rwood/GcePSSession)
- [Google Cloud IAP Documentation](https://cloud.google.com/iap/docs/using-tcp-forwarding)
- [PowerShell SSH Remoting](https://docs.microsoft.com/en-us/powershell/scripting/learn/remoting/ssh-remoting-in-powershell-core)

## Version History

- **1.0.4** (2025-01-XX): Bug fixes and improvements
  - Fixed gcloud path quoting for paths with spaces in directory names
  - Improved command-line argument quoting for both -File and -Command execution
  - Enhanced module loading to track successfully loaded functions
  - Added verification that functions exist before exporting
- **1.0.3** (2025-01-XX): Bug fixes
  - Fixed handling of gcloud paths with spaces in directory names
  - Improved path quoting for PowerShell script execution
- **1.0.2** (2025-01-XX): Refactoring and improvements
  - Moved Install-GceWindowsSsh to standalone script (no longer part of module)
  - Script can now be downloaded and run directly on Windows VMs
  - Updated documentation and build scripts
- **1.0.1** (2025-01-XX): Bug fixes and improvements
  - Removed Invoke-GceCommandAs function (use New-GcePSSession with Invoke-Command instead)
  - Updated copyright and author information
  - Fixed module manifest metadata
- **1.0.0** (2025-01-XX): Initial release

---

