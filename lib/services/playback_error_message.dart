import 'package:just_audio/just_audio.dart';

/// Converts a playback failure into the message shown to the user.
///
/// Keep native player codes and original exception details so failures are
/// diagnosable instead of collapsing every playback error into "networkError".
String playbackErrorMessage(Object error) {
  if (error is PlayerException) {
    final details = error.message?.trim();
    if (details != null && details.isNotEmpty) {
      return 'Playback error (${error.code}): $details';
    }
    return 'Playback failed (code ${error.code})';
  }

  final message = error.toString().trim();
  if (message.isNotEmpty) return message;

  return 'Playback failed (${error.runtimeType})';
}
