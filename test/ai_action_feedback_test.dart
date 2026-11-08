import 'package:ebo_robot_mcp/services/ai_action_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepted first stage with deferred follow is partial, not failure', () {
    final status = AiActionFeedback.fromResponse(
      prompt: '家裡巡邏找尾牙，找到拍照並跟隨',
      response: 'MCP 已回應第一階段：全屋巡邏尋找尾牙。'
          '\n尚未執行的階段：拍照需要先確認找到目標。',
      plannedPatrol: true,
    );
    expect(status, AiActionFeedback.firstStageAccepted);
  });
  test('unavailable MCP patrol and refusal are clear failures', () {
    for (final message in [
      'MCP 尚未連線，本次沒有實體動作。',
      '目前沒有 robot_patrol 工具，未執行動作。',
      '已拆解任務，但第一階段遭取消，MCP 未執行。',
    ]) {
      expect(AiActionFeedback.fromResponse(
        prompt: '巡邏找尾牙', response: message, plannedPatrol: true,
      ), AiActionFeedback.notExecuted);
    }
  });
  test('Gemini text alone is no MCP; ordinary weather answer is not', () {
    expect(AiActionFeedback.fromResponse(
      prompt: '請前進', response: '【未執行 MCP】Gemini 只回傳文字。',
      plannedPatrol: false,
    ), AiActionFeedback.notExecuted);
    expect(AiActionFeedback.fromResponse(
      prompt: '今天氣溫多少', response: '今天 23 度。',
      plannedPatrol: false,
    ), AiActionFeedback.completedOrAnswered);
  });
}
