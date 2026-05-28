# Custom Platform Script Command Reference

## Script Structure

Every custom platform script is a JSON document:

```json
{
    "Id": "PlatformName",
    "BackEnd": "Scriptable",
    "Meta": {
        "Author": "Author Name",
        "Description": "Description of the platform",
        "ScriptVersion": "1.0",
        "Last Updated": "YYYY-MM-DD"
    },
    "CheckSystem": { ... },
    "CheckPassword": { ... },
    "ChangePassword": { ... },
    "DiscoverAccounts": { ... },
    "Functions": []
}
```

- `Id`: Alphanumeric only (regex: `^[a-zA-Z0-9]+$`). No spaces, hyphens, or special characters.
- `BackEnd`: Must be `"Scriptable"`.
- `Meta`: Must include `Author`, `Description`, `ScriptVersion`, `Last Updated` (YYYY-MM-DD format).

## Operations

| Operation | Purpose | Required |
|-----------|---------|----------|
| `CheckSystem` | Test connectivity using the service account | Recommended |
| `CheckPassword` | Verify stored password matches the target | Recommended |
| `ChangePassword` | Update password for a managed account | Recommended |
| `DiscoverAccounts` | Enumerate accounts on the target | Optional |

Each operation has a `Parameters` array and a `Do` array of commands.

## Parameters

### Well-Known Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `Address` | String | Network address of the asset |
| `FuncUsername` | String | Service account username |
| `FuncPassword` | Secret | Service account password |
| `AccountUsername` | String | Target account username |
| `AccountPassword` | Secret | Target account current password |
| `NewPassword` | Secret | New password for password change |

### Custom Parameters

Define custom parameters (e.g., `SfClientId`, `ApiKey`) configured per-asset in Safeguard:

```json
{ "SfClientId": { "Type": "String", "Required": true } }
{ "SfClientSecret": { "Type": "Secret", "Required": true } }
{ "ApiVersion": { "Type": "String", "Required": false, "DefaultValue": "v62.0" } }
```

**Supported types:** `String`, `Secret`, `boolean`, `integer`

**Important:** Secret parameter values must be configured via the Safeguard GUI (Asset > Custom Script Parameters). The REST API strips secret values on write.

## HTTP Commands

### BaseAddress

Set the base URL for all subsequent HTTP requests:

```json
{ "BaseAddress": { "Address": "https://%Address%" } }
```

### NewHttpRequest

Create a new HTTP request object:

```json
{ "NewHttpRequest": { "ObjectName": "RequestName" } }
```

### Headers

Add headers to a request object:

```json
{ "Headers": {
    "RequestObjectName": "RequestName",
    "AddHeaders": { "Authorization": "Bearer %Token%", "Content-Type": "application/json" }
} }
```

### Request

Execute an HTTP request:

```json
{ "Request": {
    "RequestObjectName": "RequestName",
    "ResponseObjectName": "ResponseName",
    "Verb": "GET|POST|PUT|DELETE|PATCH",
    "Url": "/api/endpoint/%Variable%",
    "SubstitutionInUrl": true,
    "IgnoreServerCertAuthentication": false,
    "IsSecret": false,
    "Content": {
        "ContentType": "application/json",
        "ContentObjectName": "BodyObject"
    }
} }
```

## SSH Commands

### SshConnect

Open an SSH connection:

```json
{ "SshConnect": {
    "Address": "%Address%",
    "Port": "%Port%",
    "UserName": "%FuncUsername%",
    "Password": "%FuncPassword%",
    "RequestTerminal": "%RequestTerminal%",
    "ConnectionObjectName": "SshConn"
} }
```

### SshCommand

Execute a command over SSH:

```json
{ "SshCommand": {
    "ConnectionObjectName": "SshConn",
    "Command": "echo 'test'",
    "ResponseObjectName": "CmdResp"
} }
```

Check `CmdResp.ExitStatus` for the exit code and `CmdResp.Output` for stdout.

### SshDisconnect

Close an SSH connection:

```json
{ "SshDisconnect": { "ConnectionObjectName": "SshConn" } }
```

## Data Commands

### SetItem

Create or set a variable:

```json
{ "SetItem": { "Name": "VariableName", "Value": "some value" } }
{ "SetItem": { "Name": "SecretVar", "Value": "%SomeSecret%", "IsSecret": true } }
{ "SetItem": { "Name": "JsonBody", "Value": { "key": "value" } } }
```

