import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/action_map.dart';
import '../services/ai_notebook.dart';
import '../services/diagnostics.dart';
import '../services/gemini_service.dart';
import '../services/ebo_task_planner.dart';
import '../services/widget_quick_commands.dart';
import '../services/mcp_service.dart';
import 'ai_conversation_panel.dart';

/// Complete, encrypted, user-controlled conversation surface.
class AiConversationScreen extends StatefulWidget {
  final String apiKey;
  final McpClient mcp;
  final Diagnostics logs;
  final ApproveTool approve;
  final String? widgetVoiceMode;
  final int voiceRequestId;
  const AiConversationScreen({
    super.key,
    required this.apiKey,
    required this.mcp,
    required this.logs,
    required this.approve,
    this.widgetVoiceMode,
    this.voiceRequestId = 0,
  });

  @override
  State<AiConversationScreen> createState() => _AiConversationScreenState();
}

class _AiConversationScreenState extends State<AiConversationScreen> with WidgetsBindingObserver {
  final _notebook = AiNotebook();
  final _agent = GeminiAgent();
  final _recorder = AudioRecorder();
  final _input = TextEditingController();
  bool _busy = false;
  bool _recording = false;
  bool _recordingGroundedQuestion = false;
  int _consumedVoiceRequest = 0;
  String? _voiceStatus;

