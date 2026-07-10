# INTENT.md — EnterpriseAI Local Runtime and Gateway

## 1. Purpose

This repository implements a Microsoft Configuration Manager (MECM/SCCM) compatible Windows deployment package that installs, configures, and manages a workstation-local AI runtime and gateway stack on enterprise developer workstations.

The stack consists of:
- **Ollama** — local model runtime, running as a protected Windows service
- **LiteLLM** — OpenAI-compatible AI gateway/proxy, running as a Windows service and serving as the sole user-facing endpoint

## 2. Scope

- Silent install, repair, and uninstall via MECM/SCCM Software Center
- Service lifecycle management (create, start, stop, remove, recovery)
- Service account provisioning and hardening
- Filesystem ACL enforcement
- Windows Firewall rule management
- LiteLLM API-key enforcement and model-alias gating
- Configuration rendering from templates
- Offline-installable release artifact generation via CI
- Dependency vendoring (Ollama binary, LiteLLM wheelhouse, Python runtime, service wrapper)
- Validation and health checks
- MECM/SCCM detection logic

## 3. Out-of-Scope Items

This package must **not**:
- Install AI models (model content is delivered by separate packages)
- Remove models by default during uninstall
- Install or manage user clients (Open WebUI, Continue.dev, Cline, aider, etc.)
- Expose Ollama or LiteLLM to the LAN
- Require Internet access at endpoint install time
- Allow users to pull arbitrary models
- Embed static plaintext service account passwords in committed scripts
- Claim Windows Firewall perfectly enforces loopback per-process isolation
- Remove unrelated firewall rules during uninstall

## 4. Architecture

```
User AI Client
      |
      | HTTP (OpenAI API)
      v
LiteLLM (127.0.0.1:4000)   [EnterpriseAI-LiteLLM service]
      |
      | HTTP (Ollama API)
      v
Ollama (127.0.0.2:11434)   [EnterpriseAI-Ollama service]
      |
      v
Models (C:\ProgramData\EnterpriseAI\Models)
```

Both services run as a local non-admin service account (`svc_EnterpriseAI`) under Windows. LiteLLM is the only documented user endpoint.

## 5. Service Model

| Service Name         | Binary/Process   | Account            | Purpose                            |
|----------------------|-----------------|--------------------|------------------------------------|
| EnterpriseAI-Ollama  | ollama.exe       | svc_EnterpriseAI   | Local model inference backend      |
| EnterpriseAI-LiteLLM | python / litellm | svc_EnterpriseAI   | OpenAI-compatible gateway/proxy    |

Both services are configured with automatic recovery (restart on failure).

## 6. Endpoint Model

| Endpoint               | Binding            | Audience       | Notes                             |
|------------------------|-------------------|----------------|-----------------------------------|
| http://127.0.0.1:4000  | Loopback only      | Users/clients  | LiteLLM; requires API key         |
| http://127.0.0.2:11434 | Loopback only      | LiteLLM only   | Ollama; not a user endpoint        |

Validation **must fail** if either service is detected listening on a non-loopback address.

## 7. Security Assumptions

- Host OS is enterprise-managed, patched, and joined to an Active Directory domain.
- Local administrators are fully trusted; this package cannot prevent admin bypass.
- The workstation is not shared between untrusted users.
- Network-level controls (corporate firewall, proxy) are enforced upstream.
- LiteLLM API key is injected at deployment time via a MECM parameter, not committed to the repository.
- ACLs prevent ordinary users from modifying service binaries, configuration, and secrets.
- Model content is delivered and managed by a separate package with its own access controls.

## 8. Threat Model

See `docs/admin/threat-model.md` for full details. Summary:

