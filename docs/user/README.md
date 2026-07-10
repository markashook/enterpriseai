# EnterpriseAI — User Documentation

## Overview

This directory contains end-user documentation for connecting to the EnterpriseAI Local Runtime and Gateway.

## Contents

| Document | Description |
|----------|-------------|
| [connecting-clients.md](connecting-clients.md) | How to connect OpenAI-compatible clients |
| [api-key-use.md](api-key-use.md) | How to use the API key |
| [continue-dev.md](continue-dev.md) | Continue.dev configuration example |
| [open-webui.md](open-webui.md) | Open WebUI connection example |

## Important Notes

- Connect to **LiteLLM only** at `http://127.0.0.1:4000`
- An API key is required for all requests
- Available model aliases are managed by your administrator
- Model installation is administrator-managed; users cannot install or pull models
- Ollama is a backend service — do not connect to it directly

## Getting Your API Key

Contact your system administrator to obtain the LiteLLM API key for your workstation.
