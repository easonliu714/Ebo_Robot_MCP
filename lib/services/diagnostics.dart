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
  File? _persistentFile;
  Future<void> _writes = Future<void>.value();

  Future<void> initialize() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _persistentFile = File(dir.path + '/ebo_events.jsonl');
      final file = _persistentFile!;
      if (await file.exists()) {
        final lines = await file.readAsLines();
        for (final line in lines.skip(lines.length > limit ? lines.length - limit : 0)) {
          try {
            final obj = jsonDecode(line);
            if (obj is! Map) continue;
            final time = DateTime.tryParse(obj['time']?.toString() ?? '');
            if (time == null) continue;
            events.add(DiagnosticEvent(time, obj['level']?.toString() ?? 'INFO',
                obj['component']?.toString() ?? 'APP',
                Redactor.clean(obj['message']?.toString() ?? '')));
          } catch (_) {
            // Ignore a truncated line left by a sudden process termination.
          }
        }
      }
      notifyListeners();
    } catch (_) {
      // Diagnostics remain usable in memory if the filesystem is unavailable.
    }
  }

  void _persist(DiagnosticEvent event) {
    _writes = _writes.then((_) async {
      final file = _persistentFile;
      if (file == null) return;
      if (await file.exists() && await file.length() > 512 * 1024) {
        final recent = events.skip(events.length > 250 ? events.length - 250 : 0)
            .map((e) => jsonEncode(e.toJson())).join('\n');
        await file.writeAsString(recent + '\n', flush: true);
      } else {
        await file.writeAsString(jsonEncode(event.toJson()) + '\n',
            mode: FileMode.append, flush: true);
      }
    }).catchError((Object _) {
      // Logging must never break robot controls.
    });
  }

  void log(String component, String message, {String level = 'INFO'}) {
    final safe = Redactor.clean(message);
    final event = DiagnosticEvent(DateTime.now(), level, component, safe);
    events.add(event);
    if (events.length > limit) events.removeAt(0);
    _persist(event);
    notifyListeners();
    if (kDebugMode) debugPrint('[$component][$level] $safe');
  }

  void clear() {
    events.clear();
    _writes = _writes.then((_) async {
      await _persistentFile?.writeAsString('');
    });
    notifyListeners();
  }

  Future<File> writeExport({
    required bool mcpOnline,
    required int toolCount,
  }) async {
    await _writes;
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
