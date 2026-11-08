/// User-visible result classifier. A plan that sent only its first stage
/// must not be mislabeled "no MCP" solely because later stages are deferred.
enum AiActionFeedback {
  notExecuted,
  firstStageAccepted,
  completedOrAnswered;

  static AiActionFeedback fromResponse({
    required String response,
    required String prompt,
    required bool plannedPatrol,
  }) {
    if (plannedPatrol &&
        response.startsWith('MCP 已回應第一階段：')) {
      return AiActionFeedback.firstStageAccepted;
    }
    if (response.startsWith('【未執行 MCP】') || plannedPatrol) {
      return AiActionFeedback.notExecuted;
    }
    final physicalIntent = RegExp(
        r'巡邏|回充|移動|拍照|跟隨|尋找|導航|錄影|前進|後退|左轉|右轉|停止')
        .hasMatch(prompt);
    if (physicalIntent &&
        RegExp(r'未執行|本次沒有實體動作|沒有任何 MCP')
            .hasMatch(response)) {
      return AiActionFeedback.notExecuted;
    }
    return AiActionFeedback.completedOrAnswered;
  }
}
