<#
.SYNOPSIS
Upload a custom platform to Safeguard and optionally create an asset and test account.

.DESCRIPTION
Connects to a Safeguard appliance, creates or updates a custom platform with the
provided script, and optionally creates an asset and test account for testing.

.PARAMETER PlatformFile
Path to the custom platform JSON script file.

.PARAMETER PlatformName
Display name for the platform in Safeguard. Defaults to the filename without extension.

.PARAMETER NetworkAddress
Network address of the target asset. If provided, an asset will be created.

.PARAMETER AssetDisplayName
Display name for the asset. Defaults to the NetworkAddress.

.PARAMETER TestAccountName
Name of the test account to create on the asset. Defaults to config TestAccountName.

.PARAMETER ServiceAccountName
Name of the service account for the asset.

.PARAMETER ServiceAccountCredentialType
Credential type for the service account. Default is "Custom".

.PARAMETER ConfigPath
Path to the configuration file. Defaults to config/config.json.

.PARAMETER ReplacePlatform
If the platform already exists, delete and recreate it.

.EXAMPLE
.\scripts\upload-to-safeguard.ps1 -PlatformFile "platforms\salesforce\SalesforceCustomPlatform.json"

.EXAMPLE
.\scripts\upload-to-safeguard.ps1 -PlatformFile "platforms\myapp\MyApp.json" -NetworkAddress "app.example.com" -TestAccountName "test"
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [string]$PlatformFile,
    [Parameter(Mandatory=$false)]
    [string]$PlatformName,
    [Parameter(Mandatory=$false)]
    [string]$NetworkAddress,
    [Parameter(Mandatory=$false)]
    [string]$AssetDisplayName,
    [Parameter(Mandatory=$false)]
    [string]$TestAccountName,
    [Parameter(Mandatory=$false)]
    [string]$ServiceAccountName,
    [Parameter(Mandatory=$false)]
    [ValidateSet("None","Password","Custom")]
    [string]$ServiceAccountCredentialType = "Custom",
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath,
    [Parameter(Mandatory=$false)]
    [switch]$ReplacePlatform
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent

# Import modules
Import-Module safeguard-ps -ErrorAction Stop
Import-Module (Join-Path $repoRoot "src/customplatform/customplatforms.psm1") -Force -ErrorAction Stop
. (Join-Path $repoRoot "utils/logging.ps1")
. (Join-Path $repoRoot "utils/validation.ps1")
. (Join-Path $repoRoot "utils/common-functions.ps1")

Write-StepHeader "Upload Custom Platform to Safeguard"

# Validate platform file
if (-not (Test-Path $PlatformFile))
{
    Write-Failure "Platform file not found: $PlatformFile"
    exit 1
}

$validation = Test-PlatformScriptJson -FilePath $PlatformFile
if (-not $validation.IsValid)
{
    Write-Failure "Platform script validation failed:"
    foreach ($err in $validation.Errors) { Write-Host "  - $err" -ForegroundColor Red }
    exit 1
}

if ($validation.Warnings.Count -gt 0)
{
    foreach ($warn in $validation.Warnings) { Write-Info "  Warning: $warn" }
}

# Resolve platform name from filename if not provided
if (-not $PSBoundParameters.ContainsKey("PlatformName") -or [string]::IsNullOrEmpty($PlatformName))
{
    $PlatformName = [System.IO.Path]::GetFileNameWithoutExtension($PlatformFile)
}

# Load config
$config = Get-ToolkitConfig -ConfigPath $ConfigPath
$insecure = $false
if ($config.PSObject.Properties["Insecure"] -and $config.Insecure -eq $true) { $insecure = $true }

# Resolve test account name
if (-not $PSBoundParameters.ContainsKey("TestAccountName") -or [string]::IsNullOrEmpty($TestAccountName))
{
    if ($config.PSObject.Properties["TestAccountName"] -and -not [string]::IsNullOrEmpty($config.TestAccountName))
    {
        $TestAccountName = $config.TestAccountName
    }
}

# Connect to Safeguard
Write-StepHeader "Step 1: Connect to Safeguard"
Connect-SafeguardFromConfig -ConfigPath $ConfigPath

# Step 2: Create or update custom platform
Write-StepHeader "Step 2: Upload Custom Platform"

$existingPlatform = Find-ExistingPlatform -Insecure:$insecure $PlatformName

