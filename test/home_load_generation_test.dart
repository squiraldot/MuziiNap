import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/utils/home_load_generation.dart';

void main() {
  test('a newer Home load invalidates an older in-flight response', () {
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
