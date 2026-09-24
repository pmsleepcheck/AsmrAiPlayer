# Windows 播放后端缺失：接入 just_audio_media_kit

- **创建时间**：2026-09-23
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：用户反馈「还是会一直播放失败，是不是和 win 有关系 播放模块调不到」——是。

---

## 1. 目标（Goal）

> Windows 上点击播放能真正出声：just_audio 在 Windows 有可用后端（media_kit），不再 MissingPlugin/永久失败。

## 2. 范围（Scope）

**包含：**
- 根因：`just_audio`/`audio_session`/`audio_service` 均无 Windows 原生实现（包内无 `windows/`；`generated_plugins.cmake` 未注册任何音频插件）→ 方法通道无 handler。
- 接入 `just_audio_media_kit`（官方文档推荐的 Windows 方案）+ `media_kit_libs_windows_audio`（libmpv 音频库）。
- 在 `main()` 最早处（任何 `AudioPlayer()` 构造之前）`JustAudioMediaKit.ensureInitialized()`。
- 既有分段超时/AudioSession 降级保留（audio_session/audio_service 在 Windows 仍无实现，降级路径正是为此）。

**不包含：**
- 不改 Android/iOS/macOS 播放路径（仅 Windows/Linux 启用 media_kit 后端）。
- 不做 Windows 通知栏（audio_service 无 Win 实现，维持降级）。
- 不改 fileKey / 下载 / DB。

## 3. 验收标准（Acceptance）

- [x] 本地缓存音频在 Windows 点击后能出声（需用户新 exe 复测；构建已含 libmpv 后端）。
- [x] 网络播放列表 LockCachingAudioSource 在 Windows 可播（经 just_audio 本地代理 → media_kit UriAudioSourceMessage；协议白名单默认含 http/file）。
- [x] analyze 无新增 warning（4 既有）；210 测试过；`build windows --release` 成功且 `generated_plugins.cmake` 含 media_kit_libs_windows_audio。

## 4. 拆解步骤（Steps）

- [x] **Step 0**：建本 TODO + 定位（三包均无 windows/ 实现）。
- [x] **Step 1**：pubspec 加 `just_audio_media_kit` + `media_kit_libs_windows_audio`；`main()` 最早初始化（`WidgetsFlutterBinding.ensureInitialized()` 后、`setupServiceLocator()` 前）。
- [x] **Step 2**：analyze/test/build + 同步 AGENTS/CLAUDE + 归档。

## 5. 风险与回滚（Risks）

- media_kit 体积增加（libmpv dll ~18MB）；仅 Windows 打包。
- LockCachingAudioSource 走本地 http 代理：media_kit 协议白名单默认含 http/file（已验证 `just_audio_media_kit.dart:26-36`）。
- `AudioPlayerService` 单例在 `setupServiceLocator()` 构造即 `_init()` → `ensureInitialized` 必须在 `setupServiceLocator` 之前（已落实 + 文档化）。
- 回滚：删两依赖 + 删 `main.dart` 的 import/调用即可恢复原状（原状=Windows 必挂）。

## 6. 备注 / 决策记录

- 证据：`pubspec.lock` 仅 just_audio/just_audio_web/just_audio_platform_interface；`windows/flutter/generated_plugins.cmake` 原本只有 secure_storage/permission/sqlite/url_launcher；Pub Cache 中 just_audio、audio_session、audio_service 均无 `windows/` 目录。
- 官方 Windows 方案（just_audio README）：`just_audio_media_kit` + `media_kit_libs_windows_audio`。
- 兼容链：`LockCachingAudioSource extends StreamAudioSource` → `_setup` 起本地代理、`_toMessage` → `ProgressiveAudioSourceMessage`（extends `UriAudioSourceMessage`）→ media_kit `_convertAudioSourceIntoMediaKit` 的 `UriAudioSourceMessage` 分支 → `Media(proxyUri)`。本地 `AudioSource.uri(file://)` 同分支。
- 构建踩坑：首次 build 时 media_kit 下载的 `mpv-dev-*.7z` 校验失败（Integrity check failed）→ 删坏缓存重下后 `BUILD_RC=0`。若再遇到：删 `build/windows/x64/mpv-dev-*.7z` 重建。
- `ANALYZE_RC=1` 是 4 个既有 warning（RC 由 issues 计数驱动），非新增。

---

## ✅ 完成标记

- 完成时间：2026-09-23 23:40
- 执行命令：`/init`（手动等价：已同步 AGENTS.md + CLAUDE.md）
- CLAUDE.md 更新摘要：audio 段追加「Windows playback backend」——三包无 Windows 原生实现是播放必挂根因；`JustAudioMediaKit.ensureInitialized()` 必须在 `main()` 中 `setupServiceLocator()` 之前（DI 构造首个 AudioPlayer）；仅 windows/linux 启用，移动端保持原生；协议白名单默认覆盖 file/http；audio_session/audio_service 降级超时在 Windows 仍负载；勿把 ensureInitialized 挪到 DI 之后。
- 关联 commit：无（非 git 仓库）

---

## ⛔ 取消标记

- 取消时间：
- 取消原因：
- 后续指向：
