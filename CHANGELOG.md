# Changelog

## 0.1.2+3 — 2026-11-05

- Map all 15 real EBO-162 MCP tools to localized Chinese names and schema-aware manual controls in the Control tab.
- Initialize 9 conservative quick actions (forward/backward/turn/stop/photo/10-second recording/dock/stop patrol) only when exact tool names and required schemas match, preserving user's existing mappings.
- Correct recording semantics: `robot_record_video` accepts `recordSeconds`; remove unsupported start/stop recording toggle and simulated REC indicator.
- Remove unsupported gimbal shortcut; replace with `robot_stop_patrol`.
- Enforce MCP JSON Schema numeric bounds and 0–5 m forward/backward / 0–360° turn safety limits.
- Add catalog and binding unit tests; preserve encrypted config, Gemini integration, and exportable diagnostics.
- RTSP remote viewing is unchanged: private LAN URL requires VPN/subnet access.



## 0.1.1+2 — 2026-11-05

- Fix CI static analysis: remove the auto-generated Flutter `test/widget_test.dart` before `flutter analyze`.
- Retain real unit tests in `test/core_test.dart`.
- Bump Flutter app version and APK artifact labels to v0.1.1.


## 0.1.0+1 — 2026-11-05

- First Android Flutter controller preview.
- RTSP monitor and shareable local PNG screenshot.
- MCP Streamable HTTP initialize / tools/list / tools/call with session.
- Explicit robot D-pad, stop, gimbal, return-to-dock, photo and record mappings.
- Gemini text and audio commands with per-tool approval dialog.
- Android encrypted storage for all credentials and configured URLs.
- Versioned redacted JSONL diagnostics (including MCP tool schemas) exported through Android Share.
- GitHub Actions tests and versioned APK artifacts; optional permanent release signing.

### Limitations

- Requires real EBO-162 MCP tools/list and on-device validation.
- Video start/stop controls MCP recording only; no local MP4 is produced.
- First-time manual tool mapping is mandatory for safety.
- Debug artifacts have ephemeral signatures; configure release signing for in-place updates.
