import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';

/// 应用内 HTTP 代理配置（传输层，与 asmr 节点切换无关）。
///
/// 通过 `IOHttpClientAdapter.findProxy` 挂到各 `Dio` 实例上。`findProxy`
/// 是**每次请求时**回调的，闭包内实时读 [AppSettingsService] 当前值 ——
/// 开关/地址变更对下一个请求即刻生效，无需 listener 重挂或重启。
///
/// 关闭代理或地址非法时回退 `HttpClient.findProxyFromEnvironment`
/// （尊重 `HTTP_PROXY` 等环境变量），不写死 `DIRECT`。
///
/// 不覆盖：just_audio 流式播放（自有 HTTP 栈）。图片/字幕缓存经
/// `ProxiedHttpFileService`（flutter_cache_manager）走同一 findProxy。
class ProxyConfig {
  ProxyConfig._();

  /// `主机:端口`；主机可为 `host` 或 `[IPv6]`。端口 1..65535。
  static final RegExp _addrRe = RegExp(
    r'^(?:\[([0-9a-fA-F:.]+)\]|([^:/\s]+)):(\d{1,5})$',
  );

  /// 把用户输入规范化为 `host:port`（IPv6 保留方括号）。
  ///
  /// 接受可选 scheme 与尾部斜杠（`http://127.0.0.1:7890/` →
  /// `127.0.0.1:7890`）；无法解析时返回 `null`。
  static String? normalize(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    s = s.replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'), '');
    s = s.replaceFirst(RegExp(r'/+$'), '');
    final m = _addrRe.firstMatch(s);
    if (m == null) return null;
    final port = int.parse(m.group(3)!);
    if (port < 1 || port > 65535) return null;
    final host = m.group(1) != null ? '[${m.group(1)}]' : m.group(2)!;
    return '$host:$port';
  }

  /// 计算 dart:io `HttpClient.findProxy` 的返回值。
  ///
  /// 开启且地址合法 → `PROXY host:port`；否则回退环境变量探测。
  static String resolve(
    Uri url, {
    required bool enabled,
    required String address,
  }) {
    if (enabled) {
      final normalized = normalize(address);
      if (normalized != null) return 'PROXY $normalized';
    }
    return HttpClient.findProxyFromEnvironment(url);
  }

  /// 每次建连时回调的解析器，实时读 [settings] 当前值 ——
  /// 开关/地址变更对下一个请求即刻生效，无需重新 apply。
  static String Function(Uri url) resolver(AppSettingsService settings) =>
      (url) => resolve(
            url,
            enabled: settings.proxyEnabled,
            address: settings.proxyUrl,
          );

  /// 把 [settings] 的代理配置挂到 [dio]（仅 `IOHttpClientAdapter`，
  /// 即 VM/桌面/移动端的默认适配器）。幂等：重复调用覆盖同一字段。
  ///
  /// dio ≥5.9 的 `IOHttpClientAdapter` 不再暴露 `findProxy` 字段，改为在
  /// `createHttpClient` 里给 `HttpClient.findProxy` 挂闭包 —— 该闭包同样
  /// 是每次建连时回调（dart:io 默认也是建连时调 `findProxy`）。
  static void apply(Dio dio, AppSettingsService settings) {
    final adapter = dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.createHttpClient = () {
        final client = HttpClient()
          // 与 dio 默认适配器一致（见 io_adapter.dart `_createHttpClient`）。
          ..idleTimeout = const Duration(seconds: 3)
          ..findProxy = resolver(settings);
        return client;
      };
    }
  }
}
