import 'package:youtube_explode_dart/js_challenge.dart';

import 'player_js_service.dart';

class NsigDecipherService {
  NsigDecipherService(this._executor);

  final PlayerJavaScriptExecutor _executor;

  Future<String> decipher(Uri playerUrl, String value) async {
    if (value.isEmpty) {
      throw const FormatException('Missing YouTube n parameter');
    }
    final result = await _executor
        .solve(playerUrl, JSChallengeType.n, value)
        .timeout(const Duration(seconds: 12));
    if (result == null || result.isEmpty || result == value) {
      throw const FormatException('YouTube n parameter was not deciphered');
    }
    return result;
  }
}
