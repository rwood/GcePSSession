<#
.SYNOPSIS
    Initializes GcePSSession by checking prerequisites and creating configuration.

.DESCRIPTION
    This script initializes the GcePSSession module by:
    1. Checking for PowerShell Core (pwsh) version 7.5 or greater
    2. Offering to install pwsh via MSI installer if not found
    3. Creating SSH key pair if needed
    4. Creating configuration file (.GcePSSession.json) with default credentials

.PARAMETER Domain
    Domain name for the remote PSSession account. If not provided, will be prompted.

.PARAMETER UserName
    Username for the remote PSSession account. If not provided, will be prompted.

.PARAMETER Force
    Force re-creation of SSH key and configuration file even if they exist.

.EXAMPLE
    .\Initialize-GcePSSession.ps1
    
    Interactive initialization - will prompt for domain and username.

.EXAMPLE
    .\Initialize-GcePSSession.ps1 -Domain "mydomain" -UserName "jdoe"
    
    Non-interactive initialization with provided credentials.

.NOTES
    Requires Administrator privileges to install PowerShell Core.
    The SSH key will be created at $env:USERPROFILE\.ssh\gcepssession
    The configuration file will be created at $env:USERPROFILE\.GcePSSession.json
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$false)]
    [string]$Domain,
    
    [Parameter(Mandatory=$false)]
    [string]$UserName,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Function to check PowerShell Core version
function Test-PowerShellCore {
    param([version]$MinimumVersion = [version]"7.5")
    
    $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if (-not $pwsh) {
        return $false
    }
    
    try {
        $versionOutput = & pwsh.exe -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
        $version = [version]$versionOutput
        return $version -ge $MinimumVersion
    } catch {
        return $false
    }
}

# Function to get latest PowerShell Core download URL
function Get-PowerShellCoreDownloadUrl {
    try {
        # Get the latest stable release from GitHub API
        $releasesUrl = "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
        $release = Invoke-RestMethod -Uri $releasesUrl -UseBasicParsing
        
        # Find the Windows x64 MSI asset
        $msiAsset = $release.assets | Where-Object { 
            $_.name -match '\.msi$' -and $_.name -match 'win-x64'
        } | Select-Object -First 1
        
        if ($msiAsset) {
            return $msiAsset.browser_download_url
        }
        
        # Fallback: construct URL from tag name
        $tagName = $release.tag_name -replace '^v', ''
        $version = [version]$tagName
        $msiUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$tagName/PowerShell-$tagName-win-x64.msi"
        return $msiUrl
    } catch {
        Write-Warning "Failed to get latest PowerShell release info: $_"
        # Fallback to a known stable version
        return "https://github.com/PowerShell/PowerShell/releases/download/v7.5.0/PowerShell-7.5.0-win-x64.msi"
    }
}

