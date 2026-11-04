import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class McpConfig {
  final Uri endpoint;
  final String bearer;
  const McpConfig(this.endpoint, this.bearer);

  static McpConfig parse(String input) {
    final text = input.trim();
    if (text.isEmpty) throw const FormatException('請貼上 MCP 配置');
    String url = '';
    String authorization = '';
    if (text.startsWith('{')) {
      final root = jsonDecode(text) as Map<String, dynamic>;
      final servers = root['mcpServers'];
      Map<String, dynamic> node = root;
      if (servers is Map && servers.isNotEmpty) {
        node = Map<String, dynamic>.from(servers.values.first as Map);
      }
      url = (node['url'] ?? '').toString();
      final headers = node['headers'];
      if (headers is Map) {
        authorization = (headers['Authorization'] ?? headers['authorization'] ?? '').toString();
      }
      final args = (node['args'] as List?)?.map((e) => e.toString()).toList() ?? [];
      for (var i = 0; i < args.length; i++) {
        if (args[i].startsWith('https://')) url = args[i];
        if (args[i] == '--header' && i + 1 < args.length) {
          final item = args[++i];
          if (item.toLowerCase().startsWith('authorization:')) {
            authorization = item.substring(item.indexOf(':') + 1).trim();
          }
        }
      }
    } else {
      throw const FormatException('請使用官方「複製配置」JSON');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery) {
      throw const FormatException('MCP 必須使用有效且無查詢參數的 HTTPS URL');
    }
    if (!authorization.toLowerCase().startsWith('bearer ') ||
        authorization.substring(7).trim().isEmpty) {
      throw const FormatException('找不到 Authorization Bearer 憑證');
    }
    return McpConfig(uri, authorization.substring(7).trim());
  }
}

class McpTool {
  final String name;
  final String description;
  final Map<String, dynamic> schema;
  const McpTool(this.name, this.description, this.schema);

  factory McpTool.fromJson(Map<String, dynamic> json) => McpTool(
    json['name']?.toString() ?? '',
    json['description']?.toString() ?? '',
    Map<String, dynamic>.from(json['inputSchema'] is Map
        ? json['inputSchema'] as Map : {'type': 'object', 'properties': {}}),
  );
}

class McpException implements Exception {
  final String message;
  const McpException(this.message);
  @override
  String toString() => message;
}

class McpClient {
  final http.Client _http;
  McpConfig? config;
  String? _session;
  String _protocol = '2025-03-26';
  int _nextId = 0;
  Future<void> _queue = Future<void>.value();
  bool connected = false;
  List<McpTool> tools = [];

  McpClient({http.Client? client}) : _http = client ?? http.Client();

