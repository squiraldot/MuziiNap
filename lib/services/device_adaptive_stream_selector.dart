import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:just_audio/just_audio.dart';

/// Network transport categories used by the adaptive stream policy.
enum DeviceNetworkType { wifi, mobile, offline, other }

/// Immutable, isolate-safe snapshot of the device capabilities relevant to
/// stream selection. It contains only primitive values and can cross isolates.
class DeviceStreamProfile {
  const DeviceStreamProfile({
    required this.androidApiLevel,
    required this.isLowRamDevice,
    required this.networkType,
  });

  final int? androidApiLevel;
  final bool isLowRamDevice;
  final DeviceNetworkType networkType;

  bool get isLegacyAndroid =>
      androidApiLevel != null && androidApiLevel! < 29;

  /// Opus is reserved for API 29+ devices that are not marked low-RAM and
  /// currently use Wi-Fi. Cellular networks intentionally prefer AAC.
  bool get prefersOpus =>
      allowsOpus &&
      !isLowRamDevice &&
      networkType == DeviceNetworkType.wifi;

  // Unknown API level is treated conservatively like a legacy device.
  bool get allowsOpus =>
      androidApiLevel != null && androidApiLevel! >= 29;

  bool get requiresWebClient => !allowsOpus;

  int get preferredItag => prefersOpus ? 251 : 140;

  /// Reuses the hardware snapshot while updating only the network category.
  DeviceStreamProfile withNetworkType(DeviceNetworkType nextNetworkType) =>
      DeviceStreamProfile(
        androidApiLevel: androidApiLevel,
        isLowRamDevice: isLowRamDevice,
        networkType: nextNetworkType,
      );

  /// ExoPlayer buffer profile selected once before AudioPlayer construction.
  /// A constrained device gets a smaller ceiling; capable Wi-Fi devices use
  /// the requested 30-second ceiling and 1.5-second startup reserve.
  AndroidLoadControl get androidLoadControl {
    final Duration minBuffer;
    final Duration maxBuffer;

    if (isLowRamDevice ||
        (!allowsOpus && networkType != DeviceNetworkType.mobile)) {
      minBuffer = const Duration(milliseconds: 2500);
      maxBuffer = const Duration(seconds: 12);
    } else if (prefersOpus) {
      minBuffer = const Duration(seconds: 2);
      maxBuffer = const Duration(seconds: 30);
    } else if (networkType == DeviceNetworkType.mobile) {
      minBuffer = const Duration(seconds: 2);
      maxBuffer = const Duration(seconds: 18);
    } else {
      minBuffer = const Duration(milliseconds: 2500);
      maxBuffer = const Duration(seconds: 15);
    }

    return AndroidLoadControl(
      minBufferDuration: minBuffer,
      maxBufferDuration: maxBuffer,
      bufferForPlaybackDuration: const Duration(seconds: 1),
      bufferForPlaybackAfterRebufferDuration: const Duration(seconds: 2),
      prioritizeTimeOverSizeThresholds: !isLowRamDevice,
      backBufferDuration: Duration.zero,
    );
  }

  Map<String, Object?> toJson() => {
        'androidApiLevel': androidApiLevel,
        'isLowRamDevice': isLowRamDevice,
        'networkType': networkType.name,
      };

  factory DeviceStreamProfile.fromJson(Map<String, Object?> json) {
    final rawNetworkType = json['networkType']?.toString();
    final networkType = DeviceNetworkType.values.firstWhere(
      (value) => value.name == rawNetworkType,
      orElse: () => DeviceNetworkType.other,
    );
    return DeviceStreamProfile(
      androidApiLevel: (json['androidApiLevel'] as num?)?.toInt(),
      // Missing capability data must not accidentally enable high-bitrate
      // experimental formats on an unknown device.
      isLowRamDevice: json['isLowRamDevice'] is bool
          ? json['isLowRamDevice'] as bool
          : true,
      networkType: networkType,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceStreamProfile &&
      other.androidApiLevel == androidApiLevel &&
      other.isLowRamDevice == isLowRamDevice &&
      other.networkType == networkType;

  @override
  int get hashCode =>
      Object.hash(androidApiLevel, isLowRamDevice, networkType);
}

/// Reads device/network state on the UI/platform isolate. Do not call this
/// from StreamProvider's Isolate.run resolver; pass [DeviceStreamProfile.toJson]
/// to that isolate instead. The public just_audio API does not expose the
/// device's MediaCodec inventory, so actual decoder incompatibility is handled
/// by retrying with AAC after a native decoder/renderer error.
class DeviceAdaptiveStreamSelector {
  DeviceAdaptiveStreamSelector({
    DeviceInfoPlugin? deviceInfo,
    Connectivity? connectivity,
  })  : _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
        _connectivity = connectivity ?? Connectivity();

  final DeviceInfoPlugin _deviceInfo;
  final Connectivity _connectivity;

  /// Recognizes native decoder/renderer failures so playback can retry with
  /// the AAC fallback retained in the low-quality stream slot.
  static bool isDecoderCompatibilityFailure(Object error) {
    final message = error.toString().toLowerCase();
    return const [
      'decoderinitializationexception',
      'decoder',
      'mediacodecrenderer',
      'mediacodec',
      'no suitable decoder',
      'unsupported audio format',
      'audio sink',
    ].any(message.contains);
  }

  Future<DeviceStreamProfile> detect() async {
    int? apiLevel;
    var isLowRamDevice = true;

    try {
      final android = await _deviceInfo.androidInfo;
      apiLevel = android.version.sdkInt;
      isLowRamDevice = android.isLowRamDevice;
    } catch (_) {
      // Keep conservative defaults when the platform channel is unavailable.
    }

    var networkType = DeviceNetworkType.other;
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet)) {
        networkType = DeviceNetworkType.wifi;
      } else if (results.contains(ConnectivityResult.mobile)) {
        networkType = DeviceNetworkType.mobile;
      } else if (results.contains(ConnectivityResult.none) ||
          results.isEmpty) {
        networkType = DeviceNetworkType.offline;
      }
    } catch (_) {
      // Network detection is advisory; resolver timeouts remain authoritative.
    }

    return DeviceStreamProfile(
      androidApiLevel: apiLevel,
      isLowRamDevice: isLowRamDevice,
      networkType: networkType,
    );
  }
}
