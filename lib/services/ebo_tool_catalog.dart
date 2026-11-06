import 'action_map.dart';
import 'mcp_service.dart';

/// Catalog based on the verified EBO-162 tools/list inputSchema.
/// These are labels/examples, not hard-coded copies of authentication data.
class EboToolCatalog {
  static const labels = <String, String>{
    'robot_move': '方向與動作控制',
    'robot_navigate': '地圖導航',
    'robot_patrol': '全屋自動巡邏',
    'robot_take_photo': '機器人拍照',
    'robot_play_music': '播放音樂',
    'robot_go_home': '返回充電座',
    'robot_stop_patrol': '停止巡邏／導航',
    'robot_follow': '跟隨人員或寵物',
    'robot_search_360': '360° 環境搜尋',
    'robot_record_video': '定時錄影',
    'robot_music_control': '音樂播放控制',
    'robot_set_volume': '調整音量',
    'robot_speak': '機器人語音播報',
    'robot_list_locations': '列出地圖位置',
    'robot_status': '取得機器人狀態',
  };

  static const hints = <String, String>{
    'robot_move': '方向捷徑會帶入正確 moveId、短距離或角度。請勿用任意 JSON 嘗試高速移動。',
    'robot_navigate': '必須先呼叫「列出地圖位置」，再使用確切 locationName。',
    'robot_patrol': 'duration 0 代表無時間限制；預設僅測試 60 秒。',
    'robot_take_photo': '觸發機器人本體拍照，並非手機 RTSP 截圖。',
    'robot_play_music': '可以指定 song、singer 或 text 分類。',
    'robot_go_home': 'startUp=true 返回充電座；false 取消返回。',
    'robot_stop_patrol': '停止巡邏與導航；不是 robot_move 的方向停止。',
    'robot_follow': 'trackTarget：4 人員、3 寵物；mode：0 跟隨、1 鎖定。',
    'robot_search_360': 'objId 留空為一般環視；此動作會旋轉整個機器人。',
    'robot_record_video': '錄製指定秒數，並無獨立的「停止錄影」Tool。',
    'robot_music_control': 'controlType：1 重播、2 暫停、3 繼續、4 停止、5 下一首、6 上一首。',
    'robot_set_volume': 'direction：0 指定 volume、1 增加、2 減少。',
    'robot_speak': 'text 必填。按執行前可再次確認要播報的內容。',
    'robot_list_locations': '查詢既有地圖位置，提供給地圖導航使用。',
    'robot_status': '查詢電量、任務與其他機器人狀態。',
  };

  /// Only known, bounded test examples. Required free-text fields are blank;
  /// the user must fill them in and pass schema checks before execution.
  static Map<String, dynamic> suggestedArgs(String name) => switch (name) {
    'robot_patrol' => {'duration': 60},
    'robot_go_home' => {'startUp': true},
    'robot_follow' => {'mode': 1, 'trackTarget': 4},
    'robot_search_360' => <String, dynamic>{},
    'robot_record_video' => {'recordSeconds': 10},
    'robot_music_control' => {'controlType': 2},
    'robot_set_volume' => {'direction': 2},
    'robot_navigate' => {'locationName': ''},
    'robot_speak' => {'text': ''},
    _ => <String, dynamic>{},
  };


