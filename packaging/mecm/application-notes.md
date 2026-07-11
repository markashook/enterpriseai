# EnterpriseAI Local Runtime and Gateway — MECM/SCCM Application Notes

## Overview

This document describes how to configure the EnterpriseAI Local Runtime and Gateway as a MECM/SCCM application.

## Application Type

- **Type:** Script Installer
- **Platform:** Windows 10 (1809+) / Windows Server 2019+, x64
- **Requires elevation:** Yes (must run as Local System or equivalent)
- **Offline:** Yes — no Internet access required on the target workstation

## Deployment Type Commands

### Install Command

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json
```

To pass a service account password securely via MECM task sequence variables, use a wrapper script or pass as an encrypted MECM parameter. Do NOT hardcode passwords in the install command. Example with a task sequence variable:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { $pw = ConvertTo-SecureString '%SVC_PASSWORD%' -AsPlainText -Force; & '.\scripts\Install-EnterpriseAI.ps1' -ConfigPath '.\config\enterpriseai.package.json' -ServiceAccountPassword $pw }"
```

> **Security note:** Use MECM task sequence variables or Configuration Manager application parameters for sensitive values. Do not embed plaintext passwords in the content source.

### Repair Command

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Repair-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json
```

### Uninstall Command

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json
```

## Detection Method

- **Type:** Custom Script
- **Script:** `packaging/mecm/detection-method.ps1`
- **Run script as 32-bit process:** No
- **Run script in 64-bit PowerShell host:** Yes

The detection method outputs `"Installed"` and exits 0 if the application is detected. If the application is not detected (or partially installed), the script outputs nothing and exits 0. MECM interprets output presence as detection.

## Application Properties

| Property            | Value                                              |
|---------------------|----------------------------------------------------|
| Name                | EnterpriseAI Local Runtime and Gateway             |
| Publisher           | EnterpriseAI                                       |
| Software version    | See VERSION file in package source                 |
| Category            | Developer Tools / AI Runtime                       |
| Maximum allowed run time | 60 minutes                                   |
| Estimated installation time | 10 minutes                              |

## Deployment Settings

- **Purpose:** Required (for developer workstations)
- **Action:** Install
- **User experience:** Install for system
- **Logon requirement:** Whether or not a user is logged on
- **Installation behavior:** Install for system

## Content Source

The content source must be the unpacked release ZIP:

```
EnterpriseAI-LocalRuntimeGateway-<version>-win-x64\
├── README.txt
├── VERSION
├── manifest\
├── config\
├── scripts\
├── vendor\
├── docs\
└── packaging\mecm\
```

The content source must be accessible from the distribution point(s). The vendor directories contain all upstream components; no Internet access is required during installation.

## Prerequisites

- Windows 10 1809 (build 17763) or later, or Windows Server 2019 or later
- x64 architecture
- No additional software prerequisites required at install time

## Service Account

The installer creates a local service account `svc_EnterpriseAI`. If your organization requires the password to be set, pass it via a MECM task sequence variable or secure parameter. The installer will fail clearly if a required password is not provided.

## Post-Install Validation

After deployment, run the validation script to confirm correct installation:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json
```

## Known Limitations

- **Windows Firewall loopback enforcement:** Windows Firewall cannot guarantee per-process isolation for all loopback traffic. The primary protection is the loopback-only service binding. See `docs/admin/firewall.md` for details.
- **Local administrator bypass:** Local administrators can bypass all workstation-local controls. This package is not a substitute for enterprise-level network controls.
- **LiteLLM is a Python application:** LiteLLM runs via a vendored Python runtime. Startup may be slower than a native Windows executable.

## Troubleshooting

See `docs/admin/troubleshooting.md` for MECM/SCCM-specific troubleshooting guidance.

Install log: `C:\ProgramData\EnterpriseAI\Logs\Install\install.log`
