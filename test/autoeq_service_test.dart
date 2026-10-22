import 'package:flutter_test/flutter_test.dart';
import '../lib/models/equalizer.dart';
import '../lib/services/autoeq_service.dart';

void main() {
  test('parses AutoEq PEQ response into supported filter types', () {
    final profile = AutoEqProfile.fromResponse(
      name: 'Demo Headphone',
      source: 'oratory1990',
      rig: 'GRAS 43AG-7',
      response: {
        'parametric_eq': {
          'preamp': -5.2,
          'filters': [
            {'type': 'LOW_SHELF', 'fc': 100, 'q': 0.7, 'gain': 3.0},
            {'type': 'PEAKING', 'fc': 1000, 'q': 1.2, 'gain': -2.5},
            {'type': 'HIGH_SHELF', 'fc': 8000, 'q': 0.8, 'gain': 1.5},
          ],
        },
      },
    );

    expect(profile.name, 'Demo Headphone');
    expect(profile.preampDb, -5.2);
    expect(profile.bands, hasLength(3));
    expect(profile.bands[0].type, EqualizerFilterType.lowShelf);
    expect(profile.bands[1].frequency, 1000);
    expect(profile.bands[2].type, EqualizerFilterType.highShelf);
  });

  test('rejects unsupported or invalid AutoEq filters', () {
    expect(
      () => AutoEqProfile.fromResponse(
        name: 'Bad',
        source: 'source',
        rig: 'rig',
        response: {
          'parametric_eq': {
            'filters': [
              {'type': 'NOTCH', 'fc': 1000, 'q': 1, 'gain': 2},
            ],
          },
        },
      ),
      throwsFormatException,
    );
  });
}
