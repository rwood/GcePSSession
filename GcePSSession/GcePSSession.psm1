
#Get public and private function definition files.
$Public = @( Get-ChildItem -Path $PSScriptRoot\public\*.ps1 -Recurse -ErrorAction SilentlyContinue )
$Private = @( Get-ChildItem -Path $PSScriptRoot\private\*.ps1 -Recurse -ErrorAction SilentlyContinue )

#Dot source the files.
$LoadedFunctions = @()
Foreach ($import in @($Public + $Private)) {
    Try {
        . $import.fullname -ErrorAction Stop
        # Track successfully loaded public functions
        if ($Public -contains $import) {
            # Extract function name from file (remove .ps1 extension)
            $functionName = [System.IO.Path]::GetFileNameWithoutExtension($import.Name)
            # Verify the function actually exists before adding to export list
            if (Get-Command -Name $functionName -ErrorAction SilentlyContinue) {
                $LoadedFunctions += $functionName
            }
        }
    }
    Catch {
        Write-Warning "Failed to import function $($import.Name): $_"
    }
}

# Export only functions that were successfully loaded
# This ensures functions that fail due to #Requires directives aren't exported
if ($LoadedFunctions.Count -gt 0) {
    Export-ModuleMember -Function $LoadedFunctions
} else {
    Write-Warning "No functions were successfully loaded from the module."
}
