
class AdvancedDspConfig {
  final bool enabled;
  final bool bassBoostEnabled;
  final double bassBoostAmountDb;
  final double bassBoostFrequencyHz;
  final double bassBoostQ;
  final bool loudnessEnabled;
  final double loudnessAmountDb;
  final bool compressorEnabled;
  final double compressorThresholdDb;
  final double compressorRatio;
  final double compressorAttackMs;
  final double compressorReleaseMs;
  final double compressorKneeDb;
  final double compressorMakeupGainDb;
  final double limiterCeilingDb;
  final double limiterReleaseMs;
  final bool soundFxEnabled;
  final double xBassAmountDb;
  final double xTrebleAmountDb;
  final double powerBassAmountDb;
  final bool dynamicBassEnabled;
  final double dynamicBassAmountDb;
  final bool surroundEnabled;
  final double surroundAmount;
  final double stereoBalance;
  final double stereoWidth;

  AdvancedDspConfig({
    this.enabled = true,
    this.bassBoostEnabled = false,
    double bassBoostAmountDb = 0,
    double bassBoostFrequencyHz = 70,
    double bassBoostQ = 0.9,
    this.loudnessEnabled = false,
    double loudnessAmountDb = 0,
    this.compressorEnabled = false,
    double compressorThresholdDb = -18,
    double compressorRatio = 2,
    double compressorAttackMs = 10,
    double compressorReleaseMs = 120,
    double compressorKneeDb = 6,
    double compressorMakeupGainDb = 0,
    double limiterCeilingDb = -1,
    double limiterReleaseMs = 80,
    this.soundFxEnabled = false,
    double xBassAmountDb = 0,
    double xTrebleAmountDb = 0,
    double powerBassAmountDb = 0,
    this.dynamicBassEnabled = false,
    double dynamicBassAmountDb = 0,
    this.surroundEnabled = false,
    double surroundAmount = 0,
    double stereoBalance = 0,
    double stereoWidth = 1,
  })  : bassBoostAmountDb = _range(
          bassBoostAmountDb, 0, 12, 'bassBoostAmountDb'),
        bassBoostFrequencyHz = _range(
          bassBoostFrequencyHz, 40, 180, 'bassBoostFrequencyHz'),
        bassBoostQ = _range(bassBoostQ, 0.2, 2.0, 'bassBoostQ'),
        loudnessAmountDb = _range(loudnessAmountDb, 0, 12, 'loudnessAmountDb'),
        compressorThresholdDb = _range(
          compressorThresholdDb, -60, 0, 'compressorThresholdDb'),
        compressorRatio = _range(compressorRatio, 1, 20, 'compressorRatio'),
        compressorAttackMs = _range(
          compressorAttackMs, 0.1, 100, 'compressorAttackMs'),
        compressorReleaseMs = _range(
          compressorReleaseMs, 10, 1000, 'compressorReleaseMs'),
        compressorKneeDb = _range(compressorKneeDb, 0, 40, 'compressorKneeDb'),
        compressorMakeupGainDb = _range(
          compressorMakeupGainDb, -12, 12, 'compressorMakeupGainDb'),
        limiterCeilingDb = _range(
          limiterCeilingDb, -12, 0, 'limiterCeilingDb'),
        limiterReleaseMs = _range(
          limiterReleaseMs, 10, 1000, 'limiterReleaseMs'),
        xBassAmountDb = _range(xBassAmountDb, 0, 12, 'xBassAmountDb'),
        xTrebleAmountDb = _range(xTrebleAmountDb, 0, 12, 'xTrebleAmountDb'),
        powerBassAmountDb = _range(powerBassAmountDb, 0, 12, 'powerBassAmountDb'),
        dynamicBassAmountDb = _range(
          dynamicBassAmountDb, 0, 12, 'dynamicBassAmountDb'),
        surroundAmount = _range(surroundAmount, 0, 1, 'surroundAmount'),
        stereoBalance = _range(stereoBalance, -1, 1, 'stereoBalance'),
        stereoWidth = _range(stereoWidth, 1, 2, 'stereoWidth');

