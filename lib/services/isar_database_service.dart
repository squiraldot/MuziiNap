import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/local_library_models.dart';

/// App-scoped Isar database owner for the future Hive-to-Isar library migration.
///
/// Hive remains the active source of truth until a separate, verified data
/// migration is implemented. Initialize this service only when an Isar-backed
/// library feature is enabled; do not open a second database during every boot.
class IsarDatabaseService extends GetxService {
  static const String databaseName = 'muziinap_local_library';

  Isar? _isar;
  Future<Isar>? _opening;

  bool get isInitialized => _isar?.isOpen ?? false;

  /// Opens one shared Isar instance and coalesces concurrent initialization.
  Future<Isar> initialize() async {
    final existing = _isar;
    if (existing != null && existing.isOpen) return existing;

    final pending = _opening;
    if (pending != null) return pending;

    final opening = _openDatabase();
    _opening = opening;
    try {
      return await opening;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<Isar> _openDatabase() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final databaseDirectory =
        Directory(p.join(supportDirectory.path, 'isar'));
    await databaseDirectory.create(recursive: true);

    final database = await Isar.open(
      [
        DownloadedSongSchema,
        LocalPlaylistSchema,
      ],
      directory: databaseDirectory.path,
      name: databaseName,
    );

    _isar = database;
    return database;
  }

  /// Access only after [initialize] has completed.
  Isar get instance {
    final database = _isar;
    if (database == null || !database.isOpen) {
      throw StateError(
        'IsarDatabaseService.initialize() must complete before use.',
      );
    }
    return database;
  }

  /// Explicit close hook for tests or controlled application teardown.
  Future<void> close() async {
    final database = _isar;
    _isar = null;
    _opening = null;
    if (database != null && database.isOpen) {
      await database.close();
    }
  }

  @override
  void onClose() {
    unawaited(close());
    super.onClose();
  }
}
