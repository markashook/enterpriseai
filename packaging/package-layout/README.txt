EnterpriseAI Local Runtime and Gateway
======================================

VERSION: See VERSION file
PLATFORM: Windows 10 / Server 2019 x64 and later

CONTENTS
--------
  README.txt              - This file
  VERSION                 - Package version
  manifest/               - Package manifest, dependency lock, hashes, SBOM
  config/                 - Configuration templates and package config
  scripts/                - Install, repair, uninstall, detection, validation scripts
  scripts/modules/        - Reusable PowerShell modules
  vendor/                 - Vendored upstream components (Ollama, LiteLLM, Python, service wrapper)
  docs/                   - Administrator and user documentation
  packaging/mecm/         - MECM/SCCM detection method, command files, and application notes

QUICK START (MECM/SCCM)
------------------------
See packaging/mecm/application-notes.md for MECM/SCCM application setup.

Install command:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json

Repair command:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Repair-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json

Uninstall command:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json

Detection method:
  See packaging/mecm/detection-method.ps1

REQUIREMENTS
------------
- Windows 10 (1809 / build 17763) or later, or Windows Server 2019 or later
- x64 architecture
- Local administrator privileges for install/repair/uninstall
- Internet access NOT required during installation (offline-installable)

ENDPOINTS AFTER INSTALL
-----------------------
  LiteLLM API:  http://127.0.0.1:4000   (user-facing, requires API key)
  Ollama:       http://127.0.0.2:11434  (backend only, not a user endpoint)

NOTE: Ollama is a protected backend service. Users should connect to LiteLLM only.

SUPPORT
-------
See docs/admin/troubleshooting.md for troubleshooting guidance.
