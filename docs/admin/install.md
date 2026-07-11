# Installation Guide

## Prerequisites

- Windows 10 (build 17763 / 1809) or later, or Windows Server 2019 or later
- x64 architecture
- Local administrator privileges
- Package content source accessible (from distribution point or local path)
- Internet access: **NOT required** — the package is offline-installable

## MECM/SCCM Deployment

See `packaging/mecm/application-notes.md` for full MECM/SCCM application setup instructions.

**Install command:**
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json
```

## Manual Installation

1. Extract the release ZIP to a local directory.
2. Open an elevated PowerShell session.
3. Navigate to the extracted directory.
4. Run the install script:

```powershell
.\scripts\Install-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json
```

To provide a service account password:
```powershell
$pw = Read-Host -AsSecureString "Service account password"
.\scripts\Install-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json -ServiceAccountPassword $pw
```

## What the Install Does

1. Validates arguments and package configuration
2. Validates package integrity (SHA256 hashes)
3. Creates required directories under `C:\Program Files\EnterpriseAI` and `C:\ProgramData\EnterpriseAI`
4. Stages runtime files (Ollama, Python, LiteLLM) from the vendor directory
5. Creates or repairs the `svc_EnterpriseAI` local service account
6. Applies filesystem ACLs
7. Writes the LiteLLM API key to `C:\ProgramData\EnterpriseAI\Secrets`
8. Renders Ollama and LiteLLM configuration from templates
9. Creates Windows services (`EnterpriseAI-Ollama`, `EnterpriseAI-LiteLLM`)
10. Configures service recovery (auto-restart on failure)
11. Creates package firewall rules (`EnterpriseAI-*`)
12. Starts both services
13. Runs post-install validation
14. Writes package state to registry

## Post-Install Validation

After installation, run the validation script to verify correct configuration:

```powershell
.\scripts\Test-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json
```

## Log File

Install log: `C:\ProgramData\EnterpriseAI\Logs\Install\install.log`

## Troubleshooting

See [troubleshooting.md](troubleshooting.md) for common issues and resolutions.
