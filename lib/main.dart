import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';

import 'services/action_map.dart';
import 'services/config_store.dart';
import 'services/diagnostics.dart';
import 'services/gemini_service.dart';
import 'services/mcp_service.dart';

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

class _ControllerScreenState extends State<ControllerScreen> {
  final _store = ConfigStore();
  final _mcp = McpClient();
  final _agent = GeminiAgent();
  final _logs = Diagnostics();
  final _actionMap = ActionMap();
  final _recorder = AudioRecorder();
  final _input = TextEditingController();
  final _mcpInput = TextEditingController();
  final _keyInput = TextEditingController();
  final _rtspInput = TextEditingController();
  late final Player _player;
  late final VideoController _video;

  int _page = 0;
  String _version = '0.1.0+1';
  bool _connecting = false;
  bool _videoRequested = false;
  bool _aiBusy = false;
  bool _commandBusy = false;
  bool _voiceRecording = false;
  bool _robotRecording = false;
  String _aiAnswer = '';
  PrivateSettings _settings = PrivateSettings();

  @override
  void initState() {
    super.initState();
    _player = Player(configuration: const PlayerConfiguration(bufferSize: 1024 * 1024));
    _video = VideoController(_player);
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
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _logs.initialize();
    try {
      final loaded = await _store.load();
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      _settings = loaded;
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
    setState(() => _connecting = true);
    _logs.log('MCP', '開始初始化 MCP Session');
    try {
      final config = McpConfig.parse(_settings.mcpJson);
      final tools = await _mcp.connect(config);
      _logs.log('MCP', '連線成功，取得 ' + tools.length.toString() + ' 個工具');
      if (tools.isEmpty) _notify('MCP 已連線但沒有工具');
    } catch (e) {
      _logs.log('MCP', '連線失敗：' + e.toString(), level: 'ERROR');
      _notify('MCP 連線失敗，請匯出診斷紀錄');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _startStream() async {
    final raw = _settings.rtspUrl.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme.toLowerCase() != 'rtsp' || uri.host.isEmpty) {
      _notify('RTSP 網址格式不正確');
      return;
    }
    _logs.log('RTSP', '開始播放串流（網址未記錄）');
    try {
      await _player.open(Media(raw), play: true);
      if (mounted) setState(() => _videoRequested = true);
      _logs.log('RTSP', '已啟動播放器；若黑畫面請檢查 Wi-Fi 與 RTSP');
    } catch (e) {
      if (mounted) setState(() => _videoRequested = false);
      _logs.log('RTSP', '串流啟動失敗：' + e.runtimeType.toString(), level: 'ERROR');
    }
  }

  Future<void> _saveSettings() async {
    final newSettings = PrivateSettings(
      mcpJson: _mcpInput.text.trim(),
      geminiKey: _keyInput.text.trim(),
      rtspUrl: _rtspInput.text.trim(),
      actionMap: _actionMap.exportJson(),
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
    if (_commandBusy && action != 'stop') return;
    final binding = _actionMap[action];
    if (binding == null || binding.tool.isEmpty) {
      _notify('「' + (robotActions[action] ?? action) + '」尚未綁定 MCP 工具');
      return;
    }
    if (!_mcp.connected) {
      _notify('請先連線 MCP');
      return;
    }
    if (action != 'stop') setState(() => _commandBusy = true);
    try {
      final definition = _mcp.tools.where((t) => t.name == binding.tool).firstOrNull;
      if (definition == null) throw const FormatException('工具不在目前 tools/list 中');
      ActionMap.validateArguments(definition, binding.args);
      await _mcp.call(binding.tool, binding.args);
      _logs.log('ACTION', '成功：' + (robotActions[action] ?? action) +
          ' → ' + binding.tool);
      if (mounted && action == 'record_start') setState(() => _robotRecording = true);
      if (mounted && action == 'record_stop') setState(() => _robotRecording = false);
      if (mounted) _notify((robotActions[action] ?? action) + '執行成功');
    } catch (e) {
      _logs.log('ACTION', (robotActions[action] ?? action) +
          '失敗：' + e.toString(), level: 'ERROR');
      _notify('命令未成功，請檢查診斷紀錄');
    } finally {
      if (mounted && action != 'stop') setState(() => _commandBusy = false);
    }
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

  Future<void> _askGemini({List<int>? audio}) async {
    if (_aiBusy) return;
    final text = _input.text.trim();
    if (audio == null && text.isEmpty) return;
    setState(() => _aiBusy = true);
    _logs.log('AI', audio == null ? '收到文字命令（不記錄內容）' : '收到語音命令（不保存音檔）');
    try {
      final answer = audio == null
          ? await _agent.runText(
              apiKey: _settings.geminiKey,
              prompt: text,
              mcp: _mcp,
              approve: _approveTool,
              onStep: (v) => _logs.log('AI', v))
          : await _agent.runAudio(
              apiKey: _settings.geminiKey,
              bytes: Uint8List.fromList(audio),
              mcp: _mcp,
              approve: _approveTool,
              onStep: (v) => _logs.log('AI', v));
      if (!mounted) return;
      setState(() => _aiAnswer = answer);
      _logs.log('AI', '模型回覆成功（不記錄回覆內容）');
      if (audio == null) _input.clear();
    } catch (e) {
      _logs.log('AI', 'AI 執行失敗：' + e.toString(), level: 'ERROR');
      _notify('AI 執行失敗，請匯出診斷紀錄');
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _toggleVoice() async {
    if (_aiBusy) return;
    try {
      if (!_voiceRecording) {
        if (!await _recorder.hasPermission()) {
          _notify('請授予麥克風權限');
          return;
        }
        final dir = await getTemporaryDirectory();
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: dir.path + '/ebo_voice.m4a',
        );
        if (mounted) setState(() => _voiceRecording = true);
        _logs.log('VOICE', '開始錄音');
      } else {
        final path = await _recorder.stop();
        if (mounted) setState(() => _voiceRecording = false);
        if (path == null) throw const FormatException('未取得錄音檔');
        final file = File(path);
        final bytes = await file.readAsBytes();
        await file.delete();
        _logs.log('VOICE', '已停止錄音並刪除暫存檔');
        await _askGemini(audio: bytes);
      }
    } catch (e) {
      if (mounted) setState(() => _voiceRecording = false);
      _logs.log('VOICE', '語音功能錯誤：' + e.runtimeType.toString(), level: 'ERROR');
      _notify('語音錄製或傳送失敗');
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
    child: Container(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(child: Video(controller: _video, controls: NoVideoControls)),
          Positioned(
            left: 8, top: 8,
            child: Chip(
              avatar: Icon(Icons.circle,
                color: _mcp.connected ? Colors.greenAccent : Colors.orangeAccent,
                size: 11),
              label: Text(_mcp.connected ? 'MCP 已連線' : 'MCP 未連線'),
            ),
          ),
          if (!_videoRequested)
            const Center(child: Text('請至設定頁輸入 RTSP 位址並啟動')),
          if (_robotRecording)
            const Positioned(
              top: 10, right: 12,
              child: Chip(label: Text('機器人 REC', style: TextStyle(color: Colors.redAccent))),
            ),
        ],
      ),
    ),
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
            onPressed: _startStream,
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
            icon: Icon(_robotRecording ? Icons.stop : Icons.videocam),
            label: Text(_robotRecording ? '停止機器人攝影' : '開始機器人攝影'),
            onPressed: () => _robotAction(
              _robotRecording ? 'record_stop' : 'record_start'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      const Text('攝影按鈕呼叫 MCP 工具；僅在伺服器回報成功後顯示 REC。'
          '手機截圖會建立本地 PNG 並開啟分享選單。'),
    ],
  );

  Widget _directionButton(String action, IconData icon) => SizedBox(
    width: 95, height: 62,
    child: FilledButton.tonal(
      style: FilledButton.styleFrom(
        backgroundColor: action == 'stop' ? const Color(0xFF862B2B) : null,
        padding: const EdgeInsets.all(5),
      ),
      onPressed: (_commandBusy && action != 'stop')
          ? null : () => _robotAction(action),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 24),
        Text(robotActions[action] ?? action, style: const TextStyle(fontSize: 11)),
      ]),
    ),
  );

  Widget _controlPage() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      _videoPanel(),
      const SizedBox(height: 12),
      const Center(child: Text('單次控制 · 請先設定每個動作的 Tool 與 JSON 參數')),
      const SizedBox(height: 8),
      Center(child: Column(children: [
        _directionButton('forward', Icons.keyboard_arrow_up),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _directionButton('left', Icons.keyboard_arrow_left),
          _directionButton('stop', Icons.stop_circle),
          _directionButton('right', Icons.keyboard_arrow_right),
        ]),
        _directionButton('backward', Icons.keyboard_arrow_down),
      ])),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(
          onPressed: () => _robotAction('dock'),
          icon: const Icon(Icons.battery_charging_full),
          label: const Text('回充'),
        ),
        OutlinedButton.icon(
          onPressed: () => _robotAction('gimbal'),
          icon: const Icon(Icons.control_camera),
          label: const Text('雲台歸位'),
        ),
      ]),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: () => setState(() => _page = 3),
        icon: const Icon(Icons.tune),
        label: const Text('編輯工具映射'),
      ),
    ],
  );

  Widget _aiPage() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('Gemini AI 指令', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Text('AI 每次執行 MCP 工具前都會顯示確認視窗。'
          '文字與語音共用設定頁中的 Gemini API Key。'),
      const SizedBox(height: 18),
      TextField(
        controller: _input,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: '例：請機器人向前移動並拍照',
          labelText: '自然語言指令',
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _aiBusy ? null : () => _askGemini(),
        icon: const Icon(Icons.send),
        label: const Text('傳送文字指令'),
      ),
      const SizedBox(height: 12),
      FilledButton.tonalIcon(
        onPressed: _aiBusy ? null : _toggleVoice,
        icon: Icon(_voiceRecording ? Icons.stop_circle : Icons.mic),
        label: Text(_voiceRecording ? '停止錄音並送出' : '開始錄製語音指令'),
      ),
      if (_aiBusy) const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(),
      ),
      const SizedBox(height: 18),
      const Text('AI 回覆', style: TextStyle(fontWeight: FontWeight.bold)),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SelectableText(_aiAnswer.isEmpty ? '尚無執行結果' : _aiAnswer),
        ),
      ),
    ],
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
          onPressed: () => setState(() => _page = 4),
          icon: const Icon(Icons.bug_report_outlined),
        ),
      ],
    ),
    body: SafeArea(
      child: switch (_page) {
        0 => _monitorPage(),
        1 => _controlPage(),
        2 => _aiPage(),
        3 => _settingsPage(),
        _ => _diagnosticsPage(),
      },
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _page,
      onDestinationSelected: (i) => setState(() => _page = i),
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
    _input.dispose();
    _mcpInput.dispose();
    _keyInput.dispose();
    _rtspInput.dispose();
    _logs.dispose();
    unawaited(_mcp.disconnect().whenComplete(_mcp.dispose));
    _agent.dispose();
    unawaited(_player.dispose());
    unawaited(_recorder.dispose());
    super.dispose();
  }
}
