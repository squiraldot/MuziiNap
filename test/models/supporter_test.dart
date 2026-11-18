import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/models/supporter.dart';

void main() {
  test('parses supporter and ignores unknown keys', () {
    final response = SupportersResponse.fromJson({
      'updated_at': '2026-11-16T10:00:00.000Z', 'total': 1, 'future': true,
      'supporters': [{
        'name': 'Alex', 'message': 'Keep up the music!', 'amount': 15,
        'currency': 'USD', 'supported_at': '2026-11-15T10:00:00.000Z',
        'private_event_id': 'ignored',
      }],
    });
    expect(response.supporters.single.name, 'Alex');
    expect(response.supporters.single.amount, 15);
    expect(response.supporters.single.message, 'Keep up the music!');
  });

  test('handles anonymous name and missing nullable fields', () {
    final s = Supporter.fromJson({'name': null, 'message': null});
    expect(s.name, 'Anonymous supporter');
    expect(s.message, isNull);
    expect(s.amount, isNull);
    expect(s.currency, isNull);
    expect(s.supportedAt, isNull);
  });

  test('rejects malformed timestamps and invalid field types', () {
    expect(() => Supporter.fromJson({'name': 'A', 'supported_at': 'bad'}), throwsFormatException);
    expect(() => Supporter.fromJson({'name': 42}), throwsFormatException);
    expect(() => Supporter.fromJson({'name': 'A', 'amount': '15'}), throwsFormatException);
  });

  test('accepts an authoritative empty response', () {
    final r = SupportersResponse.fromJson({'total': 0, 'supporters': <Object>[]});
    expect(r.total, 0);
    expect(r.supporters, isEmpty);
  });

  test('caps records at ten and preserves backend order', () {
    final r = SupportersResponse.fromJson({
      'total': 11, 'supporters': List.generate(11, (i) => {'name': 'User $i'}),
    });
    expect(r.supporters, hasLength(10));
    expect(r.supporters.first.name, 'User 0');
    expect(r.supporters.last.name, 'User 9');
  });

  test('rejects malformed response shape', () {
    expect(() => SupportersResponse.fromJson({'total': '0', 'supporters': []}), throwsFormatException);
  });
}