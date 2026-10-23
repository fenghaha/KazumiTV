# KazumiTV development

This is a downstream presentation branch of Predidit/Kazumi. The user chose a cinema-style TV UI with large posters and horizontal shelves, for both a Hisense TV and XGIMI Z9X projector. The old Carey-L TV fork and Muse patch are historical references only.

## Keep upstream merges small

- Put TV presentation, input and adapters under `lib/tv/`; prefer conditional hooks in existing entry points over rewriting original screens.
- Leave rule parsing, `apiLevel`, network clients, storage schema and playback resolution upstream-owned. Never spoof a version to get a source accepted.
- `tool/tv/upstream.json` records the actually merged upstream commit. Run `check_upstream.py`; after merging upstream, update the record with `record_upstream.py`.
- App name is **KazumiTV**. Keep the upstream semantic/build version. Track TV changes separately with `KAZUMI_TV_REVISION`.
- Android packaging is an opt-in overlay. Use `tool/tv/build.sh`; unflavored upstream builds must continue working.
- Do not reformat untouched upstream files or generated MobX code.

## Input and TV UX

- Directional navigation, visible focus, automatic scroll and focus restoration are required. Do not depend on touch or a vendor-specific remote button.
- Use `TvTextInput` for TV inputs: Android EditText owns the IME; browsing focus and editing focus are distinct. Never globally steal keys from an IME or a modal.
- QR input is optional and short-lived. Do not log entered text/tokens; revoke sessions on close, honor disabled state and rediscover LAN addresses.
- Check 960×540 and 1280×720 logical layouts. Do not infer the projector/TV ABI or Android version from its name.

## Verification and records

- Run rule compatibility checks, `flutter analyze --no-fatal-infos`, upstream tests and TV widget/service tests, then build APKs. Preserve upstream baseline info lints rather than changing unrelated code.
- Actual IME/remote/codec/audio/danmaku acceptance must be recorded separately on both devices. A compiled APK and mocked UI test are not device acceptance.
- Keep signing material, API credentials and private config outside Git. The independent Emby bridge is a separate project; do not bake home endpoints or credentials into the client.
- Record important decisions and current build/acceptance status in KnowledgeHub's KazumiTV project. Do not modify production services merely to test client UI.