  Future<void> _showFailureDialog(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(Redactor.clean(message)),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('了解')),
        ],
      ),
    );
  }

  Widget _voiceStatusBanner() => MaterialBanner(
    leading: Icon(_recording ? Icons.mic : Icons.info_outline,
        color: _recording ? Colors.redAccent : Colors.cyanAccent),
    content: Text(_voiceStatus ?? '', style: const TextStyle(fontSize: 12)),
    actions: [
      TextButton(onPressed: () => setState(() => _voiceStatus = null),
          child: const Text('關閉提示')),
    ],
  );


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeWidgetVoice());
  }

  @override
  void didUpdateWidget(covariant AiConversationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.voiceRequestId != widget.voiceRequestId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _consumeWidgetVoice());
    }
  }

  void _consumeWidgetVoice() {
    if (!mounted || widget.voiceRequestId == 0 ||
        _consumedVoiceRequest == widget.voiceRequestId) return;
    _consumedVoiceRequest = widget.voiceRequestId;
    final mode = widget.widgetVoiceMode;
    if (mode != 'voice_qa' && mode != 'voice_mcp') return;
    if (_busy || _recording) {
      setState(() => _voiceStatus = '目前已有 AI 指令或錄音尚未完成，未重新啟動麥克風。');
      unawaited(_showFailureDialog('尚無法開始新的語音功能',
          '目前正在處理其他指令或錄音。請先完成或停止目前流程，再點擊桌面小工具。'));
      return;
    }
    if (widget.apiKey.trim().isEmpty) {
      setState(() => _voiceStatus = '尚未設定 Gemini API Key，沒有開始錄音。');
      unawaited(_showFailureDialog('Gemini API Key 尚未設定',
          '請至「設定」填入 Gemini API Key，再點擊桌面小工具。'));
      return;
    }
    setState(() => _voiceStatus = '已收到桌面語音入口，正在檢查麥克風權限並啟動錄音…');
    widget.logs.log('WIDGET', '已進入 AI 前景，啟動語音錄製模式：' + mode);
    unawaited(_toggleVoice(groundedQuestion: mode == 'voice_qa'));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || !_recording) return;
    // Privacy/safety: do not continue recording if screen is backgrounded.
    unawaited(_recorder.stop().then((_) {
      if (mounted) setState(() {
        _recording = false;
        _recordingGroundedQuestion = false;
      });
      widget.logs.log('WIDGET', 'App 進入背景：停止錄音，不送出指令');
      if (mounted) setState(() => _voiceStatus = '錄音已因離開 App 而停止，沒有送出任何指令。');
    }).catchError((Object e) {
      widget.logs.log('WIDGET', '背景停止錄音失敗：' +
          e.runtimeType.toString(), level: 'ERROR');
    }));
  }

  Future<void> _load() async {
    try {
      await _notebook.load();
      if (mounted) setState(() {});
    } catch (e) {
      widget.logs.log('AI', '載入私人對話失敗：${e.runtimeType}', level: 'ERROR');
      _notify('讀取 AI 對話失敗，請檢查加密儲存');
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(Redactor.clean(message))),
    );
  }

  Future<void> _send({Uint8List? audio}) async {
    if (_busy) return;
    final typed = _input.text.trim();
    if (audio == null && typed.isEmpty) return;
    setState(() {
      _busy = true;
      if (audio != null) _voiceStatus = '正在辨識語音並確認 MCP 指令類型…';
    });
    String? forwardToGrounded;
    try {
      // Voice MCP goes through an explicit transcription stage. This lets the
      // user see what was heard and prevents factual Q&A from silently
      // activating an unrelated robot tool.
      final prompt = audio == null ? typed : await _agent.transcribeAudio(
        apiKey: widget.apiKey,
        bytes: audio,
      );
      if (audio != null) {
        widget.logs.log('VOICE_MCP', '語音已辨識，開始判斷資訊查詢或機器人指令');
        if (mounted) setState(() => _voiceStatus = '語音辨識完成：$prompt');
      }
      if (EboWidgetQuickCommand.isInformationQuestion(prompt)) {
        final reroute = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('目前使用的是 AI／MCP 指令入口'),
            content: SingleChildScrollView(child: Text(
              '輸入／辨識內容：$prompt\n\n這是資訊查詢，不是機器人移動或拍照命令。'
              '為避免誤執行，本次沒有呼叫 MCP。\n\n'
              '是否改用 Gemini 即時查詢，並讓 EBO 語音播報？')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消，先不執行')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('改用語音查詢')),
            ],
          ),
        );
        if (reroute == true) {
          forwardToGrounded = prompt;
          if (mounted) setState(() => _voiceStatus = '已切換至即時查詢，準備取得資料與語音播報。');
        } else {
          await _notebook.addMessage('user', prompt);
          await _notebook.addMessage('assistant',
              '【未執行 MCP】這是資訊查詢。請使用「語音查詢＋EBO 語音回覆」。');
          if (mounted) setState(() => _voiceStatus = '未執行 MCP：已取消資訊查詢轉換。');
        }
        widget.logs.log('VOICE_MCP', '資訊查詢未進入機器人動作工具');
        return;
      }
      final previousContext = _notebook.contextForModel;
      await _notebook.addMessage('user', prompt);
      if (mounted) setState(() {});
      final plan = EboTaskPlan.fromPrompt(prompt, _notebook.notes);
      final response = plan != null
          ? await plan.startPatrol(
              mcp: widget.mcp,
              approve: widget.approve,
              onStep: (v) => widget.logs.log('AI_PLAN', v),
            )
          : await _agent.runText(
              apiKey: widget.apiKey,
              prompt: prompt,
              contextNotes: previousContext,
              mcp: widget.mcp,
              approve: widget.approve,
              onStep: (v) => widget.logs.log('AI', v),
            );
      await _notebook.addMessage('assistant', response);
      widget.logs.log('AI', 'AI 回答已加密保存至手機');
      final notExecuted = response.startsWith('【未執行 MCP】') ||
          (RegExp(r'未執行|本次沒有實體動作').hasMatch(response) &&
              RegExp(r'巡邏|回充|移動|拍照|跟隨|尋找|導航|錄影').hasMatch(prompt));
      if (mounted) setState(() {
        _voiceStatus = notExecuted
            ? '⚠️ AI 有回覆，但未確認任何新的 MCP 動作。'
            : 'AI 已完成處理；請查看下方對話或機器人確認視窗。';
      });
      if (notExecuted) {
        await _showFailureDialog('沒有執行機器人動作',
            'Gemini 沒有成功送出 MCP 動作。\n\n$response\n\n'
            '請確認 MCP 已連線及語音模式是否正確。');
      }
    } catch (e) {
      final summary = e is GeminiApiException
          ? 'Gemini HTTP ${e.statusCode} / ${e.apiStatus}'
          : e is McpException ? Redactor.clean(e.message)
          : e is FormatException ? e.message : e.runtimeType.toString();
      widget.logs.log('AI', '指令失敗：$summary', level: 'ERROR');
      try {
        await _notebook.addMessage('assistant',
            '【未執行 MCP】指令失敗：$summary');
      } catch (_) { /* Log will still include sanitized failure. */ }
      if (mounted) setState(() => _voiceStatus = '⚠️ 沒有執行 MCP：$summary');
      await _showFailureDialog('AI／MCP 指令無法執行',
          '本次沒有確認任何新的機器人動作。\n原因：$summary\n\n'
          '請檢查 Gemini API Key、連線與 Log。');
    } finally {
      if (mounted) setState(() => _busy = false);
      if (forwardToGrounded != null && mounted) {
        final question = forwardToGrounded;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_groundedSpeak(promptOverride: question));
        });
      }
    }
  }

  Future<void> _toggleVoice({bool groundedQuestion = false}) async {
    if (_busy) return;
    if (_recording && _recordingGroundedQuestion != groundedQuestion) {
      _notify('請先按目前的錄音按鈕結束錄音');
      return;
    }
    try {
      if (!_recording) {
        if (!await _recorder.hasPermission()) {
          setState(() => _voiceStatus = '無法啟動錄音：尚未授予麥克風權限。');
          await _showFailureDialog('麥克風權限不足',
              '請在 Android 設定中允許 EBO 使用麥克風，再重新點擊桌面小工具。');
          return;
        }
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/ebo_voice_command.m4a';
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );
        if (mounted) setState(() {
          _recording = true;
          _recordingGroundedQuestion = groundedQuestion;
          _voiceStatus = groundedQuestion
              ? '🔴 正在錄音：語音查詢 → Gemini 即時查詢 → EBO 語音回答。再點擊語音按鈕送出。'
              : '🔴 正在錄音：語音指令 → 文字辨識 → MCP 控制。再點擊語音按鈕送出。';
        });
      } else {
        final path = await _recorder.stop();
        if (mounted) setState(() {
          _recording = false;
          _voiceStatus = groundedQuestion
              ? '錄音完成，正在轉寫及取得即時資訊…'
              : '錄音完成，正在辨識指令及確認 MCP 動作…';
        });
        if (path == null) throw const FormatException('找不到錄音資料');
        final file = File(path);
        final bytes = await file.readAsBytes();
        await file.delete();
        if (groundedQuestion) {
          await _voiceGroundedQuestion(Uint8List.fromList(bytes));
        } else {
          await _send(audio: Uint8List.fromList(bytes));
        }
      }
    } catch (e) {
      if (mounted) setState(() {
        _recording = false;
        _recordingGroundedQuestion = false;
      });
      widget.logs.log('VOICE', '錄音失敗：${e.runtimeType}', level: 'ERROR');
      if (mounted) setState(() => _voiceStatus = '語音錄製失敗，沒有執行 MCP。');
      await _showFailureDialog('語音錄製或傳送失敗',
          '無法完成錄音流程：${e.runtimeType}。請檢查麥克風權限、儲存空間與網路。');
    }
  }

  Future<void> _voiceGroundedQuestion(Uint8List audio) async {
    if (_busy) return;
    setState(() => _busy = true);
    String? transcript;
    try {
      widget.logs.log('VOICE_QA', '開始語音轉文字（音檔不保留）');
      transcript = await _agent.transcribeAudio(
        apiKey: widget.apiKey,
        bytes: audio,
      );
      widget.logs.log('VOICE_QA', '語音轉寫成功；準備進行 Grounding 即時查詢');
      _input.text = transcript;
    } catch (e) {
      widget.logs.log('VOICE_QA',
          '轉寫失敗：' + e.runtimeType.toString(), level: 'ERROR');
      await _showFailureDialog('無法辨識語音問題',
          '這次沒有執行任何 MCP 動作。請重新錄製語音並確認背景噪音。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted || transcript == null) return;
    // This mode NEVER forwards a voice transcript to robot MCP controls.
    await _groundedSpeak(promptOverride: transcript);
  }

  Future<void> _groundedSpeak({String? promptOverride}) async {
    if (_busy) return;
    final prompt = promptOverride ?? _input.text.trim();
    if (prompt.isEmpty) {
      await _showFailureDialog('尚未輸入查詢內容',
          '請輸入問題及城市，例如：桃園市今天下午天氣。');
      return;
    }
    final notes = _notebook.contextForModel;
    setState(() => _busy = true);
    try {
      await _notebook.addMessage('user', prompt);
      final answer = await _agent.runGroundedQuestion(
        apiKey: widget.apiKey,
        prompt: prompt,
        contextNotes: notes,
      );
      final displayText = '${answer.text}\n來源：\n${answer.sources.join('\n')}';
      await _notebook.addMessage('assistant', displayText);
      widget.logs.log('AI', '搜尋有來源的最新資訊，數量：${answer.sources.length}');
      if (mounted) setState(() {});
      await _speak(answer.text);
    } catch (e) {
      widget.logs.log('AI', '即時資訊取得失敗：${e.runtimeType}', level: 'ERROR');
      await _showFailureDialog('即時查詢失敗',
          '目前無法取得可核實的資料與來源，因此沒有讓 EBO 播報。\n請確認 Gemini Key、網路或稍後重試。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _speak(String text) async {
    final tool = widget.mcp.tools
        .where((t) => t.name == 'robot_speak').firstOrNull;
    if (!widget.mcp.connected || tool == null) {
      await _showFailureDialog('EBO 語音播報無法執行',
          'MCP 尚未連線，或原廠未提供 robot_speak。\nAI 查詢內容仍會保留於對話紀錄。');
      return;
    }
    var spoken = text.split('\n來源：').first
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll(RegExp(r'[*#_]+'), '').trim();
    if (spoken.isEmpty) {
      await _showFailureDialog('沒有可播報內容',
          'Gemini 沒有提供可用於 EBO 播報的文字。');
      return;
    }
    if (spoken.length > 220) spoken = spoken.substring(0, 220);
    final args = <String, dynamic>{'text': spoken};
    final properties = tool.schema['properties'];
    if (properties is Map && properties.containsKey('lang')) {
      final field = properties['lang'];
      final enums = field is Map && field['enum'] is List
          ? (field['enum'] as List).map((x) => x.toString()).toList()
          : <String>[];
      if (enums.isNotEmpty) {
        final chinese = ['zh-TW', 'zh', 'zh_CN', 'zh-CN']
            .where(enums.contains).firstOrNull;
        if (chinese == null) {
          await _showFailureDialog('EBO 語音無法執行',
              '原廠 robot_speak 未提供可辨識的繁體／中文語言選項。');
          return;
        }
        args['lang'] = chinese;
      } else {
        args['lang'] = 'zh-TW';
      }
    }
    try {
      ActionMap.validateArguments(tool, args);
      if (!await widget.approve(tool.name, args)) {
        _notify('您已取消 EBO 語音播報，沒有送出 MCP 指令');
        return;
      }
      await widget.mcp.call(tool.name, args);
      widget.logs.log('VOICE', 'robot_speak 已送出');
      _notify('已傳送至 EBO 語音播放工具');
    } catch (e) {
      widget.logs.log('VOICE', 'EBO 播報失敗：${e.runtimeType}', level: 'ERROR');
      await _showFailureDialog('EBO 語音播報無法執行',
          '已取得 AI 回答，但 robot_speak 沒有成功完成 MCP 呼叫：${e.runtimeType}。\n請檢查 Log。');
    }
  }

  Future<void> _repeatFavorite(String prompt) async {
    if (_busy) return;
    _input.text = prompt;
    await _send();
  }

  Future<void> _createNote() async {
    final edit = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新增私人記憶／詞典'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('只保存您主動核准的背景資訊，例如習慣用語、指定稱呼、'
            '預設城市。不要在這裡儲存金鑰或密碼。'),
          const SizedBox(height: 8),
          TextField(controller: edit, maxLength: 400, maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(), labelText: '記憶內容')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, edit.text),
            child: const Text('儲存筆記')),
        ],
      ),
    );
    edit.dispose();
    if (note == null || note.trim().isEmpty) return;
    try {
      await _notebook.addNote(note);
      if (mounted) setState(() {});
    } catch (e) {
      _notify('記憶筆記保存失敗');
    }
  }

  Future<void> _longPress(AiMessage message) async {
    if (!mounted) return;
    final isFavorite = _notebook.favorites.contains(message.text);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.role == 'user') ListTile(
            leading: Icon(isFavorite ? Icons.star_border : Icons.star),
            title: Text(isFavorite ? '取消最愛' : '加入最愛快速指令'),
            onTap: () => Navigator.pop(ctx, 'favorite')),
          ListTile(
            leading: const Icon(Icons.menu_book),
            title: const Text('登載到長期記憶／詞典'),
            onTap: () => Navigator.pop(ctx, 'note')),
          if (message.role == 'assistant') ListTile(
            leading: const Icon(Icons.volume_up_outlined),
            title: const Text('讓 EBO 語音播報此回答'),
            onTap: () => Navigator.pop(ctx, 'speak')),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('複製內容'),
            onTap: () => Navigator.pop(ctx, 'copy')),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('刪除此則訊息'),
            onTap: () => Navigator.pop(ctx, 'delete')),
        ],
      )),
    );
    try {
      if (choice == 'favorite') {
        await _notebook.toggleFavorite(message.text);
      } else if (choice == 'note') {
        await _notebook.addNote(message.text);
      } else if (choice == 'speak') {
        await _speak(message.text);
      } else if (choice == 'copy') {
        await Clipboard.setData(ClipboardData(text: message.text));
      } else if (choice == 'delete') {
        await _notebook.removeMessage(message.id);
      }
      if (mounted) setState(() {});
    } catch (e) {
      _notify('更新對話內容失敗');
    }
  }

  Future<void> _clearChat() async {
    final confirm = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除全部 AI 對話？'),
        content: const Text('最愛與長期記憶筆記不會被清除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確認清除')),
        ],
      ));
    if (confirm != true) return;
    await _notebook.clearChat();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    if (_voiceStatus != null) _voiceStatusBanner(),
    Expanded(child: AiConversationPanel(
    notebook: _notebook,
    input: _input,
    busy: _busy,
    voiceRecording: _recording,
    onSend: () => _send(),
    onVoice: () => _toggleVoice(),
    onVoiceGrounded: () => _toggleVoice(groundedQuestion: true),
    voiceRecordingGrounded: _recordingGroundedQuestion,
    onGroundedSpeak: () => _groundedSpeak(),
    onAddNote: _createNote,
    onClearChat: _clearChat,
    onLongPress: _longPress,
    onFavoriteTap: _repeatFavorite,
    onNoteDelete: (note) async {
      await _notebook.removeNote(note);
      if (mounted) setState(() {});
    },
    onSpeak: _speak,
  )),
  ]);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _recorder.dispose();
    _agent.dispose();
    super.dispose();
  }
}
