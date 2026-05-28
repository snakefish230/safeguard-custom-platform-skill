# Salesforce Custom Platform -- Working Reference Implementation

This is a complete, working example of a custom platform for Salesforce CRM using
OAuth 2.0 Password flow with the Salesforce REST API.

## Custom Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `SfClientId` | String | Salesforce Connected App Consumer Key |
| `SfClientSecret` | Secret | Salesforce Connected App Consumer Secret |
| `ApiVersion` | String | Salesforce API version (default: `v62.0`) |

## Operations Implemented

### CheckSystem

Authenticates as the service account via OAuth password flow. Returns `true` if
the token endpoint returns HTTP 200.

```json
{
    "BaseAddress": { "Address": "https://%Address%" }
},
{
    "SetItem": {
        "Name": "TokenUrl",
        "Value": "/services/oauth2/token?grant_type=password&client_id=%SfClientId%&client_secret=%SfClientSecret%&username=%FuncUsername%&password=%FuncPassword%",
        "IsSecret": true
    }
},
{
    "Request": {
        "RequestObjectName": "AuthReq",
        "ResponseObjectName": "AuthResp",
        "Verb": "POST",
        "Url": "%TokenUrl%",
        "SubstitutionInUrl": true,
        "IsSecret": true,
        "Content": {}
    }
},
{
    "Condition": {
        "If": "AuthResp.StatusCode == 200",
        "Then": { "Do": [{ "Return": { "Value": true } }] },
        "Else": { "Do": [{ "Return": { "Value": false } }] }
    }
}
```

### CheckPassword

Same OAuth flow but using `AccountUsername`/`AccountPassword` instead of the
service account credentials. If the target account can authenticate, the
password is correct.

### ChangePassword

1. Authenticate as service account (OAuth)
2. Extract bearer token from response
3. SOQL query to find the user: `SELECT Id FROM User WHERE Username='%AccountUsername%' AND IsActive=true`
4. POST new password to `/services/data/v62.0/sobjects/User/{userId}/password`
5. Return `true` on HTTP 204 or 200

Key patterns used:

```json
{
    "ExtractJsonObject": { "JsonObjectName": "AuthResp", "Name": "AuthJson" }
},
{
    "SetItem": { "Name": "BearerToken", "Type": "Secret", "Value": "%{AuthJson.access_token}%" }
},
{
    "Request": {
        "Verb": "GET",
        "Url": "services/data/%ApiVersion%/query?q=SELECT+Id+FROM+User+WHERE+Username='%AccountUsername%'+AND+IsActive=true",
        "SubstitutionInUrl": true
    }
},
{
    "ExtractJsonObject": { "JsonObjectName": "QResp", "Name": "QJson" }
},
{
    "Condition": {
        "If": "QJson.totalSize == 0",
        "Then": { "Do": [{ "Throw": { "Value": "User not found" } }] }
    }
},
{
    "SetItem": { "Name": "UserId", "Value": "%{QJson.records[0].Id}%" }
},
{
    "SetItem": { "Name": "CBody", "Value": { "NewPassword": "%NewPassword%" }, "IsSecret": true }
},
{
    "Request": {
        "Verb": "POST",
        "Url": "services/data/%ApiVersion%/sobjects/User/%UserId%/password",
        "SubstitutionInUrl": true,
        "IsSecret": true,
        "Content": { "ContentType": "application/json", "ContentObjectName": "CBody" }
    }
}
```

### DiscoverAccounts

1. Authenticate as service account
2. SOQL query: `SELECT Id,Username,Email FROM User WHERE IsActive=true`
3. ForEach over records, `WriteDiscoveredAccount` for each username

## Salesforce Prerequisites

1. **Create a Connected App** in Salesforce:
   - Setup > App Manager > New Connected App
   - Enable OAuth: scopes `api`, `refresh_token`, `offline_access`
   - Set callback URL (any valid URL)

2. **Configure Connected App policies**:
   - Admin-approved users
   - Relaxed IP restrictions
   - Assign permission set to the service account user

3. **Service Account** in Salesforce:
   - Profile: System Administrator (or custom with "Reset User Passwords", "Manage Users", "API Enabled")

4. **Note the Consumer Key and Consumer Secret** from the Connected App

## Safeguard Configuration

After uploading the platform and creating an asset:

1. Set `SfClientId` and `SfClientSecret` via the Safeguard GUI (Asset > Custom Script Parameters)
2. Set the service account username/password on the asset connection properties
3. Create a test account and run ChangePassword before CheckPassword

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `invalid_grant` | Service account not pre-authorized for Connected App, or bad credentials |
| `not pre-authorized` | Assign the user to the Connected App's permission set |
| `API_DISABLED_FOR_ORG` | Enable API access in Salesforce org settings |
| User not found | Verify the AccountUsername matches the Salesforce username exactly (case-sensitive email format) |