# Function to install PowerShell Core via MSI
function Install-PowerShellCore {
    Write-Host "Installing PowerShell Core (pwsh)..." -ForegroundColor Yellow
    
    # Check if running as Administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Error "Administrator privileges are required to install PowerShell Core. Please run this script as Administrator."
        return $false
    }
    
    try {
        # Get download URL
        Write-Host "  Fetching latest PowerShell Core download URL..." -ForegroundColor Gray
        $downloadUrl = Get-PowerShellCoreDownloadUrl
        Write-Host "  Download URL: $downloadUrl" -ForegroundColor Gray
        
        # Create temp directory
        $tempDir = Join-Path $env:TEMP "GcePSSession-Init"
        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }
        
        # Download MSI
        $msiPath = Join-Path $tempDir "PowerShell.msi"
        Write-Host "  Downloading PowerShell Core MSI..." -ForegroundColor Gray
        Invoke-WebRequest -Uri $downloadUrl -OutFile $msiPath -UseBasicParsing
        
        if (-not (Test-Path $msiPath)) {
            Write-Error "Failed to download PowerShell Core MSI."
            return $false
        }
        
        # Install MSI silently
        Write-Host "  Installing PowerShell Core (this may take a few minutes)..." -ForegroundColor Gray
        $installArgs = @(
            "/i",
            "`"$msiPath`"",
            "/quiet",
            "/norestart",
            "ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1",
            "ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1",
            "ENABLE_PSREMOTING=1",
            "ADD_PATH=1",
            "REGISTER_MANIFEST=1"
        )
        
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
            Write-Error "MSI installation failed with exit code: $($process.ExitCode)"
            return $false
        }
        
        # Clean up downloaded file
        Remove-Item -Path $msiPath -Force -ErrorAction SilentlyContinue
        
        # Refresh PATH environment variable
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        # Wait a moment for PATH to propagate
        Start-Sleep -Seconds 2
        
        # Verify installation
        $pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
        if ($pwsh) {
            if (Test-PowerShellCore) {
                Write-Host "  PowerShell Core installed successfully." -ForegroundColor Green
                return $true
            } else {
                Write-Warning "PowerShell Core installed but version check failed. You may need to restart your terminal."
                return $false
            }
        } else {
            Write-Warning "PowerShell Core installation completed, but pwsh.exe not found in PATH. You may need to restart your terminal."
            return $false
        }
    } catch {
        Write-Error "Failed to install PowerShell Core: $_"
        return $false
    }
}

# Function to create SSH key
function New-SshKey {
    param(
        [Parameter(Mandatory=$true)]
        [string]$KeyPath,
        
        [Parameter(Mandatory=$true)]
        [string]$Comment
    )
    
    $sshKeygen = Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue
    if (-not $sshKeygen) {
        Write-Error "ssh-keygen.exe not found. Please install OpenSSH client."
        return $false
    }
    
    # Ensure .ssh directory exists
    $sshDir = Split-Path -Path $KeyPath -Parent
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        Write-Verbose "Created .ssh directory: $sshDir"
    }
    
    # Check if key already exists
    if ((Test-Path $KeyPath) -and -not $Force) {
        Write-Warning "SSH key already exists at $KeyPath. Use -Force to overwrite."
        return $true
    }
    
    try {
        Write-Host "Generating SSH key pair..." -ForegroundColor Yellow
        & ssh-keygen.exe -t rsa -f $KeyPath -C $Comment -N '""' -q
        
        if (Test-Path $KeyPath) {
            Write-Host "  SSH key created successfully at $KeyPath" -ForegroundColor Green
            return $true
        } else {
            Write-Error "SSH key generation failed."
            return $false
        }
    } catch {
        Write-Error "Failed to generate SSH key: $_"
        return $false
    }
}

# Main script logic
Write-Host "=== GcePSSession Initialization ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check for PowerShell Core
Write-Host "[1/3] Checking for PowerShell Core (pwsh) 7.5+..." -ForegroundColor Yellow
$hasPowerShellCore = Test-PowerShellCore

if (-not $hasPowerShellCore) {
    Write-Warning "PowerShell Core (pwsh) version 7.5 or greater is required but not found."
    
    if ($PSCmdlet.ShouldProcess("PowerShell Core", "Install via MSI installer")) {
        $response = Read-Host "Would you like to install PowerShell Core now? (Y/N)"
        if ($response -match '^[Yy]') {
            if (-not (Install-PowerShellCore)) {
                Write-Error "PowerShell Core installation failed. Please install manually from https://aka.ms/powershell and run this script again."
                exit 1
            }
            $hasPowerShellCore = Test-PowerShellCore
        } else {
            Write-Host "Installation cancelled. Please install PowerShell Core manually from https://aka.ms/powershell and run this script again." -ForegroundColor Yellow
            exit 0
        }
    }
}

if (-not $hasPowerShellCore) {
    Write-Error "PowerShell Core (pwsh) 7.5+ is required but not available."
    Write-Host "Please install PowerShell Core from: https://aka.ms/powershell" -ForegroundColor Yellow
    exit 1
}

$pwshVersion = & pwsh.exe -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
Write-Host "  ✓ PowerShell Core $pwshVersion found" -ForegroundColor Green
Write-Host ""

# Step 2: Check for configuration file
Write-Host "[2/3] Checking for configuration file..." -ForegroundColor Yellow
$configFilePath = Join-Path $env:USERPROFILE ".GcePSSession.json"

if ((Test-Path $configFilePath) -and -not $Force) {
    Write-Host "  ✓ Configuration file already exists at $configFilePath" -ForegroundColor Green
    Write-Host "    Use -Force to recreate it." -ForegroundColor Gray
    Write-Host ""
    
    # Still need to check SSH key
    $sshKeyPath = Join-Path $env:USERPROFILE ".ssh\gcepssession"
    if (-not (Test-Path $sshKeyPath)) {
        Write-Host "[3/3] SSH key not found. Creating..." -ForegroundColor Yellow
        
        # Get domain and username from existing config or prompt
        if (-not $Domain -or -not $UserName) {
            try {
                $existingConfig = Get-Content -Path $configFilePath -Raw | ConvertFrom-Json
                if ($existingConfig.UserName -match '^(.+)\\(.+)$') {
                    $Domain = $matches[1]
                    $UserName = $matches[2]
                    Write-Host "  Using domain and username from existing config: $Domain\$UserName" -ForegroundColor Gray
                }
            } catch {
                # Config exists but couldn't parse it, will prompt below
            }
        }
        
        if (-not $Domain) {
            $Domain = Read-Host "Enter domain name for remote PSSession account"
        }
        if (-not $UserName) {
            $UserName = Read-Host "Enter username for remote PSSession account"
        }
        
        $comment = "$Domain\$UserName"
        if (New-SshKey -KeyPath $sshKeyPath -Comment $comment) {
            Write-Host "  ✓ SSH key created" -ForegroundColor Green
        } else {
            Write-Error "Failed to create SSH key."
            exit 1
        }
    } else {
        Write-Host "  ✓ SSH key already exists" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Initialization complete!" -ForegroundColor Green
    exit 0
}

# Step 3: Prompt for credentials if not provided
Write-Host "[3/3] Setting up configuration..." -ForegroundColor Yellow

if (-not $Domain) {
    $Domain = Read-Host "Enter domain name for remote PSSession account"
    if ([string]::IsNullOrWhiteSpace($Domain)) {
        Write-Error "Domain name is required."
        exit 1
    }
}

if (-not $UserName) {
    $UserName = Read-Host "Enter username for remote PSSession account"
    if ([string]::IsNullOrWhiteSpace($UserName)) {
        Write-Error "Username is required."
        exit 1
    }
}

# Create SSH key
$sshKeyPath = Join-Path $env:USERPROFILE ".ssh\gcepssession"
$comment = "$Domain\$UserName"

Write-Host "Creating SSH key pair..." -ForegroundColor Yellow
if (-not (New-SshKey -KeyPath $sshKeyPath -Comment $comment)) {
    Write-Error "Failed to create SSH key."
    exit 1
}

# Create configuration file
Write-Host "Creating configuration file..." -ForegroundColor Yellow
$config = @{
    KeyFilePath = $sshKeyPath
    UserName    = "$Domain\$UserName"
}

$jsonContent = $config | ConvertTo-Json -Depth 10

if ($PSCmdlet.ShouldProcess($configFilePath, "Create configuration file")) {
    try {
        Set-Content -Path $configFilePath -Value $jsonContent -Encoding UTF8 -ErrorAction Stop
        
        # Make the file hidden
        try {
            $file = Get-Item -Path $configFilePath -Force -ErrorAction Stop
            if (($file.Attributes -band [System.IO.FileAttributes]::Hidden) -eq 0) {
                $file.Attributes = $file.Attributes -bor [System.IO.FileAttributes]::Hidden
            }
        } catch {
            Write-Warning "Could not set hidden attribute on configuration file: $_"
        }
        
        Write-Host "  ✓ Configuration file created at $configFilePath" -ForegroundColor Green
    } catch {
        Write-Error "Failed to create configuration file: $_"
        exit 1
    }
}

Write-Host ""
Write-Host "=== Initialization Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  SSH Key: $sshKeyPath" -ForegroundColor Gray
Write-Host "  Username: $Domain\$UserName" -ForegroundColor Gray
Write-Host "  Config File: $configFilePath" -ForegroundColor Gray
Write-Host ""
Write-Host "You can now use New-GcePSSession without specifying -KeyFilePath and -UserName." -ForegroundColor Green
Write-Host "To update these values, use: Set-GcePSSession" -ForegroundColor Gray

