import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PrivateSettings {
  String mcpJson;
  String geminiKey;
  String rtspUrl;
  String actionMap;

  PrivateSettings({
    this.mcpJson = '',
    this.geminiKey = '',
    this.rtspUrl = '',
    this.actionMap = '',
  });
}

class ConfigStore {
  static const _storage = FlutterSecureStorage();

  Future<PrivateSettings> load() async => PrivateSettings(
    mcpJson: await _storage.read(key: 'mcp_json') ?? '',
    geminiKey: await _storage.read(key: 'gemini_key') ?? '',
    rtspUrl: await _storage.read(key: 'rtsp_url') ?? '',
    actionMap: await _storage.read(key: 'action_map') ?? '',
  );

  Future<void> save(PrivateSettings settings) async {
    await _storage.write(key: 'mcp_json', value: settings.mcpJson);
    await _storage.write(key: 'gemini_key', value: settings.geminiKey);
    await _storage.write(key: 'rtsp_url', value: settings.rtspUrl);
    await _storage.write(key: 'action_map', value: settings.actionMap);
  }
}
