import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import '../lib/models/equalizer.dart';
import '../lib/models/equalizer_preset.dart';
import '../lib/services/equalizer_preset_store.dart';

void main() {
  late Directory tempDirectory;
  late EqualizerPresetStore store;

  setUpAll(() async {
    tempDirectory = await Directory.systemTemp.createTemp('muziinap-eq-test-');
    Hive.init(tempDirectory.path);
  });

  setUp(() {
    store = EqualizerPresetStore();
  });

  tearDown(() async {
    if (Hive.isBoxOpen(EqualizerPresetStore.boxName)) {
      await Hive.box(EqualizerPresetStore.boxName).clear();
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDirectory.delete(recursive: true);
  });

  test('persists custom presets across store instances', () async {
    final created = await store.create(
      name: 'My Bass',
      config: EqualizerConfig.graphic10Band().copyWith(preampDb: -3),
    );

    final reloaded = await EqualizerPresetStore().getCustom(created.id);

    expect(reloaded, equals(created));
  });

  test('updates a custom preset without changing its identity or creation time',
      () async {
    final created = await store.create(
      name: 'My Preset',
      config: EqualizerConfig.graphic10Band(),
    );

    final updated = await store.update(
      created,
      name: 'Updated',
      config: created.config.copyWith(preampDb: -2),
    );

    expect(updated.id, created.id);
    expect(updated.createdAt, created.createdAt);
    expect(updated.name, 'Updated');
    expect(updated.config.preampDb, -2);
    expect(updated.updatedAt.isBefore(created.updatedAt), isFalse);
  });

  test('duplicates built-in and custom presets as editable custom presets',
      () async {
    final builtIn = EqualizerBuiltInPresets.byId('builtin-bass-boost')!;

    final duplicate = await store.duplicate(builtIn);

    expect(duplicate.isBuiltIn, isFalse);
    expect(duplicate.author, 'User');
    expect(duplicate.id, isNot(builtIn.id));
    expect(duplicate.config, equals(builtIn.config));
  });

  test('rejects direct persistence of built-in presets', () async {
    expect(
      () => store.save(EqualizerBuiltInPresets.all.first),
      throwsArgumentError,
    );
  });

  test('deletes only the requested custom preset', () async {
    final first = await store.create(
      name: 'First',
      config: EqualizerConfig.graphic10Band(),
    );
    final second = await store.create(
      name: 'Second',
      config: EqualizerConfig.graphic10Band(),
    );

    await store.delete(first.id);

    expect(await store.getCustom(first.id), isNull);
    expect(await store.getCustom(second.id), equals(second));
  });
}
