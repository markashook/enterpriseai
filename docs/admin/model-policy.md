# Model Policy

## Overview

The EnterpriseAI package does **not** install model content. Models are delivered by separate packages and placed under `C:\ProgramData\EnterpriseAI\Models`.

## Approved Models

The approved model list is defined in `config/approved-models.example.json`. This file must be customized for your deployment and the active version placed at:

```
C:\ProgramData\EnterpriseAI\Config\approved-models.json
```

LiteLLM will only expose model aliases defined in the approved list. Requests for other model names are rejected.

## Adding or Changing Approved Models

1. Edit the approved models configuration to add or modify model aliases.
2. Run the repair script to re-render the LiteLLM configuration:
   ```
   .\scripts\Repair-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json
   ```
3. Validate the configuration:
   ```
   .\scripts\Test-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json
   ```

## Model Content Packages

Model content packages are expected to:
1. Place model files or registry references under `C:\ProgramData\EnterpriseAI\Models`
2. Be installed and uninstalled independently of this package
3. Not interfere with the EnterpriseAI service configuration

## Runtime Model Pulls

By default, runtime model pulls are **disabled** (`RuntimeModelPullsEnabled: false`).

If runtime pulls are required:
1. Set `RuntimeModelPullsEnabled: true` in `config/enterpriseai.package.json`
2. Set `ApprovedModelRegistryUrl` to the approved internal registry URL
3. Run repair to apply the updated configuration
4. Validate that only the approved registry is reachable

**Security note:** Enabling runtime model pulls increases risk. Ensure the approved registry URL points to an internal, controlled registry. Public Internet model pulls are not supported.

## Users Cannot Pull Models

There is no supported user-facing path to pull arbitrary models:
- LiteLLM rejects requests for unapproved model aliases
- The Ollama API pull endpoint is not accessible to users (Ollama binds to `127.0.0.2`, not `127.0.0.1`)
- ACLs prevent users from writing to the Models directory
