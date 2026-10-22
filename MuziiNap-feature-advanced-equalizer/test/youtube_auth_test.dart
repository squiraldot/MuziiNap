import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/youtube_auth.dart';

void main() {
  test('parses a primary channel dataSyncId', () {
    final identity = YouTubeSessionIdentity.fromDataSyncId(
      'USER_SESSION_ID||',
      authUser: '0',
    );

    expect(identity.delegatedSessionId, isNull);
    expect(identity.userSessionId, 'USER_SESSION_ID');
    expect(identity.authUser, '0');
    expect(identity.accountKey, '0:USER_SESSION_ID');
  });

  test('parses a delegated brand channel dataSyncId', () {
    final identity = YouTubeSessionIdentity.fromDataSyncId(
      'DELEGATED_SESSION_ID||USER_SESSION_ID',
      authUser: '1',
    );

    expect(identity.delegatedSessionId, 'DELEGATED_SESSION_ID');
    expect(identity.userSessionId, 'USER_SESSION_ID');
    expect(identity.authUser, '1');
    expect(identity.accountKey, '1:DELEGATED_SESSION_ID');
  });

  test('falls back safely when dataSyncId is absent', () {
    final identity = YouTubeSessionIdentity.fromDataSyncId(null);

    expect(identity.delegatedSessionId, isNull);
    expect(identity.userSessionId, isNull);
    expect(identity.authUser, '0');
    expect(identity.accountKey, '0:primary');
  });

  test('builds a stable home context signature', () {
    expect(
      YouTubeHomeContextSignature.build(language: 'en', country: 'IN'),
      'en|IN',
    );
    expect(
      YouTubeHomeContextSignature.build(language: 'hi', country: 'IN'),
      'hi|IN',
    );
  });
}
