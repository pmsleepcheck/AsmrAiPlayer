# Windows 下载完成后无反馈 / 不自动播放 + 下载路径可见

- **创建时间**：2026-09-23
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：用户 Windows 实机反馈

---

## 1. 目标（Goal）

> ① 明确并展示 Windows 下载目录（当前为 `Documents\downloads\...`，用户找不到文件）；② 音频入队下完后无任何播放/强反馈 → 单曲下载完成后自动开始播放；③ 视频 `OpenFilex` 打开失败时给出「打开所在文件夹」兜底。

## 2. 范围（Scope）

**包含：**
- `DownloadService.downloadsRootPath()` 暴露下载根路径。
- 下载管理页展示路径 +「打开文件夹」。
- `DownloadJob` 携带 `work`/`files`/`playOnComplete`；单曲音频入队 `playOnComplete: true`，成功后经注入的 `playJob` 调 `IAudioPlayerService.playWithContext`。
- `PlaybackContext` 同目录播放列表扩展名从 `{mp3,wav}` 扩到常见音频格式（否则 m4a/flac 下完自动播放必「播放列表为空」）。
- 视频打开失败 SnackBar 增加「打开文件夹」action；打开结果打日志。

**不包含：**
- 批量下载完成后自动连播。
- 改 Windows 落盘根目录（仍 `getApplicationDocumentsDirectory()/downloads`，避免绝对路径 DB 失效）。
- 队列持久化 / 跨重启恢复。

## 3. 验收标准（Acceptance）

- [x] 下载管理页可见下载根路径，点「打开文件夹」能在资源管理器打开。
- [x] 详情页单曲音频入队，下完后应用内自动播放该曲（mp3 与 m4a 均可）。
- [x] 批量下载不自动播放。
- [x] 视频下载完成打开失败时 SnackBar 可跳到所在文件夹。
- [x] `flutter analyze` 无新增 warning；队列相关测试通过。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：TODO 文档（本文件）
  - 涉及文件：`docs/todos/active/20260923-windows-download-complete-play.md`
- [x] **Step 2**：`DownloadService.downloadsRootPath` + 下载管理路径/打开文件夹
  - 涉及文件：`download_service.dart`、`download_management_screen.dart`、`strings.dart`
  - 验证：analyze；管理页显示路径
- [x] **Step 3**：队列 `playOnComplete` + DI 注入 `playJob` + 详情页单曲入队接线
  - 涉及文件：`download_queue_service.dart`、`service_locator.dart`、`detail_viewmodel.dart`
  - 验证：单测 playJob 触发；手动单曲下载后播放
- [x] **Step 4**：`PlaybackContext` 扩展音频扩展名
  - 涉及文件：`playback_context.dart`、`test/core/audio/models/playback_context_playlist_test.dart`
  - 验证：测试非 mp3/wav 同目录列表非空
- [x] **Step 5**：视频打开失败「打开文件夹」+ 日志
  - 涉及文件：`detail_screen.dart`
  - 验证：analyze；无关联播放器时 SnackBar 有 action
- [x] **Step 6**：analyze + test + 重编 exe
  - 验证：analyze 仅 3 个既有 warning；队列/播放列表新测试 11 个全过（全量 196 通过，2 个既有 playlist_builder 路径分隔符失败）；`flutter build windows --release` RC=0

## 5. 风险与回滚（Risks）

- **风险**：详情 VM 已 dispose 后 job 才完成 → 自动播放必须只依赖 Job 快照的 `work`/`files`，不碰 VM。
- **风险**：扩展名放宽后把字幕/视频误入列表 → 仍先按扩展名白名单过滤，视频扩展名不在白名单。
- **回滚**：去掉 `playJob` 接线与 `playOnComplete` 默认 false 即恢复「只改状态不播放」。

## 6. 备注 / 决策记录

- Windows 下载根 = `getApplicationDocumentsDirectory()` + `downloads`（约 `C:\Users\<user>\Documents\downloads\<workId>\<fileKey>\<原名>`）；**不迁移**旧绝对路径行。
- 单曲下完自动播放；批量只改管理页状态。
- `PlaybackContext` 原 `{mp3,wav}` 白名单是历史遗留，与 `isAudioFile`/just_audio 能力不一致，导致「下完播不了」。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-23 16:22
- 执行命令：`/init`（本会话手动同步 AGENTS.md/CLAUDE.md，无 /init 工具）
- CLAUDE.md 更新摘要：download 段补充 `downloadsRootPath`/下载管理路径展示；队列段补充 `playOnComplete`/`playJob` 单曲自动播放不变量；`PlaybackContext` 扩展音频扩展名白名单。
- 关联 commit：（非 git 仓库）

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

> 任务取消时填写此块，**不需要执行 `/init`**，将文件移入 `docs/todos/cancelled/`。

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：<例如：方案被替换为 XYZ / 优先级下调 / 上游接口取消>
- 后续指向：<如有继任任务，写明对应的 TODO 路径；否则留空>
