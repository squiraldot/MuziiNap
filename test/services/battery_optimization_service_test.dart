import 'package:flutter_test/flutter_test.dart';
import 'package:muziinap/services/battery_optimization_service.dart';

void main() {
  test('battery optimization request targets the installed Android application', () {
    expect(
      BatteryOptimizationService.applicationId,
      'com.merrmist.muziinapmusic',
    );
  });
}
