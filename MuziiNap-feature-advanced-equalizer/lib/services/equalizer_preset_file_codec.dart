import 'dart:convert';

import '../models/equalizer.dart';
import '../models/equalizer_preset.dart';

class EqualizerPresetFileCodec {
  static const String format = 'muziinap-eq';
  static const int version = 3;
  static const String extension = 'mneq';
  static const String mimeType = 'application/json';

  static bool isSupportedFileName(String fileName) {
    final normalized = fileName.trim().toLowerCase();
    return normalized.endsWith('.$extension');
  }

  static String encode(EqualizerPreset preset) {
    final config = preset.config;
    final document = <String, Object>{
      'format': format,
      'version': version,
      'name': preset.name,
      'author': preset.author,
      'description': preset.description,
      'enabled': config.enabled,
      'preamp': config.preampDb,
      'outputGain': config.outputGainDb,
      'limiterEnabled': config.limiterEnabled,
      'advancedDsp': config.advancedDsp.toJson(),
      'bands': config.bands
          .map((band) => <String, Object>{
                'type': band.type.value,
                'frequency': band.frequency,
                'gainDb': band.gainDb,
                'q': band.q,
                'enabled': band.enabled,
              })
          .toList(growable: false),
    };

    return const JsonEncoder.withIndent('  ').convert(document);
  }

  static EqualizerPreset decode(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) {
        throw const FormatException('Equalizer preset must be a JSON object');
      }

      final json = Map<String, Object?>.from(decoded);
      if (json['format'] != format) {
        throw const FormatException('Unsupported equalizer preset format');
      }

      final rawVersion = json['version'];
      if (rawVersion is! int || (rawVersion != 1 && rawVersion != 2 && rawVersion != version)) {
        throw FormatException(
          'Unsupported equalizer preset version: ' + rawVersion.toString(),
        );
      }

      final rawBands = json['bands'];
      if (rawBands is! List) {
        throw const FormatException('Equalizer preset bands must be a list');
      }

      final bands = rawBands.asMap().entries.map((entry) {
        final band = entry.value;
        if (band is! Map) {
          throw const FormatException('Equalizer preset band must be an object');
        }
        final bandJson = Map<String, Object?>.from(band);
        return EqualizerBand(
          id: 'imported-' + entry.key.toString(),
          type: EqualizerFilterTypeJson.parse(bandJson['type']),
          frequency: _readDouble(bandJson, 'frequency'),
          gainDb: _readDouble(bandJson, 'gainDb'),
          q: _readDouble(bandJson, 'q'),
          enabled: _readBool(bandJson, 'enabled'),
        );
      }).toList(growable: false);

      final config = EqualizerConfig(
        enabled: _readBool(json, 'enabled'),
        preampDb: _readDouble(json, 'preamp'),
        outputGainDb: _readOptionalDouble(json, 'outputGain', fallback: 0),
        limiterEnabled: _readOptionalBool(
          json,
          'limiterEnabled',
          fallback: true,
        ),
        advancedDsp: json['advancedDsp'] is Map
            ? AdvancedDspConfig.fromJson(
                Map<String, Object?>.from(json['advancedDsp'] as Map),
              )
            : AdvancedDspConfig(),
        bands: bands,
      );

      final name = _readString(json, 'name');
      final author = _readString(json, 'author');
      final description = _readOptionalString(json, 'description', fallback: '');
      final now = DateTime.now().toUtc();
      return EqualizerPreset(
        id: 'imported-' + now.microsecondsSinceEpoch.toString(),
        name: name,
        author: author,
        description: description,
        createdAt: now,
        updatedAt: now,
        isBuiltIn: false,
        config: config,
      );
    } on FormatException {
      rethrow;
    } on ArgumentError catch (error) {
      throw FormatException('Invalid equalizer preset: ' + error.message.toString());
    } on TypeError catch (error) {
      throw FormatException('Invalid equalizer preset: ' + error.toString());
    } on JsonUnsupportedObjectError catch (error) {
      throw FormatException('Invalid equalizer preset JSON: ' + error.toString());
    } catch (error) {
      throw FormatException('Invalid equalizer preset: ' + error.toString());
    }
  }

  static String _readString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) return value;
    throw FormatException('Equalizer preset ' + key + ' must be a non-empty string');
  }

  static String _readOptionalString(
    Map<String, Object?> json,
    String key, {
    required String fallback,
  }) {
    final value = json[key];
    if (value == null) return fallback;
    if (value is String) return value;
    throw FormatException('Equalizer preset ' + key + ' must be a string');
  }

  static double _readDouble(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is num && value.isFinite) return value.toDouble();
    throw FormatException('Equalizer preset ' + key + ' must be a finite number');
  }

  static double _readOptionalDouble(
    Map<String, Object?> json,
    String key, {
    required double fallback,
  }) {
    final value = json[key];
    if (value == null) return fallback;
    if (value is num && value.isFinite) return value.toDouble();
    throw FormatException('Equalizer preset ' + key + ' must be a finite number');
  }

  static bool _readBool(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is bool) return value;
    throw FormatException('Equalizer preset ' + key + ' must be a boolean');
  }

  static bool _readOptionalBool(
    Map<String, Object?> json,
    String key, {
    required bool fallback,
  }) {
    final value = json[key];
    if (value == null) return fallback;
    if (value is bool) return value;
    throw FormatException('Equalizer preset ' + key + ' must be a boolean');
  }
}
