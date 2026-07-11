# EnterpriseAI Local Runtime and Gateway — Administrator Documentation

## Overview

This directory contains administrator documentation for deploying and managing the EnterpriseAI Local Runtime and Gateway package on enterprise Windows workstations.

## Contents

| Document                        | Description                                           |
|---------------------------------|-------------------------------------------------------|
| [install.md](install.md)        | Installation guide                                    |
| [repair.md](repair.md)          | Repair guide                                         |
| [uninstall.md](uninstall.md)    | Uninstall guide                                      |
| [configuration.md](configuration.md) | Configuration reference                         |
| [firewall.md](firewall.md)      | Firewall behavior and limitations                    |
| [model-policy.md](model-policy.md) | Model policy and approved models                  |
| [troubleshooting.md](troubleshooting.md) | Troubleshooting guide                        |
| [threat-model.md](threat-model.md) | Security threat model                             |

## Architecture Summary

```
User AI Client (e.g., Continue.dev, Open WebUI)
      |
      | HTTP (OpenAI API) - requires API key
      v
LiteLLM  [http://127.0.0.1:4000]  [EnterpriseAI-LiteLLM service]
      |
      | HTTP (Ollama API) - internal only
      v
Ollama   [http://127.0.0.2:11434] [EnterpriseAI-Ollama service]
      |
      v
Models  [C:\ProgramData\EnterpriseAI\Models]
```

Both services run under the local service account `svc_EnterpriseAI`. Users connect only to LiteLLM. Ollama is a protected backend service.

## Quick Reference

| Item                  | Value                                          |
|-----------------------|------------------------------------------------|
| LiteLLM Endpoint      | http://127.0.0.1:4000                          |
| Ollama Endpoint       | http://127.0.0.2:11434 (backend only)          |
| Install Root          | C:\Program Files\EnterpriseAI                  |
| ProgramData Root      | C:\ProgramData\EnterpriseAI                    |
| Service Account       | svc_EnterpriseAI                               |
| Ollama Service        | EnterpriseAI-Ollama                            |
| LiteLLM Service       | EnterpriseAI-LiteLLM                           |
| Firewall Rule Prefix  | EnterpriseAI-                                  |
| Registry Key          | HKLM:\Software\EnterpriseAI\LocalRuntimeGateway|
| Install Log           | C:\ProgramData\EnterpriseAI\Logs\Install\install.log |
