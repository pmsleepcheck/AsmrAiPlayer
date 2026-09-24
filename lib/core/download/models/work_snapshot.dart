import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/data/models/works/work.dart';

/// 详情页持久化快照：入队下载时拷贝的 Work + 整棵 Files 树。
class WorkSnapshot {
  final Work work;
  final Files? files;
  final int updatedAt;

  const WorkSnapshot({
    required this.work,
    this.files,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'work': work.toJson(),
        if (files != null) 'files': files!.toJson(),
        'updatedAt': updatedAt,
      };

  factory WorkSnapshot.fromJson(Map<String, dynamic> json) {
    return WorkSnapshot(
      work: Work.fromJson(json['work'] as Map<String, dynamic>),
      files: json['files'] == null
          ? null
          : Files.fromJson(json['files'] as Map<String, dynamic>),
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}
