import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Top-level accent color variants. Surfaces stay neutral (white/black) across
/// all variants — only the `primary` token rotates. Persisted by
/// [AppSettingsService.colorVariant].
enum ColorVariant {
  blue,
  mono,
  green,

  /// Modernist 设计稿的招牌红。持久化按 `name` 存取，旧存档解析不到时
  /// 由 `orElse` 落回默认值，因此新增枚举值不影响已安装用户。
  still,
}

/// 播放页字幕显示三模式（bug.txt 2）。
/// 持久化按 `name`；旧存档无键 → [SubtitleDisplayMode.inApp]。
enum SubtitleDisplayMode {
  /// 关闭：不显示自动字幕条 / 不开系统悬浮。
  off,

  /// 应用内：播放页底部当前行字幕条（点击仍可进全屏歌词）。
  inApp,

  /// 弹窗：Android 系统悬浮字幕；无系统悬浮能力的平台降级为应用内字幕条。
  popup,
}

class AppSettingsService extends ChangeNotifier {
  static const String _serverUrlKey = 'server_url';
  static const String _smartPathKey = 'smart_path_enabled';
  static const String _audioFormatOrderKey = 'audio_format_order';
  static const String _colorVariantKey = 'color_variant';
  static const String _lyricOverlayUnlockedKey = 'lyric_overlay_unlocked';
  static const String _backgroundPlayKey = 'background_play_enabled';
  // 跨多个列表 ViewModel 共享的「仅看带字幕作品」筛选。收敛到此单点，
  // 取代各 VM 自行 SharedPreferences.getInstance() + dispose 回写陈旧值。
  static const String _subtitleFilterKey = 'subtitle_filter';
  static const String _proxyEnabledKey = 'proxy_enabled';
  static const String _proxyUrlKey = 'proxy_url';
  static const String _noImageModeKey = 'no_image_mode';
  static const String _subtitleDisplayModeKey = 'subtitle_display_mode';

  /// 本地缓存页视图：true=文件夹树形（默认，按磁盘真实目录层级），
  /// false=显示全部文件（按作品分组的扁平列表）。
  static const String _localCacheTreeModeKey = 'local_cache_tree_mode';

  /// 附加缓存/扫描目录（绝对路径列表，默认空 = 仅默认下载根）。
  /// 只读扫描源：新下载仍写默认根；Win/Android 同一代码路径。
  static const String _downloadExtraDirsKey = 'download_extra_dirs';

  static const String defaultServerUrl = 'https://api.asmr.one/api';
  static const ColorVariant defaultColorVariant = ColorVariant.blue;
  static const SubtitleDisplayMode defaultSubtitleDisplayMode =
      SubtitleDisplayMode.inApp;
  static const String defaultProxyUrl = '127.0.0.1:7890';
  static const bool defaultLocalCacheTreeMode = true;
  static const List<String> defaultAudioFormatOrder = [
    'mp3',
    'flac',
    'wav',
    'opus',
    'm4a',
    'aac'
  ];

  /// Available server options
  static const Map<String, String> serverOptions = {
    'https://api.asmr.one/api': '主站 (asmr.one)',
    'https://api.asmr-100.com/api': '节点1 (asmr-100.com)',
    'https://api.asmr-200.com/api': '节点2 (asmr-200.com)',
    'https://api.asmr-300.com/api': '节点3 (asmr-300.com)',
  };

  final SharedPreferences _prefs;

  late String _serverUrl;
  late bool _smartPathEnabled;
  late List<String> _audioFormatOrder;
  late ColorVariant _colorVariant;
  late bool _lyricOverlayUnlocked;
  late bool _backgroundPlayEnabled;
  late bool _hasSubtitleFilter;
  late bool _proxyEnabled;
  late String _proxyUrl;
  late bool _noImageMode;
  late List<String> _downloadExtraDirs;
  late SubtitleDisplayMode _subtitleDisplayMode;
  late bool _localCacheTreeMode;

  AppSettingsService(this._prefs) {
    _serverUrl = _prefs.getString(_serverUrlKey) ?? defaultServerUrl;
    _smartPathEnabled = _prefs.getBool(_smartPathKey) ?? true;
    final savedOrder = _prefs.getStringList(_audioFormatOrderKey);
    _audioFormatOrder = savedOrder ?? List.from(defaultAudioFormatOrder);
    final savedVariant = _prefs.getString(_colorVariantKey);
    _colorVariant = ColorVariant.values.firstWhere(
      (v) => v.name == savedVariant,
      orElse: () => defaultColorVariant,
    );
    _lyricOverlayUnlocked = _prefs.getBool(_lyricOverlayUnlockedKey) ?? false;
    _backgroundPlayEnabled = _prefs.getBool(_backgroundPlayKey) ?? true;
    _hasSubtitleFilter = _prefs.getBool(_subtitleFilterKey) ?? false;
    _proxyEnabled = _prefs.getBool(_proxyEnabledKey) ?? false;
    _proxyUrl = _prefs.getString(_proxyUrlKey) ?? defaultProxyUrl;
    _noImageMode = _prefs.getBool(_noImageModeKey) ?? false;
    _downloadExtraDirs =
        _prefs.getStringList(_downloadExtraDirsKey) ?? const [];
    final savedSubtitleMode = _prefs.getString(_subtitleDisplayModeKey);
    _subtitleDisplayMode = SubtitleDisplayMode.values.firstWhere(
      (m) => m.name == savedSubtitleMode,
      orElse: () => defaultSubtitleDisplayMode,
    );
    _localCacheTreeMode =
        _prefs.getBool(_localCacheTreeModeKey) ?? defaultLocalCacheTreeMode;
  }

