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
import '../services/mcp_service.dart';
import 'ai_conversation_panel.dart';

/// Complete, encrypted, user-controlled conversation surface.
class AiConversationScreen extends StatefulWidget {
  final String apiKey;
  final McpClient mcp;
  final Diagnostics logs;
  final ApproveTool approve;
  const AiConversationScreen({
    super.key,
    required this.apiKey,
    required this.mcp,
    required this.logs,
    required this.approve,
  });

  @override
  State<AiConversationScreen> createState() => _AiConversationScreenState();
}

class _AiConversationScreenState extends State<AiConversationScreen> {
  final _notebook = AiNotebook();
  final _agent = GeminiAgent();
  final _recorder = AudioRecorder();
  final _input = TextEditingController();
  bool _busy = false;
  bool _recording = false;
  bool _recordingGroundedQuestion = false;

  @override
  void initState() {
    super.initState();
    _load();
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
    final prompt = _input.text.trim();
    if (audio == null && prompt.isEmpty) return;
    final previousContext = _notebook.contextForModel;
    setState(() => _busy = true);
    try {
      await _notebook.addMessage('user',
          audio == null ? prompt : '🎙️ 由手機錄音輸入語音指令');
      if (mounted) setState(() {});
      final response = audio == null
          ? await _agent.runText(
              apiKey: widget.apiKey,
              prompt: prompt,
              contextNotes: previousContext,
              mcp: widget.mcp,
              approve: widget.approve,
              onStep: (v) => widget.logs.log('AI', v),
            )
          : await _agent.runAudio(
              apiKey: widget.apiKey,
              bytes: audio,
              contextNotes: previousContext,
              mcp: widget.mcp,
              approve: widget.approve,
              onStep: (v) => widget.logs.log('AI', v),
            );
      await _notebook.addMessage('assistant', response);
      widget.logs.log('AI', 'AI 回答已加密保存至手機');
      if (mounted) setState(() {});
    } catch (e) {
      widget.logs.log('AI', '一般對話失敗：${e.runtimeType}', level: 'ERROR');
      _notify('AI 指令失敗，請匯出 Log');
    } finally {
      if (mounted) setState(() => _busy = false);
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
          _notify('需要授予麥克風權限');
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
        });
      } else {
        final path = await _recorder.stop();
        if (mounted) setState(() => _recording = false);
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
      _notify('語音指令錄製／傳送失敗');
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
      _notify('無法辨識語音問題，請重新錄製');
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
      _notify('請輸入問題及城市，例如：桃園市今天下午天氣');
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
      _notify('目前無法確認最新資料或來源，未安排語音播報');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _speak(String text) async {
    final tool = widget.mcp.tools
        .where((t) => t.name == 'robot_speak').firstOrNull;
    if (!widget.mcp.connected || tool == null) {
      _notify('MCP 未連線或未提供 robot_speak 工具');
      return;
    }
    var spoken = text.split('\n來源：').first
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll(RegExp(r'[*#_]+'), '').trim();
    if (spoken.isEmpty) {
      _notify('沒有可播報的文字');
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
          _notify('機器人的語言選項沒有可辨識的中文語系');
          return;
        }
        args['lang'] = chinese;
      } else {
        args['lang'] = 'zh-TW';
      }
    }
    try {
      ActionMap.validateArguments(tool, args);
      if (!await widget.approve(tool.name, args)) return;
      await widget.mcp.call(tool.name, args);
      widget.logs.log('VOICE', 'robot_speak 已送出');
      _notify('已傳送至 EBO 語音播放工具');
    } catch (e) {
      widget.logs.log('VOICE', 'EBO 播報失敗：${e.runtimeType}', level: 'ERROR');
      _notify('EBO 播報未成功，請查看 Log');
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
  Widget build(BuildContext context) => AiConversationPanel(
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
  );

  @override
  void dispose() {
    _input.dispose();
    _recorder.dispose();
    _agent.dispose();
    super.dispose();
  }
}
