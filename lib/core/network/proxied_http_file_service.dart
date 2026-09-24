import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:aaplay/core/network/proxy_config.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';

/// 走应用内代理的 [HttpFileService]：给 `cached_network_image` /
/// flutter_cache_manager 的图片、字幕缓存挂与 Dio 相同的 `HttpClient.findProxy`
/// （每次建连实时读设置）。代理关闭/设置未就绪时回退环境变量探测。
///
/// 此前缓存下载绕过代理 → 开了代理后 API/媒体可用、封面全挂。
class ProxiedHttpFileService extends HttpFileService {
  ProxiedHttpFileService() : super(httpClient: createProxiedClient());

  /// 创建带 `findProxy` 的 [http.Client]。[settings] 可选：单元测试不传
  /// getIt 时也能构造（回退环境变量）。
  static http.Client createProxiedClient({AppSettingsService? settings}) {
    AppSettingsService? resolved = settings;
    final inner = HttpClient()
      ..idleTimeout = const Duration(seconds: 3)
      ..findProxy = (url) {
        resolved ??= _settingsOrNull();
        if (resolved == null) {
          return HttpClient.findProxyFromEnvironment(url);
        }
        return ProxyConfig.resolve(
          url,
          enabled: resolved!.proxyEnabled,
          address: resolved!.proxyUrl,
        );
      };
    return IOClient(inner);
  }

  static AppSettingsService? _settingsOrNull() {
    try {
      return GetIt.I.isRegistered<AppSettingsService>()
          ? GetIt.I<AppSettingsService>()
          : null;
    } catch (_) {
      return null;
    }
  }
}
