# Safeguard Custom Platform Skill

An [Agent Skill](https://agentskills.io) that gives AI agents the expertise to build, deploy, and test Custom Platforms for **One Identity Safeguard for Privileged Passwords (SPP)**.

Custom Platforms extend Safeguard's ability to manage privileged accounts on applications and systems that are not natively supported -- such as Salesforce, ServiceNow, MongoDB, custom REST APIs, and SSH-based infrastructure.

## What This Skill Does

When activated, the skill guides an agent through a structured 7-phase workflow:

1. **Feasibility Assessment** -- determine if the target platform can be integrated (HTTP/REST, SSH, or Database)
2. **Requirements Gathering** -- document operations, authentication methods, and permissions
3. **Environment Setup** -- install dependencies and configure connectivity to the Safeguard appliance
4. **Script Development** -- select a template, customize the JSON platform script, and validate
5. **Upload and Configure** -- deploy the platform, create an asset, and set up test accounts
6. **Testing** -- run end-to-end tests (connectivity, password change, password check, discovery)
7. **Iteration and Documentation** -- fix failures, re-upload, and document the finished platform

## Prerequisites

- **PowerShell 7.4 LTS** (7.6+ has a known serialization bug)
- **[safeguard-ps](https://github.com/OneIdentity/safeguard-ps)** PowerShell module
- Network access to a Safeguard SPP appliance
- A Safeguard service account with **Authorizer** and **Asset Administrator** roles

## Directory Structure

```
safeguard-custom-platform-skill/
├── SKILL.md                          # Skill metadata and core workflow instructions
├── README.md                         # This file
├── scripts/
│   ├── setup-dev-environment.ps1     # Bootstrap: install modules, create config
│   ├── generate-platform.ps1         # Interactive wizard to scaffold a new platform
│   ├── upload-to-safeguard.ps1       # Upload platform, create asset and account
│   └── test-platform.ps1             # End-to-end test runner with pass/fail reporting
├── references/
│   ├── script-command-reference.md   # Full JSON script format and command reference
│   ├── authentication-methods.md     # Safeguard and target platform auth methods
│   ├── permission-requirements.md    # Service account permissions at every level
│   └── salesforce-example.md         # Working Salesforce reference implementation
└── assets/
    └── templates/
        ├── base-platform.json        # Minimal skeleton (start here if nothing else fits)
        ├── http-oauth-password.json  # REST API with OAuth 2.0 password flow
        ├── http-apikey.json          # REST API with API key authentication
        ├── http-basic.json           # REST API with Basic authentication
        ├── ssh-password.json         # SSH-based platforms (Linux/Unix)
        └── database-sql.json        # Database platforms (via SSH or REST proxy)
```

## How Agent Skills Work

Agent Skills use **progressive disclosure** to minimize context usage:

1. **Discovery** -- the agent reads only `name` and `description` from the SKILL.md frontmatter at startup
2. **Activation** -- when a task matches (e.g., "create a custom platform for ServiceNow"), the full SKILL.md body loads into context
3. **Execution** -- the agent follows the workflow, loading reference files and templates only as needed

This means the skill can be installed alongside many other skills without consuming context until it is actually needed.

## Compatible Agents

This skill follows the open [Agent Skills specification](https://agentskills.io/specification) and works with any compatible agent, including:

- [Claude Code](https://claude.ai/code)
- [OpenCode](https://opencode.ai/)
- [VS Code / GitHub Copilot](https://code.visualstudio.com/)
- [Cursor](https://cursor.com/)
- [Gemini CLI](https://geminicli.com/)
- [OpenHands](https://openhands.dev/)

See the full list of supported clients at [agentskills.io/clients](https://agentskills.io/clients).

## Installation

Copy or symlink this directory into the skill location expected by your agent. For example:

**VS Code / GitHub Copilot:**
```bash
cp -r safeguard-custom-platform-skill .agents/skills/safeguard-custom-platform-skill
```

**Claude Code:**
```bash
cp -r safeguard-custom-platform-skill .claude/skills/safeguard-custom-platform-skill
```

**OpenCode:**
```bash
cp -r safeguard-custom-platform-skill .opencode/skills/safeguard-custom-platform-skill
```

Consult your agent's documentation for the exact skills directory path.

## Quick Start

Once installed, ask your agent something like:

- "Create a custom platform for ServiceNow"
- "Add Salesforce support to Safeguard"
- "Build a custom platform script for our MongoDB servers"
- "Help me integrate an unsupported system with Safeguard for privileged account management"

The agent will activate the skill and walk you through the full workflow.

## Available Templates

| Template | Use Case |
|----------|----------|
| `http-oauth-password.json` | SaaS/cloud APIs using OAuth 2.0 with username/password grant |
| `http-apikey.json` | APIs authenticated with a static API key header |
| `http-basic.json` | APIs using HTTP Basic authentication |
| `ssh-password.json` | Linux/Unix servers and network devices accessible over SSH |
| `database-sql.json` | Databases accessed via an SSH jump host or REST API proxy |
| `base-platform.json` | Minimal skeleton when none of the above fit |

## Key Constraints

- **Secret parameters** (API keys, client secrets) must be set through the Safeguard web GUI -- the REST API strips secret values on write.
- **Test ordering matters** -- always run ChangePassword before CheckPassword. The vault must contain a password before CheckPassword can compare.
- **Scripts execute on the appliance** -- the Safeguard appliance runs the platform script, not the automation host. The appliance needs network access to the target.

## Related Resources

- [SafeguardCustomPlatform Wiki](https://github.com/OneIdentity/SafeguardCustomPlatform/wiki)
- [Command Reference](https://github.com/OneIdentity/SafeguardCustomPlatform/wiki/Command-Reference)
- [Sample Scripts](https://github.com/OneIdentity/SafeguardCustomPlatform/tree/master/SampleScripts)
- [safeguard-ps Module](https://github.com/OneIdentity/safeguard-ps)
- [Agent Skills Specification](https://agentskills.io/specification)
