import 'package:ebo_robot_mcp/services/widget_quick_commands.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('four home shortcuts map to exact verified MCP tool names', () {
    expect(EboWidgetQuickCommand.resolve('quick_dock', []).tool, 'robot_go_home');
    expect(EboWidgetQuickCommand.resolve('quick_photo', []).tool, 'robot_take_photo');
    final patrol = EboWidgetQuickCommand.resolve('quick_patrol', []);
    expect(patrol.tool, 'robot_patrol');
    // Generic patrol must not pretend to search an unnamed target.
    expect(patrol.arguments.containsKey('targetName'), isFalse);
    expect(patrol.arguments, {'duration': 120});
    final pet = EboWidgetQuickCommand.resolve('quick_pet', ['尾牙是家裡的寵物貓']);
    expect(pet.tool, 'robot_patrol');
    expect(pet.arguments, {'duration': 120, 'objId': '2', 'targetName': '尾牙'});
    expect(() => EboWidgetQuickCommand.resolve('quick_pet', []),
        throwsFormatException);
  });
  test('incorrect voice MCP mode detects factual queries, not robot commands', () {
    expect(EboWidgetQuickCommand.isInformationQuestion('今天中和區的天氣如何？'), isTrue);
    expect(EboWidgetQuickCommand.isInformationQuestion('請機器人回充'), isFalse);
    expect(EboWidgetQuickCommand.isInformationQuestion('請左轉 15 度'), isFalse);
  });
}