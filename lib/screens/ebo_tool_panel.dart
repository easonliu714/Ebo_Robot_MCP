import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/action_map.dart';
import '../services/diagnostics.dart';
import '../services/ebo_tool_catalog.dart';
import '../services/mcp_service.dart';

class EboToolPanel extends StatelessWidget {
  final McpClient mcp;
  final Diagnostics logs;
  const EboToolPanel({super.key, required this.mcp, required this.logs});

  Future<void> execute(BuildContext context, McpTool tool) async {
    final edit = TextEditingController(text: jsonEncode(EboToolCatalog.suggestedArgs(tool.name)));
    final okay = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(EboToolCatalog.labels[tool.name] ?? tool.name),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(EboToolCatalog.hints[tool.name] ?? tool.description),
        const SizedBox(height: 10),
        SelectableText(const JsonEncoder.withIndent('  ').convert(tool.schema),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        const SizedBox(height: 10),
        TextField(controller: edit, maxLines: 5, minLines: 2,
          decoration: const InputDecoration(labelText: 'JSON Arguments',
            border: OutlineInputBorder())),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('確認參數')),
      ],
    ));
    final raw = edit.text;
    edit.dispose();
    if (okay != true || !context.mounted) return;
    try {
      if (!mcp.connected) throw const FormatException('MCP 尚未連線');
      final value = jsonDecode(raw);
      if (value is! Map) throw const FormatException('參數必須是 JSON 物件');
      final args = Map<String, dynamic>.from(value);
      ActionMap.validateArguments(tool, args);
      if (tool.name == 'robot_navigate' &&
          (args['locationName']?.toString().trim().isEmpty ?? true)) {
        throw const FormatException('先查詢 robot_list_locations');
      }
      if (tool.name == 'robot_speak' &&
          (args['text']?.toString().trim().isEmpty ?? true)) {
        throw const FormatException('text 不可空白');
      }
      final confirmed = await showDialog<bool>(context: context,
        barrierDismissible: false, builder: (ctx) => AlertDialog(
        title: const Text('確認機器人操作'),
        content: SelectableText(Redactor.clean('${tool.name}\n${jsonEncode(args)}')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('執行')),
        ],
      ));
      if (confirmed != true) return;
      final result = await mcp.call(tool.name, args);
      logs.log('TOOLS', '完成工具 ${tool.name}');
      if (context.mounted) {
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('工具回應'),
          content: SingleChildScrollView(child: SelectableText(
            Redactor.clean(const JsonEncoder.withIndent('  ').convert(result)))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉'))],
        ));
      }
    } catch (e) {
      logs.log('TOOLS', '工具 ${tool.name} 執行失敗：${e.runtimeType}', level: 'ERROR');
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Redactor.clean(e.toString()))));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('完整 MCP 工具（${mcp.tools.length} 個）',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const Text('按工具檢視 Schema 與設定參數，經確認後才執行。'),
      ...mcp.tools.map((t) => Card(child: ListTile(
        title: Text(EboToolCatalog.labels[t.name] ?? t.name),
        subtitle: Text('${t.name}\n${EboToolCatalog.hints[t.name] ?? t.description}',
            maxLines: 3, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.play_circle_outline),
        onTap: () => execute(context, t),
      ))),
    ],
  );
}
