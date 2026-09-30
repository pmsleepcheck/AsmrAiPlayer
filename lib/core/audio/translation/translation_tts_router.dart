import 'dart:typed_data';

import 'fish_tts_config.dart';
import 'fish_tts_service.dart';
import 'supertonic_tts_service.dart';
import 'tts_synthesizer.dart';

/// 按 `FishTtsConfigStore.ttsSource` 把合成请求分发到对应引擎。
///
/// 控制器只拿这一个对象，切换引擎 = 改配置（`setTtsSource`），无需重建依赖。
/// 新增引擎：实现 [TtsSynthesizer] → 加 [TtsSource] 枚举值 → 在这里注册。
class TranslationTtsRouter implements TtsSynthesizer {
  final FishTtsConfigStore config;
  final FishTtsService fish;
  final SupertonicTtsService supertonic;

  const TranslationTtsRouter({
    required this.config,
    required this.fish,
    required this.supertonic,
  });

  /// 当前生效的引擎。未知配置值由 `TtsSource.fromId` 兜底为 supertonic。
  TtsSynthesizer get current => switch (config.ttsSource) {
        TtsSource.fish => fish,
        TtsSource.supertonic => supertonic,
      };

  @override
  Future<Uint8List> synthesize(String text) => current.synthesize(text);
}
