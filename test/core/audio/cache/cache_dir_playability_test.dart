// cache_dir_playability_test.dart：**依次**扫描本机缓存目录里的每个文件，
// 断言它「能正常播放」或「已被明确排除在播放入口之外」。
//
// 回归背景：本地缓存页曾对每一行无条件渲染播放按钮，字幕（.vtt/.lrc/.txt）
// 被合成为「1 首」的播放列表送进 setAudioSource → mpv 卡在加载态 → 下一次
// stop() 与在途加载交错把播放串行链锁死，表现为「重启前再也无法播放」。
//
// 本测试两段：
//  1) 固定夹具（任何机器都跑）——临时文件/元数据/字幕绝不可播放；
//  2) 真实目录扫描（目录存在才跑）——逐个文件验证分类 + 音频文件头嗅探。
//
// @created 2026-09-28

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/audio/models/playback_context.dart';
import 'package:aaplay/core/download/models/download_entry.dart';
import 'package:aaplay/presentation/viewmodels/local_cache_viewmodel.dart';

String _fileName(File f) => Uri.file(f.path).pathSegments.last;

DownloadEntry _entry(String name, String path, {int size = 0}) =>
    DownloadEntry(
      workId: '0',
      fileKey: 'k',
      fileName: name,
      filePath: path,
      // 扫盘回填的历史行 mediaType 为空：判定必须完全依赖扩展名。
      mediaType: '',
      sourceUrl: '',
      size: size,
      createdAt: 0,
    );

/// 读文件头若干字节。
List<int> _head(File f, [int n = 16]) {
  final raf = f.openSync();
  try {
    return raf.readSync(n);
  } finally {
    raf.closeSync();
  }
}

String _ascii(List<int> b, int offset, int len) {
  if (b.length < offset + len) return '';
  return String.fromCharCodes(b.sublist(offset, offset + len));
}

/// 纯字节嗅探：文件头是否像「能正常播放」的音频。
/// 对应格式：mp3(ID3/帧同步) / wav(RIFF..WAVE) / flac / ogg·opus / m4a·aac
/// (ftyp 或 ADTS 帧同步) / wma(ASF 头) / aiff(FORM)。
bool _looksLikeAudioBytes(List<int> b) {
  if (b.length < 4) return false;
  if (_ascii(b, 0, 3) == 'ID3') return true;
  // MPEG / ADTS 帧同步
  if (b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) return true;
  final head = _ascii(b, 0, 4);
  if (head == 'RIFF') return _ascii(b, 8, 4) == 'WAVE';
  if (head == 'fLaC' || head == 'OggS' || head == 'FORM') return true;
  return _ascii(b, 4, 4) == 'ftyp';
}

bool _looksLikeAudio(File f) => _looksLikeAudioBytes(_head(f));

Directory? _dirUnder(String? base, List<String> parts) {
  if (base == null || base.isEmpty) return null;
  final sep = Platform.pathSeparator;
  return Directory('$base$sep${parts.join(sep)}');
}

void main() {
  group('固定夹具：不可播放文件一律被挡在播放入口外', () {
    test('字幕 / 元数据 / 临时文件 / 无扩展名 → 不是可播放音频', () {
      const names = [
        '01.vtt',
        '02.lrc',
        '03.srt',
        '04.txt',
        'album.json',
        'cover.jpg',
        'Track01.wav.dl_tmp',
        '1633133_1932437.part',
        'no-extension',
      ];
      for (final n in names) {
        final e = _entry(n, '/x/$n');
        expect(PlaybackContext.isPlayableAudioTitle(n), isFalse, reason: n);
        expect(LocalCacheViewModel.isAudioEntry(e), isFalse, reason: n);
        expect(LocalCacheViewModel.isPlayableEntry(e), isFalse, reason: n);
      }
    });

    test('type=audio 也不能翻案（本地缓存 mediaType 来自 API）', () {
      const e = DownloadEntry(
        workId: '0',
        fileKey: 'k',
        fileName: '01.vtt',
        filePath: '/x/01.vtt',
        mediaType: 'audio',
        sourceUrl: '',
        size: 1,
        createdAt: 0,
      );
      expect(LocalCacheViewModel.isPlayableEntry(e), isFalse);
    });

    test('白名单音频扩展名 → 可播放（播放入口保留）', () {
      for (final n in ['01.mp3', '02.wav', '03.flac', '04.m4a', '05.opus']) {
        final e = _entry(n, '/x/$n');
        expect(LocalCacheViewModel.isPlayableEntry(e), isTrue, reason: n);
      }
    });
  });

  group('真实缓存目录逐个文件扫描', () {
    test('Downloads（本地缓存落盘根）：每个文件可播放或被明确排除', () {
      final profile = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'];
      final root = _dirUnder(profile, ['Documents', 'downloads']);
      if (root == null || !root.existsSync()) return; // 非本机/无缓存 → 跳过

      final files = root
          .listSync(recursive: true)
          .whereType<File>()
          .toList(growable: false);
      expect(files, isNotEmpty, reason: 'Downloads 目录为空，扫描失去意义');

      var playableCount = 0;
      for (final f in files) {
        final name = _fileName(f);
        final isTemp = name.endsWith('.part') ||
            name.endsWith('.dl_tmp') ||
            name.endsWith('.dl_bak');
        final e = _entry(name, f.path, size: f.lengthSync());

        if (isTemp) {
          expect(LocalCacheViewModel.isPlayableEntry(e), isFalse,
              reason: '$name 是未完成的临时文件，绝不能进播放器');
          continue;
        }

        if (PlaybackContext.isPlayableAudioTitle(name)) {
          playableCount++;
          expect(LocalCacheViewModel.isAudioEntry(e), isTrue, reason: name);
          expect(_looksLikeAudio(f), isTrue,
              reason: '$name 被判定为可播放音频，但文件头不像音频 → 播放必然失败');
        } else {
          // 非音频白名单文件绝不进应用内播放（视频除外，它走外部打开）。
          expect(LocalCacheViewModel.isAudioEntry(e), isFalse,
              reason: '$name 不在音频白名单内，却进了音频播放入口');
          if (PlaybackContext.isSubtitleTitle(name)) {
            expect(LocalCacheViewModel.isPlayableEntry(e), isFalse,
                reason: '$name 是字幕，没有播放按钮');
          }
        }
      }

      expect(playableCount, greaterThan(0),
          reason: '扫描到 0 个可播放音频，说明分类逻辑或目录结构有问题');
    });

    test('audio_cache（流式播放缓存）：完整缓存文件必须是合法音频，part 残留不参与', () {
      final appData = Platform.environment['APPDATA'];
      final root = _dirUnder(
          appData, ['com.aaplay', 'AsmrAiPlayer', 'audio_cache']);
      if (root == null || !root.existsSync()) return; // 无缓存 → 跳过

      for (final f in root.listSync().whereType<File>()) {
        final name = _fileName(f);
        if (name.endsWith('.mime')) continue;
        if (name.endsWith('.part')) {
          // 未完成的下载残留：不能被当成完整缓存播放。
          expect(PlaybackContext.isPlayableAudioTitle(name), isFalse,
              reason: '$name 是未完成的 .part 缓存');
          continue;
        }
        expect(f.lengthSync(), greaterThan(0), reason: '$name 是空缓存文件');
        expect(_looksLikeAudioBytes(_head(f)), isTrue,
            reason: '缓存文件 $name 文件头不像音频 → 播放必然失败');
      }
    });
  });
}
