/// Offline Hindi (Devanagari) to Roman Hindi transliteration.
///
/// This intentionally changes script only; it does not translate meaning.
/// Characters outside the supported Devanagari range are preserved verbatim.
class HindiRomanizer {
  HindiRomanizer._();

  static final Map<String, String> _cache = <String, String>{};

  static const _independentVowels = <int, String>{
    0x0905: 'a', 0x0906: 'aa', 0x0907: 'i', 0x0908: 'ee',
    0x0909: 'u', 0x090A: 'oo', 0x090B: 'ri', 0x090F: 'e',
    0x0910: 'ai', 0x0913: 'o', 0x0914: 'au',
  };

  static const _consonants = <int, String>{
    0x0915: 'k', 0x0916: 'kh', 0x0917: 'g', 0x0918: 'gh', 0x0919: 'ng',
    0x091A: 'ch', 0x091B: 'chh', 0x091C: 'j', 0x091D: 'jh', 0x091E: 'ny',
    0x091F: 'T', 0x0920: 'Th', 0x0921: 'D', 0x0922: 'Dh', 0x0923: 'N',
    0x0924: 't', 0x0925: 'th', 0x0926: 'd', 0x0927: 'dh', 0x0928: 'n',
    0x092A: 'p', 0x092B: 'ph', 0x092C: 'b', 0x092D: 'bh', 0x092E: 'm',
    0x092F: 'y', 0x0930: 'r', 0x0932: 'l', 0x0935: 'v', 0x0936: 'sh',
    0x0937: 'Sh', 0x0938: 's', 0x0939: 'h', 0x0958: 'q', 0x0959: 'kh',
    0x095A: 'gh', 0x095B: 'z', 0x095C: 'R', 0x095D: 'Rh', 0x095E: 'f',
    0x095F: 'y',
  };

  static const _matras = <int, String>{
    0x093E: 'aa', 0x093F: 'i', 0x0940: 'ee', 0x0941: 'u',
    0x0942: 'oo', 0x0943: 'ri', 0x0947: 'e', 0x0948: 'ai',
    0x094B: 'o', 0x094C: 'au',
  };

  static String transliterate(String input) {
    final cached = _cache[input];
    if (cached != null) return cached;
    final result = input.splitMapJoin(
      RegExp(r'[\u0900-\u097F]+'),
      onMatch: (match) => _transliterateDevanagari(match[0]!),
      onNonMatch: (text) => text,
    );
    // Keep the cache bounded for long sessions with many different songs.
    if (_cache.length >= 200) _cache.clear();
    _cache[input] = result;
    return result;
  }

  static String _transliterateDevanagari(String input) {
    final output = StringBuffer();
    final runes = input.runes.toList();
    var i = 0;
    while (i < runes.length) {
      final rune = runes[i];
      final consonant = _consonants[rune];
      if (consonant != null) {
        output.write(consonant);
        final next = i + 1 < runes.length ? runes[i + 1] : null;
        if (next == 0x094D) {
          i += 2;
          continue;
        }
        if (next != null && _matras.containsKey(next)) {
          output.write(_matras[next]!);
          i += 2;
          continue;
        }
        output.write('a');
        i++;
        continue;
      }
      final vowel = _independentVowels[rune];
      if (vowel != null) {
        output.write(vowel);
      } else if (rune == 0x0902 || rune == 0x0901) {
        output.write('n');
      } else if (rune == 0x0903) {
        output.write('h');
      } else if (rune == 0x093C || rune == 0x094D) {
        // Nukta and virama are handled with their preceding consonant.
      } else {
        output.writeCharCode(rune);
      }
      i++;
    }
    var result = output.toString();
    // Omit the final inherent schwa in the common Hindi word-final case.
    if (runes.isNotEmpty && _consonants.containsKey(runes.last) && result.endsWith('a')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
