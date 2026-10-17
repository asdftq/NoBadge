# Changelog

## 0.1.39

- Support Apple Silicon on macOS 27, preserving the macOS 26.5.1 and later adapter.
- Select compatibility by OS family and validate settings at runtime instead of blocking each new minor or patch build.
- Restore pending sessions across compatible macOS 26/27 upgrades, retaining schema, cache and transaction checks.
- Clarify that unsupported systems need a NoBadge update.

## 0.1.38

- Publish the app source under the MIT license.
- Add a local source build that needs no purchase key and updates by rebuilding.
- Keep signed downloads, purchase activation and in-app updates available through the website.

## 0.1.37

- Check for and install signed, notarized updates directly in NoBadge using Sparkle.
- Check daily with an About preference, and restore badge settings before restarting for an update.


## 0.1.36

- Activate a purchase license on up to three Macs, with secure Keychain storage and a 30-day offline allowance.
- Block badge suppression without a valid NoBadge license while keeping restoration and quitting available.


## 0.1.32
- Use the notification service's NSUserDefaults container client for badge preferences, preserving the existing fresh-file and cache verification guards.

## 0.1.31
- Retain the last narrow restoration journal after verification, so a delayed macOS settings overwrite cannot erase the only recovery record.
- Keep the active recovery journal when archiving the restored session fails; never apply a completed receipt automatically over later user edits.

## 0.1.30
- Save settings away from the main thread while preserving the newest choice during rapid interactions.
- Wait for pending saves before reconciliation and exit; restore safely if saving fails.

## 0.1.29
- Address notification preferences through their actual group-container domain, avoiding a separate absolute-path cache for the same file.
- Fail closed when the qualified container-preference interface is unavailable.

## 0.1.28
- Wait for the signaled notification daemon to exit before verifying a badge transaction; keep recovery pending if termination cannot be confirmed.

## 0.1.27
- Support arrow-key navigation and Space/Return in the native app exceptions table.
- Preserve a checkbox's keyboard and accessibility focus when its value changes.

## 0.1.26
- Rebase suppression on a fresh settings snapshot after a transient concurrent change, with three bounded attempts and restoration priority.
- Preserve unrelated flags and durable recovery data when contention persists.

## 0.1.25
- Use a continuous clock for the unavailable-Focus grace period so wall-clock rollback cannot prolong it.

## 0.1.24
- Exercise durable transaction recovery at every write boundary and verify real journal allocation failures on an isolated full APFS volume.

## 0.1.23
- Use continuous clocks for refresh cooldowns and failure windows.
- Expire captured temporary badge modes on timer completion and reevaluate them safely after system-clock changes.

## 0.1.22
- Show the expiration time of temporary badge overrides in Settings and the menu.

## 0.1.21
- Keep read-only installer launches outside the production lifecycle and recovery lock.
- Guide customers to install in Applications and provide purchased-update downloads.

## 0.1.20
- Follow the owner's direct-sale distribution decision: use a quiet, earned rating/review invitation in Settings after Focus ends, linking to an explicit email-draft feedback page.
- Add Support, Privacy and Rate or review links to About. No browser opens automatically, no review is transmitted by the app, and every rating follows the same path.

## 0.1.19
- Add earned StoreKit review eligibility: seven days, three restored Focus sessions on distinct days, a 120-day cooldown, and one attempt per version.
- Cancel requests during Focus, setup, failures, background use, sleep, shutdown, or closed settings. The current Developer ID build keeps App Store requests disabled until a compliant store build and listing exist.

## 0.1.0
- Initialize the original native application and isolated verification harness.

## 0.1.1
- Qualify read-only Focus detection and scoped notification badge mutation on macOS 26.5.1.
- Preserve user settings while allowing observed daemon-owned registration metadata refreshes.

## 0.1.2
- Add durable per-app recovery journals and serialized reversible transactions.
- Respect external changes, apply exceptions immediately, and prioritize restoration over refresh cooldowns.

## 0.1.3
- Add native menu bar controls, current state, Focus selection, and live app exceptions.
- Connect guided setup, bounded badge tests, and safe lifecycle controls.

## 0.1.4
- Add bounded shutdown coordination, privacy-safe local diagnostics, and export review.
- Complete English/Korean setup and recovery copy.

## 0.1.5
- Prepare universal signed ZIP/DMG candidates, notarization, and local update-signature verification.
- Prepare the $2.99 one-time digital-download sales draft.

## 0.1.6
- Preserve setup progress across relaunch and require readable Focus data before activation.
- Avoid initializing an unopened menu popover.

## 0.1.7
- Route Apps and Help before opening Settings, including the first click.
- Drain an in-flight refresh before the final quit restoration.

## 0.1.8
- Synchronize badge changes through the preference service so its cache cannot undo a file-only restoration.
- Keep unrelated preference keys outside the app-record mutation.

## 0.1.9
- Load app icons only when displayed and release closed setup/settings/popover views.
- Align app labels and switches consistently.
- Reopening NoBadge shows its controls, with a keyboard shortcut to open them.

## 0.1.10
- Complete uninstall preparation when no login item was registered.
- Show the exact diagnostic summary before saving it.

## 0.1.11
- Restore standard native editing and window keyboard commands in the menu bar app.

## 0.1.12
- Schedule task-triggered quit and updater relaunch outside the MainActor job to avoid a nested-loop termination deadlock.

## 0.1.13
- Include multiline text and dynamic settings labels in Korean localization.

## 0.1.14
- Default to English regardless of the macOS language. Korean is available only through the app's Language setting.
- Apply language changes immediately to open views, native menus, window titles and time formatting; preserve the choice across relaunch.

## 0.1.15
- Resolve overlapping scheduled/manual Focus assertions using their start order; handle omitted inactive records and missing display-name metadata.
- Skip daemon cooldowns for unchanged badge settings and immediate exception restoration.

## 0.1.16
- Show an explicit two-step permission walkthrough on first use and for previously skipped setup, with a permanent review entry.
- Replace the status-item popover with a native menu and open independent windows on the pointer's display, including Finder reopen with Hidden Bar running.
- Make General and Help compact, keep English as the default, and show the actual Focus state next to the main action.
- Cache app identity separately from changing badge flags, group notification helpers with their owning app, and load bounded thumbnail icons off the main actor.
- Interrupt pending suppression when Focus or user intent changes; retain safe journal restoration on quit.

## 0.1.17
- Compare cache agreement on user preferences instead of stale daemon registration metadata; write from the latest disk snapshot without relaxing unknown-field or flag checks.
- Retry restoration from a fresh snapshot after a bounded pre-write concurrency conflict, preserving macOS registration updates and unrelated settings during rapid quit.
- Treat an absent usernoted process during its restart as already refreshed, while still rejecting failures when the process is running.
- Keep asynchronous restoration runnable while showing a quit failure alert, and schedule retries outside the Swift executor.
- Use native checkboxes for app exceptions and retain diagnostic error copy in verification mode.

## 0.1.18
- Render app exceptions with reusable native table rows and asynchronous thumbnails, avoiding whole SwiftUI row-tree updates during scrolling.
- Drain temporary app-catalog objects and release thumbnail caches when windows close.
