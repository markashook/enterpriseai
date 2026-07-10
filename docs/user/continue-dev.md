# Continue.dev Configuration

## Overview

[Continue.dev](https://continue.dev) is an open-source AI coding assistant for VS Code and JetBrains IDEs. You can connect it to your local EnterpriseAI gateway.

## Configuration

Edit your Continue.dev configuration file (`~/.continue/config.json` or via the Continue extension settings):

```json
{
  "models": [
    {
      "title": "EnterpriseAI - Chat",
      "provider": "openai",
      "model": "approved-chat",
      "apiBase": "http://127.0.0.1:4000",
      "apiKey": "<your-api-key>"
    },
    {
      "title": "EnterpriseAI - Code",
      "provider": "openai",
      "model": "approved-code",
      "apiBase": "http://127.0.0.1:4000",
      "apiKey": "<your-api-key>"
    }
  ]
}
```

Replace `<your-api-key>` with your actual API key.

## Notes

- Use `http://127.0.0.1:4000` as the API base — this is the LiteLLM gateway
- Do not point Continue.dev directly at Ollama (`http://127.0.0.2:11434`)
- Available model names depend on what your administrator has approved
- Model installation is administrator-managed
