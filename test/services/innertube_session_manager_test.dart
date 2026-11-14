import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:muziinap/services/innertube_session_manager.dart';
import 'package:muziinap/services/credential_vault.dart';

class MemoryCredentialStorage implements CredentialStorageBackend {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  late Directory tempDirectory;
  late Box<dynamic> box;
  late InnerTubeSessionManager manager;
  late CredentialVault vault;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('innertube_session_');
    Hive.init(tempDirectory.path);
    box = await Hive.openBox<dynamic>('test_preferences');
    vault = CredentialVault(backend: MemoryCredentialStorage());
    await vault.migrateLegacyCredentials(box);
    manager = InnerTubeSessionManager(box: box, credentialVault: vault);
  });

  tearDown(() async {
    await box.close();
    await Hive.close();
    await tempDirectory.delete(recursive: true);
  });

  test('creates WEB_REMIX headers with a valid SAPISIDHASH', () async {
    await manager.storeCookies('SAPISID=secret-value; SID=session-value');

    final headers =
        manager.getAuthenticatedHeaders('https://music.youtube.com/youtubei/v1/browse');
    final authorization = headers['authorization']!;
    final match = RegExp(r'^SAPISIDHASH (\d+)_([a-f0-9]{40})$')
        .firstMatch(authorization);

    expect(match, isNotNull);
    final timestamp = match!.group(1)!;
    final expected = sha1Hex(
      '$timestamp secret-value https://music.youtube.com',
    );
    expect(match.group(2), expected);
    expect(headers['x-youtube-client-name'], '67');
    expect(headers['content-type'], 'application/json');
    expect(headers['cookie'], 'SAPISID=secret-value; SID=session-value');
  });

  test('rejects non-YouTube origins before exposing session credentials',
      () async {
    await manager.storeCookies('SAPISID=secret-value');

    expect(
      () => manager.getAuthenticatedHeaders('https://attacker.example/path'),
      throwsA(
        isA<InnerTubeSessionException>().having(
          (error) => error.code,
          'code',
          InnerTubeSessionError.untrustedOrigin,
        ),
      ),
    );
  });

  test('reports missing SAPISID instead of creating anonymous auth headers',
      () async {
    await vault.saveActiveSession({'cookies': 'SID=session-value'});

    expect(
      () => manager.getAuthenticatedHeaders('https://music.youtube.com'),
      throwsA(
        isA<InnerTubeSessionException>().having(
          (error) => error.code,
          'code',
          InnerTubeSessionError.missingSapisid,
        ),
      ),
    );
  });

  test('rejects an explicitly expired session', () async {
    await expectLater(
      manager.storeCookies(
        'SAPISID=secret-value',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
      throwsA(isA<InnerTubeSessionException>().having(
        (error) => error.code,
        'code',
        InnerTubeSessionError.expired,
      )),
    );
  });
}

String sha1Hex(String value) {
  return sha1.convert(utf8.encode(value)).toString();
}
