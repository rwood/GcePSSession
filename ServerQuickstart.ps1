if($PSVersionTable.PSEdition -eq 'Core'){
    Write-Error "This script should not be run in PowerShell Core (pwsh)."
    exit 1
}

$env:ChocolateyInstall = Convert-Path "$((Get-Command choco).Path)\..\.."   
Import-Module "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"

# Upgrade to powershell-core
choco upgrade -y powershell-core -Force

Update-SessionEnvironment

$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if(-not $pwsh){
    Write-Error "pwsh.exe not found. Please install PowerShell Core"
    exit 1
}

Invoke-WebRequest -Uri https://raw.githubusercontent.com/rwood/GcePSSession/refs/heads/main/Install-GceWindowsSsh.ps1 -OutFile Install-GceWindowsSsh.ps1
pwsh -File .\Install-GceWindowsSsh.ps1
Remove-Item -Path Install-GceWindowsSsh.ps1