### ExtractJsonObject

Parse a JSON string into a navigable object. **Important:** Do not pass the
response object directly. First extract `.Content` into a string variable, then
parse that string. This two-step pattern is proven correct:

```json
{ "SetItem": { "Name": "JsonString", "Value": "%{Response.Content}%" } },
{ "ExtractJsonObject": { "JsonObjectName": "JsonString", "Name": "ParsedResult" } }
```

After extraction, access properties: `%{ParsedResult.property}%` or `%{ParsedResult.records[0].Id}%`.

### Log

Write a debug message to the Safeguard task log:

```json
{ "Log": { "Text": "Discovered %{count}% users at offset %{offset}%" } }
```

### Status

Report progress during long-running operations (e.g., discovery):

```json
{ "Status": {
    "Type": "Discovering",
    "Percent": 50,
    "Message": { "Name": "DiscoveringAccounts", "Parameters": ["%Address%"] }
} }
```

## Control Flow Commands

### Condition

Conditional branching:

```json
{ "Condition": {
    "If": "ResponseObj.StatusCode == 200",
    "Then": { "Do": [ ... ] },
    "Else": { "Do": [ ... ] }
} }
```

### Switch

Multi-branch matching:

```json
{ "Switch": {
    "MatchValue": "%{ResponseObj.StatusCode.ToString()}%",
    "Cases": [
        { "CaseValue": "200|(OK)", "Do": [ { "Return": { "Value": "true" } } ] },
        { "CaseValue": "404|(NotFound)", "Do": [ { "Return": { "Value": "false" } } ] }
    ],
    "DefaultCase": [ { "Throw": { "Value": "Unexpected status code" } } ]
} }
```

### ForEach

Iterate over a collection:

```json
{ "ForEach": {
    "CollectionName": "Records",
    "ElementName": "item",
    "Body": {
        "Do": [
            { "WriteDiscoveredAccount": { "Name": "%{item.Username}%" } }
        ]
    }
} }
```

### ForEachLine

Iterate over lines of text output (useful for SSH command output):

```json
{ "ForEachLine": {
    "Content": "%{CmdResp.Output}%",
    "ElementName": "line",
    "Body": {
        "Do": [
            { "WriteDiscoveredAccount": { "Name": "%line%" } }
        ]
    }
} }
```

### For

C-style loop with initializer, condition, and increment. Useful for paginated API calls:

```json
{ "For": {
    "Before": "offset = 0",
    "Condition": "hasMore",
    "End": "offset = offset + PageSize",
    "Body": { "Do": [ ... ] }
} }
```

Use `SetItem` to set `hasMore = false` when the stop condition is met (e.g., result count < page size).

See [references/servicenow-example.md](servicenow-example.md) for a complete paginated discovery example.

### Try/Catch

Error handling:

```json
{ "Try": {
    "Do": [ ... ],
    "Catch": [ ... ]
} }
```

## Output Commands

### WriteDiscoveredAccount

Output a discovered account (used in `DiscoverAccounts`):

```json
{ "WriteDiscoveredAccount": { "Name": "%{item.Username}%" } }
```

### Return

Return a value from the operation:

```json
{ "Return": { "Value": "true" } }
```

Return `true` for success, `false` for "not found" / "password mismatch".

### Throw

Throw an error and fail the operation:

```json
{ "Throw": { "Value": "Descriptive error message: %{Response.Content}%" } }
```

## Variable Substitution

- `%VariableName%` -- simple string substitution
- `%{Expression}%` -- inline expression (property access, method calls)
- `%{Response.StatusCode.ToString()}%` -- convert to string
- `%{Parsed.records[0].Id}%` -- array indexing
- `%{Parsed.result[0].sys_id.Value}%` -- nested property access
- `%{Convert.ToBase64String(Encoding.UTF8.GetBytes(Username + ':' + Password))}%` -- Base64 encoding
- `%{Collection.Count()}%` -- count items in a collection
- `%{Collection.FirstOrDefault(o => o.prop != null && o.prop.Value == Target)}%` -- LINQ query
- `%{"literal" + Variable + "more literal"}%` -- string concatenation

### LINQ Expressions

Collections support LINQ-style methods for querying objects:

```json
{ "SetItem": {
    "Name": "MatchedUser",
    "Value": "%{ Users.FirstOrDefault(o => o.user_name != null && o.user_name.Value == AccountUserName) }%"
} }
```

