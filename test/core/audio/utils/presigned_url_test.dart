import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/audio/utils/presigned_url.dart';

void main() {
  group('PresignedUrl.isExpired', () {
    final now = DateTime.utc(2026, 9, 24, 12, 0, 0);

    test('X-Amz 签名未过期返回 false', () {
      final url = 'https://cdn.example.com/a.mp3'
          '?X-Amz-Date=20260924T110000Z&X-Amz-Expires=3600';
      expect(PresignedUrl.isExpired(url, now: now), isFalse);
    });

    test('X-Amz 签名已过期返回 true', () {
      final url = 'https://cdn.example.com/a.mp3'
          '?X-Amz-Date=20260924T090000Z&X-Amz-Expires=3600';
      expect(PresignedUrl.isExpired(url, now: now), isTrue);
    });

    test('Expires Unix 秒未过期返回 false', () {
      final futureEpoch =
          now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
      expect(
        PresignedUrl.isExpired('https://cdn.example.com/a.mp3?Expires=$futureEpoch',
            now: now),
        isFalse,
      );
    });

    test('Expires Unix 秒已过期返回 true', () {
      final pastEpoch = now
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch ~/
          1000;
      expect(
        PresignedUrl.isExpired('https://cdn.example.com/a.mp3?expires=$pastEpoch',
            now: now),
        isTrue,
      );
    });

    test('无签名参数返回 null（保持原行为）', () {
      expect(PresignedUrl.isExpired('https://cdn.example.com/a.mp3', now: now),
          isNull);
    });

    test('file:// 本地路径返回 null', () {
      expect(PresignedUrl.isExpired('file:///C:/audio/a.mp3', now: now), isNull);
    });

    test('null/空串/非法 URL 返回 null', () {
      expect(PresignedUrl.isExpired(null, now: now), isNull);
      expect(PresignedUrl.isExpired('', now: now), isNull);
      expect(PresignedUrl.isExpired('not a url', now: now), isNull);
    });

    test('X-Amz 参数无法解析时返回 null 而非误判', () {
      final url = 'https://cdn.example.com/a.mp3'
          '?X-Amz-Date=bad&X-Amz-Expires=3600';
      expect(PresignedUrl.isExpired(url, now: now), isNull);
    });
  });
}
