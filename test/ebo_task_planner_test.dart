import 'package:ebo_robot_mcp/services/ebo_task_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved cat note and direct patrol request creates verified args', () {
    final plan = EboTaskPlan.fromPrompt(
        '在家裡巡邏，尋找尾牙，拍一張照片並且跟隨他5分鐘',
        ['尾牙是家裡的寵物貓']);
    expect(plan, isNotNull);
    expect(plan!.patrolArguments,
        {'duration': 120, 'objId': '2', 'targetName': '尾牙'});
    expect(plan.wantsPhoto, isTrue);
    expect(plan.wantsFollow, isTrue);
    expect(plan.followMinutes, 5);
    expect(plan.deferredStages, contains('尚未執行'));
  });

  test('5 minute follow must not be mistaken for patrol duration', () {
    final plan = EboTaskPlan.fromPrompt(
        '全屋巡邏並尋找尾牙，跟隨他5分鐘', ['尾牙是家裡的寵物貓']);
    expect(plan!.durationSeconds, 120);
  });

  test('explicit 99 minute patrol capped to 300 seconds', () {
    final plan = EboTaskPlan.fromPrompt(
        '家裡巡邏99分鐘並找尾牙', ['尾牙是家裡的寵物貓']);
    expect(plan!.durationSeconds, 300);
  });

  test('missing approved note must never guess target type', () {
    expect(EboTaskPlan.fromPrompt('巡邏找尾牙', []), isNull);
    expect(EboTaskPlan.fromPrompt('巡邏找小狗', ['尾牙是寵物貓']), isNull);
    expect(EboTaskPlan.fromPrompt('今天天氣如何', ['尾牙是貓']), isNull);
  });
}
