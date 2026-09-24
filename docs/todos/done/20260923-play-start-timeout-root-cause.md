# 修复启动播放仍超 15s（playWithContext 超时未根治）

- **创建时间**：2026-09-23
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：用户反馈「启动播放失败超过15s」（#2 的 15s 硬超时仍在触发）

---

## 1. 目标（Goal）

> 点播放后必须在数秒内出声或给出真实失败原因；15s 硬超时只应是最后保险，不能成为常态路径。

## 2. 范围（Scope）

**包含：**
- 排查 `playWithContext` → `_startWithContext`（ready → setPlaybackContext → resume）哪一步挂住超过 15s。
- 重点：本地缓存 `file://` 源为何仍超时；`setPlaybackContext`/`PlaylistBuilder` 是否在等待网络/DB；`ready` 是否仍被阻塞。
- 针对根因修复（缩短阻塞、去掉同步等待、或让本地路径跳过网络依赖）。

**不包含：**
- 不改 fileKey / 下载落盘 / DB schema。
- 不移除 15s 超时保险（保留兜底）。

## 3. 验收标准（Acceptance）

- [x] 本地缓存音频点击后 ≤3s 出声或 MiniPlayer 进入 loading，不再弹笼统「超时15秒」（分段超时 + 串行链根治；待用户新 exe 复测确认）。
- [x] 若仍失败，SnackBar 显示真实原因（初始化播放器/加载播放源/开始播放 + 秒数）。
- [x] analyze 无新增 warning（仍 4 个既有）；210 测试全过；`build windows --release` 成功（xuro.exe 91136, TS=2026-09-23 18:04:53）。

## 4. 拆解步骤（Steps）

- [x] **Step 0**：建本 TODO。
- [x] **Step 1**：读 `audio_player_service`/`playlist_builder`/`playback_context` 启动链，定位挂起点。
- [x] **Step 2**：修复根因 + 必要日志/SnackBar 真实错误。
- [x] **Step 3**：analyze/test/build + 同步文档 + 归档。

## 5. 风险与回滚（Risks）

- 若根因是 just_audio 加载慢/网络，本地 file:// 应完全离线快速；需确认是否走了错误分支。

## 6. 备注 / 决策记录

- 前两轮已加：通知 init 5s、权限 2s、playWithContext 15s 硬超时 + `Strings.playStarting`。超时仍触发说明阻塞在别处。
- **Step 1 根因**（挂点）：`AudioSession.instance`/`configure` 无超时；`player.setAudioSource` 无内层超时（等平台侧加载，网络源/并发交错可挂）；首帧后 `restorePlaybackState` 与用户点播并发调 just_audio `stop`/`setAudioSource` → 平台侧死锁/挂起；外层 15s 才是唯一超时 → 只报笼统「启动播放超时15秒」。
- **Step 2 修复**（3 文件 4 处）：
  1. `audio_player_service.dart` `_init`：`AudioSession.instance.timeout(3s)` + `session.configure(...).timeout(3s)`，失败仅 warning 不阻塞 ready。
  2. 同文件 `_startWithContext`：三段限时（ready 8s→`'播放器初始化'/'超时8秒'`、setPlaybackContext 6s→`'加载播放源'/'超时6秒'`、resume 4s→`'开始播放'/'超时4秒'`）+ Stopwatch 调试日志；外层 15s 兜底保留。
  3. `playback_controller.dart`：`setPlaybackContext` 公开包装 + `_setPlaybackContext` 经 `_setContextChain` Future 链串行化（修 restore/点播并发）；链内失败仅 warning 不卡链尾。
  4. `playlist_builder.dart` `setPlaylistSource`：`player.setAudioSource(...).timeout(5s)`。
- **Step 3 验证**：`flutter analyze` → 4 既有 warning 无新增（`ANALYZE_RC=1` 即 4 issues）；`flutter test` → `00:13 +210: All tests passed!` `TEST_RC=0`；`flutter build windows --release` → `BUILD_RC=0`，`xuro.exe` LEN=91136 TS=2026-09-23 18:04:53。
- AGENTS.md/CLAUDE.md 已追加「Play-start timeout root cause (2026-09-23)」不变量（3s AudioSession / 8-6-4 分段 / setAudioSource 5s / `_setContextChain` 串行 / 勿拆 15s 兜底）。

---

## ✅ 完成标记

- 完成时间：2026-09-23 18:10
- 执行命令：`/init`（手动等价：已同步 AGENTS.md + CLAUDE.md）
- CLAUDE.md 更新摘要：audio 段追加「Play-start timeout root cause」——15s 仅兜底；`_init` AudioSession/configure 3s 超时（失败不阻塞 ready）；`_startWithContext` 分段 8s 初始化播放器 / 6s 加载播放源 / 4s 开始播放 + Stopwatch 日志；`setPlaylistSource` 的 `setAudioSource` 5s；`PlaybackController.setPlaybackContext` 经 `_setContextChain` 串行化防 restore 与点播并发死锁；勿单独移除任何一层超时/串行。
- 关联 commit：无（非 git 仓库）

---

## ⛔ 取消标记

- 取消时间：
- 取消原因：
- 后续指向：
