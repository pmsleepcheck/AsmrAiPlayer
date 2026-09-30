import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/audio/i_audio_player_service.dart';
import 'package:aaplay/core/platform/sleep_timer_controller.dart';
import 'package:aaplay/screens/settings/sleep_timer_dialog.dart';
import 'package:aaplay/widgets/player/sleep_timer_footer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只暴露 pause()，其余走 noSuchMethod 抛错以捕获未预期调用。
class _FakeAudioService implements IAudioPlayerService {
  @override
  Future<void> pause() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('未预期调用: ${invocation.memberName}');
}

/// bug.txt 2026-09-28 ③：睡眠倒计时**整行**可点（原热区只有右侧「修改」文案）。
void main() {
  late SleepTimerController controller;

  setUp(() => controller = SleepTimerController(_FakeAudioService()));

  Future<void> pumpFooter(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerSleepTimerFooter(sleepTimer: controller),
        ),
      ),
    );
  }

  testWidgets('点左侧图标打开定时对话框', (tester) async {
    await pumpFooter(tester);
    await tester.tap(find.byIcon(Icons.bedtime_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SleepTimerDialog), findsOneWidget);
  });

  testWidgets('点行内最左侧空白处也打开对话框', (tester) async {
    await pumpFooter(tester);
    final rect = tester.getRect(find.byType(InkWell));
    await tester.tapAt(Offset(rect.left + 4, rect.center.dy));
    await tester.pumpAndSettle();
    expect(find.byType(SleepTimerDialog), findsOneWidget);
  });

  testWidgets('点右侧「修改」文案仍然打开对话框', (tester) async {
    await pumpFooter(tester);
    await tester.tap(find.text(Strings.playerSleepTimerChange));
    await tester.pumpAndSettle();
    expect(find.byType(SleepTimerDialog), findsOneWidget);
  });

  testWidgets('未设置时显示未启用文案（样式不变）', (tester) async {
    await pumpFooter(tester);
    expect(find.byType(Divider), findsOneWidget);
    expect(find.text(Strings.playerSleepTimerChange), findsOneWidget);
    expect(find.byType(InkWell), findsOneWidget);
  });
}
