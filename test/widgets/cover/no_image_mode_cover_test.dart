import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';
import 'package:aaplay/core/settings/no_image_mode.dart';
import 'package:aaplay/widgets/detail/work_cover.dart';
import 'package:aaplay/widgets/mini_player/mini_player_cover.dart';
import 'package:aaplay/widgets/player/square_cover.dart';
import 'package:aaplay/widgets/work_card/components/work_cover_image.dart';

const _url = 'https://cdn.example.com/cover.jpg';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(width: 240, child: child)));

Future<void> _registerSettings(WidgetTester tester, {required bool noImage}) async {
  SharedPreferences.setMockInitialValues({'no_image_mode': noImage});
  final prefs = await SharedPreferences.getInstance();
  if (GetIt.I.isRegistered<AppSettingsService>()) {
    await GetIt.I.unregister<AppSettingsService>();
  }
  GetIt.I.registerSingleton<AppSettingsService>(AppSettingsService(prefs));
  expect(GetIt.I<AppSettingsService>().noImageMode, noImage);
  await tester.pumpWidget(const SizedBox()); // 让后续 pump 重建
}

void main() {
  tearDown(() async {
    await GetIt.I.reset();
  });

  group('noImageModeEnabled / withNoImageMode', () {
    test('GetIt 未注册 settings → false（无 DI 测试安全回退）', () async {
      await GetIt.I.reset();
      expect(noImageModeEnabled(), isFalse);
    });

    test('注册后读取 prefs', () async {
      SharedPreferences.setMockInitialValues({'no_image_mode': true});
      final prefs = await SharedPreferences.getInstance();
      GetIt.I.registerSingleton<AppSettingsService>(AppSettingsService(prefs));
      expect(noImageModeEnabled(), isTrue);
      await GetIt.I.unregister<AppSettingsService>();
    });
  });

  group('封面不加载网络图', () {
    testWidgets('WorkCoverImage：on → 无 CachedNetworkImage + 占位 icon', (tester) async {
      await _registerSettings(tester, noImage: true);
      await tester.pumpWidget(_host(const WorkCoverImage(
        imageUrl: _url,
        workId: 1,
        sourceId: 'RJ001',
        durationSeconds: 65,
      )));
      await tester.pump();
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      // 角标仍保留
      expect(find.text('RJ001'), findsOneWidget);
      expect(find.text('1:05'), findsOneWidget);
    });

    testWidgets('WorkCoverImage：off → 渲染网络图', (tester) async {
      await _registerSettings(tester, noImage: false);
      await tester.pumpWidget(_host(const WorkCoverImage(
        imageUrl: _url,
        workId: 1,
        sourceId: 'RJ001',
      )));
      await tester.pump();
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      expect(find.byIcon(Icons.image_outlined), findsNothing);
    });

    testWidgets('WorkCover（详情）：on → 占位；off → 网络图', (tester) async {
      await _registerSettings(tester, noImage: true);
      await tester.pumpWidget(_host(const WorkCover(
        imageUrl: _url,
        workId: 2,
        sourceId: 'RJ002',
        heroTag: 'work-cover-2',
      )));
      await tester.pump();
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);

      await _registerSettings(tester, noImage: false);
      await tester.pumpWidget(_host(const WorkCover(
        imageUrl: _url,
        workId: 2,
        sourceId: 'RJ002',
        heroTag: 'work-cover-2',
      )));
      await tester.pump();
      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });

    testWidgets('SquareCover：on 有 URL → image 占位非音符；off → 网络图', (tester) async {
      await _registerSettings(tester, noImage: true);
      await tester.pumpWidget(_host(const SquareCover(coverUrl: _url)));
      await tester.pump();
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(find.byIcon(Icons.music_note), findsNothing);

      await _registerSettings(tester, noImage: false);
      await tester.pumpWidget(_host(const SquareCover(coverUrl: _url)));
      await tester.pump();
      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });

    testWidgets('MiniPlayerCover：on 有 URL → 占位不走网络', (tester) async {
      await _registerSettings(tester, noImage: true);
      await tester.pumpWidget(_host(const MiniPlayerCover(coverUrl: _url)));
      await tester.pump();
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    });
  });
}
