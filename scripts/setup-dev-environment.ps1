<#
.SYNOPSIS
Bootstrap the development environment for the Safeguard LLM Platform Toolkit.

.DESCRIPTION
This script installs required PowerShell modules, imports toolkit modules,
and creates a configuration file from the example template.

.EXAMPLE
.\scripts\setup-dev-environment.ps1

.EXAMPLE
.\scripts\setup-dev-environment.ps1 -SkipModuleInstall
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false)]
    [switch]$SkipModuleInstall,
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Determine repo root
$repoRoot = Split-Path $PSScriptRoot -Parent

Write-Host ""
Write-Host "=== Safeguard LLM Platform Toolkit - Environment Setup ===" -ForegroundColor Cyan
Write-Host "Repository: $repoRoot"
Write-Host ""

# Step 1: Install safeguard-ps module
Write-Host "--- Step 1: PowerShell Module Installation ---" -ForegroundColor Cyan

if (-not $SkipModuleInstall)
{
    $sgModule = Get-Module -Name safeguard-ps -ListAvailable
    if ($sgModule -and -not $Force)
    {
        Write-Host "safeguard-ps module is already installed (version: $($sgModule.Version))" -ForegroundColor Green
    }
    else
    {
        Write-Host "Installing safeguard-ps module..."
        try
        {
            # Ensure PSGallery is registered
            if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue))
            {
                Register-PSRepository -Default -ErrorAction SilentlyContinue
            }
            Install-Module -Name safeguard-ps -Force -Scope CurrentUser -AllowClobber
            Write-Host "safeguard-ps module installed successfully." -ForegroundColor Green
        }
        catch
        {
            Write-Host "WARNING: Failed to install safeguard-ps: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "You can install it manually: Install-Module -Name safeguard-ps -Force -Scope CurrentUser" -ForegroundColor Yellow
        }
    }
}
else
{
    Write-Host "Skipping module installation (--SkipModuleInstall)" -ForegroundColor Yellow
}

# Step 2: Verify toolkit modules exist
Write-Host ""
Write-Host "--- Step 2: Verify Toolkit Modules ---" -ForegroundColor Cyan

$customPlatformModule = Join-Path $repoRoot "src/customplatform/customplatforms.psm1"
if (Test-Path $customPlatformModule)
{
    Write-Host "Custom platform module found: $customPlatformModule" -ForegroundColor Green
}
else
{
    Write-Host "ERROR: Custom platform module not found at $customPlatformModule" -ForegroundColor Red
    Write-Host "Ensure the repository is complete." -ForegroundColor Red
    exit 1
}

$utilFiles = @("logging.ps1", "validation.ps1", "common-functions.ps1")
foreach ($util in $utilFiles)
{
    $utilPath = Join-Path $repoRoot "utils/$util"
    if (Test-Path $utilPath)
    {
        Write-Host "Utility found: $utilPath" -ForegroundColor Green
    }
    else
    {
        Write-Host "WARNING: Utility not found: $utilPath" -ForegroundColor Yellow
    }
}

# Step 3: Create configuration file
Write-Host ""
Write-Host "--- Step 3: Configuration File ---" -ForegroundColor Cyan

$configDir = Join-Path $repoRoot "config"
$configFile = Join-Path $configDir "config.json"
$configExample = Join-Path $configDir "config.example.json"

if (Test-Path $configFile)
{
    if ($Force)
    {
        Write-Host "Overwriting existing config.json (--Force specified)" -ForegroundColor Yellow
        Copy-Item $configExample $configFile -Force
        Write-Host "Configuration file created: $configFile" -ForegroundColor Green
    }
    else
    {
        Write-Host "config.json already exists. Use -Force to overwrite." -ForegroundColor Yellow
    }
}
else
{
    if (Test-Path $configExample)
    {
        Copy-Item $configExample $configFile
        Write-Host "Configuration file created: $configFile" -ForegroundColor Green
        Write-Host "IMPORTANT: Edit $configFile with your Safeguard appliance details." -ForegroundColor Yellow
    }
    else
    {
        Write-Host "ERROR: config.example.json not found at $configExample" -ForegroundColor Red
        exit 1
    }
}

# Step 4: Test module imports
Write-Host ""
Write-Host "--- Step 4: Test Module Imports ---" -ForegroundColor Cyan

try
{
    Import-Module safeguard-ps -ErrorAction Stop
    Write-Host "safeguard-ps imported successfully." -ForegroundColor Green
}
catch
{
    Write-Host "WARNING: Could not import safeguard-ps: $($_.Exception.Message)" -ForegroundColor Yellow
}

try
{
    Import-Module $customPlatformModule -Force -ErrorAction Stop
    Write-Host "customplatforms.psm1 imported successfully." -ForegroundColor Green
}
catch
{
    Write-Host "WARNING: Could not import customplatforms.psm1: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Step 5: Check PowerShell version
Write-Host ""
Write-Host "--- Step 5: Environment Check ---" -ForegroundColor Cyan

$psVersion = $PSVersionTable.PSVersion
Write-Host "PowerShell version: $psVersion"

if ($psVersion.Major -eq 7 -and $psVersion.Minor -ge 6)
{
    Write-Host "WARNING: PowerShell 7.6+ has a known SYSLIB0051 serialization bug." -ForegroundColor Yellow
    Write-Host "Recommendation: Use PowerShell 7.4 LTS for best compatibility." -ForegroundColor Yellow
}
elseif ($psVersion.Major -lt 5 -or ($psVersion.Major -eq 5 -and $psVersion.Minor -lt 1))
{
    Write-Host "WARNING: PowerShell 5.1 or later is required." -ForegroundColor Yellow
}
else
{
    Write-Host "PowerShell version is compatible." -ForegroundColor Green
}

# Step 6: Verify templates
Write-Host ""
Write-Host "--- Step 6: Available Templates ---" -ForegroundColor Cyan

$templateDirs = @("base", "http", "ssh", "database")
foreach ($dir in $templateDirs)
{
    $templatePath = Join-Path $repoRoot "templates/$dir"
    if (Test-Path $templatePath)
    {
        $templates = Get-ChildItem $templatePath -Filter "*.json" -ErrorAction SilentlyContinue
        if ($templates)
        {
            foreach ($t in $templates)
            {
                Write-Host "  $dir/$($t.Name)" -ForegroundColor Green
            }
        }
    }
}

# Summary
Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Edit config/config.json with your Safeguard appliance details"
Write-Host "  2. Run: .\scripts\generate-platform.ps1  (to create a new platform)"
Write-Host "  3. Run: .\scripts\upload-to-safeguard.ps1 (to deploy to Safeguard)"
Write-Host "  4. Run: .\scripts\test-platform.ps1       (to test operations)"
Write-Host ""
