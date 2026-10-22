import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/equalizer.dart';

class AutoEqProfileSummary {
  const AutoEqProfileSummary({
    required this.name,
    required this.form,
    required this.source,
    required this.rig,
  });

  final String name;
  final String form;
  final String source;
  final String rig;
}

class AutoEqProfile {
  const AutoEqProfile({
    required this.name,
    required this.source,
    required this.rig,
    required this.preampDb,
    required this.bands,
  });

  final String name;
  final String source;
  final String rig;
  final double preampDb;
  final List<EqualizerBand> bands;

  EqualizerConfig toConfig() {
    return EqualizerConfig.graphic10Band().copyWith(
      enabled: true,
      preampDb: preampDb,
      bands: bands,
    );
  }

  static AutoEqProfile fromResponse({
    required String name,
    required String source,
    required String rig,
    required Map<String, dynamic> response,
  }) {
    final rawPeq = response['parametric_eq'];
    if (rawPeq is! Map) {
      throw const FormatException('AutoEq response has no parametric EQ');
    }
    final filters = rawPeq['filters'];
    if (filters is! List || filters.isEmpty) {
      throw const FormatException('AutoEq response has no PEQ filters');
    }

    final bands = <EqualizerBand>[];
    for (var index = 0;
        index < filters.length && index < EqualizerConfig.maxParametricBands;
        index++) {
      final raw = filters[index];
      if (raw is! Map) {
        throw const FormatException('Invalid AutoEq filter');
      }
      final type = switch (raw['type']) {
        'LOW_SHELF' => EqualizerFilterType.lowShelf,
        'PEAKING' => EqualizerFilterType.peaking,
        'HIGH_SHELF' => EqualizerFilterType.highShelf,
        _ => throw const FormatException('Unsupported AutoEq filter type'),
      };
      bands.add(
        EqualizerBand(
          id: 'autoeq-$index',
          type: type,
          frequency: _number(raw['fc']),
          gainDb: _number(raw['gain']),
          q: _number(raw['q']),
          enabled: true,
        ),
      );
    }

    if (bands.isEmpty) {
      throw const FormatException('AutoEq response produced no filters');
    }

    return AutoEqProfile(
      name: name,
      source: source,
      rig: rig,
      preampDb: _number(rawPeq['preamp'], fallback: 0),
      bands: List.unmodifiable(bands),
    );
  }

  static double _number(Object? value, {double? fallback}) {
    if (value is num && value.isFinite) return value.toDouble();
    if (fallback != null) return fallback;
    throw const FormatException('Invalid AutoEq numeric value');
  }
}

class AutoEqService {
  AutoEqService({http.Client? client}) : _client = client ?? http.Client();

  static const baseUrl = 'https://autoeq.app';
  final http.Client _client;
  List<AutoEqProfileSummary>? _catalog;
  DateTime? _catalogFetchedAt;
  List<Map<String, dynamic>>? _targets;