| Threat                        | Mitigation                                                              | Residual Risk          |
|-------------------------------|-------------------------------------------------------------------------|------------------------|
| Bypass LiteLLM via Ollama     | Ollama binds to 127.0.0.2; firewall rules restrict direct access        | Admin can bypass       |
| Arbitrary model loading       | Model directory ACLs restrict writes; no user pull path                 | Admin can bypass       |
| Unauthorized model pulls      | RuntimeModelPullsEnabled=false; Ollama outbound blocked by firewall     | Admin can bypass       |
| API key leakage               | Key stored in Secrets dir; ACL restricts user read; never logged        | Memory scraping        |
| Configuration tampering       | ACLs restrict config dir; repair restores config                        | Admin can bypass       |
| LAN exposure                  | Loopback-only binding; firewall inbound rules                           | Misconfiguration       |
| Local privilege escalation    | Service account is non-admin; limited permissions                       | OS vulnerabilities     |
| Service account misuse        | Account denied interactive logon; LSA right restricted                  | Admin can bypass       |

**Important:** Local administrators can bypass all workstation-local controls. This package is not a substitute for enterprise-level network controls.

## 9. Filesystem Layout

### Install Root: `C:\Program Files\EnterpriseAI`

```
C:\Program Files\EnterpriseAI\
├── bin\                    # Utility scripts and helpers
├── ollama\                 # Ollama binary and assets
├── litellm\                # LiteLLM Python application
├── python\                 # Vendored Python runtime
├── service-wrapper\        # Service wrapper (if required)
└── VERSION                 # Package version file
```

### ProgramData Root: `C:\ProgramData\EnterpriseAI`

```
C:\ProgramData\EnterpriseAI\
├── Config\                 # Active configuration files
├── LiteLLM\                # LiteLLM working directory
├── Ollama\                 # Ollama working directory
├── Models\                 # Model content (populated by separate package)
├── Logs\                   # Log files (Install, Repair, Uninstall, LiteLLM, Ollama)
├── Secrets\                # API keys and credentials (restricted ACL)
├── State\                  # Package state files
└── Validation\             # Validation results and reports
```

## 10. Service Account Model

- Default account: `.\svc_EnterpriseAI` (local account)
- Non-admin, minimal privileges
- Granted: "Log on as a service" LSA right
- Denied: Interactive logon where practical
- Filesystem permissions: read/execute on install root; write on Logs; read on Config and Secrets; read/execute on Models
- Created during install if absent; repaired during repair
- **Disabled** (not deleted) by default during uninstall
- No committed plaintext password; password must be supplied as a secure deployment parameter
- Scripts fail clearly if a required password parameter is missing

## 11. Firewall Intent and Limitations

Package-owned firewall rules use the prefix `EnterpriseAI-`. Uninstall removes only rules with this prefix.

Intended rules:
- Block inbound to LiteLLM from non-loopback addresses
- Block inbound to Ollama from non-loopback addresses
- Block Ollama outbound to Internet (to prevent model pulls)
- Allow LiteLLM outbound to approved model registry only if runtime pulls explicitly enabled

**Important limitation:** Windows Firewall loopback rules are applied to network profiles, but Windows does not enforce per-process inbound firewall rules for loopback traffic in all configurations. A process listening on 127.x.x.x is generally accessible only from the same host, but Windows Firewall cannot guarantee complete per-process isolation for all loopback traffic patterns. The primary protection is the loopback binding itself.

Validation produces a **WARN** (not PASS) if direct loopback access to Ollama cannot be fully verified as blocked.

## 12. LiteLLM API-Key Enforcement

- LiteLLM is configured to require an API key for all requests
- `RequireLiteLLMApiKey: true` is the default and must not be set to false in production
- API key is stored under `C:\ProgramData\EnterpriseAI\Secrets` with restricted ACL
- Key is injected at deployment time; never committed to the repository
- Validation tests that unauthenticated requests are rejected (HTTP 401) and authenticated requests succeed

## 13. Model Policy

- This package does **not** install model content
- Model content packages deliver files or registry/pointer references under `C:\ProgramData\EnterpriseAI\Models`
- Approved model aliases are defined in `config/approved-models.example.json` and activated in LiteLLM config
- LiteLLM is configured to route only approved aliases; unknown model names are rejected
- Users cannot add or pull arbitrary models through any supported interface