  // === Server URL ===
  String get serverUrl => _serverUrl;

  Future<void> setServerUrl(String url) async {
    if (_serverUrl == url) return;
    _serverUrl = url;
    notifyListeners();
    await _prefs.setString(_serverUrlKey, url);
  }

  // === Smart Path ===
  bool get smartPathEnabled => _smartPathEnabled;

  Future<void> setSmartPathEnabled(bool enabled) async {
    if (_smartPathEnabled == enabled) return;
    _smartPathEnabled = enabled;
    notifyListeners();
    await _prefs.setBool(_smartPathKey, enabled);
  }

  // === Subtitle Filter (shared across list ViewModels) ===
  bool get hasSubtitleFilter => _hasSubtitleFilter;

  Future<void> setHasSubtitleFilter(bool value) async {
    if (_hasSubtitleFilter == value) return;
    _hasSubtitleFilter = value;
    notifyListeners();
    await _prefs.setBool(_subtitleFilterKey, value);
  }

  // === Audio Format Order ===
  List<String> get audioFormatOrder => List.unmodifiable(_audioFormatOrder);

  /// Get supported audio file extensions with dot prefix, ordered by preference
  List<String> get audioExtensions =>
      _audioFormatOrder.map((f) => '.$f').toList();

  Future<void> setAudioFormatOrder(List<String> order) async {
    _audioFormatOrder = List.from(order);
    notifyListeners();
    await _prefs.setStringList(_audioFormatOrderKey, _audioFormatOrder);
  }

  Future<void> resetAudioFormatOrder() async {
    await setAudioFormatOrder(List.from(defaultAudioFormatOrder));
  }

  // === Lyric Overlay Lock ===
  /// `true` → 悬浮歌词可拖动调整位置；`false` → 锁定（点穿，默认）。
  bool get lyricOverlayUnlocked => _lyricOverlayUnlocked;

  Future<void> setLyricOverlayUnlocked(bool unlocked) async {
    if (_lyricOverlayUnlocked == unlocked) return;
    _lyricOverlayUnlocked = unlocked;
    notifyListeners();
    await _prefs.setBool(_lyricOverlayUnlockedKey, unlocked);
  }

  // === Background Play ===
  /// `true`（默认）→ 切后台继续播放（现有行为）；`false` → 切后台自动暂停。
  bool get backgroundPlayEnabled => _backgroundPlayEnabled;

  Future<void> setBackgroundPlayEnabled(bool enabled) async {
    if (_backgroundPlayEnabled == enabled) return;
    _backgroundPlayEnabled = enabled;
    notifyListeners();
    await _prefs.setBool(_backgroundPlayKey, enabled);
  }

  // === Proxy ===
  /// `true` → 应用内 Dio 请求走 [proxyUrl] 指定的 HTTP 代理。
  bool get proxyEnabled => _proxyEnabled;

  /// `host:port` 形态（已由设置弹窗规范化）。关闭代理时该值仅被暂存。
  String get proxyUrl => _proxyUrl;

  Future<void> setProxyEnabled(bool enabled) async {
    if (_proxyEnabled == enabled) return;
    _proxyEnabled = enabled;
    notifyListeners();
    await _prefs.setBool(_proxyEnabledKey, enabled);
  }

  Future<void> setProxyUrl(String url) async {
    if (_proxyUrl == url) return;
    _proxyUrl = url;
    notifyListeners();
    await _prefs.setString(_proxyUrlKey, url);
  }

  // === No image mode ===
  /// `true` → 列表/详情/播放器封面不发起网络图片请求（显示占位）。
  bool get noImageMode => _noImageMode;

  Future<void> setNoImageMode(bool enabled) async {
    if (_noImageMode == enabled) return;
    _noImageMode = enabled;
    notifyListeners();
    await _prefs.setBool(_noImageModeKey, enabled);
  }

  // === Extra download/cache dirs ===
  /// 附加扫描目录（绝对路径）。空列表 = 仅默认下载根（旧行为）。
  List<String> get downloadExtraDirs => List.unmodifiable(_downloadExtraDirs);

  Future<void> setDownloadExtraDirs(List<String> dirs) async {
    _downloadExtraDirs = List.from(dirs);
    notifyListeners();
    await _prefs.setStringList(_downloadExtraDirsKey, _downloadExtraDirs);
  }

  // === Color Variant ===
  ColorVariant get colorVariant => _colorVariant;

  Future<void> setColorVariant(ColorVariant variant) async {
    if (_colorVariant == variant) return;
    _colorVariant = variant;
    notifyListeners();
    await _prefs.setString(_colorVariantKey, variant.name);
  }

  // === Subtitle display mode (off / inApp / popup) ===
  SubtitleDisplayMode get subtitleDisplayMode => _subtitleDisplayMode;

  Future<void> setSubtitleDisplayMode(SubtitleDisplayMode mode) async {
    if (_subtitleDisplayMode == mode) return;
    _subtitleDisplayMode = mode;
    notifyListeners();
    await _prefs.setString(_subtitleDisplayModeKey, mode.name);
  }

  // === Local cache view (tree / flat) ===
  /// `true`（默认）→ 本地缓存按磁盘真实文件夹树展示；
  /// `false` → 按作品分组的扁平列表（显示全部文件）。
  bool get localCacheTreeMode => _localCacheTreeMode;

  Future<void> setLocalCacheTreeMode(bool enabled) async {
    if (_localCacheTreeMode == enabled) return;
    _localCacheTreeMode = enabled;
    notifyListeners();
    await _prefs.setBool(_localCacheTreeModeKey, enabled);
  }
}
