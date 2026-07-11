# Connecting AI Clients

## Endpoint

Connect your AI client to the LiteLLM endpoint:

```
http://127.0.0.1:4000
```

This endpoint is only accessible from the local workstation (loopback). It is not accessible from other machines on the network.

## Authentication

All requests require an API key. Set the `Authorization` header:

```
Authorization: ******
```

Contact your administrator for your API key.

## OpenAI-Compatible API

LiteLLM exposes an OpenAI-compatible API. Any client that supports OpenAI can connect by changing the base URL to `http://127.0.0.1:4000` and using your API key.

## Available Models

Available model aliases are managed by your administrator. To list available models:

```bash
curl http://127.0.0.1:4000/v1/models \
  -H "Authorization: ******"
```

Common aliases (configured by your administrator):
- `approved-chat` — General purpose chat
- `approved-code` — Code assistance

## Important: Ollama Is Not a User Endpoint

The Ollama service runs on `http://127.0.0.2:11434` and is a **protected backend service**. Do not connect your AI client directly to Ollama. All user traffic should go through LiteLLM at `http://127.0.0.1:4000`.

## Basic Test

```bash
curl http://127.0.0.1:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: ******" \
  -d '{
    "model": "approved-chat",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```
