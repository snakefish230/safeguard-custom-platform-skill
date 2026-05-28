---
name: safeguard-custom-platform-skill
description: >-
  Build, validate, deploy, and test Custom Platforms for One Identity Safeguard
  for Privileged Passwords (SPP). Use when asked to add support for a new
  platform, create a custom integration for privileged account management,
  extend Safeguard to unsupported systems, or build a custom platform script.
  Covers the full lifecycle: feasibility assessment, requirements gathering,
  JSON script development, upload to Safeguard, testing, and iteration.
compatibility: Requires PowerShell 7.4 LTS, the safeguard-ps module, and network access to a Safeguard appliance.
metadata:
  author: safeguard-platform-toolkit
  version: "1.0"
---

# Build Custom Platforms for One Identity Safeguard

This skill guides you through developing, deploying, and testing custom platform
scripts that enable Safeguard SPP to manage privileged accounts on systems not
natively supported (e.g., Salesforce, ServiceNow, MongoDB, custom REST APIs).

## Workflow Overview

Follow these 7 phases sequentially. Do not skip phases. Ask clarifying questions
when information is missing.

### Phase 1: Feasibility Assessment

**Do this first before writing any code.**

1. Ask for the target platform name (e.g., "Salesforce", "ServiceNow", "MongoDB")
2. Ask for the network address or URL of the target
3. Determine which communication method the platform uses:
   - **HTTP/REST** -- cloud services, SaaS, modern APIs
   - **SSH** -- Linux/Unix systems, network devices
   - **Database** -- direct database connections (requires SSH or REST proxy)
4. Supported protocols: SSH, Telnet/TN3270, HTTP/REST. If unsupported, suggest alternatives.

### Phase 2: Requirements Gathering

Document these with the user:

1. **Operations** -- which to implement:
   - `CheckSystem` (test connectivity) -- recommended
   - `CheckPassword` (verify credentials) -- recommended
   - `ChangePassword` (rotate credentials) -- recommended
   - `DiscoverAccounts` (enumerate accounts) -- optional
2. **Target authentication method**: Basic auth, OAuth 2.0, API keys, certificates
   - Read [references/authentication-methods.md](references/authentication-methods.md) for details
3. **Service account permissions** on the target platform
   - Read [references/permission-requirements.md](references/permission-requirements.md) for details
4. **Safeguard requirements**: appliance URL, service account with **Authorizer** + **Asset Administrator** roles

### Phase 3: Environment Setup

```powershell
.\scripts\setup-dev-environment.ps1
```

This installs `safeguard-ps`, downloads `customplatforms.psm1` from GitHub
(it is NOT included in the `safeguard-ps` module), and creates `config/config.json`.

If setting up manually, download `customplatforms.psm1` separately:

```powershell
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/OneIdentity/safeguard-ps/master/modules/customplatforms/customplatforms.psm1' -OutFile './customplatforms.psm1'
```

Verify connectivity:

```powershell
Import-Module safeguard-ps
Import-Module ./customplatforms.psm1
Connect-Safeguard -Appliance 'YOUR_APPLIANCE' -IdentityProvider 'local' -Credential (Get-Credential) -Insecure
Get-SafeguardLoggedInUser
```

### Phase 4: Script Development

1. **Select a template** from `assets/templates/`:
   - `http-oauth-password.json` -- OAuth 2.0 password flow APIs
   - `http-apikey.json` -- API key authenticated APIs
   - `http-basic.json` -- Basic auth APIs
   - `ssh-password.json` -- SSH/Linux systems
   - `database-sql.json` -- Database platforms (via SSH/REST proxy)
   - `base-platform.json` -- minimal skeleton

2. **Copy the template** to your platform directory and customize:
   - Update `Id` (alphanumeric only) and `Meta` fields
   - Implement each operation's `Do` array using the script commands
   - Define custom parameters (API keys, client IDs, etc.)
   - Read [references/script-command-reference.md](references/script-command-reference.md) for the full command reference

3. **Validate locally**:

```powershell
Test-SafeguardCustomPlatformScript -ScriptFile "platforms/my-platform/MyPlatform.json" -Insecure
```

### Phase 5: Upload and Configure

```powershell
# Create platform and upload script
$platform = New-SafeguardCustomPlatform -Name "MyPlatform" -ScriptFile "path/to/script.json" -Insecure

# Create asset
$asset = New-SafeguardCustomPlatformAsset -Platform $platform.Id `
    -NetworkAddress "target.example.com" `
    -DisplayName "My Platform Asset" `
    -ServiceAccountCredentialType "Custom" -Insecure

# Create test account
$account = New-SafeguardAssetAccount -Insecure $asset.Id 'test'
```

**Secret parameters (API keys, client secrets) MUST be set via the Safeguard GUI** under Asset > Custom Script Parameters. The REST API strips secret values on write.

### Phase 6: Testing

**CRITICAL: Always run ChangePassword before CheckPassword.** CheckPassword
compares the vault password against the target -- an empty vault always fails.

```powershell
.\scripts\test-platform.ps1 -AssetId $asset.Id -AccountId $account.Id
```

Or manually:

```powershell
# 1. Test connectivity
Invoke-SafeguardMethod -Service Core -Method POST -RelativeUrl "Assets/$($asset.Id)/TestConnection" -Insecure

