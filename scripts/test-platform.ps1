<#
.SYNOPSIS
End-to-end test runner for a custom platform deployed on Safeguard.

.DESCRIPTION
Tests the full lifecycle of a custom platform: connectivity, password change,
password check, and optionally account discovery. Reports pass/fail for each
operation.

.PARAMETER AssetId
The Safeguard asset ID to test against.

.PARAMETER AccountId
The Safeguard account ID to test password operations on. If not specified,
will attempt to find an account matching TestAccountName from config.

.PARAMETER AccountName
The account name to test. Used to find the AccountId if AccountId is not specified.

.PARAMETER SkipDiscovery
Skip the account discovery test.

.PARAMETER SkipChangePassword
Skip the password change test (useful if you only want to check password).

.PARAMETER TimeoutSeconds
Maximum seconds to wait for each operation. Default is 120.

.PARAMETER ConfigPath
Path to the configuration file. Defaults to config/config.json.

.EXAMPLE
.\scripts\test-platform.ps1 -AssetId 128 -AccountId 91

.EXAMPLE
.\scripts\test-platform.ps1 -AssetId 128 -AccountName "test"

.EXAMPLE
.\scripts\test-platform.ps1 -AssetId 128 -AccountName "test" -SkipDiscovery
#>
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true,Position=0)]
    [int]$AssetId,
    [Parameter(Mandatory=$false)]
    [int]$AccountId,
    [Parameter(Mandatory=$false)]
    [string]$AccountName,
    [Parameter(Mandatory=$false)]
    [switch]$SkipDiscovery,
    [Parameter(Mandatory=$false)]
    [switch]$SkipChangePassword,
    [Parameter(Mandatory=$false)]
    [int]$TimeoutSeconds = 120,
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent

# Import modules
Import-Module safeguard-ps -ErrorAction Stop
Import-Module (Join-Path $repoRoot "src/customplatform/customplatforms.psm1") -Force -ErrorAction Stop
. (Join-Path $repoRoot "utils/logging.ps1")
. (Join-Path $repoRoot "utils/validation.ps1")
. (Join-Path $repoRoot "utils/common-functions.ps1")

Write-StepHeader "Safeguard Custom Platform Test Runner"

# Load config
$config = Get-ToolkitConfig -ConfigPath $ConfigPath
$insecure = $false
if ($config.PSObject.Properties["Insecure"] -and $config.Insecure -eq $true) { $insecure = $true }

# Connect
Write-StepHeader "Step 1: Connect to Safeguard"
Connect-SafeguardFromConfig -ConfigPath $ConfigPath

# Resolve account ID if not provided
if (-not $PSBoundParameters.ContainsKey("AccountId") -or $AccountId -eq 0)
{
    if (-not $PSBoundParameters.ContainsKey("AccountName") -or [string]::IsNullOrEmpty($AccountName))
    {
        if ($config.PSObject.Properties["TestAccountName"] -and -not [string]::IsNullOrEmpty($config.TestAccountName))
        {
            $AccountName = $config.TestAccountName
        }
        else
        {
            Write-Failure "No AccountId or AccountName specified, and no TestAccountName in config."
            exit 1
        }
    }

    Write-Host "Looking up account '$AccountName' on asset $AssetId..."
    $account = Find-ExistingAccount -Insecure:$insecure $AccountName -AssetId $AssetId
    if (-not $account)
    {
        Write-Failure "Account '$AccountName' not found on asset $AssetId."
        Write-Host "Create the account first, or specify -AccountId directly." -ForegroundColor Yellow
        exit 1
    }
    $AccountId = $account.Id
    Write-Success "Found account: $AccountName (ID: $AccountId)"
}

# Track results
$results = @()

# Test 1: Test Connection
Write-StepHeader "Test 1: Test Connection (CheckSystem)"
try
{
    $testResult = Invoke-SafeguardMethod -Insecure:$insecure Core POST "Assets/$AssetId/TestConnection"
    Write-Success "TestConnection initiated. Task ID: $($testResult.Id)"
    # TestConnection is synchronous in some versions
    $results += [PSCustomObject]@{ Test = "TestConnection"; Status = "INITIATED"; Details = "Task submitted" }
}
catch
{
    Write-Failure "TestConnection failed: $($_.Exception.Message)"
    $results += [PSCustomObject]@{ Test = "TestConnection"; Status = "FAILED"; Details = $_.Exception.Message }
}

