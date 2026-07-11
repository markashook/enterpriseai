# Troubleshooting Guide

## Checking Service Status

```powershell
Get-Service -Name 'EnterpriseAI-Ollama', 'EnterpriseAI-LiteLLM' | Format-Table -AutoSize
```

## Running Validation

```powershell
.\scripts\Test-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json -Verbose
```

## Running Health Check

```powershell
.\scripts\Get-EnterpriseAIHealth.ps1 -Verbose
```

## Common Issues

### Services not starting

1. Check the install log: `C:\ProgramData\EnterpriseAI\Logs\Install\install.log`
2. Check Windows Event Log: `Get-EventLog -LogName System -Source 'Service Control Manager' -Newest 20`
3. Verify vendor binaries are present in `C:\Program Files\EnterpriseAI\`
4. Run repair: `.\scripts\Repair-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json`

### LiteLLM returns 401 Unauthorized

This is correct behavior for unauthenticated requests. Ensure your client is sending the correct API key.

See [user documentation](../../user/api-key-use.md) for how to configure the API key in your client.

### LiteLLM returns 404 for model name

The requested model alias is not in the approved models list. Check:
- `C:\ProgramData\EnterpriseAI\Config\approved-models.json`
- Ensure the model alias matches exactly (case-sensitive)

### Validation shows WARN for loopback firewall isolation

This is expected. Windows Firewall cannot guarantee per-process loopback isolation. The primary protection is the loopback-only service binding. See [firewall.md](firewall.md) for details.

### Service account issues

1. Check if `svc_EnterpriseAI` exists: `Get-LocalUser -Name svc_EnterpriseAI`
2. Check if account is enabled: `(Get-LocalUser -Name svc_EnterpriseAI).Enabled`
3. Run repair to restore the account

### ACL validation fails

Run repair to restore ACLs:
```powershell
.\scripts\Repair-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json
```

### MECM/SCCM detection not working

Verify:
1. Registry key exists: `Get-Item 'HKLM:\Software\EnterpriseAI\LocalRuntimeGateway'`
2. PackageVersion matches VERSION file
3. Both services exist: `Get-Service -Name 'EnterpriseAI-*'`
4. Install root exists: `Test-Path 'C:\Program Files\EnterpriseAI'`

### Log file locations

| Operation | Log Path |
|-----------|----------|
| Install | `C:\ProgramData\EnterpriseAI\Logs\Install\install.log` |
| Repair | `C:\ProgramData\EnterpriseAI\Logs\Repair\repair.log` |
| Uninstall | `C:\ProgramData\EnterpriseAI\Logs\Uninstall\uninstall.log` |
| LiteLLM runtime | `C:\ProgramData\EnterpriseAI\Logs\LiteLLM\` |
| Ollama runtime | `C:\ProgramData\EnterpriseAI\Logs\Ollama\` |
