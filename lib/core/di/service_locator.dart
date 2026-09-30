import 'dart:io';
import 'package:dio/dio.dart';
import 'package:aaplay/data/services/interceptors/retry_interceptor.dart';
import 'package:aaplay/data/services/interceptors/auth_interceptor.dart';
import 'package:aaplay/core/platform/dummy_lyric_overlay_controller.dart';
import 'package:get_it/get_it.dart';
import '../audio/i_audio_player_service.dart';
import '../audio/audio_player_service.dart';
import '../audio/models/playback_context.dart';
import '../../data/services/api_service.dart';
import '../../data/services/update_service.dart';
import '../../presentation/viewmodels/player_viewmodel.dart';
import '../../data/services/auth_service.dart';
import '../../presentation/viewmodels/auth_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/repositories/auth_repository.dart';
import '../subtitle/i_subtitle_service.dart';
import '../subtitle/subtitle_service.dart';
import '../subtitle/subtitle_loader.dart';
import '../../core/audio/storage/i_playback_state_repository.dart';
import '../../core/audio/storage/playback_state_repository.dart';
import '../audio/events/playback_event_hub.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/platform/i_lyric_overlay_controller.dart';
import '../../core/platform/lyric_overlay_controller.dart';
import '../../core/platform/lyric_overlay_manager.dart';
import '../../core/platform/wakelock_controller.dart';
import '../../core/platform/sleep_timer_controller.dart';
import '../../core/platform/background_play_controller.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';
import 'package:aaplay/core/network/proxy_config.dart';
import 'package:aaplay/core/database/database_service.dart';
import 'package:aaplay/core/subtitle/storage/i_user_subtitle_repository.dart';
import 'package:aaplay/core/subtitle/storage/user_subtitle_repository.dart';
import 'package:aaplay/core/subtitle/import/i_file_picker_service.dart';
import 'package:aaplay/core/subtitle/import/file_picker_service.dart';
import 'package:aaplay/core/subtitle/subtitle_import_service.dart';
import 'package:aaplay/core/download/storage/i_download_repository.dart';
import 'package:aaplay/core/download/storage/download_repository.dart';
import 'package:aaplay/core/download/storage/i_work_snapshot_repository.dart';
import 'package:aaplay/core/download/storage/work_snapshot_repository.dart';
import 'package:aaplay/core/download/download_service.dart';
import 'package:aaplay/core/download/download_queue_service.dart';
import 'package:aaplay/core/audio/translation/ear_mark_repository.dart';
import 'package:aaplay/core/audio/translation/ear_side_detector.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';
import 'package:aaplay/core/audio/translation/fish_tts_service.dart';
import 'package:aaplay/core/audio/translation/supertonic_tts_service.dart';
import 'package:aaplay/core/audio/translation/translation_session_controller.dart';
import 'package:aaplay/core/audio/translation/translation_tts_router.dart';
import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/data/models/works/work.dart';
import 'package:aaplay/utils/logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final getIt = GetIt.instance;

