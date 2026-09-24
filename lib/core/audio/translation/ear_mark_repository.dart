import 'package:shared_preferences/shared_preferences.dart';
import 'ear_side.dart';

/// 用户人工标记的主耳（按 DownloadService.fileKey 持久化）。
///
/// 存 SharedPreferences 字符串 map：`translation_ear_marks` → `{fileKey: left|right}`。
/// 检测链（文件名→波形→弹窗）命中用户标记后写入；下次直接复用。
class EarMarkRepository {
  static const String prefsKey = 'translation_ear_marks';

  final SharedPreferences _prefs;

  /// 进程内缓存，避免每次列表渲染都解 JSON。
  Map<String, EarSide>? _cache;

  EarMarkRepository(this._prefs);

  Map<String, EarSide> _load() {
    if (_cache != null) return _cache!;
    final raw = _prefs.getStringList(prefsKey);
    final map = <String, EarSide>{};
    if (raw != null) {
      for (final entry in raw) {
        final idx = entry.indexOf('=');
        if (idx <= 0) continue;
        final key = entry.substring(0, idx);
        final side = EarSide.tryParse(entry.substring(idx + 1));
        if (side != null) map[key] = side;
      }
    }
    _cache = map;
    return map;
  }

  EarSide? get(String fileKey) => _load()[fileKey];

  Future<void> mark(String fileKey, EarSide side) async {
    final map = _load();
    if (map[fileKey] == side) return;
    map[fileKey] = side;
    _cache = map;
    await _persist(map);
  }

  Future<void> clear(String fileKey) async {
    final map = _load();
    if (map.remove(fileKey) == null) return;
    _cache = map;
    await _persist(map);
  }

  Future<void> _persist(Map<String, EarSide> map) async {
    final list = map.entries.map((e) => '${e.key}=${e.value.storageValue}');
    await _prefs.setStringList(prefsKey, list.toList());
  }
}
