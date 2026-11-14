import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:muziinap/services/credential_vault.dart';

class MemoryCredentialStorage implements CredentialStorageBackend {
  final Map<String, String> values = {};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('simulated secure-storage failure');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late MemoryCredentialStorage backend;
  late CredentialVault vault;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('credential_vault_');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>('preferences');
    backend = MemoryCredentialStorage();
    vault = CredentialVault(backend: backend);
  });

  tearDown(() async {
    await box.close();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('migrates YouTube multi-account and Piped credentials before deleting Hive copies', () async {
    await box.put('yt_accounts', {
      'account-a': {
        'cookies': 'SAPISID=yt-secret; SID=session',
        'identityToken': 'identity-secret',
        'visitorData': 'visitor-private',
        'accountName': 'Account A',
        'accountPhotoUrl': 'https://example.com/avatar.png',
      },
    });
    await box.put('yt_active_account_key', 'account-a');
    await box.put('yt_cookies', 'SAPISID=yt-secret; SID=session');
    await box.put('yt_identity_token', 'identity-secret');
    await box.put('yt_visitor_data', 'visitor-private');
    await box.put('piped', {
      'isLoggedIn': true,
      'token': 'piped-secret',
      'instApiUrl': 'https://piped.example',
    });

    await vault.migrateLegacyCredentials(box);

    expect(vault.youtubeAccounts['account-a']?['cookies'],
        'SAPISID=yt-secret; SID=session');
    expect(vault.youtubeAccounts['account-a']?['identityToken'],
        'identity-secret');
    expect(vault.activeSession['cookies'], 'SAPISID=yt-secret; SID=session');
    expect(vault.pipedToken, 'piped-secret');
    expect(box.get('yt_accounts')['account-a']['accountName'], 'Account A');
    expect(box.get('yt_accounts')['account-a'].containsKey('cookies'), isFalse);
    expect(box.get('yt_accounts')['account-a'].containsKey('identityToken'), isFalse);
    expect(box.containsKey('yt_cookies'), isFalse);
    expect(box.containsKey('yt_identity_token'), isFalse);
    expect(box.containsKey('yt_visitor_data'), isFalse);
    expect(box.get('piped').containsKey('token'), isFalse);
    expect(jsonDecode(backend.values['muziinap.yt.accounts.v1']!)['account-a']['cookies'],
        'SAPISID=yt-secret; SID=session');
    expect(backend.values['muziinap.piped.token.v1'], 'piped-secret');
  });

  test('does not delete legacy credentials when secure write fails', () async {
    await box.put('yt_cookies', 'SAPISID=legacy-secret');
    await box.put('piped', {
      'isLoggedIn': true,
      'token': 'legacy-piped-secret',
      'instApiUrl': 'https://piped.example',
    });
    backend.failWrites = true;

    await expectLater(
      vault.migrateLegacyCredentials(box),
      throwsA(isA<StateError>()),
    );

    expect(box.get('yt_cookies'), 'SAPISID=legacy-secret');
    expect(box.get('piped')['token'], 'legacy-piped-secret');
    expect(vault.isReady, isFalse);
  });

  test('Piped bearer tokens are stored and cleared only through the secure backend', () async {
    await vault.migrateLegacyCredentials(box);
    await vault.savePipedToken('piped-access-token');

    expect(vault.pipedToken, 'piped-access-token');
    expect(backend.values['muziinap.piped.token.v1'], 'piped-access-token');
    expect(box.get('piped'), isNull);

    await vault.clearPipedToken();
    expect(vault.pipedToken, isNull);
    expect(backend.values.containsKey('muziinap.piped.token.v1'), isFalse);
  });

  test('secure account updates keep sensitive fields out of Hive metadata', () async {
    await vault.migrateLegacyCredentials(box);

    await vault.saveYouTubeAccounts({
      'account-b': {
        'cookies': 'SAPISID=account-b-secret',
        'identityToken': 'account-b-identity',
        'dataSyncId': 'sync-id',
        'accountName': 'Account B',
      },
    }, legacyBox: box);

    expect(vault.youtubeAccounts['account-b']?['cookies'],
        'SAPISID=account-b-secret');
    expect(box.get('yt_accounts')['account-b']['accountName'], 'Account B');
    expect(box.get('yt_accounts')['account-b'].containsKey('cookies'), isFalse);
    expect(box.get('yt_accounts')['account-b'].containsKey('dataSyncId'), isFalse);
  });
}
