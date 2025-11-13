<#
.SYNOPSIS
    Build script for GcePSSession PowerShell module.

.DESCRIPTION
    This script prepares the GcePSSession module for publishing to PowerShell Gallery.
    It validates the module manifest, runs code analysis, and prepares the module package.

.PARAMETER Configuration
    Build configuration: Development or Production (default: Development)

.PARAMETER SkipAnalysis
    Skip PSScriptAnalyzer code analysis

.PARAMETER SkipTests
    Skip Pester tests (if they exist)

.EXAMPLE
    .\Build.ps1 -Configuration Production

.EXAMPLE
    .\Build.ps1 -SkipAnalysis
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Development', 'Production')]
    [string]$Configuration = 'Development',
    
    [Parameter()]
    [switch]$SkipAnalysis,
    
    [Parameter()]
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'

# Module information
$ModuleName = 'GcePSSession'
$ModulePath = Join-Path $PSScriptRoot $ModuleName
$ManifestPath = Join-Path $ModulePath "$ModuleName.psd1"

Write-Host "=== Building $ModuleName Module ===" -ForegroundColor Cyan
Write-Host "Configuration: $Configuration" -ForegroundColor Gray
Write-Host ""

# Step 1: Verify module structure exists
Write-Host "[1/6] Verifying module structure..." -ForegroundColor Yellow
if (-not (Test-Path $ModulePath)) {
    throw "Module path not found: $ModulePath"
}
if (-not (Test-Path $ManifestPath)) {
    throw "Module manifest not found: $ManifestPath"
}
Write-Host "  ✓ Module structure verified" -ForegroundColor Green

# Step 2: Test module manifest
Write-Host "[2/6] Testing module manifest..." -ForegroundColor Yellow
try {
    $manifest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop
    Write-Host "  ✓ Manifest is valid" -ForegroundColor Green
    Write-Host "    Module: $($manifest.Name)" -ForegroundColor Gray
    Write-Host "    Version: $($manifest.Version)" -ForegroundColor Gray
    Write-Host "    Author: $($manifest.Author)" -ForegroundColor Gray
} catch {
    Write-Error "Module manifest validation failed: $_"
    throw
}

# Step 3: Verify required files exist
Write-Host "[3/6] Verifying required files..." -ForegroundColor Yellow
$requiredFiles = @(
    "$ModuleName.psm1",
    "Public\New-GcePSSession.ps1",
    "Public\Remove-GcePSSession.ps1",
    "Public\New-GceSshTunnel.ps1",
    "Public\Get-GceSshTunnel.ps1",
    "Public\Remove-GceSshTunnel.ps1",
    "Classes\GceSshTunnel.ps1",
    "Private\Get-GceSshTunnelDirectory.ps1"
)

