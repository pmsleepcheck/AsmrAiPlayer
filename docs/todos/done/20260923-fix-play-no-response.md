# 修复播放无响应（本地缓存/详情已下载播放）

- **创建时间**：2026-09-23
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：用户反馈「播放没反应」

---

## 1. 目标（Goal）

> 点击本地缓存 tab / 详情页已下载文件的播放按钮时必须有可感知结果（应用内开播或明确 SnackBar），不得静默失败。

## 2. 范围（Scope）

**包含：**
- `PlaylistBuilder` 本地路径查找改用 `candidateKeys`（新/旧 fileKey），避免已下载仍走网络流（URL 过期 → 挂起无反馈）。
- 本地缓存音频：优先经 `work_snapshots` 构建 `PlaybackContext` **应用内播放**；失败/无快照再外部打开；全程 try/catch + SnackBar。
- `detail_screen` / 本地缓存 `OpenFilex` 包 try/catch（平台异常不得吞掉）。
- `DetailViewModel.playFile`：`mediaDownloadUrl == null` 时若已有本地文件仍允许进播放管线（离线快照可能无 URL）。

**不包含：**
- 不改 fileKey 算法 / 落盘布局 / DB schema。
- 不改 just_audio 播放器本身。

## 3. 验收标准（Acceptance）

- [x] 本地缓存点播放：音频应用内出声/MiniPlayer 更新；失败有 SnackBar。
- [x] 详情页已下载音频点播放：走本地文件，不依赖网络 URL。
- [x] 已下载视频点播放：本地文件；OpenFilex 异常有提示。
- [x] `flutter analyze` 无新增 warning；下载/playlist 相关测试通过；`build windows --release` 成功。

## 4. 拆解步骤（Steps）

- [x] **Step 0**：建本 TODO。
- [x] **Step 1**：`playlist_builder` + `playFile` 本地优先/candidateKeys。
  - 涉及文件：`lib/core/audio/utils/playlist_builder.dart`、`lib/presentation/viewmodels/detail_viewmodel.dart`
  - 验证：`test/core/audio/utils/playlist_builder_test.dart` 新增 legacy key 命中用例
- [x] **Step 2**：本地缓存页应用内播音频 + 全路径错误反馈。
  - 涉及文件：`lib/screens/contents/local_cache_content.dart`
- [x] **Step 3**：详情页 OpenFilex try/catch + type 缺失扩展名兜底。
  - 涉及文件：`lib/screens/detail_screen.dart`、`lib/widgets/detail/work_file_item.dart`、`lib/presentation/viewmodels/detail_viewmodel.dart`
- [x] **Step 4**：analyze/test/build + 同步 AGENTS/CLAUDE + 归档。

## 5. 风险与回滚（Risks）

- **风险**：candidateKeys 查找增加少量 DB 命中分支（逻辑与 removeDownload 一致）。
- **回滚**：revert 本 TODO 改动即可。

## 6. 备注 / 决策记录

- 「没反应」优先怀疑：① 预签名 URL 过期 + 本地 key 未命中仍走网络；② OpenFilex 异常被 async 吞掉；③ 本地缓存音频误走外部打开无反馈。

---

## ✅ 完成标记

- 完成时间：2026-09-23 17:28
- 执行命令：`/init`
- CLAUDE.md 更新摘要：download 段补 Play-no-response 不变量（candidateKeys 本地查表、playFile URL-null 本地兜底、type 缺失扩展名判定、handleFileTap 全包 try/catch、本地缓存音频应用内播放）；Tests 段补 playlist_builder legacy key 用例。
- 关联 commit：（非 git 仓库）

---

## ⛔ 取消标记

- 取消时间：
- 取消原因：
- 后续指向：
