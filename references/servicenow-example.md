# ServiceNow Custom Platform -- Proven Working Reference Implementation

This is a complete, production-verified custom platform for ServiceNow using
API Key authentication against the ServiceNow REST Table API. Verified working
on Safeguard 8.2+ / ServiceNow Vancouver.

**Note:** This example uses the `sys_user` table for user account management. 
ServiceNow has multiple credential tables with different field formats -- see 
the [Discovery Credentials](#discovery-credentials-table) section for `discovery_credentials` table specifics.

## Custom Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `FuncApiKey` | Secret | ServiceNow API Key (set via Safeguard GUI) |
| `PageSize` | Integer | Users per page for discovery (default: 100, max: 10000) |

## ServiceNow API Endpoints Used

```
GET   /api/now/table/sys_user                           # List/query users
GET   /api/now/table/sys_user?sysparm_query=user_name=<name>&sysparm_limit=1  # Find user
PATCH /api/now/table/sys_user/<sys_id>                  # Update user (password)
```

Authentication: `x-sn-apikey` header with API Key value.

## Operations Implemented

### CheckSystem

Simple connectivity test -- queries the sys_user table endpoint.

```json
"CheckSystem": {
  "Parameters": [
    {"FuncApiKey": {"Type": "Secret"}},
    {"Address": {"Type": "String"}}
  ],
  "Do": [
    {"BaseAddress": {"Address": "https://%Address%"}},
    {"NewHttpRequest": {"ObjectName": "r"}},
    {"Request": {
      "RequestObjectName": "r",
      "ResponseObjectName": "resp",
      "Verb": "GET",
      "Url": "api/now/table/sys_user"
    }},
    {"Return": {"Value": "true"}}
  ]
}
```

### CheckPassword

Verifies the target user exists in ServiceNow by querying with the API key.

```json
"CheckPassword": {
  "Parameters": [
    {"FuncApiKey": {"Type": "Secret"}},
    {"Address": {"Type": "String"}},
    {"AccountUserName": {"Type": "String"}}
  ],
  "Do": [
    {"BaseAddress": {"Address": "https://%Address%"}},
    {"NewHttpRequest": {"ObjectName": "r"}},
    {"Headers": {"RequestObjectName": "r", "AddHeaders": {"x-sn-apikey": "%FuncApiKey%"}}},
    {"Request": {
      "RequestObjectName": "r",
      "ResponseObjectName": "resp",
      "Verb": "GET",
      "Url": "api/now/table/sys_user?sysparm_query=user_name=%AccountUserName%&sysparm_limit=1",
      "SubstitutionInUrl": true,
      "Content": {"ContentType": "application/json"}
    }},
    {"Return": {"Value": "true"}}
  ]
}
```

### ChangePassword

The most complex operation. Demonstrates the proven JSON parsing and LINQ pattern:

1. Query for user by `user_name` with `sysparm_limit=1`
2. Extract `.Content` into a string variable, then `ExtractJsonObject`
3. Use LINQ `FirstOrDefault()` to find the matching user from `result` array
4. Extract `sys_id.Value` from the matched user
5. PATCH the user record with the new password

```json
"ChangePassword": {
  "Parameters": [
    {"FuncApiKey": {"Type": "Secret"}},
    {"Address": {"Type": "String"}},
    {"AccountUserName": {"Type": "String"}},
    {"NewPassword": {"Type": "Secret"}}
  ],
  "Do": [
    {"BaseAddress": {"Address": "https://%Address%"}},
    {"NewHttpRequest": {"ObjectName": "SystemRequest"}},
    {"Headers": {"RequestObjectName": "SystemRequest", "AddHeaders": {"x-sn-apikey": "%FuncApiKey%"}}},
    {"SetItem": {"Name": "ChangePassJson", "Value": {"user_password": "%NewPassword%"}, "IsSecret": true}},
    {"Request": {
      "RequestObjectName": "SystemRequest",
      "ResponseObjectName": "SystemUsers",
      "Verb": "GET",
      "Url": "api/now/table/sys_user?sysparm_query=user_name=%AccountUserName%&sysparm_limit=1&sysparm_fields=sys_id,user_name",
      "SubstitutionInUrl": true,
      "Content": {"ContentType": "application/json"}
    }},
    {"SetItem": {"Name": "JsonString", "Value": "%{SystemUsers.Content}%"}},
    {"ExtractJsonObject": {"JsonObjectName": "JsonString", "Name": "ParsedResponse"}},
    {"SetItem": {"Name": "Users", "Value": "%{ParsedResponse.result}%"}},
    {"SetItem": {"Name": "ParsedUser", "Value": "%{ Users.FirstOrDefault(o => o.user_name != null && o.user_name.Value == AccountUserName) }%"}},
    {"SetItem": {"Name": "UserId", "Value": "%{ ParsedUser.sys_id.Value }%"}},
    {"Request": {
      "RequestObjectName": "SystemRequest",
      "ResponseObjectName": "SystemResponse",
      "Verb": "Patch",
      "Url": "api/now/table/sys_user/%UserId%",
      "SubstitutionInUrl": true,
      "Content": {
        "ContentObjectName": "ChangePassJson",
        "ContentType": "application/json"
      }
    }},
    {"Return": {"Value": true}}
  ]
}
```

### DiscoverAccounts

Paginated account enumeration using a `For` loop. Demonstrates:

- `For` loop with `Before`/`Condition`/`End`/`Body` for pagination
- `Status` command for progress reporting
- `Log` command for debug output
- `.Count()` method on collections
- Dynamic URL construction via string concatenation expressions

```json
"DiscoverAccounts": {
  "Parameters": [
    {"FuncApiKey": {"Type": "Secret"}},
    {"Address": {"Type": "String"}},
    {"PageSize": {"Type": "Integer", "Required": false, "DefaultValue": 100}}
  ],
  "Do": [
    {"BaseAddress": {"Address": "https://%Address%"}},
    {"SetItem": {"Name": "offset", "Value": 0}},
    {"SetItem": {"Name": "hasMore", "Value": true}},
    {"Status": {"Type": "Discovering", "Percent": 10, "Message": {"Name": "DiscoveringAccounts", "Parameters": ["%Address%"]}}},
    {"For": {
      "Before": "offset = 0",
      "Condition": "hasMore",
      "End": "offset = offset + PageSize",
      "Body": {"Do": [
        {"NewHttpRequest": {"ObjectName": "req"}},
        {"Headers": {"RequestObjectName": "req", "AddHeaders": {"x-sn-apikey": "%FuncApiKey%"}}},
        {"SetItem": {"Name": "url", "Value": "%{\"api/now/table/sys_user?sysparm_query=active=true&sysparm_fields=user_name,sys_id&sysparm_limit=\" + PageSize + \"&sysparm_offset=\" + offset}%"}},
        {"Request": {
          "RequestObjectName": "req",
          "ResponseObjectName": "resp",
          "Verb": "GET",
          "Url": "%url%",
          "SubstitutionInUrl": true,
          "Content": {"ContentType": "application/json"}
        }},
        {"SetItem": {"Name": "jsonStr", "Value": "%{resp.Content}%"}},
        {"ExtractJsonObject": {"JsonObjectName": "jsonStr", "Name": "parsed"}},
        {"SetItem": {"Name": "users", "Value": "%{parsed.result}%"}},
        {"SetItem": {"Name": "count", "Value": "%{users.Count()}%"}},
        {"Log": {"Text": "Discovered %{count}% users at offset %{offset}%"}},
        {"Condition": {
          "If": "count == 0",
          "Then": {"Do": [
            {"SetItem": {"Name": "hasMore", "Value": false}}
          ]},
          "Else": {"Do": [
            {"ForEach": {
              "CollectionName": "users",
              "ElementName": "user",
              "Body": {"Do": [
                {"WriteDiscoveredAccount": {"Name": "%{user.user_name.Value}%"}}
              ]}
            }}
          ]}
        }},
        {"Condition": {
          "If": "count < PageSize",
          "Then": {"Do": [
            {"SetItem": {"Name": "hasMore", "Value": false}}
          ]}
        }}
      ]}
    }},
    {"Status": {"Type": "Discovering", "Percent": 100, "Message": {"Name": "DiscoveringAccounts", "Parameters": ["%Address%"]}}},
    {"Return": {"Value": true}}
  ]
}
```

## Key Patterns from This Implementation

### Two-Step JSON Parsing (Proven Correct)

The correct pattern for parsing HTTP response bodies:

```json
{"SetItem": {"Name": "JsonString", "Value": "%{Response.Content}%"}},
{"ExtractJsonObject": {"JsonObjectName": "JsonString", "Name": "Parsed"}}
```

Do NOT pass the response object directly to `ExtractJsonObject`. First extract
`.Content` into a string variable, then parse that string.

### LINQ Expressions for Object Queries

Use `FirstOrDefault()` with a lambda to find specific items in collections:

```json
{"SetItem": {
  "Name": "MatchedUser",
  "Value": "%{ Collection.FirstOrDefault(o => o.property != null && o.property.Value == TargetValue) }%"
}}
```

### Accessing ServiceNow Field Values

ServiceNow REST API returns fields as objects with a `.Value` property:

```json
{"SetItem": {"Name": "UserId", "Value": "%{ user.sys_id.Value }%"}}
{"WriteDiscoveredAccount": {"Name": "%{user.user_name.Value}%"}}
```

### Paginated API Calls

Use the `For` loop for paginated endpoints:

```json
{"For": {
  "Before": "offset = 0",
  "Condition": "hasMore",
  "End": "offset = offset + PageSize",
  "Body": {"Do": [ ... ]}
}}
```

Stop condition: set `hasMore = false` when `count < PageSize` or `count == 0`.

## ServiceNow Prerequisites

1. **API Key**: Admin > System Security > API Keys
   - User must have `rest_service` role
   - User must have table ACL on `sys_user` (read, write for password changes)

2. **Service Account**: A ServiceNow user with:
   - API access enabled
   - Permission to read `sys_user` table
   - Permission to PATCH `user_password` field on `sys_user`

## Safeguard Configuration

1. Upload the platform script: `Import-SafeguardCustomPlatformScript`
2. Create an asset with `ServiceAccountCredentialType = "Custom"`
3. **Set `FuncApiKey` via the Safeguard GUI** (Asset > Custom Script Parameters)
4. Create a test account matching a real ServiceNow username
5. Run `Set-SafeguardAssetAccountPassword` or ChangePassword before CheckPassword

## Account Discovery Setup

Discovery requires additional Safeguard configuration beyond the script:

1. Create a discovery schedule (via GUI or API)
2. Configure a discovery rule (e.g., `NameFilter=safeguard*`, `AutoManage=false`)
3. Assign the schedule to the asset (`AccountDiscoveryScheduleId`)
4. Trigger: `Invoke-SafeguardMethod -Service Core -Method POST -RelativeUrl "Assets/{id}/DiscoverAccounts"`

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| ChangePassword silent fail | No password in vault | Run `Set-SafeguardAssetAccountPassword` first |
| Empty extraction / literal `%AccountUserName%` | Missing `SubstitutionInUrl: true` | Add `"SubstitutionInUrl": true` to the Request |
| No accounts discovered | Rule mismatch or discovery not configured | Check NameFilter, ensure schedule assigned to asset |
| API 403 | Missing ACL | Ensure `rest_service` role + `sys_user` table ACL |
| Cannot change asset platform | Safeguard limitation | Must create a new asset (cannot change platform type) |

## Discovery Credentials Table

ServiceNow's `discovery_credentials` table stores credentials used by Discovery for SSH, SNMP, Windows, etc. This table has **different field formats** than `sys_user`.

### Key Differences from sys_user

| Aspect | sys_user table | discovery_credentials table |
|--------|----------------|----------------------------|
| Field format | Objects with `.Value` property | **Plain strings** |
| Access pattern | `%{user.user_name.Value}%` | `%{cred.user_name}%` |
| Has user_password | Yes (PATCH to change) | Yes (PATCH to change) |
| Empty values | Rare | **Common** (OAuth, SNMP credentials have empty `user_name`) |

### Critical Gotchas for discovery_credentials

1. **Plain string field values**: Unlike `sys_user`, the `discovery_credentials` table returns `user_name` and `sys_id` as plain strings, NOT objects with `.Value`:
   ```json
   // WRONG for discovery_credentials:
   {"WriteDiscoveredAccount": {"Name": "%{cred.user_name.Value}%"}}
   
   // CORRECT for discovery_credentials:
   {"WriteDiscoveredAccount": {"Name": "%{cred.user_name}%"}}
   ```

2. **Filter empty usernames**: Many credential types (OAuth, SNMP, MID Server) have empty `user_name` fields. These cause `WriteDiscoveredAccount` to fail silently. Always filter:
   ```
   sysparm_query=type=ssh^use_high_security=false^user_nameISNOTEMPTY
   ```

3. **Filter values vs display names**: The `type` field uses lowercase values (`ssh`, `snmp`, `windows`), not display names (`SSH Credentials`, `SNMP Community String`).

4. **Test externally first**: Query the API directly before relying on Safeguard discovery:
   ```bash
   curl -s -H "x-sn-apikey: $KEY" \
     "https://instance.service-now.com/api/now/table/discovery_credentials?sysparm_limit=5" | jq .
   ```

### Working DiscoverAccounts for discovery_credentials

```json
"DiscoverAccounts": {
  "Parameters": [
    {"FuncApiKey": {"Type": "Secret"}},
    {"Address": {"Type": "String"}},
    {"DiscoveryQuery": {"Type": "Object", "Required": false}}
  ],
  "Do": [
    {"BaseAddress": {"Address": "https://%Address%"}},
    {"NewHttpRequest": {"ObjectName": "req"}},
    {"Headers": {"RequestObjectName": "req", "AddHeaders": {"x-sn-apikey": "%FuncApiKey%"}}},
    {"Request": {
      "RequestObjectName": "req",
      "ResponseObjectName": "resp",
      "Verb": "GET",
      "Url": "api/now/table/discovery_credentials?sysparm_query=type=ssh^use_high_security=false^user_nameISNOTEMPTY&sysparm_fields=sys_id,user_name,name,type",
      "Content": {"ContentType": "application/json"}
    }},
    {"SetItem": {"Name": "jsonStr", "Value": "%{resp.Content}%"}},
    {"ExtractJsonObject": {"JsonObjectName": "jsonStr", "Name": "parsed"}},
    {"SetItem": {"Name": "creds", "Value": "%{parsed.result}%"}},
    {"ForEach": {
      "CollectionName": "creds",
      "ElementName": "cred",
      "Body": {"Do": [
        {"WriteDiscoveredAccount": {"Name": "%{cred.user_name}%"}}
      ]}
    }},
    {"Return": {"Value": true}}
  ]
}
```

### Debugging Discovery Failures

Discovery framework failures are opaque. If discovery fails:

1. **No audit log in `AuditLog/Passwords/DiscoverAccounts`**: Framework-level failures don't create entries here
2. **Check `AuditLog/Search`**: Look for `AccountDiscoveryFailed` events (limited error details)
3. **Test the query externally**: Use curl/PowerShell to verify the API returns expected data
4. **Check for empty values**: Empty `user_name` fields cause silent failures
5. **Verify field format**: Are you using `.Value` when you shouldn't be, or vice versa?

### Discovery Rule Configuration

When creating discovery rules for `discovery_credentials`:

```powershell
# Create rule with AutoManageDiscoveredAccounts=false (important for testing)
$ruleBody = @{
    Name = "SSH Credentials"
    AssetId = 135
    NameFilter = "*"
    AutoManageDiscoveredAccounts = $false  # Prevent auto password changes
}
Invoke-SafeguardMethod -Service Core -Method POST -RelativeUrl "AssetDiscoveryRules" -Body $ruleBody -Insecure
```
