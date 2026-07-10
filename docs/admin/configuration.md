# Configuration Reference

## Package Configuration

The primary configuration file is `config/enterpriseai.package.json`.

| Field | Default | Description |
|-------|---------|-------------|
| `PackageName` | EnterpriseAI Local Runtime and Gateway | Display name |
| `PackageShortName` | EnterpriseAI | Short name used in paths |
| `InstallRoot` | `C:\Program Files\EnterpriseAI` | Installation directory |
| `ProgramDataRoot` | `C:\ProgramData\EnterpriseAI` | Data directory |
| `ServiceAccountName` | `svc_EnterpriseAI` | Local service account name |
| `OllamaServiceName` | `EnterpriseAI-Ollama` | Ollama Windows service name |
| `LiteLLMServiceName` | `EnterpriseAI-LiteLLM` | LiteLLM Windows service name |
| `OllamaEndpoint` | `http://127.0.0.2:11434` | Ollama binding (loopback only) |
| `LiteLLMEndpoint` | `http://127.0.0.1:4000` | LiteLLM binding (loopback only) |
| `RuntimeModelPullsEnabled` | `false` | Allow runtime model pulls (must remain false in production) |
| `ApprovedModelRegistryUrl` | `` | Required if RuntimeModelPullsEnabled=true |
| `RequireLiteLLMApiKey` | `true` | Require API key for all LiteLLM requests |
| `FirewallRulePrefix` | `EnterpriseAI-` | Prefix for all package firewall rules |
| `PreserveProgramDataOnUninstall` | `true` | Keep ProgramData on uninstall |
| `DisableServiceAccountOnUninstall` | `true` | Disable (not delete) service account on uninstall |
| `RemoveServiceAccountOnUninstall` | `false` | Remove service account on uninstall |
| `FailIfRegistryUrlMissingWhenPullsEnabled` | `true` | Fail validation if pulls enabled but registry URL missing |

## Non-Negotiable Configuration Values

The following values **must not** be changed in production deployments:
- `RequireLiteLLMApiKey` must be `true`
- `RuntimeModelPullsEnabled` must be `false` unless a valid `ApprovedModelRegistryUrl` is set
- `OllamaEndpoint` must be a loopback address (127.x.x.x)
- `LiteLLMEndpoint` must be a loopback address (127.x.x.x)

## LiteLLM Configuration

The active LiteLLM configuration is rendered from `config/litellm.config.template.yaml` during install/repair and placed at:

```
C:\ProgramData\EnterpriseAI\Config\litellm.config.yaml
```

Do not edit the active config file directly; edit the template and run repair.

## Ollama Configuration

Ollama environment variables are rendered from `config/ollama.env.template` during install/repair and placed at:

```
C:\ProgramData\EnterpriseAI\Config\ollama.env
```

## Approved Models

The approved model list is defined in `config/approved-models.example.json`. Copy and customize this file for your deployment. LiteLLM will only expose model aliases defined in the approved models list.

## API Key

The LiteLLM API key is stored at:

```
C:\ProgramData\EnterpriseAI\Secrets\litellm.key
```

This file is protected by filesystem ACLs. Only `SYSTEM`, `Administrators`, and `svc_EnterpriseAI` have read access. Normal users have no access.

**Never commit the API key to source control.**

## Registry Values

Package state is written to:
```
HKLM:\Software\EnterpriseAI\LocalRuntimeGateway
```

Values:
- `DisplayName` — Package display name
- `DisplayVersion` — Installed version
- `InstallRoot` — Installation root path
- `ProgramDataRoot` — ProgramData root path
- `OllamaVersion` — Installed Ollama version
- `LiteLLMVersion` — Installed LiteLLM version
- `PackageVersion` — Package version
- `InstalledOn` — Installation timestamp
