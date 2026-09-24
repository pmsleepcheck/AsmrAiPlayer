import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';

/// 当前是否处于「无图片模式」。
/// GetIt 未注册 [AppSettingsService] 时（无 DI 的 widget 测试）返回 `false`，
/// 保持默认加载封面的旧行为。
bool noImageModeEnabled() {
  try {
    if (!GetIt.I.isRegistered<AppSettingsService>()) return false;
    return GetIt.I<AppSettingsService>().noImageMode;
  } catch (_) {
    return false;
  }
}

/// 包住封面渲染：设置变更时实时重建；未注册 settings 时直接 build。
/// [builder] 收到 `noImage == true` 表示应渲染占位而非网络图。
Widget withNoImageMode(
  Widget Function(BuildContext context, bool noImage) builder,
) {
  if (!GetIt.I.isRegistered<AppSettingsService>()) {
    return Builder(builder: (context) => builder(context, false));
  }
  final settings = GetIt.I<AppSettingsService>();
  return ListenableBuilder(
    listenable: settings,
    builder: (context, _) => builder(context, settings.noImageMode),
  );
}
