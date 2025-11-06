function Invoke-GceCommandAs {

    #Requires -Version 3.0

    <#
    
    .SYNOPSIS
    
        Invoke Command on Google Cloud Engine (GCE) VM instances using IAP Tunnel.
    
    .DESCRIPTION
    
        Invoke Command on GCE VM instances using Identity-Aware Proxy (IAP) Tunnel.
        This function creates an IAP tunnel to the specified GCE VM instance and executes
        PowerShell commands remotely through the tunnel.
        
        Requires Google Cloud SDK (gcloud CLI) to be installed and configured.
        The user must have appropriate IAP permissions for the target VM instance.
    
    .PARAMETER Project
    
        The GCP project ID that contains the VM instance.
    
    .PARAMETER Zone
    
        The GCE zone where the VM instance is located.
    
    .PARAMETER InstanceName
    
        The name of the GCE VM instance.
    
    .PARAMETER ScriptBlock
    
        The PowerShell script block to execute on the remote VM.
    
    .PARAMETER FilePath
    
        Path to a PowerShell script file to execute on the remote VM.
    
    .PARAMETER ArgumentList
    
        Arguments to pass to the script block.
    
    .PARAMETER Credential
    
        Optional PSCredential for SSH authentication to the VM.
        If not provided, will use default SSH credentials.
    
    .PARAMETER LocalPort
    
        Local port to use for the IAP tunnel. Defaults to an available port.
    
    .PARAMETER RemotePort
    
        Remote port on the VM (default: 22 for SSH).
    
    .PARAMETER GcloudPath
    
        Path to gcloud CLI executable. Defaults to 'gcloud'.
    
    .PARAMETER AsJob
    
        Run the command as a background job.
    
    .PARAMETER ThrottleLimit
    
        Maximum number of concurrent connections. Defaults to 32.
    
    .EXAMPLE
    
        Invoke-GceCommandAs -Project "my-project" -Zone "us-central1-a" -InstanceName "my-vm" -ScriptBlock { Get-Process }
    
    .EXAMPLE
    
        Invoke-GceCommandAs -Project "my-project" -Zone "us-central1-a" -InstanceName "my-vm" -ScriptBlock { Get-Process } -Credential $Credential
    
    .EXAMPLE
    
        Invoke-GceCommandAs -Project "my-project" -Zone "us-central1-a" -InstanceName "my-vm" -FilePath "C:\Scripts\MyScript.ps1"
    
    #>

    #Requires -Version 3

    [CmdletBinding(DefaultParameterSetName='ScriptBlock', HelpUri='http://go.microsoft.com/fwlink/?LinkID=135225', RemotingCapability='OwnedByCommand')]
    param(
        [Parameter(ParameterSetName='ScriptBlock', Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
        [Parameter(ParameterSetName='FilePath', Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        ${Project},
    
        [Parameter(ParameterSetName='ScriptBlock', Mandatory=$true, Position=1, ValueFromPipelineByPropertyName=$true)]
        [Parameter(ParameterSetName='FilePath', Mandatory=$true, Position=1, ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        ${Zone},
    
        [Parameter(ParameterSetName='ScriptBlock', Mandatory=$true, Position=2, ValueFromPipelineByPropertyName=$true)]
        [Parameter(ParameterSetName='FilePath', Mandatory=$true, Position=2, ValueFromPipelineByPropertyName=$true)]
        [Alias('Instance')]
        [ValidateNotNullOrEmpty()]
        [string]
        ${InstanceName},
    
        [Parameter(ParameterSetName='ScriptBlock', Mandatory=$true, Position=3)]
        [Alias('Command')]
        [ValidateNotNull()]
        [scriptblock]
        ${ScriptBlock},
    
        [Parameter(ParameterSetName='FilePath', Mandatory=$true, Position=3)]
        [Alias('PSPath')]
        [ValidateNotNull()]
        [string]
        ${FilePath},
    
        [Parameter(ValueFromPipeline=$true)]
        [psobject]
        ${InputObject},
    
        [Alias('Args')]
        [System.Object[]]
        ${ArgumentList},
    
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [pscredential]
        [System.Management.Automation.CredentialAttribute()]
        ${Credential},
    
        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]
        ${LocalPort} = 0,
    
        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]
        ${RemotePort} = 22,
    
        [Parameter()]
        [string]
        ${GcloudPath} = 'gcloud',
    
        [Parameter()]
        [switch]
        ${AsJob},
    
        [Parameter()]
        [int]
        ${ThrottleLimit} = 32

    )

    Process {

        $IsVerbose = $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent

        # Handle FilePath parameter
        If ($FilePath) { 
            $ScriptContent = Get-Content -Path $FilePath -Raw
            $ScriptBlock = [ScriptBlock]::Create($ScriptContent)
        }

        # Prepare parameters for Invoke-GceIapTunnel
        $IapTunnelParams = @{
            Project = $Project
            Zone = $Zone
            InstanceName = $InstanceName
            ScriptBlock = $ScriptBlock
            GcloudPath = $GcloudPath
            LocalPort = $LocalPort
            RemotePort = $RemotePort
        }

        If ($ArgumentList) {
            $IapTunnelParams['ArgumentList'] = $ArgumentList
        }

        If ($Credential) {
            $IapTunnelParams['Credential'] = $Credential
        }

        If ($IsVerbose) {
            $IapTunnelParams['Verbose'] = $true
        }

        # Handle $Using variables by serializing them into the script block
        $UsingVariables = $ScriptBlock.ast.FindAll({$args[0] -is [System.Management.Automation.Language.UsingExpressionAst]},$True)
        If ($UsingVariables) {
            Write-Verbose "$(Get-Date): [GceCommandAs]: Processing $Using variables"
            
            $ScriptText = $ScriptBlock.Ast.Extent.Text
            $ScriptOffSet = $ScriptBlock.Ast.Extent.StartOffset
            ForEach ($SubExpression in ($UsingVariables.SubExpression | Sort-Object { $_.Extent.StartOffset } -Descending)) {

                $Name = '__using_{0}' -f (([Guid]::NewGuid().guid) -Replace '-')
                $Expression = $SubExpression.Extent.Text.Replace('$Using:','$').Replace('${Using:','${'); 
                $Value = [System.Management.Automation.PSSerializer]::Serialize((Invoke-Expression $Expression))
                
                # Inject variable initialization at the beginning of the script
                $InitCode = "`$Using:$Name = [System.Management.Automation.PSSerializer]::Deserialize('$Value'); "
                $ScriptText = $InitCode + $ScriptText.Substring(0, ($SubExpression.Extent.StartOffSet - $ScriptOffSet)) + "`${Using:$Name}" + $ScriptText.Substring(($SubExpression.Extent.EndOffset - $ScriptOffSet))
                $ScriptOffSet = $ScriptBlock.Ast.Extent.StartOffset  # Reset offset after insertion

            }
            $ScriptBlock = [ScriptBlock]::Create($ScriptText.TrimStart("{").TrimEnd("}"))
            $IapTunnelParams['ScriptBlock'] = $ScriptBlock
        }

        Write-Verbose "$(Get-Date): [GceCommandAs]: Invoking command via IAP Tunnel"

        # Execute via IAP Tunnel
        Invoke-GceIapTunnel @IapTunnelParams

    }
    
}
