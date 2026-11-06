# Changelog

## 0.2.0+5 — 2026-11-06

- Render every MCP tool returned by paginated `tools/list` (15 verified EBO tools, plus future server additions).
- Replace raw JSON entry with Chinese localized, schema-driven per-field forms: numeric input and actual ranges; optional numeric-code choices; string dropdowns for declared enums; dropdown plus manual text for open-ended strings; boolean toggles; advanced JSON for complex values.
- Add on-demand `robot_list_locations` lookup for locationName dropdown.
- Preserve AI conversations locally across navigation/app restarts using encrypted device storage, up to 60 recent turns. Never automatically clear user input.
- Long-press user messages to favorite/retire reusable commands; one tap re-sends, with standard physical-action approval. Save approved memory notes; user controls removal.
- Include explicitly opted-in notebook and limited recent conversation as non-executable context with new Gemini messages.
- Add external AI weather/current-information reply via Gemini Google Search grounding, then separate approved `robot_speak` tool call so EBO speaks the answer. No verified source means no weather announcement; requires explicit city/location in question.
- Preserve private credentials outside GitHub and conversation content outside diagnostic Log.
- Add unit tests covering persistence serialization, MCP numeric descriptions and grounded-search safety.


## 0.1.3+4 — 2026-11-05

- Fix release-signing Kotlin DSL errors when GitHub Secrets are present (explicit `java.util.Properties` import before the plugins block).
- Replace Flutter default Android launcher icons with the user's minimal cyan EBO robot/controller artwork.
- Generate standard density launcher icons and Android 8+ adaptive launcher icons in GitHub Actions.
- Keep permanent JKS signing in GitHub Secrets; do not store secret values or private signing files in the repository.
- Retain the 15 EBO MCP tools and existing diagnostic export.


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
