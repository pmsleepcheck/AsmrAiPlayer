import 'package:aaplay/core/download/models/work_snapshot.dart';
import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/data/models/works/work.dart';

abstract class IWorkSnapshotRepository {
  Future<void> save(String workId, {required Work work, Files? files});
  Future<WorkSnapshot?> load(String workId);
  Future<void> remove(String workId);
}
