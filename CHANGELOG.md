# Changelog

## 0.2.5+10 — 2026-11-08
- Polish production launcher PNG by clipping stray cyan pixels outside the round-square app tile. Preserve the original teal/blue gradient; ensure RGBA corners are truly transparent and verified in CI. Same asset generates installer, legacy and adaptive launcher icons.
- Retain real native widget layouts and Android picker preview art (robot-only Q&A, controller-only MCP, combined dual widget, and four quick actions); CI asserts manifest/preview resources were installed, not merely generated as mockups.
- Fix Android cold-launch widget race: wait for encrypted Gemini/MCP settings to finish loading before attempting to open microphone mode or resolve home-screen quick commands.
- Fix AI false alarms: a successful first-stage patrol with deferred photography/follow now shows "partial action sent" instead of a misleading "no MCP" error dialog.
- Add instant microphone-start snackbar in addition to persistent status banner, including action mode and the instruction to tap again to send.
- Add regression tests for deferred plans, failed execution and pure informational answers. Preserve MCP approval on all physical actions and existing JKS signing.


## 0.2.4+9 — 2026-11-08

- Replace launcher and installed APK adaptive/legacy icons with the approved glossy 3D robot plus controller in a cyan-to-blue rounded-square gradient. Outer corners remain transparent.
- Replace text-only home voice widget surfaces with the approved 3D art: the query widget shows the robot; the MCP voice widget shows the controller. Native text auto-sizes across launcher grid widths.
- Provide distinct Android widget-picker thumbnails via previewImage/previewLayout, proper per-provider names, a dual-mode layout and a 4-button quick-action widget (dock, patrol, find registered pet, take photo).
- All quick commands open the app for explicit confirmation, validate exact live MCP tool names/schemas, and return a persistent status / failure explanation. Patrol is capped to 120 seconds; find-pet resolves only from user-saved encrypted notebook entries.
- Add persistent foreground voice-mode indicator, recording-state feedback, information-query guidance when voice MCP mode is used for weather/news, and explicit AI/MCP failure dialogs.
- Preserve signing identity, tool mapping, encrypted credentials, favorite prompts, notebooks, and diagnostics. Built assets come from user-approved images; no API secrets are committed.


## 0.2.3+8 — 2026-11-07

- Replace the four-button D-pad with an eight-sector circular pad in the Control page and enlarged semi-transparent RTSP overlay. Tap means one step, hold means bounded repeat; center requests STOP.
- Because robot_move exposes only one moveId per call, diagonal sectors are documented and implemented as sequential 7-degree turns + 0.1-meter translations (not simultaneous linear/angular velocity). A held diagonal allows at most six pairs, with one request in flight and automatic STOP on release/background/tab exit/timeout.
- Emit safe JOYSTICK JSONL events with actual moveId, targetDistance, angleSpeed, playTime, step position, and RPC response duration. A server success cannot prove the actual physical angle, so field calibration is still required.
- Redesign Android launcher from the approved cyan robot/controller art: remove the three radio-wave arcs and enlarge the remaining artwork 1.5x. Generate 1024px PNG reproducibly during CI and install adaptive/legacy icons.
- Add native Android home-screen voice widgets: compact voice Q&A, compact voice MCP control, and combined two-action widget. A widget tap foregrounds the app and activates the selected microphone mode with Android permission checks. It never stores secrets in the widget or performs robot actions in the background; physical MCP actions still require approval.
- Keep encrypted settings, Gemini/MCP keys, RTSP monitoring, favorites, notebook and permanent signing.


## 0.2.2+7 — 2026-11-06

- Add local left-turn calibration (15° / 30° / 45°, initial 30°) to compensate for weak left response seen in real-device tests. Apply to both tap and hold; preserve right rotation at 15° and 0.2 m movement steps. Save choice securely on device and log effective angle, RPC completion time and direction.
- Resolve user-owned named-cat memory for explicit whole-house patrol/search commands. Example: a saved note "尾牙是家裡的寵物貓" + a new "在家巡邏尋找尾牙..." request becomes a verified, approval-gated `robot_patrol` call with `duration=120`, `objId="2"`, `targetName="尾牙"`. An explicitly requested patrol duration is capped at five minutes.
- Split the first executable patrol/search stage from deferred photo/follow stages. Do not claim the cat is found or automatically start follow/photography without a reliable detection signal; current EBO MCP does not provide a validated timed-stop follow control.
- Distinguish a text-only Gemini response from real MCP function calls. For physical intents without functionCall, show a prominent "未執行 MCP" reply and log an `AI_NO_TOOL` event. Never present narrative plans as completed operations.
- Log sanitized Gemini HTTP error statuses such as 429/RESOURCE_EXHAUSTED while excluding API keys, prompts and response bodies; preserve useful failure feedback in on-device conversation.
- Add BDD tests for memory-based task plans, approval denial, honest no-functionCall results, sanitized HTTP status and turning calibration.
- Preserve all established features, launcher icon, JKS signing, favorites, encrypted conversation and credentials.


## 0.2.1+6 — 2026-11-06

- On entry to Monitor/Control or return from background on a video tab, request a fresh RTSP open exactly once. Do not auto-poll during an uninterrupted foreground video session; retain manual refresh and log failures.
- Expand the Control video into an available full-screen panel with a semi-transparent direction/photo/record/charge overlay; return to regular view using one button.
- Collapse the complete MCP tools area by default and expand on demand. Preserve all 15+ dynamic tools.
- Split AI voice control from "speech question → EBO spoken answer": audio is first transcribed without robot tools, then queried using Google Search Grounding, and finally voiced by an approved `robot_speak` call. Both text and speech Q&A have explicit UI buttons. Keep ordinary text/voice MCP controls.
- Support tap-once or hold-to-repeat robot_move direction commands. A hold executes only verified short 0.2-m/15-degree micro-steps one at a time with at least 450 ms pause between completed RPCs, max 12 steps or 12 seconds. Release, timeout, app background, tab switch and errors all stop further repeats and enqueue a verified robot_move stop. This is sequential MCP stepping, not native continuous-velocity driving; stop may wait behind an in-flight step due to server/session serialization.
- Extend CI unit tests for tab-entry RTSP policy, gesture hold watchdog/stop/serial steps, and speech transcription without MCP function calling.
- Preserve encrypted credentials, user chat, favorites, notebook, robot launcher icon and permanent JKS release signing.


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
