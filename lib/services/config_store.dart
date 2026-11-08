import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PrivateSettings {
  String mcpJson;
  String geminiKey;
  String rtspUrl;
  String actionMap;
  int leftTurnDegrees;
  int turnRadiusMode;
  int diagonalTurnDegrees;

  PrivateSettings({
    this.mcpJson = '',
    this.geminiKey = '',
    this.rtspUrl = '',
    this.actionMap = '',
    this.leftTurnDegrees = 30,
    this.turnRadiusMode = 1,
    this.diagonalTurnDegrees = 7,
  });
}

class ConfigStore {
  static const _storage = FlutterSecureStorage();

  Future<PrivateSettings> load() async => PrivateSettings(
    mcpJson: await _storage.read(key: 'mcp_json') ?? '',
    geminiKey: await _storage.read(key: 'gemini_key') ?? '',
    rtspUrl: await _storage.read(key: 'rtsp_url') ?? '',
    actionMap: await _storage.read(key: 'action_map') ?? '',
    leftTurnDegrees: int.tryParse(await _storage.read(key: 'left_turn_degrees') ?? '') ?? 30,
    turnRadiusMode: int.tryParse(await _storage.read(key: 'turn_radius_mode') ?? '') ?? 1,
    diagonalTurnDegrees: int.tryParse(await _storage.read(key: 'diagonal_turn_degrees') ?? '') ?? 7,
  );

  Future<void> save(PrivateSettings settings) async {
    await _storage.write(key: 'mcp_json', value: settings.mcpJson);
    await _storage.write(key: 'gemini_key', value: settings.geminiKey);
    await _storage.write(key: 'rtsp_url', value: settings.rtspUrl);
    await _storage.write(key: 'action_map', value: settings.actionMap);
    await _storage.write(key: 'left_turn_degrees', value: settings.leftTurnDegrees.toString());
    await _storage.write(key: 'turn_radius_mode', value: settings.turnRadiusMode.toString());
    await _storage.write(key: 'diagonal_turn_degrees', value: settings.diagonalTurnDegrees.toString());
  }
}