  AdvancedDspConfig copyWith({
    bool? enabled,
    bool? bassBoostEnabled,
    double? bassBoostAmountDb,
    double? bassBoostFrequencyHz,
    double? bassBoostQ,
    bool? loudnessEnabled,
    double? loudnessAmountDb,
    bool? compressorEnabled,
    double? compressorThresholdDb,
    double? compressorRatio,
    double? compressorAttackMs,
    double? compressorReleaseMs,
    double? compressorKneeDb,
    double? compressorMakeupGainDb,
    double? limiterCeilingDb,
    double? limiterReleaseMs,
    bool? soundFxEnabled,
    double? xBassAmountDb,
    double? xTrebleAmountDb,
    double? powerBassAmountDb,
    bool? dynamicBassEnabled,
    double? dynamicBassAmountDb,
    bool? surroundEnabled,
    double? surroundAmount,
    double? stereoBalance,
    double? stereoWidth,
  }) {
    return AdvancedDspConfig(
      enabled: enabled ?? this.enabled,
      bassBoostEnabled: bassBoostEnabled ?? this.bassBoostEnabled,
      bassBoostAmountDb: bassBoostAmountDb ?? this.bassBoostAmountDb,
      bassBoostFrequencyHz: bassBoostFrequencyHz ?? this.bassBoostFrequencyHz,
      bassBoostQ: bassBoostQ ?? this.bassBoostQ,
      loudnessEnabled: loudnessEnabled ?? this.loudnessEnabled,
      loudnessAmountDb: loudnessAmountDb ?? this.loudnessAmountDb,
      compressorEnabled: compressorEnabled ?? this.compressorEnabled,
      compressorThresholdDb:
          compressorThresholdDb ?? this.compressorThresholdDb,
      compressorRatio: compressorRatio ?? this.compressorRatio,
      compressorAttackMs: compressorAttackMs ?? this.compressorAttackMs,
      compressorReleaseMs: compressorReleaseMs ?? this.compressorReleaseMs,
      compressorKneeDb: compressorKneeDb ?? this.compressorKneeDb,
      compressorMakeupGainDb:
          compressorMakeupGainDb ?? this.compressorMakeupGainDb,
      limiterCeilingDb: limiterCeilingDb ?? this.limiterCeilingDb,
      limiterReleaseMs: limiterReleaseMs ?? this.limiterReleaseMs,
      soundFxEnabled: soundFxEnabled ?? this.soundFxEnabled,
      xBassAmountDb: xBassAmountDb ?? this.xBassAmountDb,
      xTrebleAmountDb: xTrebleAmountDb ?? this.xTrebleAmountDb,
      powerBassAmountDb: powerBassAmountDb ?? this.powerBassAmountDb,
      dynamicBassEnabled: dynamicBassEnabled ?? this.dynamicBassEnabled,
      dynamicBassAmountDb: dynamicBassAmountDb ?? this.dynamicBassAmountDb,
      surroundEnabled: surroundEnabled ?? this.surroundEnabled,
      surroundAmount: surroundAmount ?? this.surroundAmount,
      stereoBalance: stereoBalance ?? this.stereoBalance,
      stereoWidth: stereoWidth ?? this.stereoWidth,
    );
  }

  Map<String, Object> toJson() => {
        'enabled': enabled,
        'bassBoostEnabled': bassBoostEnabled,
        'bassBoostAmountDb': bassBoostAmountDb,
        'bassBoostFrequencyHz': bassBoostFrequencyHz,
        'bassBoostQ': bassBoostQ,
        'loudnessEnabled': loudnessEnabled,
        'loudnessAmountDb': loudnessAmountDb,
        'compressorEnabled': compressorEnabled,
        'compressorThresholdDb': compressorThresholdDb,
        'compressorRatio': compressorRatio,
        'compressorAttackMs': compressorAttackMs,
        'compressorReleaseMs': compressorReleaseMs,
        'compressorKneeDb': compressorKneeDb,
        'compressorMakeupGainDb': compressorMakeupGainDb,
        'limiterCeilingDb': limiterCeilingDb,
        'limiterReleaseMs': limiterReleaseMs,
        'soundFxEnabled': soundFxEnabled,
        'xBassAmountDb': xBassAmountDb,
        'xTrebleAmountDb': xTrebleAmountDb,
        'powerBassAmountDb': powerBassAmountDb,
        'dynamicBassEnabled': dynamicBassEnabled,
        'dynamicBassAmountDb': dynamicBassAmountDb,
        'surroundEnabled': surroundEnabled,
        'surroundAmount': surroundAmount,
        'stereoBalance': stereoBalance,
        'stereoWidth': stereoWidth,
      };

