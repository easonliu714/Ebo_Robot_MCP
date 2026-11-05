import 'package:ebo_robot_mcp/services/action_map.dart';
import 'package:ebo_robot_mcp/services/ebo_tool_catalog.dart';
import 'package:ebo_robot_mcp/services/mcp_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const discoveredNames = [
    'robot_move', 'robot_navigate', 'robot_patrol', 'robot_take_photo',
    'robot_play_music', 'robot_go_home', 'robot_stop_patrol',
    'robot_follow', 'robot_search_360', 'robot_record_video',
    'robot_music_control', 'robot_set_volume', 'robot_speak',
    'robot_list_locations', 'robot_status',
  ];

  McpTool sampleTool(String name) {
    if (name == 'robot_move') {
      return const McpTool('robot_move', 'Movement', {
        'type': 'object',
        'required': ['moveId'],
        'properties': {
          'moveId': {'type': 'integer', 'minimum': 0, 'maximum': 15},
          'targetDistance': {'type': 'number'},
        },
      });
    }
    if (name == 'robot_record_video') {
      return const McpTool('robot_record_video', 'Record clip', {
        'type': 'object',
        'properties': {'recordSeconds': {'type': 'integer'}},
      });
    }
    return McpTool(name, 'EBO tool', const {
      'type': 'object',
      'properties': <String, dynamic>{},
    });
  }

  test('catalog has all 15 actual EBO tools with Chinese labels', () {
    expect(EboToolCatalog.labels.keys.toSet(), discoveredNames.toSet());
    expect(EboToolCatalog.labels.length, 15);
    expect(EboToolCatalog.suggestedArgs('robot_record_video'),
        {'recordSeconds': 10});
  });

  test('known tool schemas produce 9 safe quick bindings', () {
    final tools = discoveredNames.map(sampleTool).toList();
    final mappings = ActionMap();
    final added = EboToolCatalog.applyKnownDefaults(mappings, tools);
    expect(added, 9);
    expect(mappings['forward']!.tool, 'robot_move');
    expect(mappings['forward']!.args,
        {'moveId': 1, 'targetDistance': 0.2});
    expect(mappings['left']!.args,
        {'moveId': 3, 'targetDistance': 15});
    expect(mappings['stop']!.args['moveId'], 5);
    expect(mappings['record_clip']!.tool, 'robot_record_video');
    expect(mappings['record_clip']!.args['recordSeconds'], 10);
    expect(mappings['dock']!.tool, 'robot_go_home');
    expect(mappings['stop_patrol']!.tool, 'robot_stop_patrol');
  });

  test('preserves custom user settings and skips missing tools', () {
    final mappings = ActionMap();
    mappings.bindings['forward'] = const ActionBinding(
        'custom_move', {'direction': 'ahead'});
    final added = EboToolCatalog.applyKnownDefaults(
        mappings, [sampleTool('robot_move')]);
    expect(added, 4);
    expect(mappings['forward']!.tool, 'custom_move');
    expect(mappings['photo'], isNull);
    expect(mappings['dock'], isNull);
  });

  test('rejects out-of-range movement and numeric enum parameters', () {
    final tool = sampleTool('robot_move');
    expect(
      () => ActionMap.validateArguments(tool, {
        'moveId': 1, 'targetDistance': 6,
      }),
      throwsFormatException,
    );
    expect(
      () => ActionMap.validateArguments(tool, {
        'moveId': 4, 'targetDistance': 361,
      }),
      throwsFormatException,
    );
    expect(
      () => ActionMap.validateArguments(tool, {
        'moveId': 16, 'targetDistance': 0,
      }),
      throwsFormatException,
    );
    const musicTool = McpTool('robot_music_control', 'Music', {
      'type': 'object',
      'required': ['controlType'],
      'properties': {
        'controlType': {
          'type': 'integer',
          'minimum': 1,
          'maximum': 6,
        },
      },
    });
    expect(
      () => ActionMap.validateArguments(musicTool, {'controlType': 7}),
      throwsFormatException,
    );
  });
}
