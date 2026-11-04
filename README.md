# EBO Robot MCP Controller

EBO-162 Android controller built with Flutter: RTSP live view, manual MCP controls,
Gemini AI text/voice commands, and redacted exportable diagnostic logs.

**Current version: 0.1.1+2 — development preview, hardware not yet verified.**

## First start

1. In the official EBO app, enable MCP and RTSP stream.
2. In this controller, go to **設定**, paste the official **複製配置** JSON,
   enter Gemini API Key, and RTSP URL. All values are stored locally in
   Android encrypted storage.
3. Tap **加密儲存並重新連線**. Verify that tools/list returns tools.
4. Map each button to a discovered tool and JSON argument object.
   The app deliberately does not guess tool names or action parameters.
5. Use 監控, 控制, AI and Log pages. AI commands require a confirmation dialog
   before each physical tool invocation.

**Rotate any AccessKey previously published in a chat, document or repository.**
Never commit real keys, voice data, RTSP credentials, screenshots or logs.

## APK builds

GitHub Actions → Android APK → successful run → Artifacts → APK.
Filename: EBO-v0.1.1-buildN-debug.apk; internal version is 0.1.1+N.

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
