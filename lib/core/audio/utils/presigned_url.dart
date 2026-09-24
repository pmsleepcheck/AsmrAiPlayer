/// 预签名 URL 过期判断（纯函数，便于单测）。
///
/// `mediaDownloadUrl` 是 API 签发的预签名绝对 URL，签名随会话轮换
/// （X-Amz-* 等参数每次重新签发）。持久化到 SharedPreferences 的
/// `last_playback_state` 里携带的是上一会话的签名，跨会话必然过期——
/// 直接拿去 setAudioSource 会让平台侧（mpv / just_audio 本地代理）卡在
/// 死源的僵尸加载上：Dart 侧 timeout 不会取消底层加载，后续每次点播都在
/// 串行链上排队超时（表现为"第二次启动后播放全部失败"）。恢复前先用这里
/// 判定过期，过期则跳过音频恢复（配合 ApiService 刷新文件树换新签名）。
class PresignedUrl {
  PresignedUrl._();

  /// 判断 [url] 的签名是否已过期。
  ///
  /// 返回值语义：
  /// - `true`：识别出签名时间信息且已过期；
  /// - `false`：识别出签名时间信息且仍在有效期内；
  /// - `null`：识别不出签名过期信息（无签名参数 / 非 http(s) / 无法解析），
  ///   调用方应保持原有行为（不得据此跳过恢复）。
  static bool? isExpired(String? url, {DateTime? now}) {
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (!uri.isScheme('http') && !uri.isScheme('https')) return null;

    final query = uri.queryParameters;
    final reference = (now ?? DateTime.now()).toUtc();

    // AWS S3 风格：X-Amz-Date=20260924T120000Z & X-Amz-Expires=3600（秒）
    final amzDate = query['X-Amz-Date'];
    final amzExpires = query['X-Amz-Expires'];
    if (amzDate != null && amzExpires != null) {
      final signedAt = _parseAmzDate(amzDate);
      final ttlSeconds = int.tryParse(amzExpires);
      if (signedAt == null || ttlSeconds == null) return null;
      return reference.isAfter(signedAt.add(Duration(seconds: ttlSeconds)));
    }

    // 通用 Expires/expires：Unix 秒时间戳（S3 旧式 / 部分 CDN）
    final epochText = query['Expires'] ?? query['expires'];
    if (epochText != null) {
      final epoch = int.tryParse(epochText);
      if (epoch == null) return null;
      final expiry =
          DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
      return reference.isAfter(expiry);
    }

    return null;
  }

  /// 解析 `yyyyMMdd'T'HHmmss'Z'` 格式的 X-Amz-Date，非法返回 null。
  static DateTime? _parseAmzDate(String value) {
    final match = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$')
        .firstMatch(value);
    if (match == null) return null;
    return DateTime.utc(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      int.parse(match[4]!),
      int.parse(match[5]!),
      int.parse(match[6]!),
    );
  }
}
