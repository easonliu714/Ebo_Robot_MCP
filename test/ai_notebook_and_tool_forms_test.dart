import 'dart:convert';

import 'package:ebo_robot_mcp/services/ai_notebook.dart';
import 'package:ebo_robot_mcp/services/gemini_service.dart';
import 'package:ebo_robot_mcp/services/ebo_tool_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('saved chat survives import/export without discarding favorites or notes', () {
    final journal = AiNotebook();
    journal.importJson(jsonEncode({
      'messages': [
        {'id':'1', 'role':'user', 'text':'請到客廳',
          'time':'2026-11-06T08:00:00'},
        {'id':'2', 'role':'assistant', 'text':'收到',
          'time':'2026-11-06T08:01:00'},
      ],
      'favorites': ['請到客廳'],
      'notes': ['客廳在一樓'],
    }));
    final restored = AiNotebook()..importJson(journal.exportJson());
    expect(restored.messages.length, 2);
    expect(restored.messages.first.role, 'user');
    expect(restored.favorites.single, '請到客廳');
    expect(restored.notes.single, '客廳在一樓');
    expect(restored.contextForModel, contains('客廳在一樓'));
    expect(restored.contextForModel, contains('嚴禁重新執行舊指令'));
  });

  test('tool parameter catalog reports true limits and unknown range honestly', () {
    expect(EboToolCatalog.fieldTitle('recordSeconds'), '錄影秒數');
    expect(EboToolCatalog.rangeText('robot_record_video',
        'recordSeconds', {'minimum': 1, 'maximum': 60}),
        '可設定：1 ～ 60');
    expect(EboToolCatalog.rangeText('robot_move',
        'targetDistance', {}, moveId: 1), contains('0～5'));
    expect(EboToolCatalog.rangeText('robot_play_music',
        'song', {}), contains('未提供'));
    expect(EboToolCatalog.numericChoices('robot_music_control',
        'controlType')[4], '停止');
  });

  test('current answer calls Gemini Google Search independently of MCP tools', () async {
    final client = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final tools = body['tools'] as List;
      expect(tools, [{'google_search': <String, dynamic>{}}]);
      expect(body.containsKey('functionDeclarations'), false);
      return http.Response(jsonEncode({
        'candidates': [{
          'content': {'parts': [{'text': '桃園今天下午有陣雨。'}]},
          'groundingMetadata': {
            'groundingChunks': [
              {'web': {'uri': 'https://weather.example.org/today'}}
            ]
          },
        }]
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final gemini = GeminiAgent(client: client);
    final answer = await gemini.runGroundedQuestion(
      apiKey: 'test-not-real-key', prompt: '桃園今天下午天氣');
    expect(answer.text, contains('陣雨'));
    expect(answer.sources.single, startsWith('https://'));
    gemini.dispose();
  });

  test('ungrounded current answer is rejected, not spoken as fact', () async {
    final client = MockClient((req) async =>
        http.Response(jsonEncode({
          'candidates': [{
            'content': {'parts': [{'text': '可能會下雨'}]}
          }],
        }), 200, headers: {'content-type': 'application/json; charset=utf-8'}));
    final gemini = GeminiAgent(client: client);
    await expectLater(gemini.runGroundedQuestion(
      apiKey: 'test-key', prompt: '今天的天氣'), throwsFormatException);
    gemini.dispose();
  });
}
