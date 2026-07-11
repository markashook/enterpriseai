# Dependency Mirroring

## Overview

Upstream components (Ollama, LiteLLM, Python, NSSM) are downloaded and verified during CI packaging only. Endpoint workstations never download from the Internet during installation.

## How It Works

1. **Lock file**: All component versions and SHA256 hashes are pinned in `manifest/dependencies.lock.json`.
2. **CI download**: `packaging/New-DependencyBundle.ps1` downloads all components from their pinned URLs during the `package.yml` workflow run.
3. **Hash verification**: SHA256 hashes are verified before staging.
4. **Package**: All components are bundled into the release ZIP.
5. **Install**: The install script reads components from the `vendor/` directory in the package — no internet access needed.

## Updating a Dependency Version

1. Update the version, download URL, and SHA256 hash in `manifest/dependencies.lock.json`.
2. Update `manifest/hashes.sha256` with the new hash.
3. Submit a PR with the changes.
4. CI will validate the lock file is consistent.
5. After merging, create a new release tag to trigger the release workflow.

## Enterprise Mirroring

For environments that restrict internet access from the CI runner, you can mirror upstream component download URLs to an internal artifact server and update the `DownloadUrl` fields in `manifest/dependencies.lock.json` accordingly.

The SHA256 hash values must remain unchanged — they verify the content is identical to the original upstream release.
