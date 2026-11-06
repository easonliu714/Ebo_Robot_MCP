import 'dart:convert';
import 'package:ebo_robot_mcp/services/ebo_task_planner.dart';
import 'package:ebo_robot_mcp/services/gemini_service.dart';
import 'package:ebo_robot_mcp/services/mcp_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('no functionCall means no MCP execution even if AI claims a plan', () async {
    final client = MockClient((_) async => http.Response(jsonEncode({
      'candidates': [{
        'content': {'parts': [
          {'text': '我會先巡邏尋找尾牙，之後再拍照。'},
        ]},
      }],
    }), 200, headers: {'content-type': 'application/json; charset=utf-8'}));
    final agent = GeminiAgent(client: client);
    final mcp = McpClient()
      ..connected = true
      ..tools = [const McpTool('robot_patrol', 'Patrol', {
        'type': 'object', 'properties': {},
      })];
    var approvals = 0;
    final events = <String>[];
    final answer = await agent.runText(
      apiKey: 'test-api-key',
      prompt: '請巡邏尋找尾牙並拍照',
      mcp: mcp,
      approve: (_, _) async { approvals++; return true; },
      onStep: events.add,
    );
    expect(answer, contains('未執行 MCP'));
    expect(events.join(' '), contains('AI_NO_TOOL'));
    expect(approvals, 0);
    agent.dispose();
    mcp.dispose();
  });

  test('API HTTP status is reported safely without response body/key', () async {
    final client = MockClient((_) async => http.Response(jsonEncode({
      'error': {
        'code': 429,
        'status': 'RESOURCE_EXHAUSTED',
        'message': 'The secret prompt and key should never be in logs',
      },
    }), 429, headers: {'content-type': 'application/json; charset=utf-8'}));
    final agent = GeminiAgent(client: client);
    final mcp = McpClient()..connected = true;
    final events = <String>[];
    await expectLater(
      agent.runText(
        apiKey: 'test-api-key', prompt: '巡邏尋找尾牙',
        mcp: mcp, approve: (_, _) async => false, onStep: events.add,
      ), throwsA(isA<GeminiApiException>()
          .having((e) => e.statusCode, 'HTTP status', 429)
          .having((e) => e.apiStatus, 'API status', 'RESOURCE_EXHAUSTED')),
    );
    expect(events.join(' '), contains('HTTP 429'));
    expect(events.join(' '), isNot(contains('secret prompt')));
    agent.dispose();
    mcp.dispose();
  });

  test('cat patrol requires explicit approval and never calls on rejection',
      () async {
    final mcp = McpClient()
      ..connected = true
      ..tools = [const McpTool('robot_patrol', 'Patrol home', {
        'type': 'object',
        'properties': {
          'duration': {'type': 'integer'},
          'objId': {'type': 'string'},
          'targetName': {'type': 'string'},
        },
      })];
    final plan = EboTaskPlan.fromPrompt(
        '家裡巡邏找尾牙拍照', ['尾牙是家裡的寵物貓'])!;
    var approves = 0;
    final logs = <String>[];
    final result = await plan.startPatrol(
      mcp: mcp,
      approve: (name, args) async {
        approves++;
        expect(name, 'robot_patrol');
        expect(args, {'duration': 120, 'objId': '2', 'targetName': '尾牙'});
        return false;
      },
      onStep: logs.add,
    );
    expect(approves, 1);
    expect(result, contains('MCP 未執行'));
    expect(result, contains('尚未執行'));
    expect(logs.join(' '), contains('使用者拒絕'));
    mcp.dispose();
  });
}
