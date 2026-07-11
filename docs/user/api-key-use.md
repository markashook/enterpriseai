# API Key Usage

## Overview

The LiteLLM endpoint requires an API key for all requests. This key is provisioned by your administrator during package installation.

## Setting the API Key in Your Client

Most OpenAI-compatible clients use one of these methods:

### Environment Variable (recommended for terminal/CLI tools)

```bash
export OPENAI_API_KEY=<your-api-key>
export OPENAI_BASE_URL=http://127.0.0.1:4000
```

### Authorization Header (for API calls)

```
Authorization: ******
```

### Client Settings (for GUI tools)

In most GUI tools (Open WebUI, Continue.dev, etc.):
- Set the **API base URL** to `http://127.0.0.1:4000`
- Set the **API key** to your assigned key

## Obtaining Your API Key

Your API key is set by your administrator during deployment. Contact your IT/admin team if you need to retrieve or reset your API key.

## Security

- Do not share your API key with others
- Do not commit your API key to source control
- The API key grants access to AI inference on this workstation only
- Your administrator can rotate or revoke keys

## Troubleshooting

**HTTP 401 Unauthorized:** Your API key is missing or incorrect. Verify the key and that you are including the `Authorization: ****** header.

**HTTP 404 for model name:** The requested model alias is not available. Contact your administrator for the list of approved model aliases.
