# Vendor Directory

This directory contains vendored upstream components required by the EnterpriseAI Local Runtime and Gateway package.

## Contents

| Directory         | Component           | Notes                                           |
|-------------------|--------------------|-------------------------------------------------|
| `ollama/`         | Ollama Windows binary | Populated by CI packaging (`New-DependencyBundle.ps1`) |
| `litellm/`        | LiteLLM offline wheelhouse | Populated by CI packaging             |
| `python/`         | Vendored Python runtime (embeddable) | Populated by CI packaging    |
| `service-wrapper/`| Service wrapper (e.g., NSSM) | Populated by CI packaging if required |

## How Vendor Directories Are Populated

Vendor directories are **not** committed to the repository with binary content. They contain only `.gitkeep` placeholder files.

During CI packaging (`packaging/New-DependencyBundle.ps1`):
1. Versions and SHA256 hashes are read from `manifest/dependencies.lock.json`.
2. Components are downloaded from pinned URLs.
3. Hashes are verified before staging.
4. Staged components are placed in these directories.
5. A release ZIP is built that includes the populated vendor directories.

## Important

- Do NOT commit binary files to this directory.
- Do NOT modify `.gitkeep` files.
- All version pinning is in `manifest/dependencies.lock.json`.
- All hash verification is in `manifest/hashes.sha256`.
- See `docs/ci/dependency-mirroring.md` for the mirroring strategy.
