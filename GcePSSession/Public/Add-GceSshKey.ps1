function Add-GceSshKey {

    <#

    .SYNOPSIS

        Adds an SSH public key to GCP project metadata and optionally creates a local Windows user on a VM.

    .DESCRIPTION

        Adds your SSH public key to GCP project metadata in the 'ssh-keys' metadata field so the
        GCE guest agent can create a local user and install the key on Windows VMs (requires
        enable-windows-ssh=TRUE and the google-compute-engine-ssh package on the VM).

        Existing project ssh-keys are preserved; the new key is appended. If the user's key already
        exists in project metadata, the function skips the metadata update.

        When -InstanceName and -Zone are provided, the function first calls
        gcloud compute reset-windows-password to ensure the Windows user account exists on that VM.
        Use -SkipResetPassword to skip this step if the user already exists.

    .PARAMETER Project

        The GCP project ID to add the SSH key to. Required.

    .PARAMETER UserName

        The username for the local Windows account. This will be both the SSH username and the
        local account name created by the guest agent.

    .PARAMETER PublicKeyPath

        Path to the SSH public key file. Defaults to $env:USERPROFILE\.ssh\gce_windows.pub.

    .PARAMETER InstanceName

        Optional. The GCE VM instance name to create/reset the Windows user on via
        gcloud compute reset-windows-password. If not provided, only the project metadata
        is updated (the guest agent will create the user when it syncs metadata).

    .PARAMETER Zone

        The GCE zone of the VM instance. Required when InstanceName is provided.

    .PARAMETER SkipResetPassword

        Skip the gcloud compute reset-windows-password step. Use this if the user account
        already exists on the VM and you only need to update the SSH key in project metadata.

    .PARAMETER GcloudPath

        Path to gcloud CLI executable. Defaults to 'gcloud'.

    .EXAMPLE

        Add-GceSshKey -Project "scs-d-sprocket" -UserName "rwood-gce"

        Adds the default public key to project metadata. The guest agent on Windows VMs
        with enable-windows-ssh=TRUE will create the user and install the key.

    .EXAMPLE

        Add-GceSshKey -Project "scs-d-sprocket" -UserName "rwood-gce" -InstanceName "usc1sprwebp01" -Zone "us-central1-a"

        Creates the Windows user on the VM (via reset-windows-password), then adds the
        SSH key to project metadata.

    .EXAMPLE

        Add-GceSshKey -Project "scs-d-sprocket" -UserName "rwood-gce" -PublicKeyPath "$env:USERPROFILE\.ssh\id_ed25519.pub"

        Uses a custom public key file path.

    .EXAMPLE

        Add-GceSshKey -Project "scs-d-sprocket" -UserName "rwood-gce" -InstanceName "usc1sprwebp01" -Zone "us-central1-a" -SkipResetPassword

        Skips password reset (user already exists) and only updates project metadata.

    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $false)]
        [string]$PublicKeyPath = "$env:USERPROFILE\.ssh\gce_windows.pub",

        [Parameter(Mandatory = $false)]
        [string]$InstanceName,

        [Parameter(Mandatory = $false)]
        [string]$Zone,

        [Parameter(Mandatory = $false)]
        [switch]$SkipResetPassword,

        [Parameter(Mandatory = $false)]
        [string]$GcloudPath = 'gcloud'
    )

    $ErrorActionPreference = "Stop"

    if (-not (Test-Path $PublicKeyPath)) {
        throw "Public key not found: $PublicKeyPath. Generate one with: ssh-keygen -t ed25519 -f `"$($PublicKeyPath -replace '\.pub$','')`" -C `"$UserName`""
    }

    # Step 1: Optionally create/reset the Windows user on a specific VM
    if ($InstanceName -and -not $SkipResetPassword) {
        if (-not $Zone) {
            throw "Zone parameter is required when InstanceName is provided."
        }
        Write-Verbose "$(Get-Date): [Add-GceSshKey]: Creating/resetting Windows user [$UserName] on $InstanceName"
        Write-Host "Creating/resetting Windows user [$UserName] on $InstanceName..."
        & $GcloudPath compute reset-windows-password $InstanceName --project $Project --zone $Zone --user $UserName --quiet
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create/reset Windows user [$UserName] on $InstanceName (exit code: $LASTEXITCODE)"
        }
    }

    # Step 2: Read current project ssh-keys
    Write-Verbose "$(Get-Date): [Add-GceSshKey]: Reading current project ssh-keys from $Project"
    $jsonOutput = & $GcloudPath compute project-info describe --project=$Project --format=json 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to describe project $Project (exit code: $LASTEXITCODE)"
    }
    $projectInfo = $jsonOutput | ConvertFrom-Json
    $currentKeys = ($projectInfo.commonInstanceMetadata.items | Where-Object { $_.key -eq 'ssh-keys' }).value
    if (-not $currentKeys) { $currentKeys = "" }

    # Step 3: Build new key line in GCE format: username:key-type key-data comment
    $pubLine = (Get-Content $PublicKeyPath -Raw).Trim()
    $newLine = "$UserName`:$pubLine"

    # Check if this exact key line already exists
    if ($currentKeys -and $currentKeys -match [regex]::Escape("$UserName`:$pubLine")) {
        Write-Host "SSH key for [$UserName] already exists in project [$Project] metadata. Skipping update."
        Write-Verbose "$(Get-Date): [Add-GceSshKey]: Key already present, no metadata update needed"
        return
    }

    $allKeys = if ($currentKeys) { "$currentKeys`n$newLine" } else { $newLine }

    # Step 4: Write to temp file and update metadata (avoids shell quoting issues with multi-line values)
    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $tempFile -Value $allKeys -NoNewline -Encoding UTF8
        Write-Verbose "$(Get-Date): [Add-GceSshKey]: Wrote ssh-keys to temp file: $tempFile"
        Write-Host "Adding SSH key for [$UserName] to project [$Project] metadata..."
        & $GcloudPath compute project-info add-metadata --project=$Project --metadata-from-file="ssh-keys=$tempFile"
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to update project metadata (exit code: $LASTEXITCODE)"
        }
        Write-Host "Done. Guest agent on Windows VMs (with enable-windows-ssh=TRUE) will create/update user [$UserName] and install the key."
    } finally {
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
    }
}
