import 'package:flutter/material.dart';
import '../services/ai_notebook.dart';

/// Conversation stays visible until explicitly deleted. Long press any turn
/// to favorite a command or add user-approved context to the notebook.
class AiConversationPanel extends StatelessWidget {
  final AiNotebook notebook;
  final TextEditingController input;
  final bool busy;
  final bool voiceRecording;
  final VoidCallback onSend;
  final VoidCallback onVoice;
  final VoidCallback onVoiceGrounded;
  final bool voiceRecordingGrounded;
  final VoidCallback onGroundedSpeak;
  final VoidCallback onAddNote;
  final VoidCallback onClearChat;
  final void Function(AiMessage) onLongPress;
  final void Function(String) onFavoriteTap;
  final void Function(String) onNoteDelete;
  final void Function(String) onSpeak;
  const AiConversationPanel({
    super.key,
    required this.notebook,
    required this.input,
    required this.busy,
    required this.voiceRecording,
    required this.onSend,
    required this.onVoice,
    required this.onVoiceGrounded,
    required this.voiceRecordingGrounded,
    required this.onGroundedSpeak,
    required this.onAddNote,
    required this.onClearChat,
    required this.onLongPress,
    required this.onFavoriteTap,
    required this.onNoteDelete,
    required this.onSpeak,
  });

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(14),
    children: [
      const Text('Gemini AI 智慧對話',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Text('所有實體動作均需要確認。對話保留在手機加密儲存。'
          '長按訊息可加入最愛或詞典／記憶筆記。'),
      const SizedBox(height: 12),
      TextField(
        controller: input,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: '自然語言指令／問題',
          hintText: '請機器人回充，或查詢「桃園市今天下午天氣」',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: busy ? null : onSend,
        icon: const Icon(Icons.send),
        label: const Text('文字指令 → MCP 控制'),
      ),
      const SizedBox(height: 8),
      FilledButton.tonalIcon(
        onPressed: busy || (voiceRecording && voiceRecordingGrounded) ? null : onVoice,
        icon: Icon(voiceRecording ? Icons.stop_circle : Icons.mic),
        label: Text(voiceRecording && !voiceRecordingGrounded
            ? '停止錄音並執行控制' : '語音指令 → MCP 控制'),
      ),
      const SizedBox(height: 8),
      const Divider(height: 24),
      const Text('AI 即時問答 → EBO 語音回覆',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      const Text('這兩種模式均會先查詢 Google Search，'
          '確認來源後，再請 EBO 語音播報；不會將查詢文字直接當成 MCP 動作。'),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: busy ? null : onGroundedSpeak,
        icon: const Icon(Icons.edit_note),
        label: const Text('文字查詢 → EBO 語音回覆'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: busy || (voiceRecording && !voiceRecordingGrounded)
            ? null : onVoiceGrounded,
        icon: Icon(voiceRecording && voiceRecordingGrounded
            ? Icons.stop_circle : Icons.keyboard_voice),
        label: Text(voiceRecording && voiceRecordingGrounded
            ? '結束錄音 → 即時搜尋 → EBO 播報'
            : '語音查詢 → EBO 語音回覆'),
      ),
      const Text('查詢天氣或活動時間，請說明城市／地區；'
          '來源不足時不會讓 EBO 播報。'),
      if (busy) const Padding(padding: EdgeInsets.all(10),
        child: LinearProgressIndicator()),
      if (notebook.favorites.isNotEmpty) ...[
        const Divider(height: 30),
        const Text('最愛快速指令',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const Text('點擊後重新送出；如涉及機器人動作，仍須再次確認。'),
        Wrap(spacing: 8, children: notebook.favorites.map((fav) =>
          ActionChip(
            avatar: const Icon(Icons.star, size: 18),
            label: Text(fav, overflow: TextOverflow.ellipsis),
            onPressed: busy ? null : () => onFavoriteTap(fav),
          ),
        ).toList()),
      ],
      const Divider(height: 30),
      Row(children: [
        const Expanded(child: Text('詞典／長期記憶筆記',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
        IconButton(onPressed: onAddNote, icon: const Icon(Icons.add_circle_outline),
          tooltip: '新增記憶筆記'),
      ]),
      const Text('只會在您主動加入後保存。新指令會附上相關筆記及近期對話；'
          '不會將過去的機器人動作重新執行。'),
      if (notebook.notes.isEmpty)
        const Padding(padding: EdgeInsets.all(8), child: Text('尚未建立記憶筆記'))
      else
        ...notebook.notes.map((note) => ListTile(
          leading: const Icon(Icons.menu_book),
          title: Text(note, maxLines: 3, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            icon: const Icon(Icons.close),
            tooltip: '刪除筆記',
            onPressed: () => onNoteDelete(note),
          ),
        )),
      const Divider(height: 26),
      Row(children: [
        const Expanded(child: Text('AI 對話紀錄',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        TextButton.icon(
          onPressed: onClearChat,
          icon: const Icon(Icons.delete_outline),
          label: const Text('手動清除'),
        ),
      ]),
      if (notebook.messages.isEmpty)
        const Card(child: Padding(padding: EdgeInsets.all(16),
          child: Text('目前沒有對話。傳送後會持續保留，不會自動清空。')))
      else
        ...notebook.messages.map((message) => Align(
          alignment: message.role == 'user' ?
              Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Card(
              color: message.role == 'user'
                ? const Color(0xFF1D4955) : const Color(0xFF232C33),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onLongPress: () => onLongPress(message),
                child: Padding(padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(message.role == 'user' ? '我' : 'Gemini',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Text('${message.time.hour.toString().padLeft(2, '0')}:'
                          '${message.time.minute.toString().padLeft(2, '0')}',
                        style: Theme.of(context).textTheme.labelSmall),
                    ]),
                    const SizedBox(height: 6),
                    Text(message.text), // Long press belongs to InkWell; Copy is in its menu.
                    if (message.role == 'assistant')
                      Align(alignment: Alignment.centerRight,
                        child: IconButton(
                          icon: const Icon(Icons.volume_up_outlined),
                          tooltip: '讓 EBO 播報此回答',
                          onPressed: () => onSpeak(message.text),
                        )),
                  ]),
                ),
              ),
            ),
          ),
        )),
      const SizedBox(height: 50),
    ],
  );
}
