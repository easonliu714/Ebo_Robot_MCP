/// Exact-name, consent-gated home-screen actions. None of these values are
/// credentials. Every call is validated against the live MCP tools/list schema.
class EboWidgetQuickCommand {
  final String label;
  final String tool;
  final Map<String, dynamic> arguments;
  const EboWidgetQuickCommand(this.label, this.tool, this.arguments);

  static bool supports(String mode) => const {
    'quick_dock', 'quick_patrol', 'quick_pet', 'quick_photo',
  }.contains(mode);

  static String labelFor(String mode) => switch (mode) {
    'quick_dock' => '返回充電座',
    'quick_patrol' => '全屋巡邏 2 分鐘',
    'quick_pet' => '尋找登載的寵物',
    'quick_photo' => '機器人拍照',
    _ => '未知快捷動作',
  };

  static EboWidgetQuickCommand resolve(String mode, List<String> notes) {
    switch (mode) {
      case 'quick_dock':
        return const EboWidgetQuickCommand(
            '回充', 'robot_go_home', {'startUp': true});
      case 'quick_patrol':
        // The verified tool catalog uses duration alone for generic patrol.
        // Target fields are reserved for an explicitly named pet search.
        return const EboWidgetQuickCommand('全屋巡邏 2 分鐘', 'robot_patrol', {
          'duration': 120,
        });
      case 'quick_photo':
        return const EboWidgetQuickCommand('拍照', 'robot_take_photo', {});
      case 'quick_pet':
        for (final note in notes) {
          final matched = RegExp(
              r'([\u4e00-\u9fff]{1,8})\s*是.{0,12}(貓咪|貓|狗狗|狗)').firstMatch(note);
          if (matched == null) continue;
          final name = matched.group(1)!;
          final kind = matched.group(2)!;
          return EboWidgetQuickCommand('尋找寵物：$name', 'robot_patrol', {
            'duration': 120,
            'objId': kind.contains('貓') ? '2' : '3',
            'targetName': name,
          });
        }
        throw const FormatException('請先在 AI 長期記憶登載「尾牙是家裡的寵物貓」等寵物資訊');
      default:
        throw const FormatException('未支援的桌面快捷指令');
    }
  }

  /// A general information question should not be silently interpreted as a
  /// robot actuator command. Offer the dedicated grounded-Q&A flow instead.
  static bool isInformationQuestion(String transcript) {
    final information = RegExp(
        r'天氣|氣溫|降雨|預報|新聞|股價|匯率|現在幾點|幾點營業|即時資訊|氣象|下雨');
    final physical = RegExp(r'移動|前進|後退|左轉|右轉|停止|回充|巡邏|導航|拍照|錄影|跟隨|尋找|找寵');
    return information.hasMatch(transcript) && !physical.hasMatch(transcript);
  }
}