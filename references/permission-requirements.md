# Permission Requirements

## Safeguard Service Account Permissions

The account used by automation scripts to manage custom platforms.

### Development/Testing

**Role:** Appliance Administrator (full access, testing only)

### Production (Minimum Required)

**Roles:** Assign both **Authorizer** and **Asset Administrator**.

| Permission | Purpose |
|-----------|---------|
| Asset Administrator | Create/edit assets and accounts |
| Authorizer | Approve password operations |
| Manage Custom Platforms | Upload/edit custom platform scripts |
| User Management | Create service accounts (if needed) |
| Asset Management | Create and configure assets |
| Account Management | Create and manage accounts on assets |

### Creating the Service Account

1. Safeguard Web UI > Settings > Users > Create User
2. Set username (e.g., `svc_custom_platform`)
3. Assign roles
4. Set authentication: Password (dev) or Certificate (production)

## Target Platform Service Account Permissions

The service account Safeguard uses to connect to and manage accounts on the target platform.

### Minimum Permissions by Operation

| Operation | Required Permissions |
|-----------|---------------------|
| **CheckSystem** | Authenticate to the platform (read-only sufficient) |
| **CheckPassword** | Authenticate as the target account, or validate credentials via API |
| **ChangePassword** | Reset/change passwords for other accounts (admin-level) |
| **DiscoverAccounts** | List/enumerate user accounts (read access to user directory) |

### Platform-Specific Examples

**REST API Platforms (Salesforce, ServiceNow):**
- Dedicated service account with API access enabled
- Permission to reset other users' passwords
- Permission to query user lists (for discovery)
- OAuth scopes: `api`, `refresh_token`, `offline_access` (varies)

**SSH Platforms (Linux/Unix):**
- Dedicated service account with SSH access
- `sudo` or root access for password changes (`passwd`, `chpasswd`)
- Shell access for command execution
- Read access to `/etc/passwd` for discovery

**Database Platforms:**
- DBA account or equivalent
- `ALTER USER` privilege for password changes
- `SELECT` on user tables for discovery

## Network Requirements

| Source | Destination | Port | Purpose |
|--------|-------------|------|---------|
| Automation host | Safeguard appliance | 443 | Safeguard API |
| Safeguard appliance | Target platform | Varies | Script execution |

**Critical:** Custom platform scripts execute ON the Safeguard appliance, not the automation host. The appliance must have network access to the target platform.

## Security Best Practices

1. **Least privilege** -- grant only minimum permissions needed
2. **Dedicated accounts** -- never reuse personal accounts
3. **Credential rotation** -- rotate service account credentials on a schedule
4. **Audit logging** -- enable on both Safeguard and the target platform
5. **Network segmentation** -- restrict access between Safeguard and targets
6. **No hardcoded credentials** -- use Safeguard's credential injection
7. **Certificate auth preferred** -- for the Safeguard service account in production