  factory AdvancedDspConfig.fromJson(Map<String, Object?> json) {
    return AdvancedDspConfig(
      enabled: _boolOr(json, 'enabled', true),
      bassBoostEnabled: _boolOr(json, 'bassBoostEnabled', false),
      bassBoostAmountDb: _doubleOr(json, 'bassBoostAmountDb', 0),
      bassBoostFrequencyHz: _doubleOr(json, 'bassBoostFrequencyHz', 70),
      bassBoostQ: _doubleOr(json, 'bassBoostQ', 0.9),
      loudnessEnabled: _boolOr(json, 'loudnessEnabled', false),
      loudnessAmountDb: _doubleOr(json, 'loudnessAmountDb', 0),
      compressorEnabled: _boolOr(json, 'compressorEnabled', false),
      compressorThresholdDb: _doubleOr(json, 'compressorThresholdDb', -18),
      compressorRatio: _doubleOr(json, 'compressorRatio', 2),
      compressorAttackMs: _doubleOr(json, 'compressorAttackMs', 10),
      compressorReleaseMs: _doubleOr(json, 'compressorReleaseMs', 120),
      compressorKneeDb: _doubleOr(json, 'compressorKneeDb', 6),
      compressorMakeupGainDb: _doubleOr(json, 'compressorMakeupGainDb', 0),
      limiterCeilingDb: _doubleOr(json, 'limiterCeilingDb', -1),
      limiterReleaseMs: _doubleOr(json, 'limiterReleaseMs', 80),
      soundFxEnabled: _boolOr(json, 'soundFxEnabled', false),
      xBassAmountDb: _doubleOr(json, 'xBassAmountDb', 0),
      xTrebleAmountDb: _doubleOr(json, 'xTrebleAmountDb', 0),
      powerBassAmountDb: _doubleOr(json, 'powerBassAmountDb', 0),
      dynamicBassEnabled: _boolOr(json, 'dynamicBassEnabled', false),
      dynamicBassAmountDb: _doubleOr(json, 'dynamicBassAmountDb', 0),
      surroundEnabled: _boolOr(json, 'surroundEnabled', false),
      surroundAmount: _doubleOr(json, 'surroundAmount', 0),
      stereoBalance: _doubleOr(json, 'stereoBalance', 0),
      stereoWidth: _doubleOr(json, 'stereoWidth', 1),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AdvancedDspConfig &&
      other.enabled == enabled &&
      other.bassBoostEnabled == bassBoostEnabled &&
      other.bassBoostAmountDb == bassBoostAmountDb &&
      other.bassBoostFrequencyHz == bassBoostFrequencyHz &&
      other.bassBoostQ == bassBoostQ &&
      other.loudnessEnabled == loudnessEnabled &&
      other.loudnessAmountDb == loudnessAmountDb &&
      other.compressorEnabled == compressorEnabled &&
      other.compressorThresholdDb == compressorThresholdDb &&
      other.compressorRatio == compressorRatio &&
      other.compressorAttackMs == compressorAttackMs &&
      other.compressorReleaseMs == compressorReleaseMs &&
      other.compressorKneeDb == compressorKneeDb &&
      other.compressorMakeupGainDb == compressorMakeupGainDb &&
      other.limiterCeilingDb == limiterCeilingDb &&
      other.limiterReleaseMs == limiterReleaseMs &&
      other.soundFxEnabled == soundFxEnabled &&
      other.xBassAmountDb == xBassAmountDb &&
      other.xTrebleAmountDb == xTrebleAmountDb &&
      other.powerBassAmountDb == powerBassAmountDb &&
      other.dynamicBassEnabled == dynamicBassEnabled &&
      other.dynamicBassAmountDb == dynamicBassAmountDb &&
      other.surroundEnabled == surroundEnabled &&
      other.surroundAmount == surroundAmount &&
      other.stereoBalance == stereoBalance &&
      other.stereoWidth == stereoWidth;

  @override
  int get hashCode => Object.hashAll([
        enabled,
        bassBoostEnabled,
        bassBoostAmountDb,
        bassBoostFrequencyHz,
        bassBoostQ,
        loudnessEnabled,
        loudnessAmountDb,
        compressorEnabled,
        compressorThresholdDb,
        compressorRatio,
        compressorAttackMs,
        compressorReleaseMs,
        compressorKneeDb,
        compressorMakeupGainDb,
        limiterCeilingDb,
        limiterReleaseMs,
        soundFxEnabled,
        xBassAmountDb,
        xTrebleAmountDb,
        powerBassAmountDb,
        dynamicBassEnabled,
        dynamicBassAmountDb,
        surroundEnabled,
        surroundAmount,
        stereoBalance,
        stereoWidth,
      ]);

  static double _range(double value, double min, double max, String name) {
    if (!value.isFinite || value < min || value > max) {
      throw ArgumentError.value(value, name, 'Must be between $min and $max');
    }
    return value;
  }
}

enum EqualizerFilterType {
  peaking,
  lowShelf,
  highShelf,
  lowPass,
  highPass,
  bandPass,
  notch,
}

extension EqualizerFilterTypeJson on EqualizerFilterType {
  String get value => switch (this) {
        EqualizerFilterType.peaking => 'peaking',
        EqualizerFilterType.lowShelf => 'lowShelf',
        EqualizerFilterType.highShelf => 'highShelf',
        EqualizerFilterType.lowPass => 'lowPass',
        EqualizerFilterType.highPass => 'highPass',
        EqualizerFilterType.bandPass => 'bandPass',
        EqualizerFilterType.notch => 'notch',
      };

  static EqualizerFilterType parse(Object? value) {
    return EqualizerFilterType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => throw const FormatException(
        'Unsupported equalizer filter type',
      ),
    );
  }
}

class EqualizerBand {
  static const double minFrequencyHz = 20;
  static const double maxFrequencyHz = 20000;
  static const double minGainDb = -15;
  static const double maxGainDb = 15;
  static const double minQ = 0.1;
  static const double maxQ = 20;

