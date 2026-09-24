/// home_content.dart：底部导航「主页」tab——入口四宫格（推荐 / 搜索 /
/// 本地 / 定时关闭）。进页不再自动加载推荐作品网格（数据入口收敛到推荐
/// tab）；本页零网络请求、零分页状态。
///
/// @author  Elvis Juan (thanhtran0606en@gmail.com)
/// @created 2026-08-13
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/platform/sleep_timer_controller.dart';
import 'package:aaplay/core/theme/app_colors.dart';
import 'package:aaplay/core/theme/app_radius.dart';
import 'package:aaplay/core/theme/app_spacing.dart';
import 'package:aaplay/core/theme/app_text_styles.dart';
import 'package:aaplay/screens/search_screen.dart';
import 'package:aaplay/screens/settings/sleep_timer_dialog.dart';

class HomeContent extends StatelessWidget {
  const HomeContent({super.key, required this.onNavigateToTab});

  /// 切换 MainScreen 底部 Tab（index 与 NavigationBar 一致：
  /// 2 = 推荐，4 = 本地缓存）。Tab 的 PageController 归 MainScreen 私有，
  /// 经此回调注入，避免首页反向持有父级状态。
  final void Function(int index) onNavigateToTab;

  @override
  Widget build(BuildContext context) {
    final sleepTimer = GetIt.I<SleepTimerController>();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.pageMobile),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _HomeEntryTile(
                  icon: Icons.recommend_outlined,
                  activeIcon: Icons.recommend,
                  title: Strings.homeGridRecommend,
                  subtitle: Strings.homeGridRecommendDesc,
                  onTap: () => onNavigateToTab(2),
                ),
                const SizedBox(width: AppSpacing.space12),
                _HomeEntryTile(
                  icon: Icons.search,
                  title: Strings.homeGridSearch,
                  subtitle: Strings.homeGridSearchDesc,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SearchScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.space12),
          Expanded(
            child: Row(
              children: [
                _HomeEntryTile(
                  icon: Icons.download_outlined,
                  activeIcon: Icons.download,
                  title: Strings.homeGridLocal,
                  subtitle: Strings.homeGridLocalDesc,
                  onTap: () => onNavigateToTab(4),
                ),
                const SizedBox(width: AppSpacing.space12),
                // 定时状态是会话级会变的：tile 副标题/描边跟随
                // SleepTimerController（与 Settings/播放页同一数据源）。
                ListenableBuilder(
                  listenable: sleepTimer,
                  builder: (context, _) {
                    final active = sleepTimer.isActive &&
                        sleepTimer.minutes != null;
                    return _HomeEntryTile(
                      icon: Icons.bedtime_outlined,
                      activeIcon: Icons.bedtime,
                      title: Strings.homeGridSleepTimer,
                      subtitle: active
                          ? Strings.playerSleepTimerActive(
                              sleepTimer.minutes!,
                            )
                          : Strings.homeGridSleepTimerDesc,
                      highlighted: active,
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => SleepTimerDialog(
                          controller: sleepTimer,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 四宫格单格：Modernist 零圆角 + 2px 描边（`dividerThickness`），
/// 颜色全部取自 `colorScheme`（三配色不变量）；`highlighted` 仅用于
/// 定时关闭开启时的 accent 强调。
class _HomeEntryTile extends StatelessWidget {
  const _HomeEntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.activeIcon,
    this.highlighted = false,
  });

  final IconData icon;
  final IconData? activeIcon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = highlighted ? cs.primary : cs.onSurfaceVariant;
    final titleColor = highlighted ? cs.primary : cs.onSurface;

    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.lgAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: highlighted ? cs.primary : cs.outlineVariant,
                width: AppColors.dividerThickness,
              ),
            ),
            padding: const EdgeInsets.all(AppSpacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  highlighted ? (activeIcon ?? icon) : icon,
                  size: 28,
                  color: accent,
                ),
                const Spacer(),
                Text(
                  title,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: AppSpacing.space4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(color: accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
