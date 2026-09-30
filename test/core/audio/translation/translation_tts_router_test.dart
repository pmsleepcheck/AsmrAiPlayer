import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';
import 'package:aaplay/core/audio/translation/fish_tts_service.dart';
import 'package:aaplay/core/audio/translation/supertonic_tts_service.dart';
import 'package:aaplay/core/audio/translation/translation_tts_router.dart';
import 'package:aaplay/core/audio/translation/tts_synthesizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TranslationTtsRouter 分发', () {
    late FishTtsConfigStore config;
    late SharedPreferences prefs;
    late TranslationTtsRouter router;
    late Directory tmp;
    var fishHits = 0;
    var supertonicHits = 0;

    Dio countingDio(void Function() onHit) => Dio()
      ..interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          onHit();
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: [1, 2, 3],
          ));
        },
      ));

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      config = FishTtsConfigStore(prefs: prefs);
      config.debugCacheApiKey('test-key');
      tmp = await Directory.systemTemp.createTemp('tts_router_test');
      fishHits = 0;
      supertonicHits = 0;
      router = TranslationTtsRouter(
        config: config,
        fish: FishTtsService(
          config: config,
          dio: countingDio(() => fishHits++),
          cacheDirResolver: () async => tmp,
        ),
        supertonic: SupertonicTtsService(
          config: config,
          dio: countingDio(() => supertonicHits++),
          cacheDirResolver: () async => tmp,
        ),
      );
    });

    test('默认（supertonic）→ 请求打到 Supertonic', () async {
      expect(config.ttsSource, TtsSource.supertonic);
      final bytes = await router.synthesize('行');
      expect(bytes, [1, 2, 3]);
      expect(supertonicHits, 1);
      expect(fishHits, 0);
    });

    test('切到 fish → 请求改打 Fish，且配置持久化', () async {
      await config.setTtsSource(TtsSource.fish);
      final bytes = await router.synthesize('行');
      expect(bytes, [1, 2, 3]);
      expect(fishHits, 1);
      expect(supertonicHits, 0);
      expect(FishTtsConfigStore(prefs: prefs).ttsSource, TtsSource.fish);
    });

    test('切回 supertonic → 再次打到本地服务', () async {
      await config.setTtsSource(TtsSource.fish);
      await config.setTtsSource(TtsSource.supertonic);
      await router.synthesize('行');
      expect(supertonicHits, 1);
      expect(fishHits, 0);
    });
  });
}
