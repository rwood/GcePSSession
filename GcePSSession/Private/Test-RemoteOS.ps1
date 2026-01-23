function Test-RemoteOS {
    <#
    .SYNOPSIS
        Detects whether the remote SSH server is running Windows or Linux.

    .DESCRIPTION
        Performs a quick SSH probe to determine the operating system of the remote server.
        Uses the 'uname -s' command which returns 'Linux' on Linux systems and fails on Windows.
        The fallback 'echo Windows' handles the Windows case.

        This function strips domain information from the username for the probe, as Linux
        servers typically don't accept domain-qualified usernames (DOMAIN\user or user@domain).

    .PARAMETER Port
        The local port of the SSH tunnel to probe.

    .PARAMETER KeyFilePath
        Path to the SSH private key file for authentication.

    .PARAMETER UserName
        The username to use for the probe. Domain prefixes/suffixes will be stripped.

    .OUTPUTS
        [string] Returns "Linux" or "Windows"

    .EXAMPLE
        $os = Test-RemoteOS -Port 22841 -KeyFilePath "C:\Users\me\.ssh\mykey" -UserName "DOMAIN\user"
        # Returns "Linux" or "Windows"

    .NOTES
        - Returns "Windows" if the probe fails or times out (safe default for domain auth)
        - Uses BatchMode to prevent interactive prompts
        - 5 second timeout to avoid hanging
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port,

        [Parameter(Mandatory = $true)]
        [string]$KeyFilePath,

        [Parameter(Mandatory = $true)]
        [string]$UserName
    )

    # Strip domain from username for the probe
    # Linux servers typically don't accept DOMAIN\user or user@domain format
    $probeUser = $UserName
    if ($probeUser -match '\\') {
        $probeUser = ($probeUser -split '\\')[-1]
    } elseif ($probeUser -match '@') {
        $probeUser = ($probeUser -split '@')[0]
    }

    Write-Verbose "$(Get-Date): [Test-RemoteOS]: Probing remote OS using username '$probeUser' on port $Port"

    $sshArgs = @(
        "-p", $Port,
        "-i", $KeyFilePath,
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "$probeUser@localhost",
        "uname -s 2>/dev/null || echo Windows"
    )

    try {
        $result = & ssh @sshArgs 2>$null
        
        if ($result -match "Linux") {
            Write-Verbose "$(Get-Date): [Test-RemoteOS]: Detected Linux (uname returned 'Linux')"
            return "Linux"
        } elseif ($result -match "Windows") {
            Write-Verbose "$(Get-Date): [Test-RemoteOS]: Detected Windows (uname failed, fallback executed)"
            return "Windows"
        } else {
            # Blank or unexpected result - auth may have failed with stripped username
            # Default to Windows which uses domain authentication
            Write-Verbose "$(Get-Date): [Test-RemoteOS]: Probe returned unexpected result '$result', defaulting to Windows"
            return "Windows"
        }
    } catch {
        Write-Verbose "$(Get-Date): [Test-RemoteOS]: Probe failed with error: $_, defaulting to Windows"
        return "Windows"  # Default to Windows behavior on error
    }
}
