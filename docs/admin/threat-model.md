# Threat Model

## Scope

This threat model covers the workstation-local EnterpriseAI Local Runtime and Gateway package. Enterprise-level network controls are out of scope.

**Important:** Local administrators can bypass all workstation-local controls described below.

## Assets

| Asset | Sensitivity | Location |
|-------|-------------|----------|
| LiteLLM API key | High | `C:\ProgramData\EnterpriseAI\Secrets\litellm.key` |
| Model content | Medium | `C:\ProgramData\EnterpriseAI\Models` |
| LiteLLM config | Medium | `C:\ProgramData\EnterpriseAI\Config\litellm.config.yaml` |
| Ollama config | Medium | `C:\ProgramData\EnterpriseAI\Config\ollama.env` |
| Service account credentials | High | Windows SAM / LSA |
| AI inference capability | Medium | Both services |

## Threat Scenarios

### 1. Bypassing LiteLLM to Access Ollama Directly

**Threat:** A user connects directly to Ollama (`http://127.0.0.2:11434`) to bypass LiteLLM's model gating, API key requirement, and request logging.

**Mitigations:**
- Ollama binds to `127.0.0.2` (a non-standard loopback address that is less obvious)
- Windows Firewall rules block non-loopback inbound to port 11434
- ACLs prevent users from modifying Ollama configuration

**Residual Risk:** Any process running on the workstation can connect to 127.0.0.2:11434. A motivated user can discover the Ollama endpoint. Local administrators can disable firewall rules. Windows Firewall loopback enforcement has limitations.

**Validation:** Test-EnterpriseAI checks that Ollama does not bind to a LAN address.

---

### 2. Arbitrary Model Loading

**Threat:** A user loads an unapproved model by copying files into the model directory or through an API call.

**Mitigations:**
- ACLs restrict write access to `C:\ProgramData\EnterpriseAI\Models` (users cannot write)
- LiteLLM only exposes approved model aliases; arbitrary model names are rejected
- RuntimeModelPullsEnabled defaults to false

**Residual Risk:** Local administrators have full write access. SYSTEM account has full access.

---

### 3. Unauthorized Model Pulls

**Threat:** A user or process triggers Ollama to download a model from the Internet.

**Mitigations:**
- RuntimeModelPullsEnabled defaults to false in LiteLLM config
- Ollama outbound Internet access blocked by firewall rules
- No supported user-facing pull path

**Residual Risk:** A local administrator can enable pulls or disable firewall rules. If the outbound block rule is removed, Ollama can pull models directly.

---

### 4. API Key Leakage

**Threat:** The LiteLLM API key is read by an unauthorized user or appears in logs.

**Mitigations:**
- Key stored in `C:\ProgramData\EnterpriseAI\Secrets\litellm.key` with restrictive ACL
- Users have no read access to the Secrets directory
- Scripts and health checks never print or log the API key
- No plaintext key in any committed file

**Residual Risk:** Memory scraping by a process running as the service account or as an administrator. If the workstation is compromised, the key can be read from memory.

---

### 5. Configuration Tampering

**Threat:** A user modifies LiteLLM or Ollama configuration to add unapproved models, disable API key requirements, or expose services to the LAN.

**Mitigations:**
- ACLs restrict write access to Config directory
- Repair script restores configuration from templates
- Validation detects non-loopback bindings and disabled API key requirements

**Residual Risk:** Local administrators can modify any file. Configuration can be restored by repair.

---

### 6. Service Account Misuse

**Threat:** The `svc_EnterpriseAI` account is used to escalate privileges or access other system resources.

**Mitigations:**
- Account is non-admin
- Interactive logon denied where practical
- Filesystem permissions limited to required paths
- "Log on as a service" right only

**Residual Risk:** The service account has read access to the secrets directory (required to read the API key). A compromised service process could read the API key.

---

### 7. Local Privilege Escalation

**Threat:** A user exploits a vulnerability in Ollama or LiteLLM to escalate to the service account or SYSTEM.

**Mitigations:**
- Services run under non-admin `svc_EnterpriseAI`
- Services bind only to loopback (reduces attack surface from network)
- ACLs prevent users from modifying service binaries

**Residual Risk:** This depends on the security of upstream Ollama and LiteLLM software. Keep components updated. Follow enterprise patch management procedures.

---

### 8. Accidental LAN Exposure

**Threat:** A misconfiguration causes LiteLLM or Ollama to bind to a LAN-accessible address, exposing AI capabilities to the network.

**Mitigations:**
- Default configuration explicitly uses loopback-only addresses
- Validation fails if non-loopback binding is detected
- Firewall rules block inbound non-loopback traffic

**Residual Risk:** Admin misconfiguration. Validation and health checks should be run after any configuration change.

---

### 9. Supply Chain Attack

**Threat:** A malicious component is introduced through the vendored Ollama, LiteLLM, Python, or NSSM packages.

**Mitigations:**
- All component versions pinned in `manifest/dependencies.lock.json`
- SHA256 hashes verified during CI packaging
- SBOM generated for each release
- No floating versions in release builds
- Components downloaded only during CI, not at install time

**Residual Risk:** Hash verification confirms file integrity, not code trustworthiness. Keep upstream sources monitored for security advisories.

## Non-Mitigated Risks

The following risks are explicitly **not mitigated** by this package:

- Local administrator bypass of any workstation-local control
- Kernel-level or hypervisor-level attacks
- Physical access attacks
- Memory scraping by privileged processes
- Enterprise-wide model policy enforcement (requires separate management tooling)
