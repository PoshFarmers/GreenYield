import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'media_attachment.dart';

/// Local queue database for media uploads, deliberately separate from
/// PowerSync — media bytes don't belong in a relational sync stream,
/// and this queue's needs (one table, no joins, no server sync
/// protocol) don't need it. Uses `sqflite` directly.
class MediaQueueDb {
  static final MediaQueueDb instance = MediaQueueDb._();
  MediaQueueDb._();

  Database? _db;
  final _changes = StreamController<void>.broadcast();

  Future<Database> get _database async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'media_queue.db');
    final opened = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE media_attachment (
          id TEXT PRIMARY KEY,
          bucket TEXT NOT NULL,
          remote_path TEXT NOT NULL,
          local_path TEXT NOT NULL,
          owner_id TEXT,
          purpose TEXT NOT NULL,
          content_type TEXT,
          state TEXT NOT NULL,
          error_message TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      '''),
    );
    _db = opened;
    return opened;
  }

  void _notifyChanged() => _changes.add(null);

  Future<void> upsert(MediaAttachment attachment) async {
    final db = await _database;
    await db.insert(
      'media_attachment',
      attachment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notifyChanged();
  }

  Future<void> delete(String id) async {
    final db = await _database;
    await db.delete('media_attachment', where: 'id = ?', whereArgs: [id]);
    _notifyChanged();
  }

  Future<List<MediaAttachment>> _queryAll({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'media_attachment',
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
    );
    return rows.map(MediaAttachment.fromMap).toList();
  }

  /// Re-queries on every mutation, since sqflite has no built-in live
  /// query support (unlike PowerSync's `db.watch`). Fine at this scale —
  /// the queue table is small and purely local.
  Stream<List<MediaAttachment>> watch({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async* {
    yield await _queryAll(where: where, whereArgs: whereArgs, orderBy: orderBy);
    await for (final _ in _changes.stream) {
      yield await _queryAll(
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
      );
    }
  }

  Future<MediaAttachment?> getById(String id) async {
    final rows = await _queryAll(where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<MediaAttachment>> pendingUploads() => _queryAll(
    where: 'state IN (?, ?)',
    whereArgs: [AttachmentState.queuedUpload.name, AttachmentState.failed.name],
  );

  Future<List<MediaAttachment>> pendingDeletes() => _queryAll(
    where: 'state = ?',
    whereArgs: [AttachmentState.queuedDelete.name],
  );
}
