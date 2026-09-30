import 'dart:typed_data';

/// 翻译朗读的 TTS 引擎抽象。
///
/// 控制器只认识 [TtsSynthesizer]，不关心目标是本地服务还是云端 API ——
/// 接入新引擎的步骤：
///   1. 新建 `XxxTtsService implements TtsSynthesizer`；
///   2. 在 [TtsSource] 加一个枚举值（带持久化用的 `id`）；
///   3. 在 `TranslationTtsRouter` 的分发表里注册；
///   4. 设置 → AI 翻译 的引擎下拉自动带出该项（文案放 `Strings`）。
abstract class TtsSynthesizer {
  /// 合成一段字幕行，返回可直接落盘给 just_audio 的音频字节。
  /// 失败抛 `FishTtsException`（统一 TTS 异常，见 `fish_tts_config.dart`）。
  Future<Uint8List> synthesize(String text);
}

/// 当前可用的 TTS 引擎。新增引擎时先加枚举，再补 `id` 持久化与 router 分发。
enum TtsSource {
  /// Supertonic（本地离线，`supertonic serve` 的 HTTP 服务）—— **默认**。
  supertonic('supertonic'),

  /// Fish Audio 云端 API（`api.fish.audio`，需 API Key）。
  fish('fish');

  final String id;

  const TtsSource(this.id);

  /// 按持久化 id 还原；未知/空值回落 [TtsSource.supertonic]（默认引擎）。
  static TtsSource fromId(String? id) {
    for (final s in TtsSource.values) {
      if (s.id == id) return s;
    }
    return TtsSource.supertonic;
  }
}

/// 按**音频内容**猜容器扩展名，写翻译轨临时 clip 时用。
///
/// 不能再硬编码 `.mp3`：Supertonic 返回 WAV，而 Fish 返回 MP3。判定只看
/// 文件头，`unknown` 一律按 `mp3` 兜底（= 旧行为，Fish 结果不变）。
String clipExtension(List<int> bytes) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x52 /* R */ &&
      bytes[1] == 0x49 /* I */ &&
      bytes[2] == 0x46 /* F */ &&
      bytes[3] == 0x46 /* F */) {
    return 'wav';
  }
  return 'mp3';
}
