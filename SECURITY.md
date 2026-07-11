# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

To report a security vulnerability in EnterpriseAI Local Runtime and Gateway, please do **not** open a public GitHub issue.

Instead, contact the repository maintainers privately through the GitHub Security Advisory feature:
1. Go to the repository **Security** tab.
2. Select **Report a vulnerability**.
3. Provide a clear description, reproduction steps, and impact assessment.

We aim to acknowledge reports within 5 business days and provide a resolution timeline within 30 business days depending on severity.

## Security Assumptions and Scope

This package is designed for deployment on enterprise-managed Windows workstations. Key security assumptions:

- The host OS is managed and patched by enterprise IT.
- Local administrators are trusted; workstation-local controls cannot prevent admin bypass.
- Network-level controls (corporate firewall, proxy) supplement but do not replace package-level controls.
- Secrets (e.g., LiteLLM API keys) must not be stored as plaintext in committed scripts.
- The LiteLLM endpoint (`http://127.0.0.1:4000`) is loopback-only; LAN exposure is not supported.
- The Ollama endpoint (`http://127.0.0.2:11434`) is a protected backend; users should not connect to it directly.

See `docs/admin/threat-model.md` for a full threat model.
