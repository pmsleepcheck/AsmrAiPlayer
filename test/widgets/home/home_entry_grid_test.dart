import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/audio/i_audio_player_service.dart';
import 'package:aaplay/core/audio/models/audio_track_info.dart';
import 'package:aaplay/core/audio/models/playback_context.dart';
import 'package:aaplay/core/platform/sleep_timer_controller.dart';
import 'package:aaplay/screens/contents/home_content.dart';

class _NoopAudio implements IAudioPlayerService {
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> playWithContext(PlaybackContext context) async {}
  @override
  AudioTrackInfo? get currentTrack => null;
  @override
  PlaybackContext? get currentContext => null;
  @override
  Future<void> savePlaybackState() async {}
  @override
  Future<void> restorePlaybackState() async {}
}

Widget _host(void Function(int) onTap) => MaterialApp(
      home: Scaffold(body: HomeContent(onNavigateToTab: onTap)),
    );

void main() {
  setUp(() {
    if (GetIt.I.isRegistered<SleepTimerController>()) {
      GetIt.I.unregister<SleepTimerController>();
    }
    GetIt.I.registerSingleton<SleepTimerController>(
      SleepTimerController(_NoopAudio()),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('热门卡片存在并切到 Tab 3', (tester) async {
    int? target;
    await tester.pumpWidget(_host((i) => target = i));

    expect(find.text(Strings.homeGridPopular), findsOneWidget);
    expect(find.text(Strings.homeGridPopularDesc), findsOneWidget);

    await tester.tap(find.text(Strings.homeGridPopular));
    expect(target, 3);
  });

  testWidgets('原四卡仍在（推荐/搜索/本地/定时关闭）', (tester) async {
    await tester.pumpWidget(_host((_) {}));
    expect(find.text(Strings.homeGridRecommend), findsOneWidget);
    expect(find.text(Strings.homeGridSearch), findsOneWidget);
    expect(find.text(Strings.homeGridLocal), findsOneWidget);
    expect(find.text(Strings.homeGridSleepTimer), findsOneWidget);
    expect(find.text(Strings.homeGridPopular), findsOneWidget);
  });
}