Future<void> setupServiceLocator() async {
  // Windows/Linux 无 sqflite 原生实现，openDatabase 必抛（下载/字幕 DB 全挂，
  // 被 DownloadService 收敛为 ioError →「文件写入错误」）。切换到 FFI 工厂；
  // 移动端/macOS 保持 sqflite 原生工厂，行为不变。必须在首次 DB 访问前执行。
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final prefs = await SharedPreferences.getInstance();

  // 注册 EventHub
  getIt.registerLazySingleton(() => PlaybackEventHub());

  // 注册 SharedPreferences 实例
  getIt.registerSingleton<SharedPreferences>(prefs);

  // 数据库服务
  getIt.registerLazySingleton<DatabaseService>(() => DatabaseService());

  // 用户字幕存储
  getIt.registerLazySingleton<IUserSubtitleRepository>(
    () => UserSubtitleRepository(getIt<DatabaseService>()),
  );

  // 文件选择器
  getIt.registerLazySingleton<IFilePickerService>(() => FilePickerService());

  // 字幕导入服务
  getIt.registerLazySingleton<SubtitleImportService>(
    () => SubtitleImportService(
      picker: getIt<IFilePickerService>(),
      repository: getIt<IUserSubtitleRepository>(),
    ),
  );

  // 下载存储 + 服务（依赖 DatabaseService，已于上方注册）
  getIt.registerLazySingleton<IDownloadRepository>(
    () => DownloadRepository(getIt<DatabaseService>()),
  );
  // 详情页快照（入队时持久化 Work+Files；播放/离线回退用）。
  getIt.registerLazySingleton<IWorkSnapshotRepository>(
    () => WorkSnapshotRepository(getIt<DatabaseService>()),
  );
  getIt.registerLazySingleton<DownloadService>(
    () => DownloadService(
      repository: getIt<IDownloadRepository>(),
      settings: getIt<AppSettingsService>(),
      snapshots: getIt<IWorkSnapshotRepository>(),
    ),
  );

  // 后台下载队列（串行；入队后不依赖详情页存活）。
  // 单曲音频 playOnComplete=true 时，用入队时快照的 work/files 直接
  // playWithContext——不碰 DetailViewModel（可能已 dispose）；
  // job 缺快照时经 loadSnapshot 从 work_snapshots 表回填。
  getIt.registerLazySingleton<DownloadQueueService>(
    () => DownloadQueueService(
      download: ({
        required workId,
        required file,
        onProgress,
        cancelToken,
        work,
        files,
      }) =>
          getIt<DownloadService>().download(
        workId: workId,
        file: file,
        onProgress: onProgress,
        cancelToken: cancelToken,
        work: work,
        files: files,
      ),
      loadSnapshot: (workId) async {
        final snap = await getIt<IWorkSnapshotRepository>().load(workId);
        if (snap == null) return null;
        return (work: snap.work, files: snap.files);
      },
      playJob: (job) async {
        Work? work = job.work;
        Files? files = job.files;
        if (work == null || files == null) {
          final snap = await getIt<IWorkSnapshotRepository>().load(job.workId);
          work ??= snap?.work;
          files ??= snap?.files;
        }
        if (work == null || files == null) {
          AppLogger.warning('自动播放跳过（无 work/files 快照）: ${job.title}');
          return;
        }
        final ctx = PlaybackContext(
          work: work,
          files: files,
          currentFile: job.file,
        );
        if (ctx.playlist.isEmpty) {
          AppLogger.warning('自动播放跳过（同目录无可播音频）: ${job.title}');
          return;
        }
        await getIt<IAudioPlayerService>().playWithContext(ctx);
      },
    ),
  );

  // 注册 PlaybackStateRepository
  getIt.registerLazySingleton<IPlaybackStateRepository>(
    () => PlaybackStateRepository(getIt()),
  );

  // 核心服务
  getIt.registerLazySingleton<IAudioPlayerService>(
    () => AudioPlayerService(
      eventHub: getIt(),
      stateRepository: getIt(),
    ),
  );

  // 注册 PlayerViewModel
  getIt.registerLazySingleton<PlayerViewModel>(
    () => PlayerViewModel(
      audioService: getIt(),
      eventHub: getIt(),
      subtitleService: getIt(),
    ),
  );

  // 翻译混播（fish TTS 第二音轨）——列表「翻译+播放」与播放页开关/方向。
  getIt.registerLazySingleton<FishTtsConfigStore>(
    // ChangeNotifier：播放页音色预设一键切换需 Listenable 刷新。
    () => FishTtsConfigStore(prefs: prefs),
  );
  getIt.registerLazySingleton<FishTtsService>(
    // settings：Fish TTS 请求走应用内代理（与其余 Dio 客户端一致）。
    () => FishTtsService(
      config: getIt<FishTtsConfigStore>(),
      settings: getIt<AppSettingsService>(),
    ),
  );
  // Supertonic 本地服务：**不接代理**（127.0.0.1 回环，走代理反而连不上）。
  getIt.registerLazySingleton<SupertonicTtsService>(
    () => SupertonicTtsService(config: getIt<FishTtsConfigStore>()),
  );
  // 按配置分发的 TTS 总入口（默认 Supertonic，设置里可切 Fish）。
  getIt.registerLazySingleton<TranslationTtsRouter>(
    () => TranslationTtsRouter(
      config: getIt<FishTtsConfigStore>(),
      fish: getIt<FishTtsService>(),
      supertonic: getIt<SupertonicTtsService>(),
    ),
  );
  getIt.registerLazySingleton<EarMarkRepository>(
    () => EarMarkRepository(prefs),
  );
  // 波形检测的 localPath 解析器由列表入口按各自 workId 注入（detect 调用参数）。
  getIt.registerLazySingleton<EarSideDetector>(
    () => EarSideDetector(marks: getIt<EarMarkRepository>()),
  );
  getIt.registerLazySingleton<TranslationSessionController>(
    () => TranslationSessionController(
      subtitleService: getIt<ISubtitleService>(),
      eventHub: getIt<PlaybackEventHub>(),
      tts: getIt<TranslationTtsRouter>(),
      config: getIt<FishTtsConfigStore>(),
      audio: getIt<IAudioPlayerService>(),
      // 翻译音量对齐/按作品记住（2026-09-28）：主轨响度要本地路径，
      // 手动音量落作品 album.json —— 都走 DownloadService。
      resolveLocalPath: (workId, file) =>
          getIt<DownloadService>().localPathIfDownloaded(workId, file),
      readWorkVolume: (workId) =>
          getIt<DownloadService>().readTranslationVolume(workId),
      recordWorkVolume: (workId, volume) =>
          getIt<DownloadService>().recordTranslationVolume(workId, volume),
    ),
  );

  // 注册 AppSettingsService
  getIt.registerSingleton<AppSettingsService>(
    AppSettingsService(prefs),
  );

  // API 服务
  getIt.registerLazySingleton<ApiService>(
    () => ApiService(settings: getIt<AppSettingsService>()),
  );

  // 检查更新服务（独立 GitHub Dio，与 asmr 节点解耦；仅注入 settings 挂代理）
  getIt.registerLazySingleton<UpdateService>(
    () => UpdateService(settings: getIt<AppSettingsService>()),
  );

  // 添加 AuthService 注册
  getIt.registerLazySingleton<AuthService>(
    () => AuthService(settings: getIt<AppSettingsService>()),
  );

  // 添加 AuthRepository 注册
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepository(prefs),
  );

  // 修改 AuthViewModel 注册
  getIt.registerSingleton<AuthViewModel>(
    AuthViewModel(
      authService: getIt<AuthService>(),
      authRepository: getIt<AuthRepository>(),
    ),
  );

  // 添加字幕服务注册
  getIt.registerLazySingleton<ISubtitleService>(
    () => SubtitleService(),
  );

  setupSubtitleServices();

  // 注册主题控制器
  getIt.registerLazySingleton<ThemeController>(
    () => ThemeController(prefs),
  );

  // 注册 WakeLockController
  getIt.registerLazySingleton(() => WakeLockController(prefs));

  // 注册 SleepTimerController（会话级；到点 pause()，不持久化）
  getIt.registerLazySingleton(
    () => SleepTimerController(getIt<IAudioPlayerService>()),
  );

  // 注册 BackgroundPlayController（后台播放开关执行端，main 中 initialize）
  getIt.registerLazySingleton(
    () => BackgroundPlayController(
      settings: getIt<AppSettingsService>(),
      audioService: getIt<IAudioPlayerService>(),
    ),
  );
}

