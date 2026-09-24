import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aaplay/core/network/proxy_config.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';

/// 非 IO 适配器占位（验证 `ProxyConfig.apply` 的类型守卫）。
class _FakeAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw UnimplementedError();
  }
}

void main() {
  group('ProxyConfig.normalize', () {
    test('plain host:port passes through', () {
      expect(ProxyConfig.normalize('127.0.0.1:7890'), '127.0.0.1:7890');
      expect(ProxyConfig.normalize('proxy.example.com:8080'),
          'proxy.example.com:8080');
    });

    test('scheme and trailing slash stripped', () {
      expect(ProxyConfig.normalize('http://127.0.0.1:7890'), '127.0.0.1:7890');
      expect(
          ProxyConfig.normalize('HTTP://127.0.0.1:7890/'), '127.0.0.1:7890');
      expect(
          ProxyConfig.normalize('http://127.0.0.1:7890//'), '127.0.0.1:7890');
    });

    test('whitespace trimmed', () {
      expect(ProxyConfig.normalize('  127.0.0.1:7890 '), '127.0.0.1:7890');
    });

    test('IPv6 with brackets kept bracketed', () {
      expect(ProxyConfig.normalize('[::1]:7890'), '[::1]:7890');
      expect(ProxyConfig.normalize('http://[::1]:7890/'), '[::1]:7890');
    });

    test('invalid inputs rejected', () {
      expect(ProxyConfig.normalize(''), isNull);
      expect(ProxyConfig.normalize('   '), isNull);
      expect(ProxyConfig.normalize('127.0.0.1'), isNull); // 无端口
      expect(ProxyConfig.normalize('127.0.0.1:'), isNull);
      expect(ProxyConfig.normalize(':7890'), isNull); // 无主机
      expect(ProxyConfig.normalize('127.0.0.1:0'), isNull); // 端口下界
      expect(ProxyConfig.normalize('127.0.0.1:65536'), isNull); // 端口上界
      expect(ProxyConfig.normalize('127.0.0.1:abc'), isNull);
      expect(ProxyConfig.normalize('host:80/path'), isNull);
    });

    test('port boundaries 1 and 65535 accepted', () {
      expect(ProxyConfig.normalize('h:1'), 'h:1');
      expect(ProxyConfig.normalize('h:65535'), 'h:65535');
    });
  });

  group('ProxyConfig.resolve', () {
    final url = Uri.parse('https://api.asmr.one/api/works');

    test('enabled + valid address → PROXY host:port', () {
      expect(
        ProxyConfig.resolve(url, enabled: true, address: '127.0.0.1:7890'),
        'PROXY 127.0.0.1:7890',
      );
      expect(
        ProxyConfig.resolve(url,
            enabled: true, address: 'http://127.0.0.1:7890/'),
        'PROXY 127.0.0.1:7890',
      );
    });

    test('enabled but invalid address → falls back to environment', () {
      expect(
        ProxyConfig.resolve(url, enabled: true, address: 'not-an-addr'),
        ProxyConfig.resolve(url, enabled: false, address: ''),
      );
    });

    test('disabled → environment lookup (not PROXY)', () {
      final result = ProxyConfig.resolve(url, enabled: false, address: '');
      expect(result, isNot(startsWith('PROXY')));
    });
  });

  group('ProxyConfig.resolver / apply', () {
    late AppSettingsService settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      settings = AppSettingsService(prefs);
    });

    test('resolver follows live settings without re-apply', () async {
      final url = Uri.parse('https://example.com/');
      final r = ProxyConfig.resolver(settings);
      expect(r(url), isNot(startsWith('PROXY'))); // 默认关闭

      await settings.setProxyEnabled(true);
      await settings.setProxyUrl('127.0.0.1:7890');
      expect(r(url), 'PROXY 127.0.0.1:7890');

      // 关闭后立刻回退 —— 每次建连实时读设置，无需再 apply。
      await settings.setProxyEnabled(false);
      expect(r(url), isNot(startsWith('PROXY')));
    });

    test('apply wires createHttpClient on default adapter', () {
      final dio = Dio();
      ProxyConfig.apply(dio, settings);
      final adapter = dio.httpClientAdapter as IOHttpClientAdapter;
      expect(adapter.createHttpClient, isNotNull);
      final client = adapter.createHttpClient!();
      expect(client, isA<HttpClient>());
      client.close(force: true);
      dio.close(force: true);
    });

    test('apply is a no-op for non-IO adapters', () {
      final dio = Dio()..httpClientAdapter = _FakeAdapter();
      ProxyConfig.apply(dio, settings); // 不抛异常即可
      expect(dio.httpClientAdapter, isA<_FakeAdapter>());
      dio.close(force: true);
    });
  });

  group('AppSettingsService proxy persistence', () {
    test('defaults: disabled + 127.0.0.1:7890', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppSettingsService(prefs);
      expect(s.proxyEnabled, isFalse);
      expect(s.proxyUrl, '127.0.0.1:7890');
    });

    test('setters persist across reload', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppSettingsService(prefs);
      await s.setProxyEnabled(true);
      await s.setProxyUrl('10.0.0.2:1080');

      final reloaded = AppSettingsService(prefs);
      expect(reloaded.proxyEnabled, isTrue);
      expect(reloaded.proxyUrl, '10.0.0.2:1080');
    });
  });
}
