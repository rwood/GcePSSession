function Set-GcePSSession {

    #Requires -Version 3.0

    <#
    
    .SYNOPSIS
    
        Sets default values for KeyFilePath and UserName in the GcePSSession configuration file.
    
    .DESCRIPTION
    
        Updates the GcePSSession configuration file ($env:USERPROFILE\.GcePSSession.json) with
        default values for KeyFilePath and UserName. These values will be used by New-GcePSSession
        when the corresponding parameters are not provided.
        
        If the configuration file does not exist, it will be created and marked as hidden.
        Only the parameters provided will be updated; existing values for other parameters
        will be preserved.
    
    .PARAMETER KeyFilePath
    
        Path to SSH private key file for authentication. This will be used as the default
        KeyFilePath when calling New-GcePSSession without specifying the parameter.
    
    .PARAMETER UserName
    
        Username for SSH authentication. This will be used as the default UserName when
        calling New-GcePSSession without specifying the parameter.
    
    .EXAMPLE
    
        Set-GcePSSession -KeyFilePath "C:\Users\me\.ssh\mykey" -UserName "domain\user"
        
        Sets both KeyFilePath and UserName in the configuration file.
    
    .EXAMPLE
    
        Set-GcePSSession -KeyFilePath "C:\Users\me\.ssh\mykey"
        
        Updates only the KeyFilePath in the configuration file, leaving UserName unchanged.
    
    .EXAMPLE
    
        Set-GcePSSession -UserName "domain\user"
        
        Updates only the UserName in the configuration file, leaving KeyFilePath unchanged.
    
    .NOTES
    
        The configuration file is stored at $env:USERPROFILE\.GcePSSession.json and is
        created as a hidden file. If the file already exists, only the specified parameters
        will be updated while preserving other configuration values.
    
    #>

    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Low')]
    param(
        [Parameter(Mandatory=$false)]
        [string]$KeyFilePath,
        
        [Parameter(Mandatory=$false)]
        [string]$UserName
    )

    $ErrorActionPreference = 'Stop'
    $configFilePath = Join-Path $env:USERPROFILE ".GcePSSession.json"

    try {
        # Load existing config if it exists
        $config = @{}
        if (Test-Path $configFilePath) {
            try {
                $existingContent = Get-Content -Path $configFilePath -Raw -ErrorAction Stop
                $configObject = $existingContent | ConvertFrom-Json
                # Convert PSCustomObject to hashtable
                if ($configObject) {
                    $configObject.PSObject.Properties | ForEach-Object {
                        $config[$_.Name] = $_.Value
                    }
                }
                Write-Verbose "Loaded existing configuration from $configFilePath"
            } catch {
                Write-Warning "Failed to parse existing configuration file. Creating new configuration."
                $config = @{}
            }
        } else {
            Write-Verbose "Configuration file does not exist. Creating new file."
        }

        # Update config with provided parameters
        $changes = @()
        if ($PSBoundParameters.ContainsKey('KeyFilePath')) {
            $config['KeyFilePath'] = $KeyFilePath
            $changes += "KeyFilePath = '$KeyFilePath'"
        }
        
        if ($PSBoundParameters.ContainsKey('UserName')) {
            $config['UserName'] = $UserName
            $changes += "UserName = '$UserName'"
        }

        if ($changes.Count -eq 0) {
            Write-Warning "No parameters provided. Nothing to update."
            return
        }

        $changeDescription = $changes -join ', '
        
        if ($PSCmdlet.ShouldProcess($configFilePath, "Update configuration: $changeDescription")) {
            # Convert hashtable to JSON
            $jsonContent = $config | ConvertTo-Json -Depth 10
            
            # Write the file
            Set-Content -Path $configFilePath -Value $jsonContent -Encoding UTF8 -ErrorAction Stop
            
            # Make the file hidden if it doesn't already have the hidden attribute
            try {
                $file = Get-Item -Path $configFilePath -Force -ErrorAction Stop
                if (($file.Attributes -band [System.IO.FileAttributes]::Hidden) -eq 0) {
                    $file.Attributes = $file.Attributes -bor [System.IO.FileAttributes]::Hidden
                    Write-Verbose "Set hidden attribute on configuration file"
                }
            } catch {
                Write-Warning "Could not set hidden attribute on configuration file: $_"
            }
            
            Write-Verbose "Successfully updated configuration file: $configFilePath"
            Write-Host "Configuration updated successfully." -ForegroundColor Green
        }

    } catch {
        Write-Error "Failed to update configuration file: $_"
    }
}

