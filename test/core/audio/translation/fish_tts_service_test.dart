import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';
import 'package:aaplay/core/audio/translation/fish_tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FishTtsService.buildBody / cacheKey (pure)', () {
    test('body 含 text/format，有 reference_id 才带 reference_id', () {
      expect(
        FishTtsService.buildBody(text: '你好', referenceId: ''),
        {'text': '你好', 'format': 'mp3'},
      );
      expect(
        FishTtsService.buildBody(text: 'hi', referenceId: 'voice1'),
        {'text': 'hi', 'format': 'mp3', 'reference_id': 'voice1'},
      );
    });

    test('cacheKey 对 text/ref/model 敏感且稳定', () {
      final a = FishTtsService.cacheKey(
        text: '行一',
        referenceId: 'v',
        model: 's2.1-pro-free',
      );
      final b = FishTtsService.cacheKey(
        text: '行一',
        referenceId: 'v',
        model: 's2.1-pro-free',
      );
      expect(a, b);
      expect(
        a,
        isNot(FishTtsService.cacheKey(
          text: '行一',
          referenceId: 'v2',
          model: 's2.1-pro-free',
        )),
      );
      expect(
        a,
        isNot(FishTtsService.cacheKey(
          text: '行一',
          referenceId: 'v',
          model: 's1',
        )),
      );
    });
  });

  group('FishTtsConfigStore', () {
    test('model/secondaryVolume/referenceId 默认值与写入', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FishTtsConfigStore(prefs: prefs);

      expect(store.model, FishTtsConfigStore.defaultModel);
      expect(store.secondaryVolume, FishTtsConfigStore.defaultSecondaryVolume);
      expect(store.referenceId, '');

      await store.setModel('s1');
      await store.setReferenceId(' voice-x ');
      await store.setSecondaryVolume(1.5);

      expect(store.model, 's1');
      expect(store.referenceId, 'voice-x');
      expect(store.secondaryVolume, 1.0);

      await store.setModel('bogus');
      expect(store.model, FishTtsConfigStore.defaultModel);
    });

    test('delayMs 默认 0，可写入并在 reload 后保持', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FishTtsConfigStore(prefs: prefs);
      expect(store.delayMs, FishTtsConfigStore.defaultDelayMs);

      await store.setDelayMs(300);
      expect(store.delayMs, 300);
      expect(FishTtsConfigStore(prefs: prefs).delayMs, 300);

      await store.setDelayMs(-5);
      expect(store.delayMs, 0);
      expect(FishTtsConfigStore.delayOptionsMs, containsAll([0, 300, 1000]));
    });

    test('requireApiKey 未配置 → noApiKey', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FishTtsConfigStore(prefs: prefs);
      store.debugCacheApiKey('');
      await expectLater(
        store.requireApiKey(),
        throwsA(isA<FishTtsException>().having(
          (e) => e.error,
          'error',
          FishTtsError.noApiKey,
        )),
      );
    });
  });

  group('FishTtsService HTTP 映射', () {
    late Directory tmp;
    late SharedPreferences prefs;
    late FishTtsConfigStore config;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      config = FishTtsConfigStore(prefs: prefs);
      config.debugCacheApiKey('test-key');
      tmp = await Directory.systemTemp.createTemp('fish_tts_test');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('未配置 key → noApiKey', () async {
      final empty = FishTtsConfigStore(prefs: prefs);
      empty.debugCacheApiKey('');
      final svc = FishTtsService(
        config: empty,
        cacheDirResolver: () async => tmp,
      );
      await expectLater(
        svc.synthesize('x'),
        throwsA(isA<FishTtsException>().having(
          (e) => e.error,
          'error',
          FishTtsError.noApiKey,
        )),
      );
    });

    test('401 响应 → unauthorized', () async {
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(Response(
              requestOptions: options,
              statusCode: 401,
              data: [1, 2, 3],
            ));
          },
        ));
      final svc = FishTtsService(
        config: config,
        dio: dio,
        cacheDirResolver: () async => tmp,
      );
      await expectLater(
        svc.synthesize('行A'),
        throwsA(isA<FishTtsException>().having(
          (e) => e.error,
          'error',
          FishTtsError.unauthorized,
        )),
      );
    });

    test('200 写缓存；二次调用直接读缓存（拦截器计数=1）', () async {
      var hits = 0;
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            hits++;
            handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: [10, 20, 30],
            ));
          },
        ));
      final svc = FishTtsService(
        config: config,
        dio: dio,
        cacheDirResolver: () async => tmp,
      );
      final first = await svc.synthesize('缓存行');
      expect(first, [10, 20, 30]);
      final second = await svc.synthesize('缓存行');
      expect(second, [10, 20, 30]);
      expect(hits, 1);
    });
  });
}
