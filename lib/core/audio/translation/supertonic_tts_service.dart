import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:aaplay/utils/logger.dart';

import 'fish_tts_config.dart';
import 'tts_synthesizer.dart';

/// Supertonic 本地服务客户端（`pip install 'supertonic[serve]'` +
/// `supertonic serve`，默认 `http://127.0.0.1:7788`）。
///
/// 走 `POST /v1/tts`（原生端点），请求 `{text, voice, lang, response_format}`,
/// 响应为音频字节（这里固定要 `wav` —— Supertonic 不支持 mp3）。与 Fish 的差别：
///
/// - **不接 `ProxyConfig`**：目标是 127.0.0.1 回环，套上应用代理反而连不上。
/// - 磁盘缓存键 = `sha256(voice\0lang\0text)`，目录 `supertonic_tts_cache`。
/// - 额外提供 [isHealthy]（`GET /v1/health`）与 [startServer]（桌面端拉起子进程）。
class SupertonicTtsService implements TtsSynthesizer {
  static const String cacheDirName = 'supertonic_tts_cache';
  static const int defaultPort = 7788;

  final FishTtsConfigStore config;
  final Dio _dio;

  /// 可注入（测试传临时目录 resolver）。
  final Future<Directory> Function()? cacheDirResolver;

  SupertonicTtsService({
    required this.config,
    Dio? dio,
    this.cacheDirResolver,
  }) : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              // 首次合成可能要等模型加载，给足超时。
              receiveTimeout: const Duration(seconds: 120),
            ));

  /// 合成端点（跟随配置里的地址，去尾部 `/`）。
  String get endpoint => '${config.supertonicBaseUrl}/v1/tts';

  /// 健康检查端点。
  String get healthEndpoint => '${config.supertonicBaseUrl}/v1/health';

  /// 纯函数缓存键（含音色与语言，避免串音）。
  static String cacheKey({
    required String text,
    required String voice,
    required String lang,
  }) {
    final raw = '$voice\u0000$lang\u0000$text';
    return sha256.convert(raw.codeUnits).toString();
  }

  /// 构造 JSON 请求体（纯函数，单测用）。
  static Map<String, dynamic> buildBody({
    required String text,
    required String voice,
    required String lang,
    String responseFormat = 'wav',
  }) =>
      {
        'text': text,
        'voice': voice,
        'lang': lang,
        'response_format': responseFormat,
      };

  /// 同一文本的在途请求去重（与 Fish 一致：预取与当前句可能同时打同一句）。
  final Map<String, Future<Uint8List>> _inflight = {};

  @override
  Future<Uint8List> synthesize(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return Future.error(
          FishTtsException(FishTtsError.emptyAudio, 'empty text'));
    }
    final key = cacheKey(
      text: trimmed,
      voice: config.supertonicVoice,
      lang: config.supertonicLang,
    );
    final pending = _inflight[key];
    if (pending != null) return pending;
    final future = _synthesize(trimmed, key);
    _inflight[key] = future;
    future.whenComplete(() {
      if (identical(_inflight[key], future)) _inflight.remove(key);
    }).ignore();
    return future;
  }

  Future<Uint8List> _synthesize(String trimmed, String key) async {
    final dir = await _resolveCacheDir();
    final file = File(p.join(dir.path, '$key.wav'));
    if (await file.exists()) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) return Uint8List.fromList(bytes);
      } catch (e) {
        // 读失败改走本地服务，不阻断。
        AppLogger.warning('读取 Supertonic 缓存失败，改走本地服务: $e');
      }
    }

    Response<List<int>> resp;
    try {
      resp = await _dio.post<List<int>>(
        endpoint,
        data: buildBody(
          text: trimmed,
          voice: config.supertonicVoice,
          lang: config.supertonicLang,
        ),
        options: Options(
          headers: {'Content-Type': 'application/json'},
          responseType: ResponseType.bytes,
        ),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != null) {
        throw FishTtsException(FishTtsError.badResponse, 'HTTP $code');
      }
      // 连不上本地服务 = 服务没起（端口不通/连接被拒），映射成「不可用」。
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.unknown) {
        throw FishTtsException(
            FishTtsError.unavailable, config.supertonicBaseUrl);
      }
      throw FishTtsException(FishTtsError.network, e.message);
    }

    final status = resp.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw FishTtsException(FishTtsError.badResponse, 'HTTP $status');
    }

    final data = resp.data;
    if (data == null || data.isEmpty) {
      throw FishTtsException(FishTtsError.emptyAudio, 'HTTP $status');
    }
    final bytes = Uint8List.fromList(data);

    try {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (e) {
      AppLogger.warning('写入 Supertonic 缓存失败（不影响本次播放）: $e');
    }
    return bytes;
  }

  /// `GET /v1/health`：2 秒超时，连不上/非 2xx 都算「没起来」。
  Future<bool> isHealthy({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final resp = await _dio.get<dynamic>(
        healthEndpoint,
        options: Options(
          sendTimeout: timeout,
          receiveTimeout: timeout,
          validateStatus: (_) => true,
        ),
      );
      final code = resp.statusCode ?? 0;
      return code >= 200 && code < 300;
    } catch (_) {
      return false;
    }
  }

  /// 尝试拉起本地服务。只会**报告**结果，从不抛错。
  ///
  /// 顺序：已运行 → 桌面端 `supertonic` → `python -m supertonic`。
  /// 移动端没有 `Process` 起服务的条件，直接 [SupertonicLaunchStatus.unsupported]。
  Future<SupertonicLaunchStatus> startServer({
    Duration readyTimeout = const Duration(seconds: 20),
  }) async {
    if (await isHealthy()) return SupertonicLaunchStatus.alreadyRunning;
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return SupertonicLaunchStatus.unsupported;
    }

    final port = _portOf(config.supertonicBaseUrl);
    final args = <String>[
      'serve',
      '--host',
      '127.0.0.1',
      '--port',
      '$port',
    ];
    var launched = false;
    for (final cmd in <List<String>>[
      ['supertonic', ...args],
      ['python', '-m', 'supertonic', ...args],
      ['python3', '-m', 'supertonic', ...args],
    ]) {
      try {
        await Process.start(
          cmd.first,
          cmd.skip(1).toList(),
          mode: ProcessStartMode.detached,
        );
        launched = true;
        break;
      } on ProcessException {
        // 找不到这个可执行文件 → 换下一种。
      } catch (_) {
        // 其它启动异常同样视为「这条路走不通」。
      }
    }
    if (!launched) return SupertonicLaunchStatus.notFound;

    final deadline = DateTime.now().add(readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (await isHealthy()) return SupertonicLaunchStatus.started;
    }
    // 进程起来了但还没就绪（首跑要下载 ~400MB 模型）。
    return SupertonicLaunchStatus.starting;
  }

  static int _portOf(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    final port = uri?.hasPort == true ? uri!.port : 0;
    return port > 0 ? port : defaultPort;
  }

  Future<Directory> _resolveCacheDir() async {
    final custom = cacheDirResolver;
    if (custom != null) return custom();
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, cacheDirName));
  }
}

/// [SupertonicTtsService.startServer] 的结果（文案在 `Strings` 侧映射）。
enum SupertonicLaunchStatus {
  /// 服务本来就在跑。
  alreadyRunning,

  /// 拉起成功且健康检查通过。
  started,

  /// 进程已启动但还没就绪（可能正在首次下载模型），稍后重试检测。
  starting,

  /// 当前平台无法启动子进程（Android/iOS）。
  unsupported,

  /// PATH 里找不到 `supertonic` / `python`。
  notFound,

  /// 进程起来了但一直没就绪。
  failed,
}