# Test 2: Account Discovery
if (-not $SkipDiscovery)
{
    Write-StepHeader "Test 2: Account Discovery (DiscoverAccounts)"
    try
    {
        $discoveryResult = Invoke-SafeguardAccountDiscovery -Insecure:$insecure -AssetId $AssetId
        Write-Success "DiscoverAccounts initiated."
        $results += [PSCustomObject]@{ Test = "DiscoverAccounts"; Status = "INITIATED"; Details = "Check Safeguard GUI for results" }
    }
    catch
    {
        $errorMsg = $_.Exception.Message
        if ($errorMsg -match "Account discovery is not configured" -or $errorMsg -match "not supported")
        {
            Write-Info "DiscoverAccounts skipped: $errorMsg"
            $results += [PSCustomObject]@{ Test = "DiscoverAccounts"; Status = "SKIPPED"; Details = $errorMsg }
        }
        else
        {
            Write-Failure "DiscoverAccounts failed: $errorMsg"
            $results += [PSCustomObject]@{ Test = "DiscoverAccounts"; Status = "FAILED"; Details = $errorMsg }
        }
    }
}

# Test 3: Change Password
if (-not $SkipChangePassword)
{
    Write-StepHeader "Test 3: Change Password"
    try
    {
        $changeResult = Invoke-SafeguardPasswordChange -Insecure:$insecure -AccountId $AccountId -TimeoutSeconds $TimeoutSeconds
        Write-TaskResult $changeResult

        if ($changeResult.Success)
        {
            $results += [PSCustomObject]@{ Test = "ChangePassword"; Status = "PASSED"; Details = "Password changed successfully" }
        }
        elseif ($changeResult.TimedOut)
        {
            $results += [PSCustomObject]@{ Test = "ChangePassword"; Status = "TIMED OUT"; Details = "Operation did not complete within ${TimeoutSeconds}s" }
        }
        else
        {
            $results += [PSCustomObject]@{ Test = "ChangePassword"; Status = "FAILED"; Details = "Check Safeguard task logs for details" }
        }
    }
    catch
    {
        Write-Failure "ChangePassword error: $($_.Exception.Message)"
        $results += [PSCustomObject]@{ Test = "ChangePassword"; Status = "ERROR"; Details = $_.Exception.Message }
    }
}

# Test 4: Check Password
Write-StepHeader "Test 4: Check Password"

if (-not $SkipChangePassword -and $changeResult -and -not $changeResult.Success)
{
    Write-Info "Skipping CheckPassword because ChangePassword did not succeed."
    Write-Info "CheckPassword requires a password in the vault (from a successful Change or Set)."
    $results += [PSCustomObject]@{ Test = "CheckPassword"; Status = "SKIPPED"; Details = "ChangePassword did not succeed" }
}
else
{
    try
    {
        $checkResult = Invoke-SafeguardPasswordCheck -Insecure:$insecure -AccountId $AccountId -TimeoutSeconds $TimeoutSeconds
        Write-TaskResult $checkResult

        if ($checkResult.Success)
        {
            $results += [PSCustomObject]@{ Test = "CheckPassword"; Status = "PASSED"; Details = "Password verified successfully" }
        }
        elseif ($checkResult.TimedOut)
        {
            $results += [PSCustomObject]@{ Test = "CheckPassword"; Status = "TIMED OUT"; Details = "Operation did not complete within ${TimeoutSeconds}s" }
        }
        else
        {
            $results += [PSCustomObject]@{ Test = "CheckPassword"; Status = "FAILED"; Details = "Password mismatch or script error" }
        }
    }
    catch
    {
        Write-Failure "CheckPassword error: $($_.Exception.Message)"
        $results += [PSCustomObject]@{ Test = "CheckPassword"; Status = "ERROR"; Details = $_.Exception.Message }
    }
}

# Results Summary
Write-Host ""
Write-StepHeader "Test Results"

$passed = 0
$failed = 0
$skipped = 0

foreach ($r in $results)
{
    switch -Wildcard ($r.Status)
    {
        "PASSED"    { Write-Success "  $($r.Test): $($r.Status)"; $passed++ }
        "INITIATED" { Write-Host "  $($r.Test): $($r.Status) - $($r.Details)" -ForegroundColor Cyan; $passed++ }
        "SKIPPED"   { Write-Info "  $($r.Test): $($r.Status) - $($r.Details)"; $skipped++ }
        default     { Write-Failure "  $($r.Test): $($r.Status) - $($r.Details)"; $failed++ }
    }
}

Write-Host ""
Write-Host "Passed: $passed | Failed: $failed | Skipped: $skipped" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })

if ($failed -gt 0)
{
    Write-Host ""
    Write-Host "Troubleshooting tips:" -ForegroundColor Yellow
    Write-Host "  - Check Safeguard task logs for detailed error messages"
    Write-Host "  - Verify custom script parameters are set correctly in the Safeguard GUI"
    Write-Host "  - Ensure the service account has sufficient permissions on the target"
    Write-Host "  - Review the platform script for correct API endpoints and JSON parsing"
    Write-Host "  - Re-upload after fixing: Import-SafeguardCustomPlatformScript -PlatformToEdit <ID> -ScriptFile <path>"
    Write-Host ""
    exit 1
}
else
{
    Write-Host ""
    Write-Success "All tests passed."
    exit 0
}
