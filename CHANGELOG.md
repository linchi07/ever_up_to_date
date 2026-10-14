## Unreleased

* Require SHA-256 for binary updates and reject missing signatures when trusted keys are configured.
* Bind verified downloads to their release, serialize operations, and recheck cached packages before installation.
* Cover the complete transfer with timeout and cancellation, retry transient failures, and clean expired cache files.
* Add macOS local DMG/PKG opening, Linux AppImage replacement with backup, and Windows portable ZIP replacement with rollback on launch failure.
* Persist installation receipts and confirm the running version after restart.
* Add deterministic rollout cohorts and withdrawn-release handling.
* Validate schema, application ID, package/platform combinations, OS compatibility, architecture targets, and semantic versions.
* Persist Builder configuration and owner-only signing keys, embed default resources, and support non-interactive generation and dependency checks.
* Complete signed multi-platform publishing with shared version/build metadata, immutable artifacts, conditional manifest publication, and historical manifests.
* Add platform signing hooks, real-template tests, release-pipeline tests, and repository CI.

## 0.0.1

* Initial Flutter updater engine, JSON appcast models, streamed downloader, hash/signature verification, and Android/Windows/store installers.
* Initial Go Builder, image utilities, and release templates.