# 2. Change password FIRST
Invoke-SafeguardMethod -Service Core -Method POST -RelativeUrl "AssetAccounts/$($account.Id)/ChangePassword" -Insecure
Start-Sleep -Seconds 15

# 3. Verify change result (async -- poll TaskProperties)
$acct = Invoke-SafeguardMethod -Service Core -Method GET -RelativeUrl "AssetAccounts/$($account.Id)" -Insecure
$acct.TaskProperties | Select-Object LastSuccessPasswordChangeDate, LastFailurePasswordChangeDate

# 4. Check password
Invoke-SafeguardMethod -Service Core -Method POST -RelativeUrl "AssetAccounts/$($account.Id)/CheckPassword" -Insecure
Start-Sleep -Seconds 15
```

### Phase 7: Iteration and Documentation

If tests fail:

1. Check the error in Safeguard task logs
2. Fix the platform script
3. Re-upload (no need to recreate asset/account):

```powershell
Import-SafeguardCustomPlatformScript -PlatformToEdit $platform.Id -ScriptFile "path/to/script.json" -Insecure
```

4. Re-test

When working, document the platform in a README with prerequisites, permissions,
custom parameters, and setup steps.

## Gotchas

- **Id field**: Must be alphanumeric only -- no spaces, hyphens, or special characters.
- **BackEnd field**: Must always be `"Scriptable"` for custom platforms.
- **Secret params via GUI only**: The Safeguard REST API does not persist secret parameter values. You must set them in the Safeguard web UI.
- **Test ordering**: Always ChangePassword (or `Set-SafeguardAssetAccountPassword`) before CheckPassword. The vault must contain a password before CheckPassword can compare.
- **Variable delimiter collision**: Safeguard uses `%` for variable substitution. Passwords containing `%` will cause substitution errors.
- **ServiceAccountCredentialType**: Set to `"Custom"` on the asset connection properties when using custom script parameters.
- **Async operations**: Password change/check are async. Poll `TaskProperties` for results -- task submission does not guarantee success. Verify success by checking `LastSuccessPasswordChangeDate` (populated = success) and `LastFailurePasswordChangeDate` (populated = failure).
- **JSON parsing -- two-step pattern**: Do NOT pass the response object directly to `ExtractJsonObject`. First extract `.Content` into a string variable with `SetItem`, then parse that string. This is the proven correct pattern.
- **URL substitution**: Use `%VariableName%` in URLs with `"SubstitutionInUrl": true`. Do NOT use `%{UrlEncode()}%` -- it does not resolve. Missing `SubstitutionInUrl: true` causes literal `%Variable%` strings to be sent.
- **PowerShell 7.6+ bug**: Use PowerShell 7.4 LTS. There is a known SYSLIB0051 serialization bug in 7.6+. Use `Invoke-SafeguardMethod` instead of high-level cmdlets like `Test-SafeguardAssetAccountPassword` as a workaround.
- **Scripts run ON the appliance**: Custom platform scripts execute on the Safeguard appliance, not the automation host. The appliance must have network access to the target.
- **customplatforms.psm1 is separate**: The custom platform cmdlets (`New-SafeguardCustomPlatform`, `Import-SafeguardCustomPlatformScript`, etc.) are NOT included in the `safeguard-ps` module. Download `customplatforms.psm1` separately from the [safeguard-ps GitHub repo](https://github.com/OneIdentity/safeguard-ps/blob/master/modules/customplatforms/customplatforms.psm1).
- **Cannot change asset platform**: You cannot change an existing asset's platform type after creation. You must create a new asset.
- **Discovery needs Safeguard config**: Having `DiscoverAccounts` in the script is not enough. Account discovery also requires a discovery schedule and rules configured in Safeguard (via GUI or API), assigned to the asset.
- **ServiceNow field values**: ServiceNow REST API returns fields as objects with a `.Value` property. Use `%{user.user_name.Value}%` not `%{user.user_name}%`.

## Key Principles

| Principle | Implementation |
|-----------|----------------|
| Security | Use Safeguard credential injection (`%Variable%`); never hardcode secrets |
| Idempotency | Design operations for safe retries without side effects |
| Error handling | Check status codes; `Return true` for success, `false` for expected failures, `Throw` for unexpected errors |
| Secrets | Mark secret variables with `"IsSecret": true` to prevent logging |
| Validation | Test at each phase before proceeding |

## Resources in this Skill

- [Script command reference](references/script-command-reference.md) -- read when implementing script operations
- [Authentication methods](references/authentication-methods.md) -- read when configuring auth for Safeguard or target platforms
- [Permission requirements](references/permission-requirements.md) -- read when setting up service accounts
- [ServiceNow example](references/servicenow-example.md) -- read as a proven, working reference implementation
- Templates in `assets/templates/` -- copy as starting points for new platforms
- Scripts in `scripts/` -- automation for generate, upload, test, and environment setup
