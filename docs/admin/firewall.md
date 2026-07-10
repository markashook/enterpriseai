# Firewall Behavior and Limitations

## Overview

The EnterpriseAI package creates Windows Firewall rules to provide defense-in-depth for the local AI runtime. All package-owned rules use the prefix `EnterpriseAI-`.

## Rules Created

| Rule Name | Direction | Action | Port/Target |
|-----------|-----------|--------|------------|
| `EnterpriseAI-LiteLLM-Inbound-Block-NonLoopback` | Inbound | Block | TCP 4000 from non-loopback |
| `EnterpriseAI-LiteLLM-Inbound-Allow-Loopback` | Inbound | Allow | TCP 4000 from 127.0.0.1 |
| `EnterpriseAI-Ollama-Inbound-Block-NonLoopback` | Inbound | Block | TCP 11434 from non-loopback |
| `EnterpriseAI-Ollama-Inbound-Allow-Loopback` | Inbound | Allow | TCP 11434 from 127.0.0.2 |
| `EnterpriseAI-Ollama-Outbound-Block-Internet` | Outbound | Block | TCP 80/443 to Internet |

## Primary Protection: Loopback Binding

The primary security mechanism for keeping services off the LAN is **loopback-only binding**:
- LiteLLM binds to `127.0.0.1:4000`
- Ollama binds to `127.0.0.2:11434`

A service bound exclusively to a loopback address is not directly accessible from other machines on the network by design of the TCP/IP stack.

## Windows Firewall Limitations

> **Important:** Windows Firewall rules provide **defense-in-depth**, not the primary isolation mechanism.

Windows Firewall has known limitations for per-process loopback traffic:

1. **Loopback traffic bypass:** Windows does not route loopback traffic through the Windows Filtering Platform (WFP) in the same way as network traffic. Inbound firewall rules on loopback addresses may not be enforced in all Windows configurations.

2. **No per-process inbound isolation:** Windows Firewall inbound rules are applied by port, not strictly by process. Another process could listen on the same port if the service is stopped.

3. **Admin bypass:** A local administrator can disable or modify firewall rules at any time.

Because of these limitations:
- Validation produces a **WARN** (not PASS) for loopback isolation checks on the Ollama port
- Health checks acknowledge this limitation explicitly
- Administrators should not rely solely on Windows Firewall for Ollama isolation

## Uninstall Behavior

During uninstall, **only** rules with the prefix `EnterpriseAI-` are removed. Unrelated firewall rules are never modified.

## If Runtime Model Pulls Are Enabled

If `RuntimeModelPullsEnabled` is set to `true` (not recommended), the outbound block rule for Ollama is replaced with a rule permitting traffic to the approved registry URL only. The `ApprovedModelRegistryUrl` field must be set.

## Verifying Firewall Rules

```powershell
Get-NetFirewallRule -Name 'EnterpriseAI-*' | Format-Table -AutoSize
```

To run the full validation including firewall checks:

```powershell
.\scripts\Test-EnterpriseAI.ps1 -ConfigPath .\config\enterpriseai.package.json
```
