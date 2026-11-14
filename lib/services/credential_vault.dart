import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

/// Minimal boundary so migration and account handling can be tested without
/// invoking platform channels.
abstract interface class CredentialStorageBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterCredentialStorageBackend implements CredentialStorageBackend {
  FlutterCredentialStorageBackend()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(migrateWithBackup: true),
        );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Owns all account/session credentials. Android values are encrypted by
/// flutter_secure_storage using an Android Keystore-wrapped AES-GCM key.
class CredentialVault {
  CredentialVault({required CredentialStorageBackend backend})
      : _backend = backend;

  static final CredentialVault instance = CredentialVault(
    backend: FlutterCredentialStorageBackend(),
  );

  static const String _accountsKey = 'muziinap.yt.accounts.v1';
  static const String _activeSessionKey = 'muziinap.yt.active_session.v1';
  static const String _pipedTokenKey = 'muziinap.piped.token.v1';

  static const Set<String> _sensitiveAccountFields = {
    'cookies',
    'visitorData',
    'dataSyncId',
    'authUser',
    'identityToken',
  };

  final CredentialStorageBackend _backend;
  final Map<String, Map<String, dynamic>> _accounts = {};
  Map<String, dynamic> _activeSession = {};
  String? _pipedToken;
  bool _ready = false;

  bool get isReady => _ready;
  String? get pipedToken => _pipedToken?.isNotEmpty == true ? _pipedToken : null;
  Map<String, dynamic> get activeSession =>
      Map<String, dynamic>.from(_activeSession);

  Map<String, dynamic> get youtubeAccounts => {
        for (final entry in _accounts.entries)
          entry.key: Map<String, dynamic>.from(entry.value),
      };

  /// Migrates old Hive credentials only after secure writes have been read
  /// back and verified. If any secure operation fails, legacy Hive values are
  /// left untouched so the user does not lose their sessions.
  Future<void> migrateLegacyCredentials(Box<dynamic> legacyBox) async {
    final secureAccounts = _decodeMap(await _backend.read(_accountsKey));
    final legacyAccountsRaw = legacyBox.get('yt_accounts');
    final legacyAccounts = legacyAccountsRaw is Map
        ? legacyAccountsRaw.map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : <String, dynamic>{};

    final mergedAccounts = <String, Map<String, dynamic>>{};
    for (final key in {...secureAccounts.keys, ...legacyAccounts.keys}) {
      final secureValue = secureAccounts[key];
      final legacyValue = legacyAccounts[key];
      final secureRecord = secureValue is Map
          ? Map<String, dynamic>.from(secureValue)
          : <String, dynamic>{};
      final legacyRecord = legacyValue is Map
          ? Map<String, dynamic>.from(legacyValue)
          : <String, dynamic>{};
      final merged = <String, dynamic>{...secureRecord, ...legacyRecord};
      for (final field in _sensitiveAccountFields) {
        if (secureRecord.containsKey(field)) {
          merged[field] = secureRecord[field];
        }
      }
      mergedAccounts[key] = merged;
    }

    final secureActive = _decodeMap(await _backend.read(_activeSessionKey));
    final legacyActive = <String, dynamic>{
      'cookies': legacyBox.get('yt_cookies'),
      'visitorData': legacyBox.get('yt_visitor_data'),
      'dataSyncId': legacyBox.get('yt_data_sync_id'),
      'authUser': legacyBox.get('yt_auth_user'),
      'identityToken': legacyBox.get('yt_identity_token'),
    }..removeWhere((key, value) => value == null);
    final mergedActive = <String, dynamic>{...legacyActive, ...secureActive};

    final activeKey = legacyBox.get('yt_active_account_key')?.toString();
    if (activeKey != null && mergedAccounts[activeKey] != null) {
      final activeAccount = mergedAccounts[activeKey]!;
      for (final field in _sensitiveAccountFields) {
        if (!mergedActive.containsKey(field) && activeAccount[field] != null) {
          mergedActive[field] = activeAccount[field];
        }
      }
    }

    final pipedRaw = legacyBox.get('piped');
    final legacyPipedToken =
        pipedRaw is Map ? pipedRaw['token']?.toString() : null;
    final securePipedToken = await _backend.read(_pipedTokenKey);
    final mergedPipedToken = securePipedToken ??
        (legacyPipedToken?.isNotEmpty == true ? legacyPipedToken : null);

    // Persist all secrets first, then verify the exact stored payloads.
    if (mergedAccounts.isNotEmpty) {
      await _writeAndVerify(_accountsKey, jsonEncode(mergedAccounts));
    }
    if (mergedActive.isNotEmpty) {
      await _writeAndVerify(_activeSessionKey, jsonEncode(mergedActive));
    }
    if (mergedPipedToken != null) {
      await _writeAndVerify(_pipedTokenKey, mergedPipedToken);
    }

    // Only after every required secure write succeeds may plaintext Hive
    // credentials be removed. Keep account display metadata and Piped URL.
    if (legacyAccounts.isNotEmpty || mergedAccounts.isNotEmpty) {
      await legacyBox.put('yt_accounts', _safeAccounts(mergedAccounts));
    }
    for (final key in const [
      'yt_cookies',
      'yt_visitor_data',
      'yt_data_sync_id',
      'yt_auth_user',
      'yt_identity_token',
    ]) {
      await legacyBox.delete(key);
    }
    if (pipedRaw is Map) {
      final safePiped = Map<String, dynamic>.from(pipedRaw)
        ..remove('token');
      await legacyBox.put('piped', safePiped);
    }

    _accounts
      ..clear()
      ..addAll(mergedAccounts);
    _activeSession = mergedActive;
    _pipedToken = mergedPipedToken;
    _ready = true;
  }