  /// Display original English property keys alongside these localized names.
  static const parameterNames = <String, String>{
    'moveId': '移動動作代碼',
    'targetDistance': '移動距離／轉向角度',
    'locationName': '地圖位置名稱',
    'duration': '巡邏時間（秒）',
    'song': '歌曲名稱',
    'singer': '歌手名稱',
    'text': '文字內容',
    'startUp': '啟動返回充電座',
    'mode': '跟隨模式',
    'trackTarget': '追蹤對象',
    'objId': '搜尋對象代碼',
    'recordSeconds': '錄影秒數',
    'controlType': '音樂控制代碼',
    'direction': '音量控制代碼',
    'volume': '音量數值',
    'lang': '語音語言',
  };
  static const parameterHints = <String, String>{
    'moveId': '1 前進、2 後退、3 左轉、4 右轉、5 停止；其他值依韌體 Schema。',
    'targetDistance': '前後移動以公尺計，左右轉以角度計；依動作限制。',
    'locationName': '先查詢地圖位置，再選擇已儲存的位置名稱。',
    'duration': '單位為秒；0 可能表示無限制，請審慎使用。',
    'recordSeconds': '指定錄影秒數，不是開始／停止切換。',
    'startUp': '開啟為返回充電座；關閉為取消返回。',
    'mode': '0 跟隨、1 鎖定；以工具 Schema 為準。',
    'trackTarget': '4 人員、3 寵物；以工具 Schema 為準。',
    'controlType': '1 重播、2 暫停、3 繼續、4 停止、5 下一首、6 上一首。',
    'direction': '0 設定音量、1 增加、2 減少。',
    'text': '輸入希望機器人播報或使用的文字。',
    'lang': '如支援繁體中文，可使用 zh-TW；以 Schema 為準。',
  };
  static const numericLabels = <String, Map<int, String>>{
    'robot_move.moveId': {
      1: '前進', 2: '後退', 3: '左轉', 4: '右轉', 5: '停止',
    },
    'robot_follow.mode': {0: '跟隨', 1: '鎖定'},
    'robot_follow.trackTarget': {3: '寵物', 4: '人員'},
    'robot_music_control.controlType': {
      1: '重播', 2: '暫停', 3: '繼續', 4: '停止', 5: '下一首', 6: '上一首',
    },
    'robot_set_volume.direction': {0: '指定音量', 1: '增加', 2: '減少'},
  };
  static Map<int, String> numericChoices(String tool, String key) =>
      numericLabels['$tool.$key'] ?? const <int, String>{};

  static String fieldTitle(String key) => parameterNames[key] ?? key;
  static String fieldHelp(String key) => parameterHints[key] ??
      '依實際 MCP Schema 描述設定參數。';

  static String rangeText(String tool, String key, Map<String, dynamic> schema,
      {int? moveId}) {
    final min = schema['minimum'];
    final max = schema['maximum'];
    if (min is num || max is num) {
      return '可設定：${min ?? '未指定'} ～ ${max ?? '未指定'}';
    }
    if (tool == 'robot_move' && key == 'targetDistance') {
      if (moveId == 1 || moveId == 2) return '安全限制：0～5 公尺';
      if (moveId == 3 || moveId == 4) return '安全限制：0～360 度';
    }
    return '原廠 Schema 未提供上下限';
  }

  static const _quickDefault = <String, Map<String, dynamic>>{
    'forward': {'moveId': 1, 'targetDistance': 0.2},
    'backward': {'moveId': 2, 'targetDistance': 0.2},
    'left': {'moveId': 3, 'targetDistance': 15},
    'right': {'moveId': 4, 'targetDistance': 15},
    'stop': {'moveId': 5, 'targetDistance': 0},
    'photo': {},
    'record_clip': {'recordSeconds': 10},
    'dock': {'startUp': true},
    'stop_patrol': {},
  };

  static const _quickTool = <String, String>{
    'forward': 'robot_move',
    'backward': 'robot_move',
    'left': 'robot_move',
    'right': 'robot_move',
    'stop': 'robot_move',
    'photo': 'robot_take_photo',
    'record_clip': 'robot_record_video',
    'dock': 'robot_go_home',
    'stop_patrol': 'robot_stop_patrol',
  };

  /// Exact-name allowlist + real Schema validation, never substring guesses.
  /// Existing user mappings are preserved so settings remain editable.
  static int applyKnownDefaults(ActionMap map, List<McpTool> tools) {
    var added = 0;
    for (final item in _quickDefault.entries) {
      if (map[item.key] != null) continue;
      final toolName = _quickTool[item.key]!;
      final tool = tools.where((t) => t.name == toolName).firstOrNull;
      if (tool == null) continue;
      final args = Map<String, dynamic>.from(item.value);
      try {
        ActionMap.validateArguments(tool, args);
        map.bindings[item.key] = ActionBinding(toolName, args);
        added++;
      } on FormatException {
        // Firmware schema changed: leave unmapped rather than guessing.
      }
    }
    return added;
  }
}