  Future<T> _exclusive<T>(Future<T> Function() run) {
    final result = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        result.complete(await run());
      } catch (e, st) {
        result.completeError(e, st);
      }
    });
    return result.future;
  }

  Future<Map<String, dynamic>> _send(String method,
      {Map<String, dynamic>? params, bool notification = false}) async {
    final cfg = config;
    if (cfg == null) throw const McpException('尚未設定 MCP');
    final id = ++_nextId;
    final request = http.Request('POST', cfg.endpoint);
    request.headers.addAll({
      'Authorization': 'Bearer ' + cfg.bearer,
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream',
      if (_session != null) 'Mcp-Session-Id': _session!,
      if (method != 'initialize') 'MCP-Protocol-Version': _protocol,
    });
    request.body = jsonEncode({
      'jsonrpc': '2.0',
      if (!notification) 'id': id,
      'method': method,
      if (params != null) 'params': params,
    });
    final response = await _http.send(request).timeout(const Duration(seconds: 20));
    if (response.headers['mcp-session-id'] case final String sid) {
      _session = sid;
    }
    if (response.statusCode >= 400) {
      await response.stream.drain<void>();
      throw McpException('MCP HTTP ' + response.statusCode.toString());
    }
    if (notification || response.statusCode == 202 || response.statusCode == 204) {
      await response.stream.drain<void>();
      return {};
    }
    final type = response.headers['content-type'] ?? '';
    Map<String, dynamic> data;
    if (type.contains('text/event-stream')) {
      String eventData = '';
      Map<String, dynamic>? found;
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 20));
      await for (final line in lines) {
        if (line.startsWith('data:')) {
          eventData += line.substring(5).trimLeft();
        } else if (line.isEmpty && eventData.isNotEmpty) {
          final value = jsonDecode(eventData);
          eventData = '';
          if (value is Map<String, dynamic> && value['id'] == id) {
            found = value;
            break;
          }
        }
      }
      if (found == null && eventData.isNotEmpty) {
        final value = jsonDecode(eventData);
        if (value is Map<String, dynamic> && value['id'] == id) found = value;
      }
      if (found == null) throw const McpException('MCP SSE 未收到相符 JSON-RPC 回應');
      data = found;
    } else {
      final raw = await response.stream.bytesToString().timeout(const Duration(seconds: 20));
      data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    }
    if (data['error'] != null) {
      final error = data['error'];
      final code = error is Map ? error['code'] : null;
      throw McpException('MCP JSON-RPC 錯誤 ' + (code?.toString() ?? 'unknown'));
    }
    return data;
  }

  Future<List<McpTool>> connect(McpConfig value) => _exclusive(() async {
    await _releaseSession();
    connected = false;
    tools = [];
    config = value;
    _session = null;
    _protocol = '2025-03-26';
    final init = await _send('initialize', params: {
      'protocolVersion': _protocol,
      'capabilities': {},
      'clientInfo': {'name': 'ebo-android-controller', 'version': '0.1.0'},
    });
    final result = init['result'];
    if (result is Map && result['protocolVersion'] is String) {
      _protocol = result['protocolVersion'].toString();
    }
    await _send('notifications/initialized', notification: true);
    String? cursor;
    final collected = <McpTool>[];
    do {
      final page = await _send('tools/list',
          params: {if (cursor != null) 'cursor': cursor});
      final body = page['result'];
      if (body is! Map || body['tools'] is! List) {
        throw const McpException('tools/list 格式不正確');
      }
      for (final tool in (body['tools'] as List)) {
        if (tool is Map) collected.add(McpTool.fromJson(Map<String, dynamic>.from(tool)));
      }
      cursor = body['nextCursor']?.toString();
    } while (cursor != null && collected.length < 500);
    tools = collected;
    connected = true;
    return tools;
  });

  Future<Map<String, dynamic>> call(String tool, Map<String, dynamic> args) =>
      _exclusive(() async {
        if (!connected || !tools.any((t) => t.name == tool)) {
          throw const McpException('工具未確認或 MCP 尚未連線');
        }
        final rpc = await _send('tools/call', params: {
          'name': tool,
          'arguments': args,
        });
        final body = rpc['result'];
        if (body is! Map) throw const McpException('工具結果格式不正確');
        if (body['isError'] == true) throw const McpException('MCP 工具回報失敗');
        return Map<String, dynamic>.from(body);
      });

  Future<void> _releaseSession() async {
    final cfg = config;
    final sid = _session;
    if (cfg == null || sid == null) return;
    try {
      final request = http.Request('DELETE', cfg.endpoint);
      request.headers.addAll({
        'Authorization': 'Bearer ' + cfg.bearer,
        'Mcp-Session-Id': sid,
        'MCP-Protocol-Version': _protocol,
      });
      final response = await _http.send(request).timeout(const Duration(seconds: 5));
      await response.stream.drain<void>().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Some MCP servers do not implement DELETE. Local state is reset anyway.
    }
  }

  Future<void> disconnect() => _exclusive(() async {
    await _releaseSession();
    connected = false;
    tools = [];
    _session = null;
    config = null;
  });

  void dispose() => _http.close();
}