## 14. Runtime-Pull Policy

- `RuntimeModelPullsEnabled: false` by default
- If enabled, exactly one `ApprovedModelRegistryUrl` must be configured
- Validation fails if pulls are enabled without a valid registry URL
- Ollama outbound Internet access is blocked by firewall rules by default
- LiteLLM arbitrary provider egress is disabled by default

## 15. Install Behavior

`scripts/Install-EnterpriseAI.ps1`:
1. Require elevation (exit code 3 if not admin)
2. Validate arguments and config file
3. Validate package integrity (hashes where practical)
4. Create required directories
5. Stage runtime files from package vendor directories
6. Create or repair service account
7. Apply filesystem ACLs
8. Generate or install LiteLLM API key secret
9. Render Ollama environment/config from template
10. Render LiteLLM config from template
11. Create Windows services
12. Configure service recovery (auto-restart)
13. Create firewall rules
14. Start Ollama service
15. Start LiteLLM service
16. Run post-install validation
17. Write package state to registry and state file
18. Write install log to `C:\ProgramData\EnterpriseAI\Logs\Install\install.log`

Operations are idempotent where practical. Install may be re-run to repair state.

## 16. Repair Behavior

`scripts/Repair-EnterpriseAI.ps1`:
1. Require elevation
2. Reload package config
3. Recreate missing directories
4. Restore filesystem ACLs
5. Repair service account and LSA rights
6. Restore service definitions if missing or incorrect
7. Restore service recovery settings
8. Restore Ollama and LiteLLM config from templates
9. Restore firewall rules
10. Restart services if required
11. Run post-repair validation
12. Write repair log to `C:\ProgramData\EnterpriseAI\Logs\Repair\repair.log`

Repair is idempotent; safe to run multiple times.

## 17. Uninstall Behavior

`scripts/Uninstall-EnterpriseAI.ps1`:
1. Require elevation
2. Stop LiteLLM service
3. Stop Ollama service
4. Remove LiteLLM service
5. Remove Ollama service
6. Remove only package-owned firewall rules (prefix `EnterpriseAI-`)
7. Remove runtime files under `C:\Program Files\EnterpriseAI`
8. Preserve `C:\ProgramData\EnterpriseAI` by default (configurable)
9. Disable service account by default (not deleted; configurable)
10. Do not remove model content by default
11. Write uninstall log to `C:\ProgramData\EnterpriseAI\Logs\Uninstall\uninstall.log`

Parameters allow removal of ProgramData and/or the service account, but defaults preserve them.

## 18. MECM/SCCM Behavior

Detection method: `packaging/mecm/detection-method.ps1`

Detection verifies:
- Registry key `HKLM:\Software\EnterpriseAI\LocalRuntimeGateway` exists
- `PackageVersion` value matches expected version
- Both services exist
- Install root and ProgramData root directories exist

