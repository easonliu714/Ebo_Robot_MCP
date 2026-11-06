import 'dart:convert';
import 'dart:typed_data';
import 'package:ebo_robot_mcp/services/gemini_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('speech-to-question request has audio and no MCP tools', () async {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      expect(body.containsKey('tools'), false);
      final parts = ((body['contents'] as List).first as Map)['parts'] as List;
      expect((parts.first as Map).containsKey('inline_data'), true);
      expect((parts.last as Map)['text'].toString(), contains('逐字轉寫'));
      return http.Response(jsonEncode({
        'candidates': [{'content': {'parts': [
          {'text': '新北市土城區明天下午的天氣如何？'}
        ]}}],
      }), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final agent = GeminiAgent(client: client);
    final transcript = await agent.transcribeAudio(
      apiKey: 'mock-key', bytes: Uint8List.fromList([1, 2, 3]));
    expect(transcript, contains('土城區'));
    agent.dispose();
  });

  test('rejects empty audio in spoken Q&A', () async {
    final agent = GeminiAgent();
    await expectLater(agent.transcribeAudio(
      apiKey: 'mock-key', bytes: Uint8List(0)), throwsFormatException);
    agent.dispose();
  });
}
