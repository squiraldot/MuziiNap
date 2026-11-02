import 'package:flutter_test/flutter_test.dart';

import '../../lib/services/device_adaptive_stream_selector.dart';

void main() {
  group('DeviceStreamProfile.androidLoadControl', () {
    test('never configures min buffer below the rebuffer reserve', () {
      for (final apiLevel in [null, 28, 29, 35]) {
        for (final isLowRam in [false, true]) {
          for (final network in DeviceNetworkType.values) {
            final profile = DeviceStreamProfile(
              androidApiLevel: apiLevel,
              isLowRamDevice: isLowRam,
              networkType: network,
            );
            final loadControl = profile.androidLoadControl;

            expect(
              loadControl.minBufferDuration,
              greaterThanOrEqualTo(
                loadControl.bufferForPlaybackAfterRebufferDuration,
              ),
              reason: 'Invalid buffer policy for api=$apiLevel, '
                  'lowRam=$isLowRam, network=$network',
            );
          }
        }
      }
    });
  });
}
