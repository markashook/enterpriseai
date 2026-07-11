# Open WebUI Connection

## Overview

[Open WebUI](https://github.com/open-webui/open-webui) is a web-based AI interface. You can connect it to your local EnterpriseAI gateway.

> **Note:** Open WebUI is not installed by the EnterpriseAI package. It must be installed separately.

## Connecting Open WebUI to LiteLLM

When configuring Open WebUI, point it to the LiteLLM endpoint:

- **OpenAI API Base URL:** `http://127.0.0.1:4000`
- **API Key:** `<your-api-key>`

In Open WebUI settings, under **Connections** or **Admin Panel > Connections**:

1. Add an **OpenAI** connection
2. Set the URL to `http://127.0.0.1:4000/v1`
3. Set the API key to your assigned key
4. Save the connection

## Notes

- Use the LiteLLM endpoint (`http://127.0.0.1:4000`) — do NOT point Open WebUI directly at Ollama
- Only approved model aliases will be available
- Model installation is managed by your administrator
- The endpoint is loopback-only and not accessible from other machines
