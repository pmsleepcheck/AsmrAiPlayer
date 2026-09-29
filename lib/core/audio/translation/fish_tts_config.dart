import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 命名音色预设。`fromJson` 忽略未知字段（未来可加 `role` 等扩展位）。
@immutable
class FishVoicePreset {
  final String id;
  final String name;
  final String referenceId;

  const FishVoicePreset({
    required this.id,
    required this.name,
    required this.referenceId,
  });

  factory FishVoicePreset.fromJson(Map<String, dynamic> json) {
    return FishVoicePreset(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      referenceId: (json['referenceId'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'referenceId': referenceId,
      };

  FishVoicePreset copyWith({String? name, String? referenceId}) =>
      FishVoicePreset(
        id: id,
        name: name ?? this.name,
        referenceId: referenceId ?? this.referenceId,
      );

  @override
  bool operator ==(Object other) =>
      other is FishVoicePreset &&
      other.id == id &&
      other.name == name &&
      other.referenceId == referenceId;

  @override
  int get hashCode => Object.hash(id, name, referenceId);
}

/// Fish Audio TTS 配置。
///
/// - API Key 走 [FlutterSecureStorage]（不落明文 SharedPreferences）。
/// - reference_id / model / 音色预设 走 SharedPreferences（非敏感）。
/// - 二次输出与主音轨的混播次音量（0..1）也在 SharedPreferences。
class FishTtsConfigStore extends ChangeNotifier {
  static const String secureApiKey = 'fish_api_key';
  static const String prefReferenceId = 'fish_reference_id';
  static const String prefModel = 'fish_model';
  static const String prefSecondaryVolume = 'translation_secondary_volume';
  static const String prefAutoVolume = 'translation_auto_volume';
  static const String prefDelayMs = 'translation_delay_ms';
  static const String prefVoicePresets = 'fish_voice_presets';
  static const String prefActiveVoiceId = 'fish_active_voice_id';

  /// 免费开发档（fish 文档：`s2.1-pro-free`）。
  static const String defaultModel = 's2.1-pro-free';
  static const double defaultSecondaryVolume = 0.7;
  static const bool defaultAutoVolume = true;
  static const int defaultDelayMs = 0;

  static const List<String> modelOptions = [
    's2.1-pro-free',
    's2.1-pro',
    's2-pro',
    's1',
  ];

  /// 同声传译延迟档（毫秒），界面下拉选择。
  static const List<int> delayOptionsMs = [0, 100, 200, 300, 500, 1000];

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  FishTtsConfigStore({
    required SharedPreferences prefs,
    FlutterSecureStorage? secure,
  })  : _prefs = prefs,
        _secure = secure ?? const FlutterSecureStorage();

  Future<String?> readApiKey() async {
    try {
      return await _secure.read(key: secureApiKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeApiKey(String value) async {
    final v = value.trim();
    if (v.isEmpty) {
      await _secure.delete(key: secureApiKey);
      _apiKey = null;
    } else {
      await _secure.write(key: secureApiKey, value: v);
      _apiKey = v;
    }
    _apiKeyLoaded = true;
  }

  bool get hasApiKey => (_apiKey ?? '').isNotEmpty;

  String? _apiKey;
  bool _apiKeyLoaded = false;

  Future<String?> loadApiKey() async {
    if (_apiKeyLoaded) return _apiKey;
    _apiKey = await readApiKey();
    _apiKeyLoaded = true;
    return _apiKey;
  }

  /// 供服务在每次请求前调用（保证最新）。
  Future<String> requireApiKey() async {
    final key = await loadApiKey();
    if (key == null || key.trim().isEmpty) {
      throw FishTtsException(FishTtsError.noApiKey);
    }
    return key.trim();
  }

  // === 音色预设 ===

  /// 当前预设列表（JSON 数组，`fromJson` 忽略未知字段）。
  List<FishVoicePreset> get voicePresets {
    final raw = _prefs.getString(prefVoicePresets);
    if (raw == null || raw.isEmpty) {
      // 一次性迁移：旧单值 → 单条预设（仅当列表键尚不存在）。
      final legacy = (_prefs.getString(prefReferenceId) ?? '').trim();
      if (legacy.isNotEmpty) {
        final migrated = [
          FishVoicePreset(
            id: 'legacy',
            name: '默认音色',
            referenceId: legacy,
          ),
        ];
        _prefs.setString(
          prefVoicePresets,
          jsonEncode(migrated.map((e) => e.toJson()).toList()),
        );
        if ((_prefs.getString(prefActiveVoiceId) ?? '').isEmpty) {
          _prefs.setString(prefActiveVoiceId, 'legacy');
        }
        return List.unmodifiable(migrated);
      }
      return const [];
    }
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return List.unmodifiable(
        list
            .whereType<Map<String, dynamic>>()
            .map(FishVoicePreset.fromJson),
      );
    } catch (_) {
      return const [];
    }
  }

  String get activeVoiceId => _prefs.getString(prefActiveVoiceId) ?? '';

  FishVoicePreset? get activeVoice {
    final id = activeVoiceId;
    if (id.isEmpty) return null;
    for (final p in voicePresets) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 生效的 referenceId：当前预设 → 旧 `fish_reference_id` 兜底 → 空。
  String get referenceId {
    final active = activeVoice;
    if (active != null && active.referenceId.isNotEmpty) {
      return active.referenceId;
    }
    return _prefs.getString(prefReferenceId) ?? '';
  }

  Future<void> setReferenceId(String v) =>
      _prefs.setString(prefReferenceId, v.trim());

  Future<void> _persistPresets(List<FishVoicePreset> presets) async {
    await _prefs.setString(
      prefVoicePresets,
      jsonEncode(presets.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  /// 设置活动预设 id；`null`/空串清除（回落 legacy `fish_reference_id`）。
  Future<void> setActiveVoiceId(String? id) async {
    final target = (id ?? '').trim();
    if (activeVoiceId == target) return;
    if (target.isEmpty) {
      await _prefs.remove(prefActiveVoiceId);
    } else {
      await _prefs.setString(prefActiveVoiceId, target);
    }
    notifyListeners();
  }

  /// 新增/更新（按 id）。name/referenceId 会 trim。
  Future<void> upsertPreset(FishVoicePreset preset) async {
    final name = preset.name.trim();
    final ref = preset.referenceId.trim();
    if (name.isEmpty) return;
    final next = List<FishVoicePreset>.from(voicePresets);
    final i = next.indexWhere((p) => p.id == preset.id);
    final cleaned = preset.copyWith(name: name, referenceId: ref);
    if (i >= 0) {
      next[i] = cleaned;
    } else {
      next.add(cleaned);
    }
    await _persistPresets(next);
    if (activeVoiceId.isEmpty) {
      await setActiveVoiceId(cleaned.id);
    }
  }

  Future<void> removePreset(String id) async {
    final next = voicePresets.where((p) => p.id != id).toList();
    await _persistPresets(next);
    if (activeVoiceId == id) {
      await setActiveVoiceId(null);
    }
  }

  /// 生成短 id（时间戳 base36，无 uuid 依赖）。
  static String newPresetId() =>
      DateTime.now().millisecondsSinceEpoch.toRadixString(36);

  String get model {
    final m = _prefs.getString(prefModel);
    if (m == null || m.isEmpty) return defaultModel;
    return modelOptions.contains(m) ? m : defaultModel;
  }

  Future<void> setModel(String v) => _prefs.setString(prefModel, v);

  double get secondaryVolume {
    final v = _prefs.getDouble(prefSecondaryVolume);
    if (v == null || v.isNaN || v < 0) return defaultSecondaryVolume;
    return v > 1 ? 1 : v;
  }

  /// 手动音量变化要**立即**作用到进行中的会话 → 变更时 notify。
  Future<void> setSecondaryVolume(double v) async {
    final next = v.clamp(0.0, 1.0);
    if (secondaryVolume == next) return;
    await _prefs.setDouble(prefSecondaryVolume, next);
    notifyListeners();
  }

  /// 自动响度对齐开关（默认开）。关掉 = 纯手动（按 [secondaryVolume] 比例）。
  bool get translationAutoVolume =>
      _prefs.getBool(prefAutoVolume) ?? defaultAutoVolume;

  Future<void> setTranslationAutoVolume(bool v) async {
    if (translationAutoVolume == v) return;
    await _prefs.setBool(prefAutoVolume, v);
    notifyListeners();
  }

  /// 同声传译延迟（毫秒）。字幕行出现后先等这么久再播翻译轨。
  int get delayMs {
    final v = _prefs.getInt(prefDelayMs);
    if (v == null || v < 0) return defaultDelayMs;
    return v;
  }

  Future<void> setDelayMs(int v) =>
      _prefs.setInt(prefDelayMs, v < 0 ? 0 : v);

  @visibleForTesting
  void debugCacheApiKey(String? key) {
    _apiKey = key;
    _apiKeyLoaded = true;
  }
}

enum FishTtsError {
  noApiKey,
  unauthorized,
  network,
  badResponse,
  emptyAudio,
}

class FishTtsException implements Exception {
  final FishTtsError error;
  final String? detail;

  FishTtsException(this.error, [this.detail]);

  @override
  String toString() => 'FishTtsException(${error.name}${detail == null ? '' : ': $detail'})';
}
