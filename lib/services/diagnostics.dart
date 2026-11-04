import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class Redactor {
  static String clean(String raw) {
    var result = raw;
    result = result.replaceAllMapped(
      RegExp(r'Bearer\s+[A-Za-z0-9._~+/-]+', caseSensitive: false),
      (_) => 'Bearer [REDACTED]',
    );
    result = result.replaceAllMapped(
      RegExp(r'AIza[0-9A-Za-z_-]{20,}'),
      (_) => '[GEMINI_KEY_REDACTED]',
    );
    result = result.replaceAllMapped(
      RegExp(r'ebo_mcp_[A-Za-z0-9_-]+', caseSensitive: false),
      (_) => '[MCP_KEY_REDACTED]',
    );
    result = result.replaceAllMapped(
      RegExp(r'(rtsp://)[^/\s@]+@', caseSensitive: false),
      (m) => m.group(1)! + '[REDACTED]@',
    );
    result = result.replaceAllMapped(
      RegExp(r'((?:key|token|accesskey|authorization)["\x27]?\s*[:=]\s*["\x27]?)[^\s,"}\x27]+',
          caseSensitive: false),
      (m) => m.group(1)! + '[REDACTED]',
    );
    return result;
  }
}

class DiagnosticEvent {
  final DateTime timestamp;
  final String level;
  final String component;
  final String message;
  DiagnosticEvent(this.timestamp, this.level, this.component, this.message);

  Map<String, dynamic> toJson() => {
    'time': timestamp.toUtc().toIso8601String(),
    'level': level,
    'component': component,
    'message': message,
  };
}

class Diagnostics extends ChangeNotifier {
  final List<DiagnosticEvent> events = [];
  static const limit = 500;

  void log(String component, String message, {String level = 'INFO'}) {
    final safe = Redactor.clean(message);
    events.add(DiagnosticEvent(DateTime.now(), level, component, safe));
    if (events.length > limit) events.removeAt(0);
    notifyListeners();
    if (kDebugMode) debugPrint('[$component][$level] $safe');
  }

  void clear() {
    events.clear();
    notifyListeners();
  }

  Future<File> writeExport({
    required bool mcpOnline,
    required int toolCount,
  }) async {
    final package = await PackageInfo.fromPlatform();
    final dir = await getTemporaryDirectory();
    final file = File(
      dir.path + '/ebo_diagnostic_' + DateTime.now().millisecondsSinceEpoch.toString() + '.jsonl',
    );
    final lines = <String>[
      jsonEncode({
        'type': 'metadata',
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'appVersion': package.version,
        'buildNumber': package.buildNumber,
        'platform': Platform.operatingSystem,
        'mcpOnline': mcpOnline,
        'discoveredTools': toolCount,
        'privacy': 'no raw credentials, prompts, voice files, or RTSP frames',
      }),
      ...events.map((e) => jsonEncode({'type': 'event', ...e.toJson()})),
    ];
    await file.writeAsString(lines.join('\n') + '\n', flush: true);
    return file;
  }

  Future<void> shareExport({
    required bool mcpOnline,
    required int toolCount,
  }) async {
    final file = await writeExport(mcpOnline: mcpOnline, toolCount: toolCount);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      text: 'EBO Controller diagnostic log (credentials removed)',
    ));
  }
}
