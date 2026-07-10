# Uninstall Guide

## MECM/SCCM Uninstall Command

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json
```

## Manual Uninstall

```powershell
.\scripts\Uninstall-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json
```

## Default Behavior

By default, uninstall:
- Stops both services
- Removes both services
- Removes package-owned firewall rules (those with prefix `EnterpriseAI-`)
- Removes `C:\Program Files\EnterpriseAI` runtime files
- **Preserves** `C:\ProgramData\EnterpriseAI` (including logs, config, models reference)
- **Disables** (does not delete) the `svc_EnterpriseAI` service account
- Does NOT remove model content

## Optional Parameters

To also remove ProgramData:
```powershell
.\scripts\Uninstall-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json -RemoveProgramData
```

To also remove the service account:
```powershell
.\scripts\Uninstall-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json -RemoveServiceAccount
```

## Important Notes

- **Model content is never removed** by this script. Model packages must be uninstalled separately.
- **User client software** (Open WebUI, Continue.dev, etc.) is not managed by this package and will not be removed.
- Only firewall rules with the `EnterpriseAI-` prefix are removed. Unrelated rules are never touched.

## Log File

Uninstall log: `C:\ProgramData\EnterpriseAI\Logs\Uninstall\uninstall.log`
