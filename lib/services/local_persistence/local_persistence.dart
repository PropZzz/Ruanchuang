import 'dart:convert';

/// Minimal persistence primitive for LocalDataService.
///
/// Implemented with File on IO platforms and localStorage on Web.
abstract class LocalPersistence {
  Future<bool> exists();
  Future<String?> read();
  Future<void> write(String content);
}

/// Tiny test seam for LocalDataService without touching runtime storage.
class InMemoryLocalPersistence implements LocalPersistence {
  String? _content;

  @override
  Future<bool> exists() async => _content != null;

  @override
  Future<String?> read() async => _content;

  @override
  Future<void> write(String content) async {
    _content = content;
  }
}

/// Stores a separate local snapshot for the guest and each signed-in account.
class SessionScopedLocalPersistence implements LocalPersistence {
  SessionScopedLocalPersistence(this._delegate);

  static const guestScope = 'guest';
  static const _unassignedLegacyScope = 'legacy:unassigned';
  static const _sessionKey = '_sessionLocalData';
  static const _sessionVersion = 1;

  final LocalPersistence _delegate;
  final Map<String, String> _snapshots = {};
  String _activeScope = guestScope;
  bool _loaded = false;

  String get activeScope => _activeScope;

  static String accountScope(String contactAddress) =>
      'account:${contactAddress.trim()}';

  Future<void> _reload() async {
    final raw = await _delegate.read();
    _snapshots.clear();
    _activeScope = guestScope;
    _loaded = true;
    if (raw == null || raw.trim().isEmpty) return;

    Map<String, Object?>? root;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) root = Map<String, Object?>.from(decoded);
    } catch (_) {
      _snapshots[guestScope] = raw;
      return;
    }

    final session = root?[_sessionKey];
    if (session is Map && session['version'] == _sessionVersion) {
      final snapshots = session['snapshots'];
      if (snapshots is Map) {
        for (final entry in snapshots.entries) {
          if (entry.key is String && entry.value is String) {
            _snapshots[entry.key as String] = entry.value as String;
          }
        }
      }
      final activeScope = session['activeScope'];
      if (activeScope is String && activeScope.isNotEmpty) {
        _activeScope = activeScope;
      }
      final activeSnapshot = Map<String, Object?>.from(root!)
        ..remove(_sessionKey);
      if (activeSnapshot.containsKey('version')) {
        _snapshots[_activeScope] = jsonEncode(activeSnapshot);
      }
      return;
    }

    final currentUser = root?['currentUser'];
    final contactAddress = currentUser is Map
        ? currentUser['contactAddress']
        : null;
    if (contactAddress is String && contactAddress.trim().isNotEmpty) {
      _activeScope = accountScope(contactAddress);
      _snapshots[_activeScope] = raw;
    } else if (root?.containsKey('currentUser') ?? false) {
      _activeScope = guestScope;
      _snapshots[_unassignedLegacyScope] = raw;
    } else {
      _activeScope = guestScope;
      _snapshots[guestScope] = raw;
    }
  }

  Future<void> _persist() async {
    Map<String, Object?> root = {};
    final activeSnapshot = _snapshots[_activeScope];
    if (activeSnapshot != null) {
      try {
        final decoded = jsonDecode(activeSnapshot);
        if (decoded is Map) root = Map<String, Object?>.from(decoded);
      } catch (_) {
        root = {};
      }
    }
    final otherSnapshots = Map<String, String>.from(_snapshots)
      ..remove(_activeScope);
    root[_sessionKey] = {
      'version': _sessionVersion,
      'activeScope': _activeScope,
      'snapshots': otherSnapshots,
    };
    await _delegate.write(jsonEncode(root));
  }

  Future<void> selectScope(String scope) async {
    if (!_loaded) await _reload();
    if (_activeScope == scope) return;

    final previousScope = _activeScope;
    _activeScope = scope;
    try {
      await _persist();
    } catch (_) {
      _activeScope = previousScope;
      rethrow;
    }
  }

  @override
  Future<bool> exists() async {
    await _reload();
    return _snapshots.containsKey(_activeScope);
  }

  @override
  Future<String?> read() async {
    await _reload();
    return _snapshots[_activeScope];
  }

  @override
  Future<void> write(String content) async {
    if (!_loaded) await _reload();
    _snapshots[_activeScope] = content;
    await _persist();
  }
}
