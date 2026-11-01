import 'package:youtube_explode_dart/js_challenge.dart';

import 'player_js_service.dart';

class SignatureDecipherService {
  SignatureDecipherService(this._executor);

  final PlayerJavaScriptExecutor _executor;

  Future<String> decipher(Uri playerUrl, String value) async {
    if (value.isEmpty) {
      throw const FormatException('Missing encrypted YouTube signature');
    }
    final result = await _executor
        .solve(playerUrl, JSChallengeType.sig, value)
        .timeout(const Duration(seconds: 12));
    if (result == null || result.isEmpty || result == value) {
      throw const FormatException('YouTube signature was not deciphered');
    }
    return result;
  }
}
