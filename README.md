# EBO Robot MCP Controller

EBO-162 Android controller built with Flutter: RTSP live view, manual MCP controls,
Gemini AI text/voice commands, and redacted exportable diagnostic logs.

**Current version: 0.2.2+7 — development preview, hardware not yet verified.**

## First start

1. In the official EBO app, enable MCP and RTSP stream.
2. In this controller, go to **設定**, paste the official **複製配置** JSON,
   enter Gemini API Key, and RTSP URL. All values are stored locally in
   Android encrypted storage.
3. Tap **加密儲存並重新連線**. Verify that tools/list returns tools.
4. The app automatically supplies 9 conservative quick actions only when the
   exact EBO tool names and real JSON Schemas match. Existing custom mappings
   are never overwritten. Edit these under Settings if necessary.
5. The **控制** screen lists all 15 MCP tools in Chinese, provides their
   descriptions and input schemas, and opens an editable JSON argument dialog
   followed by an explicit confirmation before calling a tool.
6. Use 監控, 控制, AI and Log pages. AI commands require a confirmation dialog
   before each physical tool invocation.

**Rotate any AccessKey previously published in a chat, document or repository.**
Never commit real keys, voice data, RTSP credentials, screenshots or logs.

## 15 EBO-162 MCP tools

The **控制** page displays the live `tools/list` inventory. Supported
tools from the verified EBO-162 diagnostic log are:
`robot_move`, `robot_navigate`, `robot_patrol`, `robot_take_photo`,
`robot_play_music`, `robot_go_home`, `robot_stop_patrol`,
`robot_follow`, `robot_search_360`, `robot_record_video`,
`robot_music_control`, `robot_set_volume`, `robot_speak`,
`robot_list_locations`, `robot_status`.

One-shot movement defaults are 0.2 m forward/back and 15-degree turns;
the recording shortcut captures a 10-second clip on the robot.
`robot_record_video` does not provide separate start and stop endpoints.
No dedicated camera gimbal tool was found among these 15 tools.

RTSP monitoring still requires direct network connectivity to the robot.
If using an external Wi-Fi or cellular network, configure a safe VPN
connection into the home LAN. This version does not bypass that restriction.

## Android launcher icon

The approved robot/controller icon is committed at
`assets/icon/ebo_launcher.png`. GitHub Actions invokes `dart run flutter_launcher_icons`
**after** generating the Android platform scaffold. This overwrites the
Flutter template icon and generates both legacy and adaptive Android launcher
resources. Android launchers may cache the prior icon; restart the launcher or
reinstall the signed app if necessary.

## AI conversation, favorites and spoken answers (v0.2.2)

The AI tab keeps the latest 60 messages encrypted locally. Long-press a user
message to add/remove it from favorite quick commands; tapping a favorite resends
it through Gemini with ordinary confirmation for every physical MCP operation.
Long-press any message to add a background note to the opt-in private notebook.
Notes and last few conversational turns are included as background in the next
request but **never treated as a fresh robot command**. Clearing chat leaves
favorites and notes intact. Notes and message contents are not exported in
redacted JSONL diagnostics or stored in the repository.

For factual current weather, enter an **explicit city or area** and select
"查詢即時資訊，讓 EBO 語音回答". Gemini uses Google Search grounding
separately from MCP tool calls; the answer requires verifiable grounding
sources, then `robot_speak` sends a short Chinese TTS phrase **only after
user confirmation**. Weather depends on Google Search coverage, network and
the robot's speech support; voice output needs real-device validation.

## Dynamic MCP tool forms

The Control page uses the complete paginated `tools/list`. 15 known firmware
tool names have Chinese labels, descriptions and common numeric code hints.
Future tools appear with their raw server-provided names/descriptions.
Parameter fields honor server-provided types, ranges and enumerations:
numeric input, dropdowns, booleans, and advanced JSON for complex values.
Open-ended text fields offer an "自訂文字" dropdown option rather than
inventing unsupported choices. The navigation form can query
`robot_list_locations` on demand. All invocations require confirmation.

## APK builds

GitHub Actions → Android APK → successful run → Artifacts → APK.
Filename: EBO-v0.2.2-buildN-debug.apk; internal version is 0.2.2+N.

