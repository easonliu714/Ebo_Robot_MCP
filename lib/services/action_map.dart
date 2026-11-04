import 'dart:convert';
import 'mcp_service.dart';

const robotActions = <String, String>{
  'forward': '前進（0.2 公尺）',
  'backward': '後退（0.2 公尺）',
  'left': '左轉（15 度）',
  'right': '右轉（15 度）',
  'stop': '停止移動',
  'photo': '機器人拍照',
  'record_clip': '錄影 10 秒',
  'dock': '返回充電座',
  'stop_patrol': '停止巡邏／導航',
};

class ActionBinding {
  final String tool;
  final Map<String, dynamic> args;
  const ActionBinding(this.tool, this.args);
  Map<String, dynamic> toJson() => {'tool': tool, 'args': args};
  factory ActionBinding.fromJson(Map<String, dynamic> value) => ActionBinding(
    value['tool']?.toString() ?? '',
    Map<String, dynamic>.from(value['args'] is Map ? value['args'] as Map : {}),
  );
}

class ActionMap {
  final Map<String, ActionBinding> bindings = {};
  ActionBinding? operator [](String action) => bindings[action];

  void set(String action, String tool, String argsJson, List<McpTool> tools) {
    if (!robotActions.containsKey(action)) throw const FormatException('未知的動作');
    final definition = tools.where((t) => t.name == tool).firstOrNull;
    if (definition == null) throw const FormatException('請先選擇 MCP 工具');
    final decoded = jsonDecode(argsJson);
    if (decoded is! Map) throw const FormatException('參數必須是 JSON 物件');
    final args = Map<String, dynamic>.from(decoded);
    validateArguments(definition, args);
    bindings[action] = ActionBinding(tool, args);
  }

  static void validateArguments(McpTool tool, Map<String, dynamic> args) {
    final schema = tool.schema;
    final required = schema['required'];
    if (required is List) {
      for (final name in required) {
        if (!args.containsKey(name)) {
          throw FormatException('缺少必要參數：' + name.toString());
        }
      }
    }
    final properties = schema['properties'];
    if (properties is Map) {
      for (final entry in args.entries) {
        final spec = properties[entry.key];
        if (spec is! Map) continue;
        final type = spec['type']?.toString().toLowerCase();
        final value = entry.value;
        final valid = switch (type) {
          'string' => value is String,
          'integer' => value is int,
          'number' => value is num,
          'boolean' => value is bool,
          'array' => value is List,
          'object' => value is Map,
          _ => true,
        };
        if (!valid) throw FormatException('參數型別錯誤：' + entry.key);
        final allowed = spec['enum'];
        if (allowed is List && !allowed.contains(value)) {
          throw FormatException('參數不在允許清單：' + entry.key);
        }
      }
    }
  }

  String exportJson() => jsonEncode(
      bindings.map((key, value) => MapEntry(key, value.toJson())));

  void load(String raw) {
    bindings.clear();
    if (raw.isEmpty) return;
    final obj = jsonDecode(raw);
    if (obj is! Map) return;
    for (final entry in obj.entries) {
      if (robotActions.containsKey(entry.key) && entry.value is Map) {
        bindings[entry.key.toString()] =
            ActionBinding.fromJson(Map<String, dynamic>.from(entry.value as Map));
      }
    }
  }
}
