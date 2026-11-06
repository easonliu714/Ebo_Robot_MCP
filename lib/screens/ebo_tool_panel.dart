import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/action_map.dart';
import '../services/diagnostics.dart';
import '../services/ebo_tool_catalog.dart';
import '../services/mcp_service.dart';

/// Uses the actual paginated MCP tools/list rather than a fixed 15-item limit.
class EboToolPanel extends StatelessWidget {
  final McpClient mcp;
  final Diagnostics logs;
  const EboToolPanel({super.key, required this.mcp, required this.logs});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('完整 MCP 工具（${mcp.tools.length} 個）',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const Text('顯示所有已取得的工具。欄位依實際 Schema 生成，'
          '原廠未提供的選項或範圍不會虛構。執行前必須確認。'),
      const SizedBox(height: 10),
      ...mcp.tools.map((t) => Card(
        child: ListTile(
          title: Text(EboToolCatalog.labels[t.name] ?? t.name),
          subtitle: Text('${t.name}\n${EboToolCatalog.hints[t.name] ?? t.description}',
              maxLines: 3, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.tune),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => _ToolForm(tool: t, mcp: mcp, logs: logs),
          ),
        ),
      )),
    ],
  );
}

class _ToolForm extends StatefulWidget {
  final McpTool tool;
  final McpClient mcp;
  final Diagnostics logs;
  const _ToolForm({required this.tool, required this.mcp, required this.logs});

  @override
  State<_ToolForm> createState() => _ToolFormState();
}

class _ToolFormState extends State<_ToolForm> {
  final Map<String, TextEditingController> _editors = {};
  final Map<String, bool> _bools = {};
  final Map<String, String> _textPicks = {};
  final List<String> _locations = [];
  bool _busy = false;
  String? _error;
  static const _custom = '__custom_text__';

  Map<String, dynamic> get _properties {
    final obj = widget.tool.schema['properties'];
    return obj is Map ? Map<String, dynamic>.from(obj) : {};
  }

  List<String> get _required =>
    (widget.tool.schema['required'] as List? ?? [])
      .map((x) => x.toString()).toList();

  @override
  void initState() {
    super.initState();
    final initial = EboToolCatalog.suggestedArgs(widget.tool.name);
    for (final key in _properties.keys) {
      final value = initial[key];
      _editors[key] = TextEditingController(
        text: value == null ? '' : value is String ? value : value.toString(),
      );
      _bools[key] = value == true;
    }
  }

  @override
  void dispose() {
    for (final value in _editors.values) {
      value.dispose();
    }
    super.dispose();
  }

  String _typeOf(Map<String, dynamic> spec) {
    final raw = spec['type'];
    if (raw is String) return raw.toLowerCase();
    if (raw is List) {
      return raw.firstWhere((x) => x != 'null', orElse: () => 'string')
          .toString().toLowerCase();
    }
    return 'string';
  }