This is proven useful when the API returns a collection and you need to find a specific item by property value. Access the matched object's properties afterward:

```json
{ "SetItem": { "Name": "UserId", "Value": "%{ MatchedUser.sys_id.Value }%" } }
```

### Important Notes

- Use `%VariableName%` in URLs with `"SubstitutionInUrl": true`. Do NOT use `%{UrlEncode()}%` -- it does not resolve.
- Mark variables containing secrets with `"IsSecret": true` to prevent logging.
- Passwords containing `%` will break variable substitution.
- Some APIs (e.g., ServiceNow) return field values as objects with a `.Value` property -- use `%{item.field.Value}%` not `%{item.field}%`.

## Common Patterns

### OAuth Token Acquisition

```json
{ "SetItem": {
    "Name": "TokenUrl",
    "Value": "/oauth2/token?grant_type=password&client_id=%ClientId%&client_secret=%ClientSecret%&username=%FuncUsername%&password=%FuncPassword%",
    "IsSecret": true
} },
{ "Request": {
    "RequestObjectName": "AuthReq",
    "ResponseObjectName": "AuthResp",
    "Verb": "POST",
    "Url": "%TokenUrl%",
    "SubstitutionInUrl": true,
    "IsSecret": true,
    "Content": {}
} },
{ "SetItem": { "Name": "AuthContent", "Value": "%{AuthResp.Content}%" } },
{ "ExtractJsonObject": { "JsonObjectName": "AuthContent", "Name": "AuthJson" } },
{ "SetItem": { "Name": "BearerToken", "Type": "Secret", "Value": "%{AuthJson.access_token}%" } }
```

### Find-Then-Modify User (Proven Pattern)

Query for a user, extract the ID, then modify. This pattern is from the
verified ServiceNow implementation:

```json
{ "Request": {
    "Verb": "GET",
    "Url": "api/now/table/sys_user?sysparm_query=user_name=%AccountUserName%&sysparm_limit=1&sysparm_fields=sys_id,user_name",
    "SubstitutionInUrl": true, ...
} },
{ "SetItem": { "Name": "JsonString", "Value": "%{SystemUsers.Content}%" } },
{ "ExtractJsonObject": { "JsonObjectName": "JsonString", "Name": "ParsedResponse" } },
{ "SetItem": { "Name": "Users", "Value": "%{ParsedResponse.result}%" } },
{ "SetItem": { "Name": "ParsedUser", "Value": "%{ Users.FirstOrDefault(o => o.user_name != null && o.user_name.Value == AccountUserName) }%" } },
{ "SetItem": { "Name": "UserId", "Value": "%{ ParsedUser.sys_id.Value }%" } },
{ "Request": { "Verb": "Patch", "Url": "api/now/table/sys_user/%UserId%", "SubstitutionInUrl": true, ... } }
```

### Paginated Discovery

Use `For` loop with offset-based pagination:

```json
{ "SetItem": { "Name": "offset", "Value": 0 } },
{ "SetItem": { "Name": "hasMore", "Value": true } },
{ "For": {
    "Before": "offset = 0",
    "Condition": "hasMore",
    "End": "offset = offset + PageSize",
    "Body": { "Do": [
        { "Request": { "Verb": "GET", "Url": "%url%", ... } },
        { "SetItem": { "Name": "jsonStr", "Value": "%{resp.Content}%" } },
        { "ExtractJsonObject": { "JsonObjectName": "jsonStr", "Name": "parsed" } },
        { "SetItem": { "Name": "count", "Value": "%{parsed.result.Count()}%" } },
        { "Condition": { "If": "count == 0", "Then": { "Do": [
            { "SetItem": { "Name": "hasMore", "Value": false } }
        ] } } },
        { "ForEach": { "CollectionName": "users", "ElementName": "user", "Body": { "Do": [
            { "WriteDiscoveredAccount": { "Name": "%{user.user_name.Value}%" } }
        ] } } }
    ] }
} }
```

## External References

- [SafeguardCustomPlatform Wiki](https://github.com/OneIdentity/SafeguardCustomPlatform/wiki)
- [Command Reference](https://github.com/OneIdentity/SafeguardCustomPlatform/wiki/Command-Reference)
- [Sample Scripts](https://github.com/OneIdentity/SafeguardCustomPlatform/blob/master/SampleScripts)