  final String id;
  final EqualizerFilterType type;
  final double frequency;
  final double gainDb;
  final double q;
  final bool enabled;

  EqualizerBand({
    required this.id,
    required this.type,
    required this.frequency,
    required this.gainDb,
    required this.q,
    required this.enabled,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Band id must not be empty');
    }
    if (!frequency.isFinite ||
        frequency < minFrequencyHz ||
        frequency > maxFrequencyHz) {
      throw ArgumentError.value(
        frequency,
        'frequency',
        'Frequency must be between 20 Hz and 20 kHz',
      );
    }
    if (!gainDb.isFinite || gainDb < minGainDb || gainDb > maxGainDb) {
      throw ArgumentError.value(
        gainDb,
        'gainDb',
        'Gain must be between -15 dB and +15 dB',
      );
    }
    if (!q.isFinite || q < minQ || q > maxQ) {
      throw ArgumentError.value(
        q,
        'q',
        'Q must be between 0.1 and 20',
      );
    }
  }

  EqualizerBand copyWith({
    String? id,
    EqualizerFilterType? type,
    double? frequency,
    double? gainDb,
    double? q,
    bool? enabled,
  }) {
    return EqualizerBand(
      id: id ?? this.id,
      type: type ?? this.type,
      frequency: frequency ?? this.frequency,
      gainDb: gainDb ?? this.gainDb,
      q: q ?? this.q,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object> toJson() => {
        'id': id,
        'type': type.value,
        'frequency': frequency,
        'gainDb': gainDb,
        'q': q,
        'enabled': enabled,
      };

  factory EqualizerBand.fromJson(Map<String, Object?> json) {
    return EqualizerBand(
      id: _requireString(json, 'id'),
      type: EqualizerFilterTypeJson.parse(json['type']),
      frequency: _requireDouble(json, 'frequency'),
      gainDb: _requireDouble(json, 'gainDb'),
      q: _requireDouble(json, 'q'),
      enabled: _requireBool(json, 'enabled'),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EqualizerBand &&
        other.id == id &&
        other.type == type &&
        other.frequency == frequency &&
        other.gainDb == gainDb &&
        other.q == q &&
        other.enabled == enabled;
  }

  @override
  int get hashCode => Object.hash(
        id,
        type,
        frequency,
        gainDb,
        q,
        enabled,
      );
}

class EqualizerConfig {
  static const int maxParametricBands = 12;
  static const double minGlobalGainDb = -15;
  static const double maxGlobalGainDb = 15;

  final bool enabled;
  final double preampDb;
  final bool limiterEnabled;
  final double outputGainDb;
  final List<EqualizerBand> bands;
  final AdvancedDspConfig advancedDsp;

  EqualizerConfig({
    this.enabled = true,
    double preampDb = 0,
    this.limiterEnabled = true,
    double outputGainDb = 0,
    required List<EqualizerBand> bands,
    AdvancedDspConfig? advancedDsp,
  })  : preampDb = _clampGlobalGain(preampDb),
        outputGainDb = _clampGlobalGain(outputGainDb),
        bands = _validateBands(bands),
        advancedDsp = advancedDsp ?? AdvancedDspConfig();

  factory EqualizerConfig.graphic10Band() {
    const frequencies = [
      31.0,
      62.0,
      125.0,
      250.0,
      500.0,
      1000.0,
      2000.0,
      4000.0,
      8000.0,
      16000.0,
    ];

    return EqualizerConfig(
      bands: [
        for (var i = 0; i < frequencies.length; i++)
          EqualizerBand(
            id: 'graphic-$i',
            type: EqualizerFilterType.peaking,
            frequency: frequencies[i],
            gainDb: 0,
            q: 1,
            enabled: true,
          ),
      ],
    );
  }

  EqualizerConfig addBand(EqualizerBand band) {
    if (bands.length >= maxParametricBands) {
      throw ArgumentError.value(
        bands.length,
        'bands',
        'A parametric EQ can contain at most $maxParametricBands bands',
      );
    }
    return copyWith(bands: [...bands, band]);
  }

  EqualizerConfig removeBand(String bandId) {
    return copyWith(
      bands: bands.where((band) => band.id != bandId).toList(growable: false),
    );
  }

  EqualizerConfig copyWith({
    bool? enabled,
    double? preampDb,
    bool? limiterEnabled,
    double? outputGainDb,
    List<EqualizerBand>? bands,
    AdvancedDspConfig? advancedDsp,
  }) {
    return EqualizerConfig(
      enabled: enabled ?? this.enabled,
      preampDb: preampDb ?? this.preampDb,
      limiterEnabled: limiterEnabled ?? this.limiterEnabled,
      outputGainDb: outputGainDb ?? this.outputGainDb,
      bands: bands ?? this.bands,
      advancedDsp: advancedDsp ?? this.advancedDsp,
    );
  }

  Map<String, Object> toJson() => {
        'format': 'muziinap-eq',
        'version': 2,
        'enabled': enabled,
        'preamp': preampDb,
        'outputGain': outputGainDb,
        'limiterEnabled': limiterEnabled,
        'advancedDsp': advancedDsp.toJson(),
        'bands': bands.map((band) => band.toJson()).toList(growable: false),
      };

  factory EqualizerConfig.fromJson(Map<String, Object?> json) {
    if (json['format'] != 'muziinap-eq') {
      throw const FormatException('Unsupported equalizer format');
    }

    final version = json['version'];
    if (version != 1 && version != 2) {
      throw FormatException('Unsupported equalizer format version: $version');
    }

    final rawBands = json['bands'];
    if (rawBands is! List) {
      throw const FormatException('Equalizer bands must be a list');
    }

    return EqualizerConfig(
      enabled: _requireBool(json, 'enabled'),
      preampDb: _requireDouble(json, 'preamp'),
      outputGainDb: _requireDouble(json, 'outputGain'),
      limiterEnabled: _requireBool(json, 'limiterEnabled'),
      advancedDsp: json['advancedDsp'] is Map
          ? AdvancedDspConfig.fromJson(
              Map<String, Object?>.from(json['advancedDsp'] as Map),
            )
          : AdvancedDspConfig(),
      bands: rawBands
          .map(
            (band) => EqualizerBand.fromJson(
              Map<String, Object?>.from(band as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! EqualizerConfig ||
        other.enabled != enabled ||
        other.preampDb != preampDb ||
        other.limiterEnabled != limiterEnabled ||
        other.outputGainDb != outputGainDb ||
        other.advancedDsp != advancedDsp ||
        other.bands.length != bands.length) {
      return false;
    }

    for (var i = 0; i < bands.length; i++) {
      if (bands[i] != other.bands[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        enabled,
        preampDb,
        limiterEnabled,
        outputGainDb,
        advancedDsp,
        Object.hashAll(bands),
      );
}

List<EqualizerBand> _validateBands(List<EqualizerBand> bands) {
  if (bands.length > EqualizerConfig.maxParametricBands) {
    throw ArgumentError.value(
      bands.length,
      'bands',
      'A parametric EQ can contain at most '
          '${EqualizerConfig.maxParametricBands} bands',
    );
  }
  return List.unmodifiable(bands);
}

double _clampGlobalGain(double value) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'gain', 'Gain must be finite');
  }
  return value.clamp(
    EqualizerConfig.minGlobalGainDb,
    EqualizerConfig.maxGlobalGainDb,
  ).toDouble();
}


bool _boolOr(Map<String, Object?> json, String key, bool fallback) {
  final value = json[key];
  return value is bool ? value : fallback;
}

double _doubleOr(Map<String, Object?> json, String key, double fallback) {
  final value = json[key];
  if (value is num && value.isFinite) return value.toDouble();
  return fallback;
}

String _requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Expected string for $key');
  }
  return value;
}

double _requireDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  throw FormatException('Expected number for $key');
}

bool _requireBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('Expected boolean for $key');
}
