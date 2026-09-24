# 本地缓存音频始终应用内播放（禁止回退外部）

- **创建时间**：2026-09-23
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：用户反馈「要在项目里播放，而不是调用外部播放」

---

## 1. 目标（Goal）

> 本地缓存里点音频必须始终走应用内 MiniPlayer/播放管线；只有视频（无内置播放器）才允许 OpenFilex。

## 2. 范围（Scope）

**包含：**
- `local_cache_content._play`：非视频删除 `_openExternal` 回退；缺快照/找不到叶子/空 playlist → 用 `DownloadEntry` 合成单曲 `PlaybackContext` 应用内播。
- `PlaylistBuilder`：识别 `file://` 源，直接 `AudioSource.uri`，不再走网络/DB fileKey 查表。
- 快照命中但同目录 playlist 为空 → `withFilteredPlaylist([child])` 单曲播。

**不包含：**
- 视频仍外部打开（无内置视频播放器）。
- 不改 fileKey / 下载落盘 / DB。

## 3. 验收标准（Acceptance）

- [x] 无 work_snapshots 的音频条目点播放 → 应用内出声/MiniPlayer，不弹系统播放器。
- [x] 有快照但找不到叶子 → 仍应用内单曲播。
- [x] 视频仍 OpenFilex。
- [x] analyze 无新增 warning；相关测试过；`build windows --release` 成功。

## 4. 拆解步骤（Steps）

- [x] **Step 0**：建本 TODO。
- [x] **Step 1**：`_play` 音频永不外部 + 合成/空列表单曲 context。
- [x] **Step 2**：`PlaylistBuilder` file:// 短路 + 单测。
- [x] **Step 3**：analyze/test/build + 同步文档 + 归档。

## 5. 风险与回滚（Risks）

- 合成 Child 无 hash 时 candidateKeys 与 DB fileKey 可能不一致 → 必须靠 file:// 短路兜住本地路径，不依赖 md5 逆推。

## 6. 备注 / 决策记录

- `DownloadEntry.filePath` 即绝对路径；`Uri.file(path)` 进 `mediaDownloadUrl` 后 PlaylistBuilder 优先按 scheme=file 建源。

---

## ✅ 完成标记

- 完成时间：2026-09-23 17:49
- 执行命令：`/init`
- CLAUDE.md 更新摘要：download 段 Local-cache audio 改为 **in-app only (no external fallback)**：video 先分支 `_openExternal`，audio 三级 fallback 建 PlaybackContext（快照 playlist → withFilteredPlaylist → _syntheticSingleContext + Uri.file）；PlaylistBuilder `scheme == file` 短路 → AudioSource.uri 不走 candidateKeys/网络；明确勿重引音频外部打开分支。
- 关联 commit：（非 git 仓库）
- 验证：`flutter analyze` 4 既有 warning（无新增）；`flutter test` 210 全过；`flutter build windows --release` RC=0，`xuro.exe` TS=2026-09-23 17:48:41 LEN=91136。

---

## ⛔ 取消标记

- 取消时间：
- 取消原因：
- 后续指向：
