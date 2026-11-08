import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'services/action_map.dart';
import 'services/ai_notebook.dart';
import 'services/widget_quick_commands.dart';
import 'services/ebo_tool_catalog.dart';
import 'screens/ebo_tool_panel.dart';
import 'screens/ai_conversation_screen.dart';
import 'services/config_store.dart';
import 'services/diagnostics.dart';
import 'services/mcp_service.dart';
import 'services/video_tab_policy.dart';
import 'services/hold_move_controller.dart';
import 'services/move_step_policy.dart';
import 'services/joystick_policy.dart';
import 'widgets/robot_joystick.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const EboControllerApp());
}

class EboControllerApp extends StatelessWidget {
  const EboControllerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EBO Robot MCP',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF00BCD4),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0D141A),
    ),
    home: const ControllerScreen(),
  );
}

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> with WidgetsBindingObserver {
  static const MethodChannel _widgetChannel = MethodChannel('ebo_robot_mcp/widget');
  final _store = ConfigStore();
  final _mcp = McpClient();
  final _logs = Diagnostics();
  final _actionMap = ActionMap();
  final _mcpInput = TextEditingController();
  final _keyInput = TextEditingController();
  final _rtspInput = TextEditingController();
  late final Player _player;
  late final VideoController _video;
  late final HoldMoveController _heldMove;
  StreamSubscription<String>? _rtspErrorSubscription;

  int _page = 0;
  int _widgetVoiceRequest = 0;
  final Completer<void> _initialSettingsReady = Completer<void>();
  String? _widgetStatus;
  bool _widgetQuickBusy = false;
  String? _widgetVoiceMode;
  String _version = '0.2.5+10';
  bool _connecting = false;
  bool _videoRequested = false;
  bool _streamConnecting = false;
  bool _expandedControl = false;
  bool _holdingDirection = false;
  String? _heldDirection;
  int _joystickEpoch = 0;
  bool _joystickContact = false;
  bool _commandBusy = false;
  PrivateSettings _settings = PrivateSettings();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player = Player(configuration: const PlayerConfiguration(bufferSize: 1024 * 1024));
    _video = VideoController(_player);
    _heldMove = HoldMoveController(
      sendStep: _sendHeldMoveStep,
      sendStop: _sendHeldStop,
      onState: (active, action) {
        if (mounted) setState(() {
          _holdingDirection = active;
          _heldDirection = action;
        });
      },
      onError: (e) {
        _logs.log('MOVE_HOLD', '按住移動中斷：${e.runtimeType}', level: 'ERROR');
        _notify('連續控制已停止；請查看 Log 與機器人狀態');
      },
    );
    _rtspErrorSubscription = _player.stream.error.listen((error) {
      _logs.log('RTSP', '播放器回報錯誤：' + Redactor.clean(error), level: 'ERROR');
      if (mounted) setState(() => _videoRequested = false);
    });
    FlutterError.onError = (details) {
      _logs.log('FLUTTER', 'Unhandled framework error: ' +
          details.exceptionAsString(), level: 'ERROR');
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      _logs.log('DART', 'Unhandled runtime error: ' + error.toString(),
          level: 'ERROR');
      return false;
    };
    _widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'widgetAction') {
        await _dispatchWidgetTarget(call.arguments?.toString());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_readInitialWidgetTarget());
    });
    unawaited(_initialize());
  }

  Future<void> _readInitialWidgetTarget() async {
    try {
      final mode = await _widgetChannel.invokeMethod<String>(
          'getInitialWidgetTarget');
      await _dispatchWidgetTarget(mode);
    } on MissingPluginException {
      // Non-Android platform or Flutter unit tests: no widget channel.
    } catch (e) {
      _logs.log('WIDGET', '無法取得桌面小工具入口：' +
          e.runtimeType.toString(), level: 'WARN');
    }
  }

  /// A cold launch often receives the widget Intent before secure settings
  /// (including Gemini key) are loaded. Dispatch only after load finishes.
  Future<void> _dispatchWidgetTarget(String? mode) async {
    if (!mounted || mode == null) return;
    if (!_initialSettingsReady.isCompleted) {
      _logs.log('WIDGET', '等待加密設定初始化後再啟動桌面小工具');
      await _initialSettingsReady.future;
    }
    if (!mounted) return;
    _handleWidgetTarget(mode);
  }

  void _handleWidgetTarget(String? mode) {
    if (!mounted || mode == null) return;
    if (mode == 'voice_qa' || mode == 'voice_mcp') {
      _selectPage(2);
      setState(() {
        _widgetVoiceMode = mode;
        _widgetVoiceRequest++;
        _widgetStatus = mode == 'voice_qa'
            ? '🎙️ 已開啟「EBO 語音查詢」。即將啟動麥克風；看到錄音按鈕後開始說話，再點一次送出。'
            : '🎤 已開啟「EBO 語音控制」。錄音完成後會檢查 MCP 工具，所有機器人動作仍須確認。';
      });
      _logs.log('WIDGET', '已進入 ' +
          (mode == 'voice_qa' ? '語音查詢' : 'MCP 語音指令') +
          '模式；等待前景麥克風確認');
      _notify('已開啟語音功能，請注意 AI 分頁頂端的錄音狀態');
      return;
    }
    if (!EboWidgetQuickCommand.supports(mode)) return;
    _selectPage(1);
    setState(() {
      _widgetStatus = '已收到「' + EboWidgetQuickCommand.labelFor(mode) +
          '」桌面快捷指令。正在檢查 MCP，尚未執行實體動作。';
    });
    _logs.log('WIDGET', '收到桌面快捷 ' + mode + '；等待使用者核准');
    unawaited(_runWidgetQuick(mode));
  }

  Future<void> _widgetInformation(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(Redactor.clean(message))),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('了解')),
        ],
      ),
    );
  }

  void _setWidgetStatus(String status) {
    if (mounted) setState(() => _widgetStatus = status);
  }

  /// Every physical command is approved in the foreground, schema validated,
  /// and logged without exporting its private notebook contents.
  Future<void> _runWidgetQuick(String mode) async {
    if (_widgetQuickBusy) {
      _setWidgetStatus('已有一個桌面快捷指令執行中，未重複發送。');
      return;
    }
    _widgetQuickBusy = true;
    try {
      await _initialSettingsReady.future;
      if (!mounted) return;
      final notebook = AiNotebook();
      await notebook.load();
      final command = EboWidgetQuickCommand.resolve(mode, notebook.notes);
      if (!_mcp.connected) {
        if (_connecting) {
          for (var i = 0; i < 40 && _connecting; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        }
        if (!_mcp.connected && !_connecting) await _connectMcp();
      }
      if (!_mcp.connected) {
        throw const McpException('MCP 未連線；請確認服務、AccessKey 與網路狀態');
      }
      final tool = _mcp.tools.where((t) => t.name == command.tool).firstOrNull;
      if (tool == null) {
        throw FormatException('原廠未提供 ${command.tool}，無法執行「${command.label}」');
      }
      ActionMap.validateArguments(tool, command.arguments);
      if (!mounted) return;
      _setWidgetStatus('「${command.label}」已就緒；等待您確認實體 MCP 動作。');
      final approved = await _approveTool(command.tool, command.arguments);
      if (!approved) {
        _logs.log('WIDGET', '使用者取消快捷：' + mode);
        _setWidgetStatus('已取消「${command.label}」，沒有送出 MCP 指令。');
        return;
      }
      _setWidgetStatus('正在送出「${command.label}」至 EBO MCP…');
      final stopwatch = Stopwatch()..start();
      await _mcp.call(command.tool, command.arguments);
      stopwatch.stop();
      _logs.log('WIDGET', 'MCP 接受快捷：' + command.tool +
          ' 耗時=' + stopwatch.elapsedMilliseconds.toString() + 'ms');
      _setWidgetStatus('✅ 已送出「${command.label}」；MCP 已回應，但未確認機器人已完成實際動作。');
      _notify('「${command.label}」已送出，請確認 EBO 實體狀態');
    } catch (e) {
      final detail = e is FormatException ? e.message : e is McpException
          ? e.message : e.runtimeType.toString();
      _logs.log('WIDGET', '快捷未執行：' +
          Redactor.clean(detail), level: 'ERROR');
      _setWidgetStatus('⚠️「${EboWidgetQuickCommand.labelFor(mode)}」未執行。請閱讀錯誤視窗。');
      await _widgetInformation('桌面快捷指令無法執行',
          '功能：${EboWidgetQuickCommand.labelFor(mode)}\n原因：$detail\n\n'
          '本次未確認新的 MCP 動作。可檢查連線與 Log。');
    } finally {
      _widgetQuickBusy = false;
    }
  }

  Widget _widgetStatusBanner() => MaterialBanner(
    leading: const Icon(Icons.info_outline, color: Colors.cyanAccent),
    content: Text(_widgetStatus ?? '', style: const TextStyle(fontSize: 12)),
    actions: [
      TextButton(
        onPressed: () => setState(() => _widgetStatus = null),
        child: const Text('關閉提示'),
      ),
    ],
  );

  Future<void> _initialize() async {
    await _logs.initialize();
    try {
      final loaded = await _store.load();
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      _settings = loaded;
      _settings.leftTurnDegrees = MoveStepPolicy.normalizeLeftAngle(loaded.leftTurnDegrees);
      _version = info.version + '+' + info.buildNumber;
      _mcpInput.text = loaded.mcpJson;
      _keyInput.text = loaded.geminiKey;
      _rtspInput.text = loaded.rtspUrl;
      try {
        _actionMap.load(loaded.actionMap);
      } catch (e) {
        _logs.log('SETTINGS', '動作映射無法載入', level: 'WARN');
      }
      setState(() {});
      _logs.log('APP', '已啟動版本 v' + _version);
      if (loaded.rtspUrl.isNotEmpty) unawaited(_startStream());
      if (loaded.mcpJson.isNotEmpty) unawaited(_connectMcp());
    } catch (e) {
      _logs.log('SETTINGS', '讀取加密設定失敗：' + e.toString(), level: 'ERROR');
      _notify('無法讀取設定，請檢查裝置加密儲存空間');
    } finally {
      if (!_initialSettingsReady.isCompleted) _initialSettingsReady.complete();
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(Redactor.clean(message))),
    );
  }

  Future<void> _connectMcp() async {
    if (_connecting) return;
    // End a held move before replacing the single MCP session.
    if (_heldMove.active) await _heldMove.end();
    if (!mounted) return;
    setState(() => _connecting = true);
    _logs.log('MCP', '開始初始化 MCP Session');
    try {
      final config = McpConfig.parse(_settings.mcpJson);
      final tools = await _mcp.connect(config);
      _logs.log('MCP', '連線成功，取得 ' + tools.length.toString() + ' 個工具');
      // Only match exact EBO names and Schema; never infer motion arguments.
      final added = EboToolCatalog.applyKnownDefaults(_actionMap, tools);
      if (added > 0) {
        _settings.actionMap = _actionMap.exportJson();
        await _store.save(_settings);
        _logs.log('MAPPING', '已新增 ' + added.toString() + ' 個已驗證預設動作');
      }
      if (tools.isEmpty) _notify('MCP 已連線但沒有工具');
    } catch (e) {
      _logs.log('MCP', '連線失敗：' + e.toString(), level: 'ERROR');
      _notify('MCP 連線失敗，請匯出診斷紀錄');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  /// Only reopen once per entry to a video tab or return from background.
  /// Never poll/reopen continuously while the user stays in a foreground tab.
  Future<void> _startStream({String reason = 'manual'}) async {
    if (_streamConnecting) {
      _logs.log('RTSP', '略過重複的串流開啟要求');
      return;
    }
    final raw = _settings.rtspUrl.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme.toLowerCase() != 'rtsp' || uri.host.isEmpty) {
      _notify('RTSP 網址格式不正確');
      return;
    }
    if (mounted) setState(() => _streamConnecting = true);
    _logs.log('RTSP', '重開串流（原因：' + reason + '；網址不記錄）');
    try {
      await _player.open(Media(raw), play: true);
      if (mounted) setState(() => _videoRequested = true);
      _logs.log('RTSP', '播放器已接收開啟請求（實際畫面以播放器錯誤事件為準）');
    } catch (e) {
      if (mounted) setState(() => _videoRequested = false);
      _logs.log('RTSP', '重連失敗：' + e.runtimeType.toString(), level: 'ERROR');
    } finally {
      if (mounted) setState(() => _streamConnecting = false);
    }
  }

  void _selectPage(int target) {
    final previous = _page;
    if (previous == target) return;
    // A home-screen launch request is single-use: manual re-entry must never
    // trigger another microphone capture without a fresh widget tap.
    if (previous == 2 && target != 2) {
      _widgetVoiceRequest = 0;
      _widgetVoiceMode = null;
    }
    if (previous == 1) {
      ++_joystickEpoch;
      _joystickContact = false;
      unawaited(_heldMove.end());
    }
    setState(() {
      _page = target;
      if (target != 1) _expandedControl = false;
    });
    if (VideoTabPolicy.enteredVideoTab(previous, target) &&
        _settings.rtspUrl.isNotEmpty) {
      unawaited(_startStream(reason: 'tab-entry'));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      ++_joystickEpoch;
      _joystickContact = false;
      unawaited(_heldMove.end());
    }
    if (state == AppLifecycleState.resumed &&
        VideoTabPolicy.shouldResumeStream(_page) &&
        _settings.rtspUrl.isNotEmpty) {
      unawaited(_startStream(reason: 'foreground-resume'));
    }
  }

  Future<void> _saveSettings() async {
    // Credentials/session changes must not strand a repeating movement.
    if (_heldMove.active) await _heldMove.end();
    if (!mounted) return;
    final newSettings = PrivateSettings(
      mcpJson: _mcpInput.text.trim(),
      geminiKey: _keyInput.text.trim(),
      rtspUrl: _rtspInput.text.trim(),
      actionMap: _actionMap.exportJson(),
      leftTurnDegrees: _settings.leftTurnDegrees,
    );
    try {
      if (newSettings.mcpJson.isNotEmpty) McpConfig.parse(newSettings.mcpJson);
      if (newSettings.rtspUrl.isNotEmpty) {
        final url = Uri.tryParse(newSettings.rtspUrl);
        if (url == null || url.scheme != 'rtsp' || url.host.isEmpty) {
          throw const FormatException('RTSP URL 無效');
        }
      }
      await _store.save(newSettings);
      _settings = newSettings;
      await _mcp.disconnect();
      setState(() {});
      _logs.log('SETTINGS', '設定已保存至 Android 加密儲存');
      _notify('設定已安全儲存');
      if (newSettings.mcpJson.isNotEmpty) unawaited(_connectMcp());
      if (newSettings.rtspUrl.isNotEmpty) unawaited(_startStream());
    } catch (e) {
      _notify('設定格式有誤：' + e.toString());
    }
  }

  Future<bool> _approveTool(String name, Map<String, dynamic> args) async {
    if (!mounted) return false;
    final answer = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('確認 AI 實體動作'),
        content: SingleChildScrollView(
          child: Text('工具：' + name + '\n參數：' +
              Redactor.clean(jsonEncode(args)) +
              '\n\n機器人將執行這個動作。是否允許？'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('拒絕'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('允許執行'),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<void> _robotAction(String action) async {
    if (_holdingDirection) {
      if (action == 'stop') {
        await _heldMove.end();
      } else {
        _notify('請先放開目前按住的方向鍵');
      }
      return;
    }
    if (_commandBusy && action != 'stop') {
      await _widgetInformation('動作未執行', '上一個 MCP 動作仍在處理中，請稍後再操作。');
      return;
    }
    final binding = _actionMap[action];
    if (binding == null || binding.tool.isEmpty) {
      await _widgetInformation('MCP 動作尚未綁定',
          '「' + (robotActions[action] ?? action) + '」未設定工具，沒有送出指令。');
      return;
    }
    if (!_mcp.connected) {
      await _widgetInformation('MCP 尚未連線',
          '目前無法送出「' + (robotActions[action] ?? action) + '」。請先連線並確認 AccessKey 有效。');
      return;
    }
    if (action != 'stop') setState(() => _commandBusy = true);
    try {
      final definition = _mcp.tools.where((t) => t.name == binding.tool).firstOrNull;
      if (definition == null) throw const FormatException('工具不在目前 tools/list 中');
      // Visible, user-controlled left-turn calibration is shared by TAP/HOLD.
      final args = Map<String, dynamic>.from(binding.args);
      if (action == 'left' && binding.tool == 'robot_move' &&
          args['moveId'] == 3) {
        args['targetDistance'] = _settings.leftTurnDegrees;
      }
      ActionMap.validateArguments(definition, args);
      final elapsed = Stopwatch()..start();
      await _mcp.call(binding.tool, args);
      elapsed.stop();
      _logs.log('ACTION', 'MCP 已回應：' + (robotActions[action] ?? action) +
          ' → ' + binding.tool +
          (action == 'left' ? ' 左轉角度=' + _settings.leftTurnDegrees.toString() : '') +
          ' 耗時=' + elapsed.elapsedMilliseconds.toString() + 'ms');
      if (mounted) _notify((robotActions[action] ?? action) + '：MCP 已回應，請確認實際動作');
    } catch (e) {
      _logs.log('ACTION', (robotActions[action] ?? action) +
          '失敗：' + e.toString(), level: 'ERROR');
      await _widgetInformation('MCP 控制指令失敗',
          '動作：「' + (robotActions[action] ?? action) +
          '」\n原因：' + Redactor.clean(e.toString()) +
          '\n\n本次沒有確認新的機器人動作，請檢查診斷 Log。');
    } finally {
      if (mounted && action != 'stop') setState(() => _commandBusy = false);
    }
  }

  // Safety-critical: only the exact robot_move tool and documented moveId.
  static const _moveIds = <String, int>{
    'forward': 1, 'backward': 2, 'left': 3, 'right': 4,
  };

  bool _canHoldDirection(String action) {
    if (_commandBusy || _holdingDirection || !_mcp.connected) return false;
    final stop = _actionMap['stop'];
    final tool = _mcp.tools.where((t) => t.name == 'robot_move').firstOrNull;
    if (stop?.tool != 'robot_move' ||
        stop?.args['moveId'] != 5 || tool == null) return false;
    final steps = JoystickPolicy.isDiagonal(action)
        ? JoystickPolicy.diagonalSteps(action)
        : <JoystickMove>[
            JoystickMove(_moveIds[action] ?? -1, MoveStepPolicy.distance(
                action, leftAngle: _settings.leftTurnDegrees))
          ];
    try {
      for (final step in steps) {
        final mapping = switch (step.moveId) {
          1 => 'forward', 2 => 'backward',
          3 => 'left', 4 => 'right', _ => '',
        };
        final binding = _actionMap[mapping];
        if (binding?.tool != 'robot_move' ||
            binding?.args['moveId'] != step.moveId) return false;
        final args = Map<String, dynamic>.from(binding!.args)
          ..['targetDistance'] = step.targetDistance;
        if (JoystickPolicy.isDiagonal(action)) {
          args['angleSpeed'] = 1;
          args['playTime'] = 1;
        }
        ActionMap.validateArguments(tool, args);
      }
      ActionMap.validateArguments(tool, stop!.args);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _beginHoldDirection(String action) {
    if (!_canHoldDirection(action)) {
      _notify('長按連發須使用已確認的 robot_move 方向與停止映射');
      return;
    }
    _logs.log('MOVE_HOLD', '開始長按連續控制：$action（最長 12 秒）');
    _heldMove.start(action,
        maxSteps: JoystickPolicy.isDiagonal(action) ? 6 : 12);
  }

  Future<void> _sendHeldMoveStep(String action) async {
    if (JoystickPolicy.isDiagonal(action)) {
      await _sendDiagonalPair(action, held: true);
      return;
    }
    final binding = _actionMap[action];
    final tool = _mcp.tools.where((t) => t.name == 'robot_move').firstOrNull;
    if (binding == null || tool == null || !_mcp.connected ||
        binding.tool != 'robot_move' ||
        binding.args['moveId'] != _moveIds[action]) {
      throw const FormatException('已失去已驗證的移動映射或 MCP 連線');
    }
    // Keep HOLD bounds; old arbitrary distances are never repeated.
    final args = Map<String, dynamic>.from(binding.args)
      ..['targetDistance'] =
          MoveStepPolicy.distance(action, leftAngle: _settings.leftTurnDegrees);
    ActionMap.validateArguments(tool, args);
    final elapsed = Stopwatch()..start();
    await _mcp.call('robot_move', args);
    elapsed.stop();
    _logs.log('MOVE_HOLD', '完成長按單步：$action moveId=' +
        args['moveId'].toString() + ' angleOrDistance=' +
        args['targetDistance'].toString() +
        ' elapsedMs=' + elapsed.elapsedMilliseconds.toString());
  }

  /// A diagonal is NOT native simultaneous velocity control. Each step pair
  /// is turn (7°) then translation (0.1 m), serialized through MCP.
  Future<void> _sendDiagonalPair(String action, {required bool held}) async {
    if (!_mcp.connected) throw const McpException('MCP 尚未連線');
    final tool = _mcp.tools.where((t) => t.name == 'robot_move').firstOrNull;
    if (tool == null) throw const FormatException('缺少 robot_move');
    final steps = JoystickPolicy.diagonalSteps(action);
    final queued = <Map<String, dynamic>>[];
    for (final step in steps) {
      final mapping = switch (step.moveId) {
        1 => 'forward', 2 => 'backward',
        3 => 'left', 4 => 'right', _ => '',
      };
      final bound = _actionMap[mapping];
      if (bound?.tool != 'robot_move' ||
          bound?.args['moveId'] != step.moveId) {
        throw const FormatException('斜向控制的動作映射不符合原廠工具');
      }
      final args = Map<String, dynamic>.from(bound!.args)
        ..['moveId'] = step.moveId
        ..['targetDistance'] = step.targetDistance
        ..['angleSpeed'] = 1
        ..['playTime'] = 1;
      ActionMap.validateArguments(tool, args);
      queued.add(args);
    }
    for (var i = 0; i < queued.length; i++) {
      if (held && !_heldMove.active) {
        _logs.log('JOYSTICK', '觸控放開後，取消未送出的斜向後續步驟');
        return;
      }
      final args = queued[i];
      final clock = Stopwatch()..start();
      await _mcp.call('robot_move', args);
      clock.stop();
      _logs.log('JOYSTICK', '斜向=' + action +
          ' stage=' + (i + 1).toString() + '/' + queued.length.toString() +
          ' moveId=' + args['moveId'].toString() +
          ' targetDistance=' + args['targetDistance'].toString() +
          ' angleSpeed=1 playTime=1 elapsedMs=' +
          clock.elapsedMilliseconds.toString() +
          '（MCP 已回應，未確認實際旋轉或位移）');
    }
  }

  Future<void> _joystickTap(String action) async {
    if (action == 'stop') {
      ++_joystickEpoch;
      _joystickContact = false;
      if (_heldMove.active) await _heldMove.end();
      await _robotAction('stop');
      return;
    }
    if (!JoystickPolicy.isDiagonal(action)) {
      await _robotAction(action);
      return;
    }
    if (!_canHoldDirection(action)) {
      _notify('斜向控制須先有正確的四方向與停止工具映射');
      return;
    }
    if (!mounted) return;
    setState(() => _commandBusy = true);
    try {
      await _sendDiagonalPair(action, held: false);
    } catch (e) {
      _logs.log('JOYSTICK', '斜向單次指令異常：' +
          e.runtimeType.toString(), level: 'ERROR');
      _notify('斜向動作未完成，請查看 Log');
    } finally {
      if (mounted) setState(() => _commandBusy = false);
    }
  }

  void _joystickHoldStart(String action) {
    _joystickContact = true;
    _beginHoldDirection(action);
  }

  void _joystickHoldChange(String? action) {
    final epoch = ++_joystickEpoch;
    _joystickContact = action != null;
    unawaited(() async {
      if (_heldMove.active) await _heldMove.end();
      if (!mounted || !_joystickContact || epoch != _joystickEpoch ||
          action == null || !_canHoldDirection(action)) return;
      _beginHoldDirection(action);
    }());
  }

  void _joystickHoldEnd() {
    _joystickContact = false;
    ++_joystickEpoch;
    unawaited(_heldMove.end());
  }

  Widget _joystick({double size = 228}) => RobotJoystick(
    size: size,
    enabled: _mcp.connected && !_commandBusy,
    onTapAction: _joystickTap,
    onHoldStart: _joystickHoldStart,
    onHoldChange: _joystickHoldChange,
    onHoldEnd: _joystickHoldEnd,
  );

  Future<void> _sendHeldStop() async {
    final stop = _actionMap['stop'];
    final tool = _mcp.tools.where((t) => t.name == 'robot_move').firstOrNull;
    if (stop?.tool != 'robot_move' || tool == null ||
        stop?.args['moveId'] != 5 || !_mcp.connected) {
      throw const FormatException('無有效的 robot_move 停止映射');
    }
    ActionMap.validateArguments(tool, stop!.args);
    _logs.log('MOVE_HOLD', '長按結束：已停止續發，排入停止指令');
    await _mcp.call('robot_move', stop.args);
    _logs.log('MOVE_HOLD', '機器人回應停止指令');
  }

  Future<void> _localSnapshot() async {
    try {
      final bytes = await _player.screenshot(format: 'image/png');
      if (bytes == null) throw const FormatException('沒有可截取的影片影格');
      final folder = await getApplicationDocumentsDirectory();
      final file = File(folder.path + '/EBO_' +
          DateTime.now().millisecondsSinceEpoch.toString() + '.png');
      await file.writeAsBytes(bytes);
      _logs.log('PHOTO', '已保存手機本地截圖，可透過分享功能匯出');
      if (mounted) {
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
      }
    } catch (e) {
      _logs.log('PHOTO', '本地截圖失敗：' + e.runtimeType.toString(), level: 'ERROR');
      _notify('截圖失敗，請確認 RTSP 已顯示畫面');
    }
  }

  Future<void> _editBinding(String action) async {
    if (_mcp.tools.isEmpty) {
      _notify('請先完成 MCP tools/list 連線');
      return;
    }
    final existing = _actionMap[action];
    String? selected = existing == null ? null : existing.tool;
    if (!_mcp.tools.any((t) => t.name == selected)) selected = null;
    final editor = TextEditingController(
      text: jsonEncode(existing?.args ?? <String, dynamic>{}),
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text('綁定：' + (robotActions[action] ?? action)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: selected,
                  hint: const Text('選擇 MCP Tool'),
                  items: _mcp.tools.map((t) => DropdownMenuItem(
                    value: t.name,
                    child: Text(t.name, overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (v) => update(() => selected = v),
                ),
                const SizedBox(height: 16),
                if (selected != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _mcp.tools.firstWhere((t) => t.name == selected).description,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('工具輸入 Schema：'),
                  ),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 150),
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    color: Colors.black26,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert(
                          _mcp.tools.firstWhere((t) => t.name == selected).schema,
                        ),
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: editor,
                  minLines: 2,
                  maxLines: 7,
                  decoration: const InputDecoration(
                    labelText: 'JSON Arguments（依工具 Schema 設定）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('此設定必須由您確認工具用途與參數，系統不會猜測方向。'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  _actionMap.set(action, selected ?? '', editor.text, _mcp.tools);
                  _settings.actionMap = _actionMap.exportJson();
                  await _store.save(_settings);
                  _logs.log('MAPPING', '已更新動作映射：' + action);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  if (mounted) setState(() {});
                } catch (e) {
                  _notify('映射錯誤：' + e.toString());
                }
              },
              child: const Text('儲存映射'),
            ),
          ],
        ),
      ),
    );
    editor.dispose();
  }

  Widget _videoPanel() => AspectRatio(
    aspectRatio: 16 / 9,
    child: Container(color: Colors.black, child: _videoContent()),
  );

  Widget _videoContent({bool expanded = false}) => Stack(
        fit: StackFit.expand,
        children: [
          Video(controller: _video, controls: NoVideoControls,
              fit: expanded ? BoxFit.cover : BoxFit.contain),
          Positioned(
            left: 8, top: 8,
            child: Chip(
              avatar: Icon(Icons.circle,
                color: _mcp.connected ? Colors.greenAccent : Colors.orangeAccent,
                size: 11),
              label: Text(_mcp.connected ? 'MCP 已連線' : 'MCP 未連線'),
            ),
          ),
          if (_streamConnecting)
            const Center(child: CircularProgressIndicator())
          else if (!_videoRequested)
            const Center(child: Text('影像尚未就緒，切換分頁可重連')),
        ],
  );

  Widget _monitorPage() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      _videoPanel(),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('重連影像'),
            onPressed: () => _startStream(reason: 'manual-refresh'),
          ),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.photo_camera),
            label: const Text('手機截圖'),
            onPressed: _localSnapshot,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.camera_alt),
            label: const Text('機器人拍照'),
            onPressed: () => _robotAction('photo'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.videocam),
            label: const Text('機器人錄影 10 秒'),
            onPressed: () => _robotAction('record_clip'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      const Text('EBO 的 robot_record_video 僅提供指定秒數錄影，'
          '不支援獨立的停止錄影指令。手機截圖為本地 PNG。'),
    ],
  );

  Widget _leftTurnCalibration() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: Row(children: [
      const Icon(Icons.tune, color: Colors.cyanAccent),
      const SizedBox(width: 8),
      const Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('左轉角度校正'),
          Text('單擊與長按共用；右轉保持 15°。',
              style: TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      )),
      DropdownButton<int>(
        value: MoveStepPolicy.normalizeLeftAngle(_settings.leftTurnDegrees),
        items: const [
          DropdownMenuItem(value: 15, child: Text('15°')),
          DropdownMenuItem(value: 30, child: Text('30°')),
          DropdownMenuItem(value: 45, child: Text('45°')),
        ],
        onChanged: (_holdingDirection || _commandBusy) ? null : (value) async {
          if (value == null) return;
          setState(() => _settings.leftTurnDegrees = value);
          try {
            await _store.save(_settings);
            _logs.log('MOVE_CONFIG', '左轉校正角度=' + value.toString() + '°');
          } catch (e) {
            _logs.log('MOVE_CONFIG', '角度儲存失敗：' + e.runtimeType.toString(),
                level: 'ERROR');
            _notify('左轉校正設定無法儲存');
          }
        },
      ),
    ]),
  );

  Widget _controlPage() => _expandedControl ? _expandedControlPage() : ListView(
    padding: const EdgeInsets.all(12),
    children: [
      _videoPanel(),
      Align(alignment: Alignment.centerRight,
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _expandedControl = true),
          icon: const Icon(Icons.fullscreen),
          label: const Text('放大監控＋懸浮控制器'),
        ),
      ),
      const SizedBox(height: 8),
      const Center(child: Text('點按單步；長按連發（最多 12 秒）。放開會停止續發並送停止指令。')),
      _leftTurnCalibration(),
      // Stable widget position: never unmount the active gesture on state updates.
      Center(child: Text(_holdingDirection ? '● 連續控制：${_heldDirection ?? "未知方向"}' : ' ',
          style: const TextStyle(color: Colors.cyanAccent))),
      const SizedBox(height: 8),
      Center(child: _joystick()),
      const SizedBox(height: 4),
      const Center(child: Text('八方向圓盤：斜向為轉向 7°＋移動 0.1m，依序執行，不是同步速度控制。',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(
          onPressed: () => _robotAction('dock'),
          icon: const Icon(Icons.battery_charging_full),
          label: const Text('回充'),
        ),
        OutlinedButton.icon(
          onPressed: () => _robotAction('stop_patrol'),
          icon: const Icon(Icons.stop_circle),
          label: const Text('停止巡邏／導航'),
        ),
      ]),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: () => _selectPage(3),
        icon: const Icon(Icons.tune),
        label: const Text('編輯快捷鍵映射'),
      ),
      const Divider(height: 28),
      ExpansionTile(
        key: const PageStorageKey<String>('mcp-tools-expand'),
        initiallyExpanded: false,
        leading: const Icon(Icons.build_circle_outlined),
        title: Text('完整 MCP 工具設定（${_mcp.tools.length} 項）'),
        subtitle: const Text('點擊展開／收合，依原廠 Schema 設定每個工具'),
        children: [EboToolPanel(mcp: _mcp, logs: _logs)],
      ),
    ],
  );

  /// Video stays on a single VideoController. Buttons are semi-transparent
  /// overlays only in expanded mode. They still execute checked MCP bindings.
  Widget _expandedControlPage() => Stack(
    fit: StackFit.expand,
    children: [
      _videoContent(expanded: true),
      Positioned(right: 10, top: 10,
        child: FilledButton.tonalIcon(
          onPressed: () => setState(() => _expandedControl = false),
          icon: const Icon(Icons.fullscreen_exit),
          label: const Text('返回一般畫面'),
        ),
      ),
      Positioned(bottom: 8, left: 8, right: 8,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0x9909131B),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white38),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: _joystick(size: 194)),
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
              IconButton.filledTonal(
                tooltip: '機器人拍照',
                onPressed: () => _robotAction('photo'),
                icon: const Icon(Icons.photo_camera),
              ),
              IconButton.filledTonal(
                tooltip: '機器人錄影 10 秒',
                onPressed: () => _robotAction('record_clip'),
                icon: const Icon(Icons.videocam),
              ),
              IconButton.filledTonal(
                tooltip: '機器人回充',
                onPressed: () => _robotAction('dock'),
                icon: const Icon(Icons.battery_charging_full),
              ),
              IconButton.filledTonal(
                tooltip: '停止巡邏／導航',
                onPressed: () => _robotAction('stop_patrol'),
                icon: const Icon(Icons.pause_circle_outline),
              ),
            ]),
          ]),
        ),
      ),
    ],
  );

  Widget _aiPage() => AiConversationScreen(
    apiKey: _settings.geminiKey,
    mcp: _mcp,
    logs: _logs,
    approve: _approveTool,
    widgetVoiceMode: _widgetVoiceMode,
    voiceRequestId: _widgetVoiceRequest,
  );

  Widget _settingsPage() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('連線與隱私設定 · v' + _version,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      TextField(
        controller: _keyInput,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          labelText: 'Gemini API Key',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _mcpInput,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          labelText: '貼上 EBO App 複製的 MCP JSON 配置',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _rtspInput,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'RTSP URL',
          hintText: 'rtsp://機器人區網IP:554/main0',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _saveSettings,
        icon: const Icon(Icons.lock),
        label: const Text('加密儲存並重新連線'),
      ),
      const Divider(height: 36),
      Row(children: [
        Expanded(child: Text(
          'MCP 工具清單：' + _mcp.tools.length.toString() + ' 個',
          style: const TextStyle(fontWeight: FontWeight.bold),
        )),
        IconButton(
          onPressed: _connecting ? null : _connectMcp,
          icon: const Icon(Icons.sync),
        ),
      ]),
      if (_mcp.tools.isEmpty)
        const Text('尚未取得 MCP 工具。請先設定有效憑證並連線。'),
      const Text('常用快捷鍵：已根據實際 MCP Schema 自動預設',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ...robotActions.entries.map((entry) {
        final b = _actionMap[entry.key];
        return ListTile(
          dense: true,
          title: Text(entry.value),
          subtitle: Text(b == null ? '尚未綁定' : b.tool),
          trailing: const Icon(Icons.edit),
          onTap: () => _editBinding(entry.key),
        );
      }),
      const SizedBox(height: 10),
      const Text('15 個完整 MCP 功能位於「控制」分頁下方。'
          '下列僅供修改方向、拍照、錄影、回充等常用快捷鍵。'),
      const SizedBox(height: 12),
      const Text('MCP 憑證具有有效期限；過期請在 EBO App 更新並重新貼上。'
          '敏感資訊僅保存在本機加密儲存，不進入 GitHub 或匯出 Log。'),
    ],
  );

  Widget _diagnosticsPage() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(child: Text('診斷 Log · v' + _version,
              style: const TextStyle(fontWeight: FontWeight.bold))),
          IconButton(
            tooltip: '清除 Log',
            onPressed: _logs.clear,
            icon: const Icon(Icons.delete_outline),
          ),
          FilledButton.tonalIcon(
            onPressed: () async {
              try {
                await _logs.shareExport(
                  mcpOnline: _mcp.connected,
                  toolCount: _mcp.tools.length,
                  toolMetadata: _mcp.tools.map((t) => {
                    'name': t.name,
                    'description': t.description,
                    'inputSchema': t.schema,
                  }).toList(),
                );
              } catch (e) {
                _notify('匯出失敗：' + e.runtimeType.toString());
              }
            },
            icon: const Icon(Icons.ios_share),
            label: const Text('匯出 Log'),
          ),
        ]),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text('匯出為 JSONL，包含版本、時間、MCP 連線狀態、工具 Schema、操作與錯誤摘要；'
            '不包含 API Key、MCP AccessKey、語音內容或影像。'),
      ),
      Expanded(child: AnimatedBuilder(
        animation: _logs,
        builder: (context, _) => ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: _logs.events.length,
          itemBuilder: (context, index) {
            final event = _logs.events[_logs.events.length - 1 - index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SelectableText(
                event.timestamp.toIso8601String() + ' [' + event.level +
                '] ' + event.component + ': ' + event.message,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: event.level == 'ERROR' ? Colors.orangeAccent : Colors.white70,
                ),
              ),
            );
          },
        ),
      )),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('EBO-162 · v' + _version,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      actions: [
        IconButton(
          tooltip: 'MCP 重新連線',
          onPressed: _connecting ? null : _connectMcp,
          icon: _connecting ? const SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ) : const Icon(Icons.sync),
        ),
        IconButton(
          tooltip: '診斷 Log',
          onPressed: () => _selectPage(4),
          icon: const Icon(Icons.bug_report_outlined),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(children: [
        if (_widgetStatus != null) _widgetStatusBanner(),
        Expanded(child: switch (_page) {
          0 => _monitorPage(),
          1 => _controlPage(),
          2 => _aiPage(),
          3 => _settingsPage(),
          _ => _diagnosticsPage(),
        }),
      ]),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _page,
      onDestinationSelected: _selectPage,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.videocam), label: '監控'),
        NavigationDestination(icon: Icon(Icons.gamepad), label: '控制'),
        NavigationDestination(icon: Icon(Icons.smart_toy), label: 'AI'),
        NavigationDestination(icon: Icon(Icons.settings), label: '設定'),
        NavigationDestination(icon: Icon(Icons.bug_report), label: 'Log'),
      ],
    ),
  );

  @override
  void dispose() {
    ++_joystickEpoch;
    _joystickContact = false;
    WidgetsBinding.instance.removeObserver(this);
    _widgetChannel.setMethodCallHandler(null);
    if (_heldMove.active) unawaited(_heldMove.end());
    _heldMove.dispose();
    unawaited(_rtspErrorSubscription?.cancel() ?? Future<void>.value());
    _mcpInput.dispose();
    _keyInput.dispose();
    _rtspInput.dispose();
    _logs.dispose();
    unawaited(_mcp.disconnect().whenComplete(_mcp.dispose));
    unawaited(_player.dispose());
    super.dispose();
  }
}
