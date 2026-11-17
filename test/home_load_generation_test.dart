import 'package:flutter_test/flutter_test.dart';
import '../lib/utils/home_load_generation.dart';

void main() {
  test('a newer authenticated Home load invalidates an older anonymous load', () {
    final generation = HomeLoadGeneration();

    final anonymousLoad = generation.begin();
    final authenticatedLoad = generation.begin();

    expect(generation.isCurrent(authenticatedLoad), isTrue);
    expect(generation.isCurrent(anonymousLoad), isFalse);
  });

  test('the current Home load remains valid until another load starts', () {
    final generation = HomeLoadGeneration();
    final currentLoad = generation.begin();

    expect(generation.isCurrent(currentLoad), isTrue);
  });
}