MECM commands:
- Install: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json`
- Repair: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Repair-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json`
- Uninstall: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json`

## 19. Validation Behavior

`scripts/Test-EnterpriseAI.ps1` / `scripts/Get-EnterpriseAIHealth.ps1`

Validation produces results in states: `PASS`, `WARN`, `FAIL`, `SKIP`

Exit code 0 on all PASS/WARN/SKIP; non-zero (exit code 10) on any FAIL.

Health check output never includes secrets.

Checks performed:
- Package version matches expected
- Required directories exist
- Required ACLs are correct
- Service account exists and is non-admin
- Both services exist and are running
- Ollama binds only to loopback (127.0.0.2)
- LiteLLM binds only to loopback (127.0.0.1)
- LiteLLM rejects unauthenticated requests (HTTP 401)
- LiteLLM accepts authenticated requests with approved key
- LiteLLM rejects arbitrary model names
- LiteLLM exposes only approved aliases
- LiteLLM can reach Ollama backend
- Firewall rules exist with correct prefix
- Runtime pulls disabled (WARN if enabled without valid registry URL)
- Normal users cannot write to protected paths
- Secrets are not readable by normal users

## 20. GitHub Actions Packaging and Release Behavior

### ci.yml
- Runs on PRs and pushes to main
- Validates PowerShell syntax
- Runs PSScriptAnalyzer
- Runs Pester tests
- Validates JSON/YAML configuration files
- Checks default endpoints are loopback-only
- Checks firewall rule names use `EnterpriseAI-` prefix
- Checks scripts do not perform install-time upstream downloads
- Uploads test results as artifacts

### package.yml
- Manually triggered
- Runs on Windows runner
- Reads `manifest/dependencies.lock.json`
- Downloads pinned dependencies
- Verifies SHA256 hashes
- Builds release ZIP
- Uploads artifact

### release.yml
- Triggered on tags matching `v*`
- Runs CI and package jobs
- Creates GitHub release
- Attaches: ZIP, SHA256 checksum, lockfile, SBOM, release notes
- Uses least-privilege permissions
- Does not execute untrusted PR content

## 21. Dependency Vendoring Strategy

- All upstream component versions are pinned in `manifest/dependencies.lock.json`
- No floating versions in releases
- Components downloaded only during CI packaging, never at endpoint install time
- SHA256 hashes verified before packaging
- `manifest/hashes.sha256` included in release artifact
- `manifest/sbom.spdx.json` included or stubbed

Components vendored:
- **Ollama**: Official Windows binary (`ollama.exe`) pinned to a specific version and SHA256
- **LiteLLM**: Python package with offline wheelhouse; vendored Python runtime (embeddable or full)
- **Service wrapper**: NSSM or native Windows service creation; if NSSM used, vendored and pinned

CI release must not proceed if dependency versions or hashes are placeholders (`PLACEHOLDER` or empty).

## 22. Acceptance Criteria

The repository is acceptable when:
1. The full prescribed directory structure exists
2. `INTENT.md` clearly captures design intent
3. Install, repair, uninstall, detection, validation, and health-check scripts exist and are functional
4. Reusable PowerShell modules exist for all major subsystems
5. Configuration templates exist for LiteLLM and Ollama
6. MECM/SCCM command and detection files exist
7. GitHub Actions workflows exist for CI, packaging, and release
8. Dependency lockfile and hash manifest exist with no placeholder values in release builds
9. Vendor directories are present with `.gitkeep` placeholders until populated by CI
10. Administrator and user documentation exists
11. No committed secrets
12. Default endpoints are loopback-only
13. Runtime model pulls are disabled by default
14. Windows Firewall loopback limitations are clearly documented
15. Release packaging vendors all upstream components internally

## 23. Non-Negotiable Requirements

1. **No committed plaintext secrets** — passwords and API keys must never appear in committed files
2. **Loopback-only endpoints** — LiteLLM on 127.0.0.1:4000; Ollama on 127.0.0.2:11434
3. **LiteLLM API key required** — `RequireLiteLLMApiKey` must default to `true`
4. **No model installation** — this package does not install or remove model content
5. **No LAN exposure** — neither service may bind to a network interface
6. **No arbitrary model pulls** — `RuntimeModelPullsEnabled` must default to `false`
7. **Offline installable** — endpoint install must not download from the Internet
8. **Idempotent operations** — install, repair, and validation must be safe to run multiple times
9. **Uninstall preserves data** — `C:\ProgramData\EnterpriseAI` preserved by default; service account disabled not deleted by default
10. **Firewall limitations documented** — Windows Firewall per-process loopback limitations acknowledged in code and docs
11. **Validation produces WARN not FAIL** for loopback firewall limitations; produces FAIL only for confirmed misconfigurations
12. **Exit codes** — scripts must use the defined exit code convention (0=success, 1=failure, 2=invalid args, 3=not elevated, etc.)