if ($existingPlatform)
{
    if ($ReplacePlatform)
    {
        Write-Info "Platform '$PlatformName' exists (ID: $($existingPlatform.Id)). Deleting and recreating..."
        Remove-SafeguardCustomPlatform -Insecure:$insecure $existingPlatform.Id -ForceDelete
        Write-Host "Deleted old platform."
        $platform = New-SafeguardCustomPlatform -Insecure:$insecure -Name $PlatformName -ScriptFile $PlatformFile
        Write-Success "Platform created: ID=$($platform.Id), Name=$($platform.DisplayName)"
    }
    else
    {
        Write-Info "Platform '$PlatformName' already exists (ID: $($existingPlatform.Id)). Updating script..."
        $platform = Import-SafeguardCustomPlatformScript -Insecure:$insecure $existingPlatform.Id $PlatformFile
        Write-Success "Platform script updated: ID=$($platform.Id)"
    }
}
else
{
    $platform = New-SafeguardCustomPlatform -Insecure:$insecure -Name $PlatformName -ScriptFile $PlatformFile
    Write-Success "Platform created: ID=$($platform.Id), Name=$($platform.DisplayName)"
}

# Step 3: Create asset (if network address provided)
$asset = $null
if ($PSBoundParameters.ContainsKey("NetworkAddress") -and -not [string]::IsNullOrEmpty($NetworkAddress))
{
    Write-StepHeader "Step 3: Create Asset"

    if (-not $PSBoundParameters.ContainsKey("AssetDisplayName") -or [string]::IsNullOrEmpty($AssetDisplayName))
    {
        $AssetDisplayName = "$PlatformName - $NetworkAddress"
    }

    $existingAsset = Find-ExistingAsset -Insecure:$insecure $AssetDisplayName

    if ($existingAsset)
    {
        Write-Info "Asset '$AssetDisplayName' already exists (ID: $($existingAsset.Id)). Using existing."
        $asset = $existingAsset
    }
    else
    {
        $assetBody = @{
            Name = $AssetDisplayName
            Description = "Asset for $PlatformName custom platform"
            NetworkAddress = $NetworkAddress
            PlatformId = $platform.Id
        }

        if ($PSBoundParameters.ContainsKey("ServiceAccountName") -and -not [string]::IsNullOrEmpty($ServiceAccountName))
        {
            $assetBody.ConnectionProperties = @{
                ServiceAccountCredentialType = $ServiceAccountCredentialType
                ServiceAccountName = $ServiceAccountName
            }
        }

        $asset = Invoke-SafeguardMethod -Insecure:$insecure Core POST Assets -Body $assetBody
        Write-Success "Asset created: ID=$($asset.Id), Name=$($asset.Name)"
    }

    # Step 4: Create test account
    if (-not [string]::IsNullOrEmpty($TestAccountName))
    {
        Write-StepHeader "Step 4: Create Test Account"

        $existingAccount = Find-ExistingAccount -Insecure:$insecure $TestAccountName -AssetId $asset.Id

        if ($existingAccount)
        {
            Write-Info "Account '$TestAccountName' already exists (ID: $($existingAccount.Id)). Using existing."
        }
        else
        {
            $accountBody = @{
                Name = $TestAccountName
                AssetId = $asset.Id
            }

            $account = Invoke-SafeguardMethod -Insecure:$insecure Core POST AssetAccounts -Body $accountBody
            Write-Success "Account created: ID=$($account.Id), Name=$($account.Name)"
        }
    }

    # Reminder about custom script parameters
    Write-Host ""
    Write-Info "IMPORTANT: If your platform has custom script parameters (API keys, client secrets),"
    Write-Info "you must set them via the Safeguard GUI: Asset > Edit > Custom Script Parameters."
    Write-Info "Secret parameters cannot be set via the REST API."
}
else
{
    Write-Host ""
    Write-Info "No NetworkAddress provided. Skipping asset and account creation."
    Write-Info "To create an asset, re-run with: -NetworkAddress 'target.example.com'"
}

# Summary
Write-Host ""
Write-StepHeader "Summary"
Write-Host "Platform:  $($platform.DisplayName) (ID: $($platform.Id))"
Write-Host "HasScript: $($platform.CustomScriptProperties.HasScript)"
if ($asset)
{
    Write-Host "Asset:     $($asset.Name) (ID: $($asset.Id))"
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
if (-not $asset)
{
    Write-Host "  1. Create an asset: .\scripts\upload-to-safeguard.ps1 -PlatformFile '$PlatformFile' -NetworkAddress 'target.example.com'"
}
else
{
    Write-Host "  1. Set custom script parameters in the Safeguard GUI (if applicable)"
    Write-Host "  2. Test: .\scripts\test-platform.ps1 -AssetId $($asset.Id)"
}
Write-Host ""
