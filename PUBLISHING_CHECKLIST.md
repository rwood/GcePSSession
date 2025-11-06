# Quick Publishing Checklist

Use this checklist before publishing to PowerShell Gallery.

## Pre-Publishing Checklist

### Module Manifest (GcePSSession.psd1)
- [x] ModuleVersion is set correctly
- [x] Author is set
- [x] Description is clear and concise
- [x] LicenseUri is set and points to valid LICENSE.md
- [x] ProjectUri is set and points to correct GitHub repository
- [x] ReleaseNotes are filled in
- [x] Tags are appropriate and help with discovery
- [x] FunctionsToExport lists all public functions
- [x] PowerShellVersion requirement is accurate

### Files and Structure
- [x] All function files exist in Public/ and Private/ folders
- [x] Root module file (GcePSSession.psm1) exists
- [x] LICENSE.md file exists
- [x] README.md is comprehensive
- [x] No temporary files (.tmp, .bak, etc.) in module folder
- [x] No test files in module folder
- [x] No personal/private information in code

### Code Quality
- [ ] Run `Test-ModuleManifest` - passes without errors
- [ ] Run `Invoke-ScriptAnalyzer` - no critical errors
- [ ] All functions have proper help documentation
- [ ] Error handling is appropriate
- [ ] Code follows PowerShell best practices

### Testing
- [ ] Module imports without errors: `Import-Module .\GcePSSession -Force`
- [ ] All exported functions are accessible: `Get-Command -Module GcePSSession`
- [ ] Basic functionality tested locally
- [ ] No obvious bugs or issues

### Documentation
- [ ] README.md is complete and accurate
- [ ] All functions have help content (Get-Help works)
- [ ] Examples in README are tested and work
- [ ] License file is present and correct

### PowerShell Gallery Account
- [ ] Account created at https://www.powershellgallery.com/
- [ ] Email verified
- [ ] API key generated and saved securely

## Publishing Commands

### Test Build
```powershell
.\Build.ps1 -Configuration Production
```

### Validate Manifest
```powershell
Test-ModuleManifest .\GcePSSession\GcePSSession.psd1
```

### Publish Module
```powershell
# Set API key
$apiKey = Read-Host -AsSecureString "Enter PowerShell Gallery API Key"

# Publish
Publish-Module `
    -Path .\GcePSSession `
    -NuGetApiKey (ConvertFrom-SecureString $apiKey -AsPlainText) `
    -Repository PSGallery `
    -Verbose
```

### Verify Installation
```powershell
# Install from gallery
Install-Module -Name GcePSSession -Scope CurrentUser -Force

# Verify
Get-Module -ListAvailable GcePSSession
Import-Module GcePSSession
Get-Command -Module GcePSSession
```

## Common Issues

| Issue | Solution |
|-------|----------|
| "Module name already exists" | Check if name is taken, use different name or contact owner |
| "Invalid API key" | Verify API key is correct and not expired |
| "Manifest validation failed" | Run `Test-ModuleManifest` to see specific errors |
| "File not found" | Ensure all referenced files exist in module folder |
| "LicenseUri invalid" | Ensure URL is publicly accessible |

## Version Update Checklist

When updating the module:

- [ ] Increment ModuleVersion in .psd1
- [ ] Update ReleaseNotes with changes
- [ ] Test changes locally
- [ ] Run Build.ps1 -Configuration Production
- [ ] Publish update using same process

## Important Notes

1. **ProjectUri**: Currently set to `https://github.com/mkellerman/GcePSSession` - Update if your repository URL is different!

2. **LicenseUri**: Currently set to `https://github.com/mkellerman/GcePSSession/blob/main/LICENSE.md` - Ensure this URL is correct for your repository.

3. **First Time Publishing**: The module name must be unique. If "GcePSSession" is taken, you'll need to choose a different name.

4. **API Key Security**: Never commit your API key to version control. Use environment variables or secure input.

5. **Version Numbers**: Follow semantic versioning (MAJOR.MINOR.PATCH)

---

**Ready?** Run `.\Build.ps1 -Configuration Production` first, then proceed with publishing!

