import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';
import 'package:aaplay/core/audio/translation/supertonic_tts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SupertonicTtsService.buildBody / cacheKey (pure)', () {
    test('body 含 text/voice/lang，且固定要 wav', () {
      expect(
        SupertonicTtsService.buildBody(
          text: '你好',
          voice: 'M1',
          lang: 'na',
        ),
        {
          'text': '你好',
          'voice': 'M1',
          'lang': 'na',
          'response_format': 'wav',
        },
      );
    });

    test('cacheKey 对 text/voice/lang 敏感且稳定', () {
      String key({required String text, String voice = 'M1', String lang = 'na'}) =>
          SupertonicTtsService.cacheKey(text: text, voice: voice, lang: lang);

      expect(key(text: '行一'), key(text: '行一'));
      expect(key(text: '行一'), isNot(key(text: '行二')));
      expect(key(text: '行一'), isNot(key(text: '行一', voice: 'F2')));
      expect(key(text: '行一'), isNot(key(text: '行一', lang: 'ja')));
    });
  });

  group('SupertonicTtsService HTTP 映射', () {
    late Directory tmp;
    late SharedPreferences prefs;
    late FishTtsConfigStore config;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      config = FishTtsConfigStore(prefs: prefs);
      tmp = await Directory.systemTemp.createTemp('supertonic_tts_test');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('空文本 → emptyAudio', () async {
      final svc = SupertonicTtsService(
        config: config,
        cacheDirResolver: () async => tmp,
      );
      await expectLater(
        svc.synthesize('   '),
        throwsA(isA<FishTtsException>().having(
          (e) => e.error,
          'error',
          FishTtsError.emptyAudio,
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
              data: [0x52, 0x49, 0x46, 0x46, 9],
            ));
          },
        ));
      final svc = SupertonicTtsService(
        config: config,
        dio: dio,
        cacheDirResolver: () async => tmp,
      );
      final first = await svc.synthesize('缓存行');
      expect(first, [0x52, 0x49, 0x46, 0x46, 9]);
      final second = await svc.synthesize('缓存行');
      expect(second, [0x52, 0x49, 0x46, 0x46, 9]);
      expect(hits, 1);
      // 请求确实打到了本地 /v1/tts，且带了 wav 参数。
    });

    test('请求打到配置地址的 /v1/tts，body 走当前音色/语言', () async {
      String? path;
      Map<String, dynamic>? body;
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            path = options.path;
            body = options.data as Map<String, dynamic>?;
            handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: [1, 2, 3],
            ));
          },
        ));
      await config.setSupertonicVoice('F2');
      await config.setSupertonicLang('ja');
      final svc = SupertonicTtsService(
        config: config,
        dio: dio,
        cacheDirResolver: () async => tmp,
      );
      await svc.synthesize('行A');
      expect(path, 'http://127.0.0.1:7788/v1/tts');
      expect(body?['voice'], 'F2');
      expect(body?['lang'], 'ja');
      expect(body?['response_format'], 'wav');
    });

    test('非 2xx → badResponse', () async {
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(Response(
              requestOptions: options,
              statusCode: 500,
              data: [1],
            ));
          },
        ));
      final svc = SupertonicTtsService(
        config: config,
        dio: dio,
        cacheDirResolver: () async => tmp,
      );
      await expectLater(
        svc.synthesize('行B'),
        throwsA(isA<FishTtsException>().having(
          (e) => e.error,
          'error',
          FishTtsError.badResponse,
        )),
      );
    });

    test('连不上本地服务（连接被拒） → unavailable', () async {
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                error: const SocketException('Connection refused'),
              ),
            );
          },
        ));
      final svc = SupertonicTtsService(
        config: config,
        dio: dio,
        cacheDirResolver: () async => tmp,
      );
      await expectLater(
        svc.synthesize('行C'),
        throwsA(isA<FishTtsException>().having(
          (e) => e.error,
          'error',
          FishTtsError.unavailable,
        )),
      );
    });

    test('isHealthy：2xx → true；连不上 → false', () async {
      var up = true;
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            if (up) {
              handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: {'status': 'ok'},
              ));
            } else {
              handler.reject(DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ));
            }
          },
        ));
      final svc = SupertonicTtsService(config: config, dio: dio);

      expect(await svc.isHealthy(), isTrue);
      up = false;
      expect(await svc.isHealthy(), isFalse);
    });
  });
}
