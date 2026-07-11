# Repair Guide

The repair operation restores a degraded installation to a known-good state without a full reinstall.

## When to Repair

- A service has stopped and cannot be restarted
- Configuration files have been corrupted or modified
- Filesystem ACLs have been changed
- Firewall rules have been removed or modified
- The service account has been modified or disabled

## MECM/SCCM Repair Command

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Repair-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json
```

## Manual Repair

```powershell
.\scripts\Repair-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json -Verbose
```

## What Repair Does

1. Validates arguments and reloads config
2. Recreates any missing directories
3. Restores filesystem ACLs to expected values
4. Repairs the service account (creates if missing, fixes LSA rights)
5. Restores service definitions if missing or incorrect
6. Restores service recovery settings
7. Re-renders Ollama and LiteLLM configuration from templates
8. Restores any missing firewall rules
9. Restarts services if not running
10. Runs full validation

## Repair Is Idempotent

Repair is safe to run multiple times. Running repair on a healthy installation has no negative effect.

## Log File

Repair log: `C:\ProgramData\EnterpriseAI\Logs\Repair\repair.log`