The build number follows GitHub Actions run number. On every source release
update pubspec.yaml, CHANGELOG.md, and the build-name in android.yml.

**Debug artifacts are testing-only and not guaranteed to upgrade in place**,
because GitHub hosted runners use ephemeral debug signing keys.
For a persistent **release** signing certificate, set these repository secrets:

- ANDROID_KEYSTORE_BASE64 (base64 of a persistent private JKS)
- ANDROID_KEYSTORE_PASSWORD
- ANDROID_KEY_ALIAS
- ANDROID_KEY_PASSWORD

With all four secrets configured, the workflow also produces a signed release APK.
Back up that private keystore. Never commit it. Release updates must reuse the same
package ID and same signing key. Debug and release builds cannot upgrade each other.

## Export bug reports

Tap Log → 匯出 Log. Share the generated JSONL. It includes version/build,
timestamp, MCP status, sanitized tool schemas, status/error event codes. Credentials,
prompts, microphone audio and RTSP frames are not deliberately logged.
**Inspect the exported file before sharing**, since any software redactor
can miss unexpected secret formats.

## Local development

Flutter stable, Java 17 and the Android SDK are required. In this repository:

    flutter create --platforms=android --org com.easonliu714 --project-name ebo_robot_mcp .
    dart run scripts/configure_android.dart
    flutter pub get
    flutter analyze
    flutter test
    flutter run

CI generates Android scaffolding on every build instead of committing it,
then deletes the auto-generated `test/widget_test.dart` before static analysis.

## Limitations

Physical commands depend on EBO firmware and the actual tools/list Schema.
An unassigned control will do nothing. RTSP requires LAN reachability.
A successful recording MCP call does not guarantee the robot exposes a
downloadable MP4 in this app. Local snapshots can be shared as PNG.
Only one MCP client is used inside the app; close other external clients
before connecting if the EBO backend enforces a one-client restriction.

## v0.2.2: RTSP and safe held-direction control

Entering Monitor/Control from a different tab, or resuming the app while
showing video, requests **one** RTSP reconnect. No persistent foreground
reconnect loop is used. Tap "放大監控＋懸浮控制器" on the Control page to overlay
semi-transparent direction, photo, recording and charging controls on a larger
video view. The complete MCP tool list is collapsed by default.

D-pad short tap executes its existing single-step binding. Long press a
direction to repeat only **short verified robot_move steps** (forward/backward
0.2 m; turns 15 degrees). Only one step is in flight, with at least 450 ms
between completed requests, and at most 12 steps or 12 seconds per hold.
Finger release, tab switch, app background, timeout or API error stops
repetition and queues moveId=5 stop. Release does **not** guarantee an
instant physical stop: MCP calls are serialized and the in-flight step may
complete first. Test in an obstacle-free area. Gesture mode is disabled
without validated direction and stop mappings.

AI now has separate controls for:
- Text/voice `MCP 控制`: standard agent function calling with approval.
- Text question / spoken question `EBO 語音回覆`: Gemini Search-grounded
  factual answering; speech questions first use a transcription-only API
  call with **no** MCP tool declarations, then Search, then approved
  `robot_speak`. No ungrounded weather answers get spoken automatically.

## v0.2.2: AI plans vs. actual MCP actions

Gemini's ordinary prose is **not an MCP action**. The client now explicitly
reports `【未執行 MCP】` if an action request returns no functionCall, rather
than treating an AI-written plan as success. Failed API calls show a redacted
HTTP status/status enum in the JSONL Log (no secret request body).

A deliberately scoped **first-stage** command planner uses an *explicit*
user-written notebook entry such as `尾牙是家裡的寵物貓` to resolve a new
request like `在家裡巡邏尋找尾牙、拍照並跟隨他5分鐘`. It confirms and
calls `robot_patrol(duration=120, objId="2", targetName="尾牙")` only when
the live tool Schema matches. The returned reply explicitly marks photo and
five-minute follow **not executed** pending verified detection and a safe
follow-stop mechanism. There is no invented auto-detection or hidden delayed
execution. A cancelled confirmation sends no MCP request.

