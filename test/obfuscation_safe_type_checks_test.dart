import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application code does not branch on obfuscated runtime type names', () {
    const paths = [
      'lib/models/artist.dart',
      'lib/ui/widgets/content_list_widget.dart',
      'lib/ui/widgets/content_list_widget_item.dart',
      'lib/services/music_service.dart',
      'lib/services/piped_service.dart',
      'lib/ui/player/player_controller.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('runtimeType.toString()')),
        reason: '$path must use type checks that survive Dart AOT obfuscation.',
      );
    }
  });
}
