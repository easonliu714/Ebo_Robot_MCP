import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'mcp_service.dart';

typedef ApproveTool = Future<bool> Function(String name, Map<String, dynamic> args);

class GeminiSchema {
  static Map<String, dynamic> sanitize(Map<String, dynamic> input) {
    const allowed = {
      'type', 'description', 'properties', 'items', 'required', 'enum',
      'minimum', 'maximum', 'minItems', 'maxItems', 'format',
      'minLength', 'maxLength', 'nullable',
    };
    final result = <String, dynamic>{};
    for (final entry in input.entries) {
      if (!allowed.contains(entry.key)) continue;
      if (entry.key == 'properties' && entry.value is Map) {
        result['properties'] = (entry.value as Map).map((k, v) =>
          MapEntry(k.toString(), v is Map
              ? sanitize(Map<String, dynamic>.from(v)) : v));
      } else if (entry.key == 'items' && entry.value is Map) {
        result['items'] = sanitize(Map<String, dynamic>.from(entry.value as Map));
      } else if (entry.key == 'type') {
        final value = entry.value;
        final selected = value is List
            ? value.firstWhere((x) => x != 'null', orElse: () => 'object')
            : value;
        result['type'] = selected.toString().toUpperCase();
      } else {
        result[entry.key] = entry.value;
      }
    }
    result.putIfAbsent('type', () => 'OBJECT');
    if (result['type'] == 'OBJECT') {
      result.putIfAbsent('properties', () => <String, dynamic>{});
    }
    return result;
  }
}

class GeminiAgent {
  final http.Client _http;
  final String model;
  GeminiAgent({http.Client? client, this.model = 'gemini-2.5-flash'})
      : _http = client ?? http.Client();

  Future<String> runText({
    required String apiKey,
    required String prompt,
    required McpClient mcp,
    required ApproveTool approve,
    required void Function(String) onStep,
  }) => _run(
    apiKey: apiKey,
    userParts: [{'text': prompt}],
    mcp: mcp,
    approve: approve,
    onStep: onStep,
  );

  Future<String> runAudio({
    required String apiKey,
    required Uint8List bytes,
    required McpClient mcp,
    required ApproveTool approve,
    required void Function(String) onStep,
  }) {
    if (bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('音檔超過 10 MB，請縮短錄音時間');
    }
    return _run(
      apiKey: apiKey,
      userParts: [
        {'inline_data': {'mime_type': 'audio/mp4', 'data': base64Encode(bytes)}},
        {'text': '請理解這段繁體中文語音指令，決定是否需呼叫機器人工具。'},
      ],
      mcp: mcp,
      approve: approve,
      onStep: onStep,
    );
  }

  Future<String> _run({
    required String apiKey,
    required List<Map<String, dynamic>> userParts,
    required McpClient mcp,
    required ApproveTool approve,
    required void Function(String) onStep,
  }) async {
    if (apiKey.trim().isEmpty) throw const FormatException('尚未設定 Gemini API Key');
    if (!mcp.connected) throw const FormatException('請先連線 MCP');
    final tools = mcp.tools.take(48).toList();
    final lookup = <String, McpTool>{};
    final declarations = <Map<String, dynamic>>[];
    for (var i = 0; i < tools.length; i++) {
      final tool = tools[i];
      final alias = 'tool_' + i.toString() + '_' +
          tool.name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_').substring(
            0, tool.name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_').length.clamp(0, 40),
          );
      lookup[alias] = tool;
      declarations.add({
        'name': alias,
        'description': tool.description.isEmpty ? tool.name : tool.description,
        'parameters': GeminiSchema.sanitize(tool.schema),
      });
    }
    final contents = <Map<String, dynamic>>[
      {'role': 'user', 'parts': userParts},
    ];
    final uri = Uri.https(
        'generativelanguage.googleapis.com',
        '/v1beta/models/' + model + ':generateContent');
    var executed = 0;
    for (var round = 0; round < 5; round++) {
      final request = {
        'systemInstruction': {
          'parts': [{'text':
            '你是 EBO 機器人助手。僅使用已提供的工具，勿編造工具名稱或參數。'
            '每次動作都需使用者確認。優先注意安全，不要無限制移動。以繁體中文回覆。'}],
        },
        'contents': contents,
        if (declarations.isNotEmpty)
          'tools': [{'functionDeclarations': declarations}],
      };
      final response = await _http.post(uri, headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey.trim(),
      }, body: jsonEncode(request)).timeout(const Duration(seconds: 45));
      if (response.statusCode >= 400) {
        throw Exception('Gemini API HTTP ' + response.statusCode.toString());
      }
      final raw = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final candidates = raw['candidates'];
      if (candidates is! List || candidates.isEmpty) {
        throw const FormatException('Gemini 沒有回傳候選結果');
      }
      final modelContent = Map<String, dynamic>.from(
          (candidates.first as Map)['content'] as Map);
      final parts = (modelContent['parts'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final calls = parts.where((p) => p['functionCall'] is Map).toList();
      final plainText = parts.where((p) => p['text'] is String)
          .map((p) => p['text'].toString()).join('\n').trim();
      if (calls.isEmpty) return plainText.isEmpty ? '指令已處理。' : plainText;
      contents.add({'role': 'model', 'parts': parts});
      final responses = <Map<String, dynamic>>[];
      for (final part in calls) {
        final call = Map<String, dynamic>.from(part['functionCall'] as Map);
        final alias = call['name']?.toString() ?? '';
        final definition = lookup[alias];
        final args = call['args'] is Map
            ? Map<String, dynamic>.from(call['args'] as Map)
            : <String, dynamic>{};
        if (definition == null) throw const FormatException('Gemini 指向未知 MCP 工具');
        var result = <String, dynamic>{};
        if (executed >= 8) {
          result = {'error': '已達單次最多 8 個工具呼叫上限'};
        } else {
          ActionResult:
          try {
            final permitted = await approve(definition.name, args);
            if (!permitted) {
              result = {'error': '使用者拒絕執行'};
              break ActionResult;
            }
            // Validation here prevents schema-incompatible arguments being sent.
            result = await mcp.call(definition.name, args);
            executed++;
            onStep('已執行 MCP 工具：' + definition.name);
          } catch (e) {
            result = {'error': '工具執行失敗'};
            onStep('MCP 工具失敗：' + definition.name);
          }
        }
        responses.add({
          'functionResponse': {
            'name': alias,
            'response': _minimizeResult(result),
          },
        });
      }
      contents.add({'role': 'user', 'parts': responses});
    }
    return '已達 AI 最大步驟數（5 輪），停止後續工具呼叫。';
  }

  static Map<String, dynamic> _minimizeResult(Map<String, dynamic> result) {
    final message = jsonEncode(result);
    if (message.length > 3000) {
      return {'summary': message.substring(0, 3000), 'truncated': true};
    }
    return result;
  }

  void dispose() => _http.close();
}
