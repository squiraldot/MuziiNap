import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/equalizer.dart';
import '../models/equalizer_preset.dart';

class EqualizerPresetStore {
  static const boxName = 'EqualizerPresets';

  Future<List<EqualizerPreset>> listCustom() async {
    final box = await _box();
    final presets = <EqualizerPreset>[];
    for (final raw in box.values) {
      try {
        final json = raw is String
            ? Map<String, Object?>.from(jsonDecode(raw) as Map)
            : Map<String, Object?>.from(raw as Map);
        final preset = EqualizerPreset.fromJson(json);
        if (!preset.isBuiltIn) presets.add(preset);
      } catch (_) {
        // Ignore malformed user records so one corrupt preset cannot break EQ.
      }
    }
    presets.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return presets;
  }

  Future<EqualizerPreset?> getCustom(String id) async {
    final box = await _box();
    final raw = box.get(id);
    if (raw == null) return null;
    try {
      final json = raw is String
          ? Map<String, Object?>.from(jsonDecode(raw) as Map)
          : Map<String, Object?>.from(raw as Map);
      final preset = EqualizerPreset.fromJson(json);
      return preset.isBuiltIn ? null : preset;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(EqualizerPreset preset) async {
    if (preset.isBuiltIn) {
      throw ArgumentError('Built-in presets are immutable');
    }
    await (await _box()).put(preset.id, jsonEncode(preset.toJson()));
  }

  Future<void> delete(String id) async {
    final preset = await getCustom(id);
    if (preset == null) return;
    await (await _box()).delete(id);
  }

  Future<EqualizerPreset> create({
    required String name,
    required EqualizerConfig config,
    String author = 'User',
    String description = '',
  }) async {
    final now = DateTime.now().toUtc();
    final preset = EqualizerPreset(
      id: 'custom-${now.microsecondsSinceEpoch}',
      name: name.trim(),
      author: author,
      description: description,
      createdAt: now,
      updatedAt: now,
      isBuiltIn: false,
      config: config,
    );
    await save(preset);
    return preset;
  }

  Future<EqualizerPreset> update(
    EqualizerPreset preset, {
    String? name,
    String? description,
    EqualizerConfig? config,
  }) async {
    if (preset.isBuiltIn) {
      throw ArgumentError('Built-in presets are immutable');
    }
    final updated = preset.copyWith(
      name: name?.trim(),
      description: description,
      config: config,
      updatedAt: DateTime.now().toUtc(),
    );
    await save(updated);
    return updated;
  }

  Future<EqualizerPreset> duplicate(
    EqualizerPreset preset, {
    String? name,
  }) async {
    return create(
      name: name ?? '${preset.name} Copy',
      author: preset.author == 'MuziiNap' ? 'User' : preset.author,
      description: preset.description,
      config: preset.config,
    );
  }

  Future<Box<dynamic>> _box() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box(boxName);
    return Hive.openBox(boxName);
  }
}
