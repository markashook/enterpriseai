# EnterpriseAI Local Runtime and Gateway

A Microsoft Configuration Manager (MECM/SCCM) compatible Windows deployment package that installs and manages a workstation-local AI runtime and gateway stack on enterprise developer workstations.

## What This Package Does

- Installs **Ollama** as a protected local model inference service (`EnterpriseAI-Ollama`)
- Installs **LiteLLM** as an OpenAI-compatible AI gateway (`EnterpriseAI-LiteLLM`)
- Configures both services to bind on loopback addresses only
- Enforces API key authentication on the LiteLLM endpoint
- Restricts access to only approved model aliases
- Manages service accounts, ACLs, and Windows Firewall rules
- Supports silent install, repair, and uninstall via MECM/SCCM

## Architecture

```
User AI Client (Continue.dev, Open WebUI, etc.)
      │
      │  http://127.0.0.1:4000  (requires API key)
      ▼
 LiteLLM  [EnterpriseAI-LiteLLM]
      │
      │  http://127.0.0.2:11434  (internal only)
      ▼
  Ollama  [EnterpriseAI-Ollama]
      │
      ▼
C:\ProgramData\EnterpriseAI\Models
```

**Users connect only to LiteLLM.** Ollama is a protected backend service.

## Quick Start

### MECM/SCCM Deployment

See [`packaging/mecm/application-notes.md`](packaging/mecm/application-notes.md) for full setup instructions.

| Command | Script |
|---------|--------|
| Install | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json` |
| Repair | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Repair-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json` |
| Uninstall | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json` |

### Post-Install Validation

```powershell
.\scripts\Test-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json
```

## Default Endpoints

| Endpoint | Address | Access |
|----------|---------|--------|
| LiteLLM (user-facing) | `http://127.0.0.1:4000` | Requires API key |
| Ollama (backend only) | `http://127.0.0.2:11434` | Internal only |

## Requirements

- Windows 10 (build 17763) or later / Windows Server 2019 or later
- x64 architecture
- Local administrator privileges for install/repair/uninstall
- No Internet access required at install time (offline-installable)

## Documentation

- **Administrators:** [`docs/admin/`](docs/admin/)
- **Users:** [`docs/user/`](docs/user/)
- **CI/CD:** [`docs/ci/`](docs/ci/)
- **Design intent:** [`INTENT.md`](INTENT.md)
- **Security policy:** [`SECURITY.md`](SECURITY.md)

## Repository Structure

```
.
├── INTENT.md              # Design intent for maintainers
├── config/                # Configuration templates
├── scripts/               # Install, repair, uninstall, detection, validation
│   └── modules/           # Reusable PowerShell modules
├── packaging/             # Build scripts and MECM/SCCM files
├── vendor/                # Vendored upstream components (populated by CI)
├── manifest/              # Dependency lockfile, hashes, SBOM
├── docs/                  # Administrator and user documentation
├── tests/                 # Pester test scaffolding
└── .github/workflows/     # CI, package, and release workflows
```

## Security

This package does not:
- Install AI models (model content is a separate package)
- Expose services to the LAN
- Allow arbitrary model pulls by default
- Commit plaintext secrets

See [`SECURITY.md`](SECURITY.md) and [`docs/admin/threat-model.md`](docs/admin/threat-model.md) for details.

