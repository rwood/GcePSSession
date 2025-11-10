# Check if running in PowerShell Core (pwsh) or Windows PowerShell
$isPowerShellCore = ($PSVersionTable.PSEdition -eq 'Core') -or ($PSVersionTable.PSVersion.Major -ge 6)

if (-not $isPowerShellCore) {
    Write-Warning "This script is designed to run in PowerShell Core (pwsh)."
    Write-Host "Current PowerShell version: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
    Write-Host "Attempting to launch with pwsh..." -ForegroundColor Yellow
    
    # Try to launch with pwsh if available
    if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
        Write-Host "Found pwsh.exe, relaunching script..." -ForegroundColor Green
        & pwsh.exe -File $MyInvocation.MyCommand.Path
        exit
    } else {
        Write-Error "pwsh.exe not found. Please install PowerShell Core or run this script with pwsh.exe"
        exit 1
    }
}

Write-Host "Running in PowerShell Core (pwsh) - Version $($PSVersionTable.PSVersion)" -ForegroundColor Green

choco upgrade -y powershell-core -Force
Invoke-WebRequest -Uri https://raw.githubusercontent.com/rwood/GcePSSession/refs/heads/main/Install-GceWindowsSsh.ps1 -OutFile Install-GceWindowsSsh.ps1
.\Install-GceWindowsSsh.ps1