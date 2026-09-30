import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';
import 'package:aaplay/core/audio/translation/supertonic_tts_service.dart';
import 'package:aaplay/core/audio/translation/tts_synthesizer.dart';
import 'package:aaplay/screens/settings/fish_tts_settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late FishTtsConfigStore config;
  late SupertonicTtsService supertonic;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    config = FishTtsConfigStore(prefs: prefs);
    supertonic = SupertonicTtsService(
      config: config,
      // 健康检测在测试里永远失败 → 不打真实网络。
      dio: Dio()
        ..interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
            ));
          },
        )),
    );
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FishTtsSettingsDialog(config: config, supertonic: supertonic),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('默认 Supertonic：显示引擎下拉与本地服务分区，隐藏 Fish 配置', (tester) async {
    await pumpDialog(tester);

    expect(find.text(Strings.ttsSourceSupertonic), findsWidgets);
    expect(find.text(Strings.supertonicBaseUrlLabel), findsOneWidget);
    expect(find.text(Strings.supertonicVoiceLabel), findsOneWidget);
    expect(find.text(Strings.supertonicLangLabel), findsOneWidget);
    expect(find.text(Strings.supertonicCheck), findsOneWidget);
    expect(find.text(Strings.supertonicStart), findsOneWidget);
    // Fish 专属区不显示。
    expect(find.text(Strings.fishApiKey), findsNothing);
    expect(find.text(Strings.voicePresetSection), findsNothing);
    expect(find.text(Strings.fishModel), findsNothing);
    // 与引擎无关的两区始终可见。
    expect(find.text(Strings.translationDelayLabel), findsOneWidget);
    expect(
      find.textContaining(Strings.translationSecondaryVolumeLabel),
      findsOneWidget,
    );
  });

  testWidgets('切换菜单两项；切到 Fish 后显示 Key/预设/模型、隐藏本地服务分区',
      (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text(Strings.ttsSourceSupertonic).first);
    await tester.pumpAndSettle();

    expect(find.text(Strings.ttsSourceSupertonic), findsWidgets);
    expect(find.text(Strings.ttsSourceFish), findsOneWidget);

    await tester.tap(find.text(Strings.ttsSourceFish));
    await tester.pumpAndSettle();

    expect(find.text(Strings.fishApiKey), findsOneWidget);
    expect(find.text(Strings.voicePresetSection), findsOneWidget);
    expect(find.text(Strings.fishModel), findsOneWidget);
    expect(find.text(Strings.supertonicBaseUrlLabel), findsNothing);
    expect(find.text(Strings.supertonicCheck), findsNothing);
  });

  testWidgets('保存后引擎切换落盘', (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text(Strings.ttsSourceSupertonic).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(Strings.ttsSourceFish));
    await tester.pumpAndSettle();

    // 不填 API Key（测试环境无 secure storage 插件），只验证引擎落盘。
    await tester.tap(find.text(Strings.save));
    await tester.pumpAndSettle();

    expect(config.ttsSource, TtsSource.fish);
    expect(FishTtsConfigStore(prefs: prefs).ttsSource, TtsSource.fish);
  });

  testWidgets('保存后 Supertonic 音色/地址落盘', (tester) async {
    await pumpDialog(tester);

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'http://127.0.0.1:9000/');
    await tester.enterText(fields.at(1), 'F3');
    await tester.enterText(fields.at(2), 'ja');
    await tester.tap(find.text(Strings.save));
    await tester.pumpAndSettle();

    expect(config.supertonicBaseUrl, 'http://127.0.0.1:9000');
    expect(config.supertonicVoice, 'F3');
    expect(config.supertonicLang, 'ja');
    expect(config.ttsSource, TtsSource.supertonic);
  });
}
