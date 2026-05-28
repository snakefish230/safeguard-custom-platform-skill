# Authentication Methods

Authentication applies at two levels:

1. **Safeguard Authentication** -- how the agent/automation connects to the Safeguard appliance
2. **Target Platform Authentication** -- how the custom platform script authenticates with the managed application

## Safeguard Authentication

### Password-Based (Development/Testing)

1. Create a local user in Safeguard (e.g., `svc_custom_platform`)
2. Assign roles: **Appliance Administrator** (dev) or **Authorizer** + **Asset Administrator** (production)
3. Set a password

```powershell
Import-Module safeguard-ps

$password = ConvertTo-SecureString 'YourPassword' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('svc_custom_platform', $password)

Connect-Safeguard -Appliance 'safeguard.example.com' `
    -IdentityProvider 'local' `
    -Credential $cred `
    -Insecure  # Only for self-signed certificates

Get-SafeguardLoggedInUser
```

### Certificate-Based (Production)

More secure. Recommended for production.

1. Generate a client certificate:

```powershell
$cert = New-SelfSignedCertificate `
    -Type ClientCertificate `
    -Subject "CN=svc_custom_platform" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyAlgorithm "RSA" -KeyLength 2048 `
    -KeyExportPolicy "Exportable" `
    -NotAfter (Get-Date).AddYears(3)

# Export PFX (private key) and CER (public key)
$pfxPassword = ConvertTo-SecureString -String "YourPfxPassword" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "svc_custom_platform.pfx" -Password $pfxPassword
Export-Certificate -Cert $cert -FilePath "svc_custom_platform.cer" | Out-Null
```

2. Upload the `.cer` file to the user in Safeguard (Settings > Users > Certificates)
3. Connect:

```powershell
Connect-Safeguard `
    -Appliance "safeguard.example.com" `
    -CertificateFilePath "svc_custom_platform.pfx" `
    -Password "YourPfxPassword"
```

## Target Platform Authentication

These are the methods your custom platform script uses to connect to the managed application.

### Basic Authentication (Username/Password)

Use `FuncUsername`/`FuncPassword` for service account, `AccountUsername`/`AccountPassword` for target account.

### OAuth 2.0 Password Flow

For REST APIs with OAuth username/password grant:

```json
{
    "SetItem": {
        "Name": "TokenUrl",
        "Value": "/oauth2/token?grant_type=password&client_id=%ClientId%&client_secret=%ClientSecret%&username=%FuncUsername%&password=%FuncPassword%",
        "IsSecret": true
    }
}
```

Examples: Salesforce, ServiceNow (see [references/servicenow-example.md](servicenow-example.md) for a working implementation)

### OAuth 2.0 JWT Bearer Flow

For server-to-server authentication. Requires a custom parameter for the JWT private key and JWT construction logic in the script.

### API Key Authentication

Static API key in request headers:

```json
{ "Headers": {
    "RequestObjectName": "Request",
    "AddHeaders": { "x-api-key": "%ApiKey%" }
} }
```

### Certificate-Based Authentication

For platforms requiring client certificates for TLS mutual auth. Requires SSH-based or certificate-aware transport.

## Configuring Credentials in Safeguard

After uploading a platform and creating an asset:

1. **Service Account**: Set on the asset's Connection Properties
   - For `Password` type: provide username and password
   - For `Custom` type: set custom script parameters via the GUI

2. **Custom Script Parameters**: Navigate to the asset in Safeguard GUI > Edit > Custom Script Parameters
   - **Secret parameters MUST be set via the GUI** (REST API strips secret values)

3. **Managed Account Passwords**: Set on each account
   - Use `Set-SafeguardAssetAccountPassword` to store a known password
   - Or use `ChangePassword` to have Safeguard generate and store a new one

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `Connect-Safeguard` not recognized | `Install-Module -Name safeguard-ps -Force -Scope CurrentUser` |
| Certificate auth fails | Verify `.cer` uploaded to correct user, cert not expired, PFX password correct |
| SYSLIB0051 errors | Use PowerShell 7.4 LTS (known bug in 7.6+) |
| Connection test passes but operations fail | Check custom script params set via GUI, verify service account permissions |