void setupSubtitleServices() {
  getIt.registerLazySingleton<SubtitleLoader>(() {
    final dio = Dio();
    dio.interceptors.add(RetryInterceptor(dio: dio));
    dio.interceptors.add(AuthInterceptor());
    ProxyConfig.apply(dio, getIt<AppSettingsService>());
    return SubtitleLoader(dio: dio);
  });
  if (Platform.isAndroid) {
    getIt.registerLazySingleton<ILyricOverlayController>(
        () => LyricOverlayController());
  } else {
    getIt.registerLazySingleton<ILyricOverlayController>(
        () => DummyLyricOverlayController());
  }
  getIt.registerLazySingleton(() => LyricOverlayManager(
        controller: getIt(),
        subtitleService: getIt(),
        settings: getIt<AppSettingsService>(),
      ));
}

/// 首帧之后再执行的非关键启动初始化。
///
/// `LyricOverlayManager.initialize()` 会做平台通道往返（controller.initialize /
/// isShowing），放在冷启动关键路径（runApp 之前）上会拖慢首个可交互帧，而悬浮
/// 歌词在有曲目播放、用户开启之前并不需要——因此推迟到首帧绘制之后再做。
Future<void> initDeferredStartupServices() async {
  await getIt<LyricOverlayManager>().initialize();
}
