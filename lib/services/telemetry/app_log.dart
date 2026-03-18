import 'dart:convert';

import 'package:flutter/foundation.dart';

enum AppLogLevel { debug, info, warn, error }

class AppLogEntry {
  final DateTime at;
  final AppLogLevel level;
  final String category;
  final String message;
  final Map<String, Object?> data;
  final String? error;
  final String? stackTrace;

  const AppLogEntry({
    required this.at,
    required this.level,
    required this.category,
    required this.message,
    required this.data,
    this.error,
    this.stackTrace,
  });

  Map<String, Object?> toJson() => {
        'at': at.toIso8601String(),
        'level': level.name,
        'category': category,
        'message': message,
        'data': data,
        'error': error,
        'stackTrace': stackTrace,
      };

  static AppLogEntry? fromJson(Object? obj) {
    if (obj is! Map) return null;
    final m = Map<String, Object?>.from(obj);

    final atRaw = m['at'] as String?;
    final levelRaw = m['level'] as String?;
    final category = (m['category'] as String?) ?? 'app';
    final message = (m['message'] as String?) ?? '';
    final dataRaw = m['data'];

    if (atRaw == null || levelRaw == null) return null;
    final at = DateTime.tryParse(atRaw);
    if (at == null) return null;

    final level = AppLogLevel.values.cast<AppLogLevel?>().firstWhere(
          (v) => v?.name == levelRaw,
          orElse: () => null,
        ) ??
        AppLogLevel.info;

    final data = <String, Object?>{};
    if (dataRaw is Map) {
      data.addAll(Map<String, Object?>.from(dataRaw));
    }

    return AppLogEntry(
      at: at,
      level: level,
      category: category,
      message: message,
      data: data,
      error: m['error'] as String?,
      stackTrace: m['stackTrace'] as String?,
    );
  }

  String toLine() {
    final ts = at.toIso8601String();
    final d = data.isEmpty ? '' : ' data=${jsonEncode(data)}';
    final err = error == null ? '' : '\n  error=$error';
    final st = stackTrace == null ? '' : '\n  stackTrace=$stackTrace';
    return '[$ts] ${level.name.toUpperCase()} [$category] $message$d$err$st';
  }
}

class AppLogStore extends ChangeNotifier {
  AppLogStore({this.capacity = 400});

  final int capacity;
  final List<AppLogEntry> _entries = [];

  List<AppLogEntry> get entries => List.unmodifiable(_entries);

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  void log(
    AppLogLevel level,
    String category,
    String message, {
    Map<String, Object?> data = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    final entry = AppLogEntry(
      at: DateTime.now(),
      level: level,
      category: category,
      message: message,
      data: Map<String, Object?>.from(data),
      error: error?.toString(),
      stackTrace: stackTrace?.toString(),
    );

    _entries.add(entry);
    if (_entries.length > capacity) {
      _entries.removeRange(0, _entries.length - capacity);
    }

    notifyListeners();
  }

  void debug(String category, String message, {Map<String, Object?> data = const {}}) =>
      log(AppLogLevel.debug, category, message, data: data);

  void info(String category, String message, {Map<String, Object?> data = const {}}) =>
      log(AppLogLevel.info, category, message, data: data);

  void warn(String category, String message, {Map<String, Object?> data = const {}}) =>
      log(AppLogLevel.warn, category, message, data: data);

  void error(
    String category,
    String message, {
    Map<String, Object?> data = const {},
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        AppLogLevel.error,
        category,
        message,
        data: data,
        error: error,
        stackTrace: stackTrace,
      );

  String exportText({int maxLines = 800}) {
    final tail = _entries.length <= maxLines
        ? _entries
        : _entries.sublist(_entries.length - maxLines);
    return '${tail.map((e) => e.toLine()).join('\n')}\n';
  }
}
