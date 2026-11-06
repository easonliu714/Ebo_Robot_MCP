import 'action_map.dart';
import 'mcp_service.dart';

/// Narrow first-stage plan: only explicit whole-home search plus a user-saved
/// note identifying the target as a cat qualifies. Never interpret prior
/// memory as a new physical command.
class EboTaskPlan {
  final String targetName;
  final int durationSeconds;
  final bool wantsPhoto;
  final bool wantsFollow;
  final int? followMinutes;
  const EboTaskPlan(this.targetName, this.durationSeconds,
      this.wantsPhoto, this.wantsFollow, this.followMinutes);

  static EboTaskPlan? fromPrompt(String prompt, List<String> notes) {
    if (!RegExp(r'巡邏|巡逻|全屋巡|家裡巡|家中巡').hasMatch(prompt) ||
        !RegExp(r'尋找|找尋|搜索|搜尋|找出|找').hasMatch(prompt)) {
      return null;
    }
    for (final note in notes) {
      final match = RegExp(
          r'([\u4e00-\u9fff]{1,8})\s*是.{0,12}(?:貓咪|貓)').firstMatch(note);
      final name = match?.group(1);
      if (name == null || name.isEmpty || !prompt.contains(name)) continue;
      final requested = RegExp(r'巡邏.{0,8}?(\d{1,2})\s*分鐘').firstMatch(prompt);
      final minutes = requested == null ? null
          : int.tryParse(requested.group(1)!);
      final seconds = minutes == null ? 120
          : (minutes * 60).clamp(30, 300).toInt();
      final follow = RegExp(r'跟隨|跟著|追蹤').hasMatch(prompt);
      final followTime = RegExp(r'跟隨.{0,8}?(\d{1,2})\s*分鐘')
          .firstMatch(prompt);
      return EboTaskPlan(
        name,
        seconds,
        RegExp(r'拍照|照片|拍一張|攝影').hasMatch(prompt),
        follow,
        followTime == null ? null : int.tryParse(followTime.group(1)!),
      );
    }
    return null;
  }

  Map<String, dynamic> get patrolArguments => {
    'duration': durationSeconds,
    'objId': '2',
    'targetName': targetName,
  };

  String get deferredStages {
    final stages = <String>[];
    if (wantsPhoto) stages.add('拍照需要先確認目標確實出現在鏡頭中');
    if (wantsFollow) {
      stages.add('跟隨' +
          (followMinutes == null ? '' : followMinutes.toString() + ' 分鐘') +
          '需要先確認找到目標；原廠未提供可驗證的限時停止跟隨機制');
    }
    return stages.isEmpty ? '' : '\n尚未執行的階段：\n- ' +
        stages.join('\n- ');
  }

  Future<String> startPatrol({
    required McpClient mcp,
    required Future<bool> Function(String name, Map<String, dynamic> args) approve,
    required void Function(String message) onStep,
  }) async {
    if (!mcp.connected) return 'MCP 尚未連線，本次沒有實體動作。';
    final tool = mcp.tools.where((t) => t.name == 'robot_patrol').firstOrNull;
    if (tool == null) return '目前沒有 robot_patrol 工具，未執行動作。';
    final props = tool.schema['properties'];
    if (props is! Map ||
        !['duration', 'objId', 'targetName'].every(props.containsKey)) {
      return 'robot_patrol 工具參數格式已變更，為安全起見未執行。';
    }
    final args = patrolArguments;
    ActionMap.validateArguments(tool, args);
    onStep('PLAN: 巡邏尋找貓，限制 ' + durationSeconds.toString() + ' 秒');
    final permitted = await approve(tool.name, args);
    if (!permitted) {
      onStep('PLAN: 使用者拒絕巡邏，本次沒有 MCP 呼叫');
      return '已拆解任務，但第一階段遭取消，MCP 未執行。' + deferredStages;
    }
    onStep('PLAN: 開始呼叫 MCP robot_patrol');
    await mcp.call(tool.name, args);
    onStep('PLAN: robot_patrol 有回應，尚未證實目標已找到');
    return 'MCP 已回應第一階段：全屋巡邏尋找' + targetName +
        '（貓），設定上限 ' + durationSeconds.toString() +
        ' 秒。尚未確認實際找到目標。' + deferredStages;
  }
}
