import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:aaplay/core/network/proxy_config.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';
import 'package:aaplay/utils/logger.dart';
import 'fish_tts_config.dart';

/// Fish Audio `POST /v1/tts` 客户端 + 磁盘缓存。
///
/// 请求体/头按官网 docs.fish.audio：
/// `Authorization: Bearer <key>`、`model` 头、`{text, reference_id?, format}`；
/// 响应为音频字节流（默认 mp3）。缓存键 = sha256(text|reference_id|model)。
class FishTtsService {
  static const String endpoint = 'https://api.fish.audio/v1/tts';
  static const String cacheDirName = 'fish_tts_cache';

  final FishTtsConfigStore config;
  final Dio _dio;

  /// 可注入（测试传临时目录 resolver）。
  final Future<Directory> Function()? cacheDirResolver;

  /// 提供时挂应用内代理（`ProxyConfig.apply`）；测试可省略。
  final AppSettingsService? settings;

  FishTtsService({
    required this.config,
    Dio? dio,
    this.cacheDirResolver,
    this.settings,
  }) : _dio = dio ?? Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
            )) {
    final s = settings;
    if (s != null) {
      ProxyConfig.apply(_dio, s);
    }
  }

  /// 纯函数缓存键（含音色与模型，避免串音）。
  static String cacheKey({
    required String text,
    required String referenceId,
    required String model,
  }) {
    final raw = '$model\u0000$referenceId\u0000$text';
    return sha256.convert(raw.codeUnits).toString();
  }

  /// 构造 JSON 请求体（纯函数，单测用）。
  static Map<String, dynamic> buildBody({
    required String text,
    required String referenceId,
    String format = 'mp3',
  }) {
    final body = <String, dynamic>{
      'text': text,
      'format': format,
    };
    if (referenceId.isNotEmpty) {
      body['reference_id'] = referenceId;
    }
    return body;
  }

  /// 同步合成：先查缓存，未命中再 POST。返回可直接给 just_audio 的字节。
  Future<Uint8List> synthesize(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw FishTtsException(FishTtsError.emptyAudio, 'empty text');
    }
    final apiKey = await config.requireApiKey();
    final ref = config.referenceId;
    final model = config.model;
    final key = cacheKey(text: trimmed, referenceId: ref, model: model);

    final dir = await _resolveCacheDir();
    final file = File(p.join(dir.path, '$key.mp3'));
    if (await file.exists()) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) return Uint8List.fromList(bytes);
      } catch (e) {
        AppLogger.warning('读取 TTS 缓存失败，改走网络: $e');
      }
    }

    Response<List<int>> resp;
    try {
      resp = await _dio.post<List<int>>(
        endpoint,
        data: buildBody(text: trimmed, referenceId: ref),
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'model': model,
          },
          responseType: ResponseType.bytes,
        ),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw FishTtsException(FishTtsError.unauthorized, 'HTTP $code');
      }
      throw FishTtsException(FishTtsError.network, e.message);
    }

    final status = resp.statusCode ?? 0;
    if (status == 401 || status == 403) {
      throw FishTtsException(FishTtsError.unauthorized, 'HTTP $status');
    }
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
      AppLogger.warning('写入 TTS 缓存失败（不影响本次播放）: $e');
    }
    return bytes;
  }

  Future<Directory> _resolveCacheDir() async {
    final custom = cacheDirResolver;
    if (custom != null) return custom();
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, cacheDirName));
  }
}
