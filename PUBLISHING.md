# Publishing GcePSSession to PowerShell Gallery

This guide walks you through the steps to publish the GcePSSession module to the PowerShell Gallery.

## Prerequisites

1. **PowerShell Gallery Account**
   - Create an account at https://www.powershellgallery.com/
   - Verify your email address
   - Note: Publishing is free for open-source projects

2. **Required Tools**
   - PowerShell 5.1+ or PowerShell 7+
   - `PowerShellGet` module (usually pre-installed)
   - `PSScriptAnalyzer` module (for code quality checks)
   - `Pester` module (for testing, if you add tests)

3. **API Key**
   - Log in to PowerShell Gallery
   - Go to your account profile
   - Generate an API key (or use an existing one)
   - Save the API key securely (you'll need it for publishing)

## Step-by-Step Publishing Process

### Step 1: Update Module Manifest

The module manifest (`GcePSSession.psd1`) has been updated with:
- ✅ `LicenseUri` - Points to LICENSE.md
- ✅ `ProjectUri` - Points to GitHub repository
- ✅ `ReleaseNotes` - Initial release notes
- ✅ `Tags` - Enhanced tags for better discoverability

**Note**: Update the `ProjectUri` if your repository URL is different from `https://github.com/mkellerman/GcePSSession`

### Step 2: Verify Module Structure

Ensure your module has the correct structure:
```
GcePSSession/
├── GcePSSession.psd1          # Module manifest
├── GcePSSession.psm1          # Root module file
├── Public/                     # Public functions
│   ├── Install-GceWindowsSsh.ps1
│   ├── Invoke-GceCommandAs.ps1
│   ├── New-GcePSSession.ps1
│   └── Remove-GcePSSession.ps1
└── Private/                    # Private functions
    ├── New-GceSshTunnel.ps1
    └── Stop-GceSshTunnel.ps1
```

### Step 3: Test Module Locally

Before publishing, test the module:

```powershell
# Import the module
Import-Module .\GcePSSession -Force

# Verify all functions are exported
Get-Command -Module GcePSSession

# Test module manifest
Test-ModuleManifest .\GcePSSession\GcePSSession.psd1
```

### Step 4: Run Code Analysis (Recommended)

Install and run PSScriptAnalyzer:

```powershell
# Install PSScriptAnalyzer if not already installed
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force

# Run analysis on the module
Invoke-ScriptAnalyzer -Path .\GcePSSession -Recurse
```

Fix any critical issues before publishing.

### Step 5: Build the Module Package

Use the provided build script or manually prepare:

```powershell
# Option 1: Use the build script
.\Build.ps1 -Configuration Production

# Option 2: Manual preparation
# Ensure the module folder is clean and ready
# Remove any temporary files, test files, etc.
```

### Step 6: Validate Module Manifest

Verify the manifest is valid:

```powershell
$manifest = Test-ModuleManifest .\GcePSSession\GcePSSession.psd1
$manifest | Format-List Name, Version, Author, Description
```

### Step 7: Publish to PowerShell Gallery

#### Option A: Using Publish-Module (Recommended)

```powershell
# Set your API key (one-time, or use environment variable)
$apiKey = Read-Host -AsSecureString "Enter your PowerShell Gallery API Key"

# Publish the module
Publish-Module `
    -Path .\GcePSSession `
    -NuGetApiKey (ConvertFrom-SecureString $apiKey -AsPlainText) `
    -Repository PSGallery `
    -Verbose
```

#### Option B: Using Publish-Module with Environment Variable

```powershell
# Set environment variable (more secure)
$env:NuGetApiKey = "your-api-key-here"

# Publish
Publish-Module -Path .\GcePSSession -Repository PSGallery -Verbose

# Clear the environment variable after publishing
Remove-Item Env:\NuGetApiKey
```

#### Option C: Using nuget.exe

```powershell
# Create package first
$package = New-ModuleManifest -Path .\GcePSSession\GcePSSession.psd1
# Then use nuget.exe to push
```

### Step 8: Verify Publication

After publishing:

1. **Check PowerShell Gallery**: Visit https://www.powershellgallery.com/packages/GcePSSession
2. **Test Installation**:
   ```powershell
   # Uninstall local version first
   Remove-Module GcePSSession -Force
   
   # Install from gallery
   Install-Module -Name GcePSSession -Scope CurrentUser -Force
   
   # Verify installation
   Get-Module -ListAvailable GcePSSession
   Import-Module GcePSSession
   Get-Command -Module GcePSSession
   ```

## Updating the Module

When you need to publish an update:

1. **Update Version Number**
   ```powershell
   # Edit GcePSSession.psd1 and increment ModuleVersion
   # Example: Change from '1.0.0' to '1.0.1' or '1.1.0'
   ```

2. **Update ReleaseNotes**
   ```powershell
   # Edit GcePSSession.psd1 and update ReleaseNotes in PSData section
   ```

3. **Test Changes**
   ```powershell
   # Test locally before publishing
   Import-Module .\GcePSSession -Force
   ```

4. **Publish Update**
   ```powershell
   # Use the same Publish-Module command as before
   Publish-Module -Path .\GcePSSession -NuGetApiKey $apiKey -Repository PSGallery
   ```

## Version Numbering Guidelines

Follow [Semantic Versioning](https://semver.org/):
- **MAJOR.MINOR.PATCH** (e.g., 1.0.0)
- **MAJOR**: Breaking changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes

Examples:
- `1.0.0` → `1.0.1` (bug fix)
- `1.0.0` → `1.1.0` (new feature)
- `1.0.0` → `2.0.0` (breaking change)

## Common Issues and Solutions

### Issue: "Module name already exists"
**Solution**: The module name is already taken. You may need to:
- Use a different name
- Contact the owner if it's your module
- Check if you're logged in with the correct account

### Issue: "Invalid API key"
**Solution**: 
- Verify your API key is correct
- Check if the API key has expired
- Ensure you're using the key from the correct account

### Issue: "Manifest validation failed"
**Solution**:
- Run `Test-ModuleManifest` to see specific errors
- Ensure all required fields are filled
- Check that LicenseUri and ProjectUri are valid URLs

### Issue: "File not found" errors
**Solution**:
- Ensure all files referenced in the manifest exist
- Check that FunctionsToExport matches actual function names
- Verify file paths are correct

## Best Practices

1. **Always test locally** before publishing
2. **Use version control** (Git) to track changes
3. **Write release notes** for each version
4. **Tag releases** in Git with version numbers
5. **Keep dependencies minimal** - only include what's necessary
6. **Document your module** - good README and help content
7. **Follow PowerShell conventions** - use approved verbs, proper error handling
8. **Consider adding tests** using Pester

## Additional Resources

- [PowerShell Gallery Publishing Guidelines](https://docs.microsoft.com/en-us/powershell/scripting/gallery/concepts/publishing-guidelines)
- [PowerShell Gallery Documentation](https://docs.microsoft.com/en-us/powershell/scripting/gallery/overview)
- [Module Manifest Documentation](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_module_manifests)
- [PSScriptAnalyzer Rules](https://github.com/PowerShell/PSScriptAnalyzer)

## Quick Reference Commands

```powershell
# Test module manifest
Test-ModuleManifest .\GcePSSession\GcePSSession.psd1

# Analyze code quality
Invoke-ScriptAnalyzer -Path .\GcePSSession -Recurse

# Publish module
Publish-Module -Path .\GcePSSession -NuGetApiKey $apiKey -Repository PSGallery

# Install from gallery
Install-Module -Name GcePSSession -Scope CurrentUser

# Update module
Update-Module -Name GcePSSession

# Find module
Find-Module -Name GcePSSession
```

## Checklist Before Publishing

- [ ] Module manifest is complete and valid
- [ ] LicenseUri points to valid LICENSE.md file
- [ ] ProjectUri points to correct repository
- [ ] ReleaseNotes are updated
- [ ] Version number is correct
- [ ] All functions are exported correctly
- [ ] Module has been tested locally
- [ ] Code analysis passes (PSScriptAnalyzer)
- [ ] README.md is comprehensive
- [ ] LICENSE.md is present
- [ ] No temporary/test files in module folder
- [ ] API key is ready

---

**Ready to publish?** Follow the steps above and you'll have your module on PowerShell Gallery in no time!