  Widget _numberField(String key, Map<String, dynamic> spec, bool required) {
    final allowed = spec['enum'] is List
        ? (spec['enum'] as List).whereType<num>().toList() : <num>[];
    final named = EboToolCatalog.numericChoices(widget.tool.name, key);
    final options = allowed.isNotEmpty ? allowed : named.keys.toList();
    final rawMove = int.tryParse(_editors['moveId']?.text ?? '');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: _editors[key],
        onChanged: (_) => setState(() {}),
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(
          labelText: '${EboToolCatalog.fieldTitle(key)} ($key)${required ? ' *' : ''}',
          border: const OutlineInputBorder(),
          helperText: EboToolCatalog.rangeText(widget.tool.name, key, spec,
              moveId: rawMove),
          helperMaxLines: 2,
          hintText: '請輸入數值',
        ),
      ),
      if (options.isNotEmpty) ...[
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.tool.name}.$key'),
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '常用數值代碼（選擇後填入上方數值框）',
          ),
          items: options.map((n) => DropdownMenuItem<String>(
            value: n.toString(),
            child: Text('${n.toString()} — ${named[n.toInt()] ?? '原廠選項'}'),
          )).toList(),
          onChanged: (v) {
            if (v != null) setState(() => _editors[key]!.text = v);
          },
        ),
      ],
    ]);
  }

  List<String> _stringOptions(String key, Map<String, dynamic> spec) {
    final enumValue = spec['enum'];
    if (enumValue is List) return enumValue.map((x) => x.toString()).toList();
    if (key == 'locationName') return _locations;
    if (key == 'lang') return const ['zh-TW', 'en-US'];
    return const [];
  }

  Widget _stringField(String key, Map<String, dynamic> spec, bool required) {
    final values = _stringOptions(key, spec);
    final restricted = spec['enum'] is List;
    final selection = _textPicks[key] ?? _custom;
    final valid = values.contains(selection) ? selection : _custom;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<String>(
        key: ValueKey('${widget.tool.name}.$key'),
        value: valid,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: '${EboToolCatalog.fieldTitle(key)} ($key)${required ? ' *' : ''}',
          border: const OutlineInputBorder(),
        ),
        items: [
          if (!restricted || values.isEmpty)
            const DropdownMenuItem(value: _custom, child: Text('自訂文字輸入')),
          ...values.map((option) => DropdownMenuItem(
            value: option, child: Text(option, overflow: TextOverflow.ellipsis),
          )),
          if (restricted && values.isNotEmpty)
            const DropdownMenuItem(value: _custom,
                enabled: false, child: Text('請選擇原廠允許值')),
        ],
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _textPicks[key] = v;
            if (v != _custom) _editors[key]!.text = v;
          });
        },
      ),
      if (valid == _custom && (!restricted || values.isEmpty))
        Padding(padding: const EdgeInsets.only(top: 8),
          child: TextField(
            controller: _editors[key],
            maxLines: key == 'text' ? 3 : 1,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: '輸入${EboToolCatalog.fieldTitle(key)}',
              hintText: '原廠沒有提供固定文字選項，可手動輸入',
            ),
          )),
      if (key == 'locationName')
        TextButton.icon(
          onPressed: _busy ? null : _loadLocations,
          icon: const Icon(Icons.place_outlined),
          label: const Text('讀取機器人已儲存的位置清單'),
        ),
    ]);
  }

  Widget _field(String key, dynamic value) {
    final spec = value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    final required = _required.contains(key);
    final type = _typeOf(spec);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${EboToolCatalog.fieldTitle(key)} · $key',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(spec['description']?.toString() ?? EboToolCatalog.fieldHelp(key),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 7),
        if (type == 'integer' || type == 'number')
          _numberField(key, spec, required)
        else if (type == 'boolean')
          SwitchListTile(
            title: Text('${EboToolCatalog.fieldTitle(key)} ($key)'),
            value: _bools[key] ?? false,
            onChanged: (v) => setState(() => _bools[key] = v),
          )
        else if (type == 'string')
          _stringField(key, spec, required)
        else
          TextField(
            controller: _editors[key],
            minLines: 2, maxLines: 5,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: '$key · $type（JSON 格式）',
            ),
          ),
      ]),
    );
  }

  Map<String, dynamic> _collect() {
    final args = <String, dynamic>{};
    for (final entry in _properties.entries) {
      final key = entry.key;
      final spec = entry.value is Map
          ? Map<String, dynamic>.from(entry.value as Map) : <String, dynamic>{};
      final type = _typeOf(spec);
      final raw = _editors[key]?.text.trim() ?? '';
      if (type == 'boolean') {
        if (_required.contains(key) || EboToolCatalog.suggestedArgs(widget.tool.name)
            .containsKey(key)) args[key] = _bools[key] ?? false;
        continue;
      }
      if (raw.isEmpty) {
        if (_required.contains(key)) throw FormatException('請填寫：$key');
        continue;
      }
      if (type == 'integer') {
        final n = int.tryParse(raw);
        if (n == null) throw FormatException('$key 必須是整數');
        args[key] = n;
      } else if (type == 'number') {
        final n = num.tryParse(raw);
        if (n == null) throw FormatException('$key 必須是數值');
        args[key] = n;
      } else if (type == 'array' || type == 'object') {
        args[key] = jsonDecode(raw);
      } else {
        args[key] = raw;
      }
    }
    ActionMap.validateArguments(widget.tool, args);
    return args;
  }

  Future<void> _loadLocations() async {
    final exists = widget.mcp.tools.any((t) => t.name == 'robot_list_locations');
    if (!exists) {
      setState(() => _error = '目前 MCP 伺服器未提供 robot_list_locations');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final response = await widget.mcp.call('robot_list_locations', {});
      final found = <String>{};
      void scan(dynamic obj, {bool locationScope = false}) {
        if (obj is Map) {
          if (locationScope) {
            final n = obj['locationName'] ?? obj['name'];
            if (n is String && n.trim().isNotEmpty) found.add(n.trim());
          }
          for (final entry in obj.entries) {
            final k = entry.key.toString();
            if (k == 'locations' || k == 'locationList' || k == 'list') {
              scan(entry.value, locationScope: true);
            } else if (k == 'content' || k == 'result' || k == 'data') {
              scan(entry.value, locationScope: locationScope);
            } else if (k == 'text' && entry.value is String) {
              try { scan(jsonDecode(entry.value as String)); } catch (_) {}
            } else if (locationScope) {
              scan(entry.value, locationScope: true);
            }
          }
        } else if (obj is List) {
          for (final item in obj) {
            if (locationScope && item is String && item.trim().isNotEmpty) {
              found.add(item.trim());
            } else {
              scan(item, locationScope: locationScope);
            }
          }
        }
      }
      scan(response);
      if (!mounted) return;
      setState(() {
        _locations..clear()..addAll(found.take(100));
        if (_locations.isEmpty) _error = '未解析到地圖位置，可依原廠回應手動輸入';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '取得位置清單失敗：${e.runtimeType}');
      widget.logs.log('TOOLS', '取得地圖位置失敗：${e.runtimeType}', level: 'ERROR');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _execute() async {
    Map<String, dynamic> args;
    try {
      args = _collect();
      if (widget.tool.name == 'robot_navigate' &&
          (args['locationName']?.toString().trim().isEmpty ?? true)) {
        throw const FormatException('導航必須填入已儲存的地圖位置');
      }
      if (widget.tool.name == 'robot_speak' &&
          (args['text']?.toString().trim().isEmpty ?? true)) {
        throw const FormatException('語音播報內容不可為空');
      }
    } catch (e) {
      setState(() => _error = e.toString());
      return;
    }
    final approval = await showDialog<bool>(context: context,
      barrierDismissible: false, builder: (ctx) => AlertDialog(
      title: const Text('確認 MCP 機器人操作'),
      content: SingleChildScrollView(child: SelectableText(
        Redactor.clean('工具：${widget.tool.name}\n${jsonEncode(args)}'))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
          child: const Text('確認執行')),
      ],
    ));
    if (approval != true || !mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await widget.mcp.call(widget.tool.name, args);
      widget.logs.log('TOOLS', '工具執行成功：${widget.tool.name}');
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('MCP 工具回應'),
        content: SingleChildScrollView(child: SelectableText(
          Redactor.clean(const JsonEncoder.withIndent('  ').convert(result)))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx),
          child: const Text('關閉'))],
      ));
    } catch (e) {
      widget.logs.log('TOOLS', '工具執行失敗：${widget.tool.name} '
          '${e.runtimeType}', level: 'ERROR');
      if (mounted) setState(() => _error = '工具執行失敗，請匯出 Log');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(EboToolCatalog.labels[widget.tool.name] ?? widget.tool.name),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, children: [
          Text(widget.tool.name),
          const SizedBox(height: 6),
          Text(EboToolCatalog.hints[widget.tool.name] ??
              widget.tool.description),
          const Divider(height: 20),
          if (_properties.isEmpty) const Text('此工具沒有參數，可直接確認執行'),
          ..._properties.entries.map((e) => _field(e.key, e.value)),
          if (_error != null) Text(_error!,
              style: const TextStyle(color: Colors.redAccent)),
          ExpansionTile(title: const Text('進階：查看原廠 Schema'),
            children: [SelectableText(const JsonEncoder.withIndent('  ')
                .convert(widget.tool.schema))]),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('關閉')),
      FilledButton(onPressed: _busy ? null : _execute,
          child: Text(_busy ? '執行中...' : '檢查並執行')),
    ],
  );
}
