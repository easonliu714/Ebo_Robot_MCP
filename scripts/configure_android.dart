import 'dart:io';

// Run after flutter create. No credentials are committed.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('Run flutter create first.');
    exitCode = 2;
    return;
  }
  var xml = manifest.readAsStringSync();
  const permissions = '''
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
''';
  if (!xml.contains('android.permission.RECORD_AUDIO')) {
    xml = xml.replaceFirst(
      RegExp(r'(<manifest[^>]*>)'),
      RegExp(r'(<manifest[^>]*>)').firstMatch(xml)!.group(1)! + '\n' + permissions,
    );
  }
  if (!xml.contains('android:usesCleartextTraffic')) {
    xml = xml.replaceFirst(
      '<application', '<application android:usesCleartextTraffic="true"');
  }
  if (!xml.contains('android:allowBackup')) {
    xml = xml.replaceFirst(
      '<application', '<application android:allowBackup="false"');
  }
  // Brand both the launcher app name and widget-picker grouping.
  xml = xml.replaceFirst('android:label="ebo_robot_mcp"',
      'android:label="EBO 控制中心"');
  manifest.writeAsStringSync(xml);

  if (!File('android/key.properties').existsSync()) return;
  final gradle = File('android/app/build.gradle.kts');
  if (!gradle.existsSync()) {
    stderr.writeln('Expected Kotlin Gradle build file missing.');
    exitCode = 2;
    return;
  }
  var build = gradle.readAsStringSync();
  if (build.contains('// EBO_RELEASE_CONFIG')) return;
  const signing = '''
// EBO_RELEASE_CONFIG
val eboSigningProperties = Properties().apply {
    file("../key.properties").inputStream().use { stream ->
        load(stream)
    }
}

android {
    signingConfigs {
        create("eboRelease") {
            keyAlias = eboSigningProperties.getProperty("keyAlias")
            keyPassword = eboSigningProperties.getProperty("keyPassword")
            storePassword = eboSigningProperties.getProperty("storePassword")
            storeFile = file("release.jks")
        }
    }
''';
  if (!build.contains('signingConfig = signingConfigs.getByName("debug")')) {
    stderr.writeln('Unexpected Flutter Gradle signing template.');
    exitCode = 2;
    return;
  }
  // Avoid Kotlin Gradle DSL's java extension shadowing java.util.Properties.
  // An import before the plugins {} block is legal in a Kotlin build script.
  build = 'import java.util.Properties\n\n' + build;
  build = build.replaceFirst('android {', signing);
  build = build.replaceFirst(
    'signingConfig = signingConfigs.getByName("debug")',
    'signingConfig = signingConfigs.getByName("eboRelease")',
  );
  gradle.writeAsStringSync(build);
}
