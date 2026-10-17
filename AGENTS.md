# NoBadge compatibility and releases

- Preserve the previous supported OS profiles when adding a new macOS family. Isolate any changed private storage/API behavior in its OS adapter; never replace a working older path globally to fix a newer OS.
- Minor and patch releases in a supported stable OS family must not need an exact-build allowlist update. Keep runtime schema checks, dynamic API checks, cache agreement, narrow badge-bit writes and verified journal restoration. New major versions, beta build formats and architectures need explicit support decisions.
- Keep compatible recovery journals usable across supported OS upgrades. Never discard a journal merely because its originating build differs from the current build.
- For compatibility changes, use the focused compatibility/recovery checks and one actual hide/restore flow on the available Mac. Do not turn historical broad qualification checklists into new release gates.
- Update README, current compatibility documentation, public site/metadata, installer copy and release notes together. Distinguish directly verified builds from the supported OS family policy.
- Bump VERSION for a completed app release. Commit implementations with Conventional Commits. Publish only the source export allowlist to the public repository; private history, Sales and operational evidence stay private.
