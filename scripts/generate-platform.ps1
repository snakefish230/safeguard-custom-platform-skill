<#
.SYNOPSIS
Interactive wizard for generating a new custom platform script from a template.

.DESCRIPTION
Walks through platform creation by asking about the target application, supported
operations, authentication method, and other details. Copies the appropriate
template and customizes it with the provided information.

.PARAMETER PlatformName
Name for the new platform. If not specified, will be prompted.

.PARAMETER TemplateName
Name of the template to use. If not specified, will be prompted based on answers.

.PARAMETER OutputDir
Directory to write the generated platform to. Defaults to platforms/<PlatformName>/.

.EXAMPLE
.\scripts\generate-platform.ps1

.EXAMPLE
.\scripts\generate-platform.ps1 -PlatformName "MyApp" -TemplateName "http-oauth-password"
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$false)]
    [string]$PlatformName,
    [Parameter(Mandatory=$false)]
    [string]$TemplateName,
    [Parameter(Mandatory=$false)]
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent

# Import utilities
. (Join-Path $repoRoot "utils/logging.ps1")
. (Join-Path $repoRoot "utils/validation.ps1")

Write-StepHeader "Safeguard Custom Platform Generator"

# Step 1: Gather platform name
if (-not $PSBoundParameters.ContainsKey("PlatformName") -or [string]::IsNullOrEmpty($PlatformName))
{
    $PlatformName = Read-Host "Enter the platform name (e.g., Salesforce, ServiceNow, MongoDB)"
    if ([string]::IsNullOrEmpty($PlatformName))
    {
        Write-Failure "Platform name is required."
        exit 1
    }
}

$platformId = ($PlatformName -replace '[^a-zA-Z0-9]', '-').ToLower()
Write-Host "Platform: $PlatformName (ID: $platformId)"

# Step 2: Determine communication method
if (-not $PSBoundParameters.ContainsKey("TemplateName") -or [string]::IsNullOrEmpty($TemplateName))
{
    Write-Host ""
    Write-Host "How does the target application accept connections?" -ForegroundColor Cyan
    Write-Host "  [1] REST API (HTTP/HTTPS) - SaaS apps, cloud services, web APIs"
    Write-Host "  [2] SSH - Linux/Unix servers, network devices"
    Write-Host "  [3] Database - Direct database connections (via SSH proxy)"
    Write-Host "  [4] Other - Start from minimal skeleton"
    Write-Host ""

    $commMethod = Read-Host "Select [1-4]"

    switch ($commMethod)
    {
        "1" {
            Write-Host ""
            Write-Host "What authentication method does the API use?" -ForegroundColor Cyan
            Write-Host "  [1] OAuth 2.0 (client ID + client secret + username/password)"
            Write-Host "  [2] API Key (static key in header)"
            Write-Host "  [3] Basic Authentication (username/password in header)"
            Write-Host ""

            $authMethod = Read-Host "Select [1-3]"
            switch ($authMethod)
            {
                "1" { $TemplateName = "http/http-oauth-password" }
                "2" { $TemplateName = "http/http-apikey" }
                "3" { $TemplateName = "http/http-basic" }
                default {
                    Write-Info "Defaulting to OAuth password template."
                    $TemplateName = "http/http-oauth-password"
                }
            }
        }
        "2" { $TemplateName = "ssh/ssh-password" }
        "3" { $TemplateName = "database/database-sql" }
        default { $TemplateName = "base/base-platform" }
    }
}

# Step 3: Determine which operations to include
Write-Host ""
Write-Host "Which operations should the platform support?" -ForegroundColor Cyan
Write-Host "  CheckSystem     - Test connectivity (recommended)"
Write-Host "  CheckPassword   - Verify password validity (recommended)"
Write-Host "  ChangePassword  - Rotate passwords (recommended)"
Write-Host "  DiscoverAccounts - Enumerate accounts (optional)"
Write-Host ""

$includeDiscovery = Read-Host "Include DiscoverAccounts? [Y/n]"
$skipDiscovery = ($includeDiscovery -eq "n" -or $includeDiscovery -eq "N")

# Step 4: Get description
Write-Host ""
$description = Read-Host "Brief description of the platform (e.g., 'Salesforce CRM via REST API')"
if ([string]::IsNullOrEmpty($description))
{
    $description = "$PlatformName custom platform"
}

# Step 5: Resolve template path and output path
$templateFile = Join-Path $repoRoot "templates/$TemplateName.json"
if (-not (Test-Path $templateFile))
{
    Write-Failure "Template not found: $templateFile"
    Write-Host "Available templates:" -ForegroundColor Yellow
    Get-ChildItem (Join-Path $repoRoot "templates") -Recurse -Filter "*.json" | ForEach-Object {
        Write-Host "  $($_.FullName.Replace((Join-Path $repoRoot 'templates/'), '').Replace('.json', ''))"
    }
    exit 1
}

if (-not $PSBoundParameters.ContainsKey("OutputDir") -or [string]::IsNullOrEmpty($OutputDir))
{
    $OutputDir = Join-Path $repoRoot "platforms/$platformId"
}

if (-not (Test-Path $OutputDir))
{
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$outputFile = Join-Path $OutputDir "$PlatformName.json"

# Step 6: Copy and customize the template
Write-Host ""
Write-StepHeader "Generating Platform Script"

$content = Get-Content $templateFile -Raw

# Replace placeholders
$content = $content -replace 'PLATFORM_ID', $platformId
$content = $content -replace 'PLATFORM_DESCRIPTION', $description
$content = $content -replace 'YYYY-MM-DD', (Get-Date -Format 'yyyy-MM-dd')

# Remove DiscoverAccounts if not wanted
if ($skipDiscovery)
{
    try
    {
        $json = $content | ConvertFrom-Json
        $json.PSObject.Properties.Remove("DiscoverAccounts")
        $content = $json | ConvertTo-Json -Depth 20
    }
    catch
    {
        Write-Info "Could not remove DiscoverAccounts automatically. Edit the file manually."
    }
}

# Write output
$content | Out-File -FilePath $outputFile -Encoding utf8 -NoNewline

Write-Success "Platform script generated: $outputFile"

# Step 7: Validate
Write-Host ""
Write-StepHeader "Validating Generated Script"

$validation = Test-PlatformScriptJson -FilePath $outputFile
if ($validation.IsValid)
{
    Write-Success "Script structure is valid."
}
else
{
    Write-Failure "Validation errors:"
    foreach ($err in $validation.Errors)
    {
        Write-Host "  - $err" -ForegroundColor Red
    }
}

if ($validation.Warnings.Count -gt 0)
{
    Write-Info "Warnings:"
    foreach ($warn in $validation.Warnings)
    {
        Write-Host "  - $warn" -ForegroundColor Yellow
    }
}

# Summary
Write-Host ""
Write-StepHeader "Summary"
Write-Host "Platform name:    $PlatformName"
Write-Host "Platform ID:      $platformId"
Write-Host "Template used:    $TemplateName"
Write-Host "Output file:      $outputFile"
Write-Host "Description:      $description"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Edit $outputFile to customize API endpoints, parameters, and logic"
Write-Host "  2. Review docs/custom-platform-guide.md for the command reference"
Write-Host "  3. Run: .\scripts\upload-to-safeguard.ps1 -PlatformFile '$outputFile'"
Write-Host ""
