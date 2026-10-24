# KazumiTV development

This is a downstream presentation branch of Predidit/Kazumi. The user chose a cinema-style TV UI with large posters and horizontal shelves, for both a Hisense TV and XGIMI Z9X projector. The old Carey-L TV fork and Muse patch are historical references only.

## Keep upstream merges small

- Put TV presentation, input and adapters under `lib/tv/`; prefer conditional hooks in existing entry points over rewriting original screens.
- Leave rule parsing, `apiLevel`, network clients, storage schema and playback resolution upstream-owned. Never spoof a version to get a source accepted.
- The user-requested optional self-hosted danmaku extension is explicitly reviewed in `tool/tv/DANMAKU.md`. Its API/client/Dio-factory/settings-key hooks are pinned by exact hashes in `reviewedExtensions`; retain the official default path and do not broaden this exception without a concrete task and regression evidence.
- `tool/tv/upstream.json` records the actually merged upstream commit. Run `check_upstream.py`; after merging upstream, update the record with `record_upstream.py`.
- App name is **KazumiTV**. Keep the upstream semantic/build version. Track TV changes separately with `KAZUMI_TV_REVISION`.
- Android packaging is an opt-in overlay. Use `tool/tv/build.sh`; unflavored upstream builds must continue working.
- Do not reformat untouched upstream files or generated MobX code.
- The user-requested ARM32 TLS performance fix rebuilds the pinned Android v1.3.1 kernel with mbedTLS -O2. Keep its source/NDK/patch and reviewed ELF SHA in `tool/tv/native/`; only `android/tv.gradle` replaces the verified ARM32 library before strip/signing. Do not restore the temporary media relay or change request/TLS verification/codec contracts to mask this issue. Other ABIs and unflavored builds stay upstream.
- Device performance tuning is opt-in through `KAZUMI_TV_DEVICE_PROFILE`. Default `generic` must not inherit the Z9X 60-second prefetch limit merely because RAM is small; only explicit `xgimi-z9x` builds use that validated tuning. Hisense needs its own later measurements. Keep this scope distinct from the shared ARM32 TLS build-correctness fix above. See `tool/tv/XGIMI_OFFLINE.md`.

## Input and TV UX

- Directional navigation, visible focus, automatic scroll and focus restoration are required. Do not depend on touch or a vendor-specific remote button.
- Use `TvTextInput` for TV inputs: Android EditText owns the IME; browsing focus and editing focus are distinct. Never globally steal keys from an IME or a modal.
- Remote input uses the fixed LAN port 8765 while the TV app runs; QR is an optional shortcut to the same root page. Revoke field leases on blur/close/disposal, reject stale-field requests, honor disabled/current-route state, rediscover physical LAN addresses and never log entered text/tokens. Do not restore per-dialog random browser addresses as the TV entry point.
- Check 960×540 and 1280×720 logical layouts. Do not infer the projector/TV ABI or Android version from its name.

## Verification and records

- Run rule compatibility checks, `flutter analyze --no-fatal-infos`, upstream tests and TV widget/service tests, then build APKs. Preserve upstream baseline info lints rather than changing unrelated code.
- Actual IME/remote/codec/audio/danmaku acceptance must be recorded separately on both devices. A compiled APK and mocked UI test are not device acceptance.
- Keep test/build workloads sequential on UBT. Use one Gradle worker, a 2 GiB Gradle JVM, in-process Kotlin and no persistent daemon for this project's APK builds; do not stop unrelated services/VMs or change host memory allocation to build the app. See `tool/tv/DANMAKU.md` for the exact environment options and the prior memory-pressure incident.
- Keep signing material, API credentials and private config outside Git. The independent Emby bridge is a separate project; do not bake home endpoints or credentials into the client.
- Record important decisions and current build/acceptance status in KnowledgeHub's KazumiTV project. Do not modify production services merely to test client UI.
