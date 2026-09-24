import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:aaplay/core/database/database_service.dart';
import 'package:aaplay/core/download/models/work_snapshot.dart';
import 'package:aaplay/core/download/storage/i_work_snapshot_repository.dart';
import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/data/models/works/work.dart';
import 'package:aaplay/utils/logger.dart';

class WorkSnapshotRepository implements IWorkSnapshotRepository {
  static const _table = 'work_snapshots';
  final DatabaseService _db;

  WorkSnapshotRepository(this._db);

  @override
  Future<void> save(String workId, {required Work work, Files? files}) async {
    final snapshot = WorkSnapshot(
      work: work,
      files: files,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final db = await _db.database;
    await db.insert(
      _table,
      {
        'work_id': workId,
        'payload': jsonEncode(snapshot.toJson()),
        'updated_at': snapshot.updatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    AppLogger.debug('详情快照已保存: $workId');
  }

  @override
  Future<WorkSnapshot?> load(String workId) async {
    final db = await _db.database;
    final rows = await db.query(
      _table,
      where: 'work_id = ?',
      whereArgs: [workId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final map = jsonDecode(rows.first['payload'] as String)
          as Map<String, dynamic>;
      return WorkSnapshot.fromJson(map);
    } catch (e) {
      AppLogger.error('详情快照解析失败: $workId', e);
      return null;
    }
  }

  @override
  Future<void> remove(String workId) async {
    final db = await _db.database;
    await db.delete(_table, where: 'work_id = ?', whereArgs: [workId]);
  }
}