The Control page now has a **left-turn calibration** dropdown: 15, 30, or
45 degrees per press/repeated step. Default is 30 degrees; right remains 15
degrees. MCP logs show requested angle, direction and response latency, not
private keys. Test in an open area before adopting larger angles.

## v0.2.3: Eight-way circular pad and Android voice home widgets

The Control page replaces the cross D-pad with a responsive circular touchpad.
Tap a sector for one safe step; hold for bounded repeat; release/center to
request stop. Diagonal sectors use **sequential** turn 7° + translate 0.1 m
because `robot_move` has no simultaneous linear/angular control interface.
This is not a guarantee of collision avoidance or exact robot odometry.
MCP acknowledgements are not physical-motion sensor feedback.

Three native **Android home-screen widgets** are available:
`EBO 語音查詢` (Google Search grounding → approval → EBO speak),
`EBO 語音指令` (Gemini function calling → MCP with confirmation), and
`EBO 雙語音控制` (both buttons). Long-press an empty Android home-screen
area → Widgets/小工具 → EBO Robot MCP → select a widget. A tap opens the
app in the foreground and begins microphone recording only after Android
permission is granted. Tap the voice button again to submit. App closed or
no network/MCP means no robot action; widgets do not keep the microphone
active in the background.

The launcher no longer shows Wi-Fi arcs. CI renders its original robot and
controller shapes at 1.5× scale using
`python3 scripts/render_launcher_icon.py`, then installs both Android icon
formats. Committed original art remains available for reproducibility.

## v0.2.4: Android launcher art and actionable home-screen widgets

A rounded cyan/blue 3D icon with transparent outer corners replaces the old
outline icon in both the installed app and signed APK. Four distinct native
home widgets are provided: EBO Voice Q&A (robot art), EBO Voice MCP Control
(controller art), Dual Voice, and Quick Actions (Dock / 2-minute Patrol /
Find Saved Pet / Photo). The widget picker uses dedicated preview images.

All widget activations bring the app to foreground. Voice modes visibly state
whether microphone capture started or permission was denied; tap again to
submit. A quick action shows its requested MCP command and arguments for
explicit approval. No background robot commands or hidden recording are used.
The pet shortcut reads an explicit cat/dog record from the encrypted notebook;
without a record it shows an error rather than guessing a target.

In the AI page, commands that cannot be executed surface a persistent
information dialog. When a weather/news question is accidentally submitted to
the voice MCP mode, the app offers to reroute to grounded Q&A. This does not
execute any MCP motion command without consent.


## v0.2.5 Widget verification and startup behavior

The real Android widgets (not screenshots) are created in
`scripts/install_android_widgets.dart` and reference the approved compressed
art in `assets/branding`. Four widget providers are installed: separate
**EBO 語音查詢** (microphone + robot), **EBO 語音控制** (microphone +
controller), combined voice buttons and a **回充 / 巡邏 / 找寵 / 拍照**
quick-command panel. Each has a distinct widget-picker preview; titles
auto-scale with Android widget size. Home-screen voice opens the foreground
app, waits for secure settings and notebook loading, then prompts clearly
when recording begins. Quick robot actions validate live MCP tool schemas
and require user confirmation before any tools/call. Errors appear as
dialogs and persistent banners. Background/automatic microphone capture is
not used.

The launcher is built from the approved 3D robot/controller artwork, retains
the blue gradient within the rounded tile and clips all pixels outside the
tile to true alpha transparency (including installer/legacy/adaptive icons).

## v0.2.6 – On-device voice controls and widget notifications

The installed Android widgets use real native `RemoteViews`, not mockups.
Their widget-picker previews use `previewLayout` with distinct art and fall back
to `previewImage` where required. The app/installer icon keeps its glossy robot
and controller over a blue-cyan gradient with transparent outer corners.

Opening a voice widget brings the app to the foreground, then explicitly
highlights active recording. The recording panel has **Cancel** (discard local
audio without triggering AI/MCP) and **Finish & Send**. A quick-command widget
shows immediate arrival feedback, asks before physical actions, and displays
clear errors or cancellation status. Empty or duplicate AI requests also report
their reason rather than appearing to do nothing. No background microphone
or unattended motion commands are started.
