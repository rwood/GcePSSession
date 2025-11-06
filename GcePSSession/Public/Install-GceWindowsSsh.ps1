function Install-GceWindowsSsh {

    #Requires -Version 5.0
    #Requires -RunAsAdministrator

    <#
    
    .SYNOPSIS
    
        Installs and configures SSH server on Windows VM in Google Cloud with PowerShell as the default shell.
    
    .DESCRIPTION
    
        This function:
        1. Installs Google Compute Engine Windows components (if not already installed)
        2. Installs Google Compute Engine SSH server (if not already installed)
        3. Configures SSH to use PowerShell as the default shell
        4. Configures SSH authentication settings
        5. Restarts the SSH service
        
        Requires Administrator privileges and PowerShell 7+ (pwsh.exe) to be installed.
    
    .PARAMETER PowerShellPath
    
        Optional path to PowerShell 7+ executable. Defaults to "C:\Program Files\PowerShell\7\pwsh.exe".
        If not found at the specified path, the function will search for pwsh.exe in PATH.
    
    .PARAMETER SkipInstallCheck
    
        Skip checking and installing Google Compute Engine packages. Use this if packages are already installed.
    
    .EXAMPLE
    
        Install-GceWindowsSsh
    
        Installs and configures SSH server with default settings.
    
    .EXAMPLE
    
        Install-GceWindowsSsh -PowerShellPath "C:\Program Files\PowerShell\8\pwsh.exe"
    
        Installs and configures SSH server using a specific PowerShell path.
    
    .EXAMPLE
    
        Install-GceWindowsSsh -SkipInstallCheck
    
        Configures SSH server without checking for or installing GCE packages.
    
    .NOTES
    
        Requires Administrator privileges
        Requires PowerShell 7+ (pwsh.exe) to be installed
        Requires googet package manager (typically available on GCE Windows images)
    
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$PowerShellPath = "C:\Program Files\PowerShell\7\pwsh.exe",
        
        [Parameter(Mandatory=$false)]
        [switch]$SkipInstallCheck
    )

    $ErrorActionPreference = 'Stop'

    Write-Host "=== Installing and Configuring SSH Server on Windows VM ===" -ForegroundColor Cyan
    Write-Host ""

    # Function to check if a package is installed
    function Test-GoogetPackageInstalled {
        param([string]$PackageName)
        
        try {
            $installed = googet installed 2>&1 | Select-String -Pattern $PackageName
            return ($null -ne $installed)
        } catch {
            return $false
        }
    }

    # Function to check if PowerShell 7+ is installed
    function Test-PowerShellInstalled {
        param([string]$Path)
        
        if (Test-Path $Path) {
            return $true
        }
        
        # Try to find pwsh.exe in PATH
        try {
            $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
            if ($pwsh) {
                $script:PowerShellPath = $pwsh.Source
                return $true
            }
        } catch {
            return $false
        }
        
        return $false
    }

    # Step 1: Check and install Google Compute Engine Windows components
    Write-Host "[1/6] Checking Google Compute Engine Windows components..." -ForegroundColor Yellow

    if (-not $SkipInstallCheck) {
        if (-not (Test-GoogetPackageInstalled -PackageName "google-compute-engine-windows")) {
            Write-Host "  Installing google-compute-engine-windows..." -ForegroundColor Gray
            googet -noconfirm=true install google-compute-engine-windows
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to install google-compute-engine-windows"
            }
            Write-Host "  ✓ Installed google-compute-engine-windows" -ForegroundColor Green
        } else {
            Write-Host "  ✓ google-compute-engine-windows is already installed" -ForegroundColor Green
        }
    } else {
        Write-Host "  Skipping install check (SkipInstallCheck specified)" -ForegroundColor Gray
    }

    # Step 2: Check and install Google Compute Engine SSH
    Write-Host "[2/6] Checking Google Compute Engine SSH..." -ForegroundColor Yellow

    if (-not $SkipInstallCheck) {
        if (-not (Test-GoogetPackageInstalled -PackageName "google-compute-engine-ssh")) {
            Write-Host "  Installing google-compute-engine-ssh..." -ForegroundColor Gray
            googet -noconfirm=true install google-compute-engine-ssh
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to install google-compute-engine-ssh"
            }
            Write-Host "  ✓ Installed google-compute-engine-ssh" -ForegroundColor Green
        } else {
            Write-Host "  ✓ google-compute-engine-ssh is already installed" -ForegroundColor Green
        }
    } else {
        Write-Host "  Skipping install check (SkipInstallCheck specified)" -ForegroundColor Gray
    }

    # Step 3: Verify PowerShell 7+ is installed
    Write-Host "[3/6] Verifying PowerShell 7+ installation..." -ForegroundColor Yellow

    if (-not (Test-PowerShellInstalled -Path $PowerShellPath)) {
        throw "PowerShell 7+ (pwsh.exe) not found at $PowerShellPath or in PATH. Please install PowerShell 7+ first."
    }

    $PowerShellPath = (Get-Command pwsh.exe -ErrorAction Stop).Source
    Write-Host "  ✓ Found PowerShell at: $PowerShellPath" -ForegroundColor Green

    # Step 4: Configure SSH DefaultShell registry entry
    Write-Host "[4/6] Configuring SSH DefaultShell registry entry..." -ForegroundColor Yellow

    $regPath = "HKLM:\SOFTWARE\OpenSSH"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
        Write-Host "  Created registry path: $regPath" -ForegroundColor Gray
    }

    try {
        $currentValue = Get-ItemProperty -Path $regPath -Name DefaultShell -ErrorAction SilentlyContinue
        if ($currentValue -and $currentValue.DefaultShell -eq $PowerShellPath) {
            Write-Host "  ✓ DefaultShell already set correctly" -ForegroundColor Green
        } else {
            New-ItemProperty -Path $regPath -Name DefaultShell -Value $PowerShellPath -PropertyType String -Force | Out-Null
            Write-Host "  ✓ Set DefaultShell to: $PowerShellPath" -ForegroundColor Green
        }
    } catch {
        throw "Failed to set DefaultShell registry value: $_"
    }

    # Step 5: Configure sshd_config file
    Write-Host "[5/6] Configuring sshd_config..." -ForegroundColor Yellow

    $sshdConfigPath = "C:\ProgramData\ssh\sshd_config"

    if (-not (Test-Path $sshdConfigPath)) {
        throw "sshd_config file not found at $sshdConfigPath. SSH may not be properly installed."
    }

    # Backup the original config
    $backupPath = "$sshdConfigPath.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item $sshdConfigPath $backupPath -Force
    Write-Host "  Created backup: $backupPath" -ForegroundColor Gray

    # Prepare the settings we need to add/update
    $settingsToAdd = @{
        'PasswordAuthentication' = 'yes'
        'PubkeyAuthentication' = 'yes'
    }

    # Process each setting
    $lines = Get-Content $sshdConfigPath
    $newLines = @()
    $settingsFound = @{}

    foreach ($line in $lines) {
        $trimmedLine = $line.Trim()
        
        # Check if this line is a setting we care about
        $matched = $false
        foreach ($key in $settingsToAdd.Keys) {
            if ($trimmedLine -match "^$key\s+") {
                $matched = $true
                $settingsFound[$key] = $true
                # Replace with our value
                $newLines += "$key $($settingsToAdd[$key])"
                Write-Host "  Updated: $key = $($settingsToAdd[$key])" -ForegroundColor Gray
                break
            }
        }
        
        if (-not $matched) {
            $newLines += $line
        }
    }

    # Add any settings that weren't found
    foreach ($key in $settingsToAdd.Keys) {
        if (-not $settingsFound[$key]) {
            $newLines += "$key $($settingsToAdd[$key])"
            Write-Host "  Added: $key = $($settingsToAdd[$key])" -ForegroundColor Gray
        }
    }

    # Write the updated config
    $newLines | Set-Content $sshdConfigPath -Encoding UTF8
    Write-Host "  ✓ Updated sshd_config" -ForegroundColor Green

    # Step 6: Restart SSH service
    Write-Host ""
    Write-Host "[6/6] Restarting SSH service..." -ForegroundColor Yellow

    try {
        $sshdService = Get-Service sshd -ErrorAction Stop
        if ($sshdService.Status -eq 'Running') {
            Restart-Service sshd -Force
            Write-Host "  ✓ SSH service restarted successfully" -ForegroundColor Green
        } else {
            Start-Service sshd
            Write-Host "  ✓ SSH service started successfully" -ForegroundColor Green
        }
        
        # Verify service is running
        Start-Sleep -Seconds 2
        $sshdService = Get-Service sshd
        if ($sshdService.Status -eq 'Running') {
            Write-Host "  ✓ SSH service is running" -ForegroundColor Green
        } else {
            Write-Warning "  SSH service is not running. Status: $($sshdService.Status)"
        }
    } catch {
        Write-Error "Failed to restart SSH service: $_"
        Write-Host "  You may need to manually restart the service or check the configuration." -ForegroundColor Yellow
        throw
    }

    Write-Host ""
    Write-Host "=== Configuration Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Summary:" -ForegroundColor Cyan
    Write-Host "  - SSH server configured with PowerShell as default shell" -ForegroundColor White
    Write-Host "  - PasswordAuthentication: Enabled" -ForegroundColor White
    Write-Host "  - PubkeyAuthentication: Enabled" -ForegroundColor White
    Write-Host ""
    Write-Host "You can now connect via SSH using:" -ForegroundColor Cyan
    Write-Host "  ssh username@vm-ip-address" -ForegroundColor White
    Write-Host ""

}

