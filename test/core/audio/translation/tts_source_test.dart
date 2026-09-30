import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';
import 'package:aaplay/core/audio/translation/tts_synthesizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('clipExtension（按内容判定容器）', () {
    test('RIFF 头 → wav（Supertonic）', () {
      expect(
        clipExtension([0x52, 0x49, 0x46, 0x46, 0x00, 0x00]),
        'wav',
      );
    });

    test('ID3 / 垃圾字节 / 空 → mp3（Fish 与旧行为）', () {
      expect(clipExtension([0x49, 0x44, 0x33, 0x00]), 'mp3');
      expect(clipExtension([0xFF, 0xFB, 0x90, 0x00]), 'mp3');
      expect(clipExtension([0x01, 0x02]), 'mp3');
      expect(clipExtension([]), 'mp3');
    });
  });

  group('TtsSource', () {
    test('未知 / 空 id 回落 supertonic（默认引擎）', () {
      expect(TtsSource.fromId(null), TtsSource.supertonic);
      expect(TtsSource.fromId(''), TtsSource.supertonic);
      expect(TtsSource.fromId('bogus'), TtsSource.supertonic);
      expect(TtsSource.fromId('fish'), TtsSource.fish);
      expect(TtsSource.fromId('supertonic'), TtsSource.supertonic);
    });
  });

  group('FishTtsConfigStore · 引擎与 Supertonic 参数', () {
    test('ttsSource 默认 supertonic，写入持久化 + 仅变更时通知', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FishTtsConfigStore(prefs: prefs);

      expect(store.ttsSource, TtsSource.supertonic);

      var notified = 0;
      store.addListener(() => notified++);

      await store.setTtsSource(TtsSource.fish);
      expect(store.ttsSource, TtsSource.fish);
      expect(notified, 1);

      // 同值再写不通知（避免切换菜单每次保存都重建播放页）。
      await store.setTtsSource(TtsSource.fish);
      expect(notified, 1);

      expect(FishTtsConfigStore(prefs: prefs).ttsSource, TtsSource.fish);
    });

    test('Supertonic 地址/音色/语言 默认值与规范化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FishTtsConfigStore(prefs: prefs);

      expect(store.supertonicBaseUrl,
          FishTtsConfigStore.defaultSupertonicBaseUrl);
      expect(store.supertonicVoice, FishTtsConfigStore.defaultSupertonicVoice);
      expect(store.supertonicLang, FishTtsConfigStore.defaultSupertonicLang);

      await store.setSupertonicBaseUrl('  http://127.0.0.1:9000/  ');
      expect(store.supertonicBaseUrl, 'http://127.0.0.1:9000');

      await store.setSupertonicBaseUrl('   ');
      expect(store.supertonicBaseUrl,
          FishTtsConfigStore.defaultSupertonicBaseUrl);

      var notified = 0;
      store.addListener(() => notified++);
      await store.setSupertonicVoice(' F2 ');
      expect(store.supertonicVoice, 'F2');
      expect(notified, 1);
      await store.setSupertonicVoice('F2');
      expect(notified, 1);

      await store.setSupertonicLang(' ja ');
      expect(store.supertonicLang, 'ja');
      await store.setSupertonicLang('');
      expect(store.supertonicLang, FishTtsConfigStore.defaultSupertonicLang);
    });
  });
}
