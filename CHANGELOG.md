# Changelog

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