  Future<List<AutoEqProfileSummary>> search(String query) async {
    final catalog = await _loadCatalog();
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return catalog.take(50).toList(growable: false);
    }
    return catalog
        .where((profile) => profile.name.toLowerCase().contains(normalized))
        .take(50)
        .toList(growable: false);
  }

  Future<AutoEqProfile> loadProfile(AutoEqProfileSummary summary) async {
    final target = await _selectTarget(summary.form);
    final requestBody = jsonEncode({
      'name': summary.name,
      'source': summary.source,
      'rig': summary.rig,
      'target': target,
      'parametric_eq': true,
      'parametric_eq_config': '8_PEAKING_WITH_SHELVES',
      'fs': 48000,
      'preamp': 0,
      // This screen only needs filter coefficients. Requesting 1 Hz response
      // curves forces AutoEq to interpolate and serialize large unused arrays.
      'response': {
        'fr_fields': <String>[],
        'fr_f_step': 10,
      },
    });

    http.Response response;
    for (var attempt = 0; ; attempt++) {
      try {
        response = await _client
            .post(
              Uri.parse(baseUrl + '/equalize'),
              headers: const {'content-type': 'application/json'},
              body: requestBody,
            )
            .timeout(const Duration(seconds: 30));
      } on TimeoutException {
        if (attempt >= 1) {
          throw const FormatException(
            'AutoEq server timed out. Please try again in a moment.',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
        continue;
      }

      if (response.statusCode == 200) break;
      final retryable = const {502, 503, 504, 520, 522, 524}
          .contains(response.statusCode);
      if (!retryable || attempt >= 1) {
        if (retryable) {
          throw FormatException(
            'AutoEq server is temporarily unavailable (' +
                response.statusCode.toString() +
                '). Please try again shortly.',
          );
        }
        throw FormatException(
          'AutoEq request failed (' + response.statusCode.toString() + ')',
        );
      }
      // The public AutoEq API can intermittently return Cloudflare 52x errors.
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Invalid AutoEq response');
    }
    return AutoEqProfile.fromResponse(
      name: summary.name,
      source: summary.source,
      rig: summary.rig,
      response: Map<String, dynamic>.from(decoded),
    );
  }

  Future<List<AutoEqProfileSummary>> _loadCatalog() async {
    final now = DateTime.now();
    if (_catalog != null &&
        _catalogFetchedAt != null &&
        now.difference(_catalogFetchedAt!) < const Duration(minutes: 10)) {
      return _catalog!;
    }

    final response = await _client.get(Uri.parse(baseUrl + '/entries'));
    if (response.statusCode != 200) {
      throw FormatException(
        'AutoEq catalog failed (' + response.statusCode.toString() + ')',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Invalid AutoEq catalog');
    }

    final profiles = <AutoEqProfileSummary>[];
    for (final entry in decoded.entries) {
      final name = entry.key.toString().trim();
      final variants = entry.value;
      if (name.isEmpty || variants is! List) continue;
      for (final variant in variants) {
        if (variant is! Map) continue;
        final form = variant['form']?.toString() ?? '';
        final source = variant['source']?.toString() ?? '';
        final rig = variant['rig']?.toString() ?? '';
        if (form.isEmpty || source.isEmpty || rig.isEmpty) continue;
        profiles.add(
          AutoEqProfileSummary(
            name: name,
            form: form,
            source: source,
            rig: rig,
          ),
        );
      }
    }
    profiles.sort((a, b) {
      final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (name != 0) return name;
      return a.source.compareTo(b.source);
    });
    _catalog = List.unmodifiable(profiles);
    _catalogFetchedAt = now;
    return _catalog!;
  }

  Future<String> _selectTarget(String form) async {
    if (_targets == null) {
      final response = await _client.get(Uri.parse(baseUrl + '/targets'));
      if (response.statusCode != 200) {
        throw FormatException(
          'AutoEq targets failed (' + response.statusCode.toString() + ')',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const FormatException('Invalid AutoEq targets');
      }
      _targets = [
        for (final target in decoded)
          if (target is Map) Map<String, dynamic>.from(target),
      ];
    }

    if (_targets!.isEmpty) {
      throw const FormatException('AutoEq returned no targets');
    }

    final normalizedForm = form.toLowerCase();
    final compatible = _targets!.where((target) {
      final values = target['compatible'];
      return values is List &&
          values.any(
            (value) =>
                normalizedForm.contains(value.toString().toLowerCase()) ||
                value.toString().toLowerCase().contains(normalizedForm),
          );
    }).toList();

    final recommended = compatible.where(
      (target) => target['recommended'] == true,
    );
    final selected = recommended.isNotEmpty
        ? recommended.first
        : (compatible.isNotEmpty ? compatible.first : _targets!.first);
    final label = selected['label']?.toString();
    if (label == null || label.isEmpty) {
      throw const FormatException('No compatible AutoEq target found');
    }
    return label;
  }

  void dispose() => _client.close();
}