  Future<void> saveYouTubeAccounts(
    Map<String, dynamic> accounts, {
    Box<dynamic>? legacyBox,
  }) async {
    final normalized = <String, Map<String, dynamic>>{
      for (final entry in accounts.entries)
        entry.key: Map<String, dynamic>.from(entry.value as Map),
    };
    final encoded = jsonEncode(normalized);
    await _writeAndVerify(_accountsKey, encoded);
    _accounts
      ..clear()
      ..addAll(normalized);
    if (legacyBox != null) {
      await legacyBox.put('yt_accounts', _safeAccounts(normalized));
    }
    _ready = true;
  }

  Future<void> saveActiveSession(Map<String, dynamic> session) async {
    final normalized = Map<String, dynamic>.from(session)
      ..removeWhere((key, value) => value == null);
    final encoded = jsonEncode(normalized);
    await _writeAndVerify(_activeSessionKey, encoded);
    _activeSession = normalized;
    _ready = true;
  }

  Future<void> clearActiveSession() async {
    await _backend.delete(_activeSessionKey);
    _activeSession = {};
  }

  Future<void> savePipedToken(String token) async {
    if (token.isEmpty) {
      throw ArgumentError.value(token, 'token', 'Token cannot be empty.');
    }
    await _writeAndVerify(_pipedTokenKey, token);
    _pipedToken = token;
    _ready = true;
  }

  Future<void> clearPipedToken() async {
    await _backend.delete(_pipedTokenKey);
    _pipedToken = null;
  }

  Future<void> clearYouTubeData() async {
    await _backend.delete(_accountsKey);
    await clearActiveSession();
    _accounts.clear();
  }

  Future<void> removeYouTubeAccount(
    String accountKey, {
    Box<dynamic>? legacyBox,
  }) async {
    final updated = youtubeAccounts..remove(accountKey);
    await saveYouTubeAccounts(updated, legacyBox: legacyBox);
  }

  Future<void> _writeAndVerify(String key, String value) async {
    await _backend.write(key, value);
    final stored = await _backend.read(key);
    if (stored != value) {
      throw StateError('Secure credential verification failed.');
    }
  }

  static Map<String, dynamic> _decodeMap(String? encoded) {
    if (encoded == null || encoded.isEmpty) return {};
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('Secure credential payload is invalid.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static Map<String, dynamic> _safeAccounts(
    Map<String, Map<String, dynamic>> accounts,
  ) {
    return {
      for (final entry in accounts.entries)
        entry.key: Map<String, dynamic>.from(entry.value)
          ..removeWhere(
            (key, value) => _sensitiveAccountFields.contains(key),
          ),
    };
  }
}
