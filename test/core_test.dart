import 'dart:convert';

import 'package:ebo_robot_mcp/services/action_map.dart';
import 'package:ebo_robot_mcp/services/diagnostics.dart';
import 'package:ebo_robot_mcp/services/gemini_service.dart';
import 'package:ebo_robot_mcp/services/mcp_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MCP config', () {
    test('extracts remote URL and Bearer without running npx', () {
      final source = jsonEncode({
        'mcpServers': {
          'ebo': {
            'command': 'npx',
            'args': [
              'mcp-remote',
              'https://example.com/api/v1/mcp',
              '--header',
              'Authorization: Bearer TEST_ONLY_VALUE',
            ],
          },
        },
      });
      final config = McpConfig.parse(source);
      expect(config.endpoint.toString(), 'https://example.com/api/v1/mcp');
      expect(config.bearer, 'TEST_ONLY_VALUE');
    });
    test('rejects missing/insecure MCP endpoint', () {
      expect(() => McpConfig.parse('{}'), throwsFormatException);
      expect(() => McpConfig.parse(jsonEncode({
        'mcpServers': {
          'ebo': {
            'url': 'http://example.com/mcp',
            'headers': {'Authorization': 'Bearer TEST_ONLY_VALUE'},
          }
        }
      })), throwsFormatException);
    });
  });

  group('Gemini schema sanitation', () {
    test('removes unsupported keys recursively and retains required', () {
      final clean = GeminiSchema.sanitize({
        r'$schema': 'http://json-schema.org',
        'type': 'object',
        'additionalProperties': false,
        'required': ['direction'],
        'properties': {
          'direction': {
            'type': 'string',
            'enum': ['forward', 'stop'],
            'default': 'forward',
          },
        },
      });
      expect(clean.containsKey(r'$schema'), false);
      expect(clean.containsKey('additionalProperties'), false);
      expect(clean['type'], 'OBJECT');
      expect(clean['required'], ['direction']);
      final props = clean['properties'] as Map;
      expect((props['direction'] as Map).containsKey('default'), false);
    });
  });

  group('Robot action mapping', () {
    final tool = McpTool('move_robot', 'Move robot', {
      'type': 'object',
      'required': ['direction'],
      'properties': {
        'direction': {'type': 'string', 'enum': ['forward', 'stop']},
      }
    });
    test('requires known tool and schema-correct arguments', () {
      final mapping = ActionMap();
      mapping.set('forward', 'move_robot', '{"direction":"forward"}', [tool]);
      expect(mapping['forward']!.args['direction'], 'forward');
      expect(() => mapping.set('forward', 'move_robot', '{}', [tool]),
          throwsFormatException);
      expect(() => mapping.set('forward', 'move_robot',
          '{"direction":"backward"}', [tool]), throwsFormatException);
      expect(() => mapping.set('left', 'other', '{}', [tool]),
          throwsFormatException);
    });
    test('persists configured action mappings', () {
      final mapping = ActionMap();
      mapping.set('stop', 'move_robot', '{"direction":"stop"}', [tool]);
      final restored = ActionMap()..load(mapping.exportJson());
      expect(restored['stop']!.tool, 'move_robot');
      expect(restored['stop']!.args['direction'], 'stop');
    });
  });

  test('diagnostics redact Bearer/MCP/Gemini/RTSP credentials', () {
    final source = 'Authorization: Bearer TEST_SECRET '
        'ebo_mcp_exampleSecret AIza123456789012345678901234567890 '
        'rtsp://admin:pass@192.168.1.10:554/main0';
    final clean = Redactor.clean(source);
    expect(clean.contains('TEST_SECRET'), false);
    expect(clean.contains('ebo_mcp_exampleSecret'), false);
    expect(clean.contains('AIza123'), false);
    expect(clean.contains('admin:pass'), false);
  });
}