$missingFiles = @()
foreach ($file in $requiredFiles) {
    $filePath = Join-Path $ModulePath $file
    if (-not (Test-Path $filePath)) {
        $missingFiles += $file
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Error "Missing required files:`n$($missingFiles -join "`n")"
    throw
}
Write-Host "  ✓ All required files present" -ForegroundColor Green

# Step 4: Verify exported functions match actual functions
Write-Host "[4/6] Verifying exported functions..." -ForegroundColor Yellow
$manifestData = Import-PowerShellDataFile -Path $ManifestPath
$exportedFunctions = $manifestData.FunctionsToExport

# Get actual functions from Public folder
$publicFunctions = Get-ChildItem -Path (Join-Path $ModulePath "Public") -Filter "*.ps1" | 
    ForEach-Object { 
        $content = Get-Content $_.FullName -Raw
        if ($content -match 'function\s+(\w+-\w+)') {
            $matches[1]
        }
    }

$missingExports = @()
foreach ($func in $publicFunctions) {
    if ($func -notin $exportedFunctions) {
        $missingExports += $func
    }
}

if ($missingExports.Count -gt 0) {
    Write-Warning "Functions found but not exported: $($missingExports -join ', ')"
}

Write-Host "  ✓ Function export verification complete" -ForegroundColor Green
Write-Host "    Exported: $($exportedFunctions.Count) functions" -ForegroundColor Gray

# Step 5: Run PSScriptAnalyzer (if not skipped)
if (-not $SkipAnalysis) {
    Write-Host "[5/6] Running PSScriptAnalyzer..." -ForegroundColor Yellow
    
    # Check if PSScriptAnalyzer is installed
    $psaModule = Get-Module -ListAvailable -Name PSScriptAnalyzer
    if (-not $psaModule) {
        Write-Warning "PSScriptAnalyzer not found. Install it with: Install-Module -Name PSScriptAnalyzer -Scope CurrentUser"
        Write-Host "  ⚠ Skipping code analysis" -ForegroundColor Yellow
    } else {
        try {
            Import-Module PSScriptAnalyzer -ErrorAction Stop
            $analysisResults = Invoke-ScriptAnalyzer -Path $ModulePath -Recurse -ErrorAction Stop
            
            $errors = $analysisResults | Where-Object { $_.Severity -eq 'Error' }
            $warnings = $analysisResults | Where-Object { $_.Severity -eq 'Warning' }
            $info = $analysisResults | Where-Object { $_.Severity -eq 'Information' }
            
            Write-Host "  Analysis Results:" -ForegroundColor Gray
            Write-Host "    Errors: $($errors.Count)" -ForegroundColor $(if ($errors.Count -eq 0) { 'Green' } else { 'Red' })
            Write-Host "    Warnings: $($warnings.Count)" -ForegroundColor $(if ($warnings.Count -eq 0) { 'Green' } else { 'Yellow' })
            Write-Host "    Information: $($info.Count)" -ForegroundColor Gray
            
            if ($errors.Count -gt 0) {
                Write-Host ""
                Write-Host "Errors found:" -ForegroundColor Red
                $errors | ForEach-Object {
                    Write-Host "  $($_.ScriptName):$($_.Line) - $($_.Message)" -ForegroundColor Red
                }
                
                if ($Configuration -eq 'Production') {
                    Write-Error "Code analysis found errors. Fix them before publishing."
                    throw
                }
            }
            
            if ($warnings.Count -gt 0 -and $Configuration -eq 'Production') {
                Write-Warning "Code analysis found warnings. Consider fixing them before publishing."
            }
            
            Write-Host "  ✓ Code analysis complete" -ForegroundColor Green
        } catch {
            Write-Warning "PSScriptAnalyzer failed: $_"
        }
    }
} else {
    Write-Host "[5/6] Skipping code analysis (SkipAnalysis specified)" -ForegroundColor Yellow
}

# Step 6: Check for common issues
Write-Host "[6/6] Checking for common issues..." -ForegroundColor Yellow
$issues = @()

# Check PSData section
if (-not $manifestData.PrivateData.PSData.LicenseUri) {
    $issues += "LicenseUri is missing from PSData"
}
if (-not $manifestData.PrivateData.PSData.ProjectUri) {
    $issues += "ProjectUri is missing from PSData"
}
if (-not $manifestData.PrivateData.PSData.ReleaseNotes) {
    $issues += "ReleaseNotes is missing from PSData"
}

# Check for temporary files
$tempFiles = Get-ChildItem -Path $ModulePath -Recurse -File | 
    Where-Object { $_.Name -match '\.(tmp|bak|old|orig|~)$' -or $_.Name -eq '.DS_Store' }
if ($tempFiles.Count -gt 0) {
    $issues += "Temporary files found: $($tempFiles.Name -join ', ')"
}

if ($issues.Count -gt 0) {
    Write-Host "  Issues found:" -ForegroundColor Yellow
    foreach ($issue in $issues) {
        Write-Host "    - $issue" -ForegroundColor Yellow
    }
    if ($Configuration -eq 'Production') {
        Write-Warning "Please fix these issues before publishing."
    }
} else {
    Write-Host "  ✓ No common issues found" -ForegroundColor Green
}

# Summary
Write-Host ""
Write-Host "=== Build Summary ===" -ForegroundColor Cyan
Write-Host "Module: $($manifest.Name)" -ForegroundColor White
Write-Host "Version: $($manifest.Version)" -ForegroundColor White
Write-Host "Path: $ModulePath" -ForegroundColor White
Write-Host ""

if ($Configuration -eq 'Production') {
    Write-Host "✓ Module is ready for publishing to PowerShell Gallery!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Review the module one more time" -ForegroundColor White
    Write-Host "2. Ensure your PowerShell Gallery API key is ready" -ForegroundColor White
    Write-Host "3. Run: Publish-Module -Path '$ModulePath' -NuGetApiKey <YourApiKey> -Repository PSGallery" -ForegroundColor White
} else {
    Write-Host "✓ Build completed successfully (Development mode)" -ForegroundColor Green
}

Write-Host ""

