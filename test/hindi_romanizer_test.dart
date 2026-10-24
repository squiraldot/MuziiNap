import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/utils/hindi_romanizer.dart';

void main() {
  group('HindiRomanizer.transliterate', () {
    test('converts Hindi Devanagari to Roman script without translating', () {
      expect(HindiRomanizer.transliterate('नमस्ते'), 'namaste');
      expect(HindiRomanizer.transliterate('भारत'), 'bhaarat');
    });

    test('preserves line breaks, punctuation, and Latin words', () {
      expect(
        HindiRomanizer.transliterate('दिल है!\nI love you, दोस्त.'),
        'dil hai!\nI love you, dost.',
      );
    });

    test('handles empty text and mixed scripts safely', () {
      expect(HindiRomanizer.transliterate(''), '');
      expect(HindiRomanizer.transliterate('Hello दुनिया 123'), 'Hello duniya 123');
      expect(HindiRomanizer.transliterate('🙂 — गीत'), '🙂 — geet');
    });
  });
}
