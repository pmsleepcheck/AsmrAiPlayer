# 本地缓存 Tab + 详情页离线降级与已下载播放

- **创建时间**：2026-09-23
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：

---

## 1. 目标（Goal）

> ① 底部导航新增「本地缓存」tab，查看/管理已下载文件（重点视频：播放/删除/打开目录）；
> ② 详情页默认在线，接口连不上时降级为本地快照详情（可见的离线提示 + 可重试）；
> ③ 详情页已下载文件除角标外增加播放按钮（已下载视频直接开本地文件）。

## 2. 范围（Scope）

**包含：**
- `DownloadService.listAllDownloads()` / `removeByEntry()` 只读+删除 API（不改落盘布局/fileKey 不变量）。
- `LocalCacheViewModel` + `LocalCacheContent`：按作品分组列出 downloads，支持全部/视频/音频过滤、单条播放、删除、打开下载根目录。
- `MainScreen` 第 5 个底部 tab（页 4）+ 标题/筛选按钮索引兼容。
- `DetailViewModel.usingLocalDetail`（快照回退标记）+ `retryFromNetwork()`；`detail_screen` 离线横幅（含快照时间/重试）。
- `WorkFileItem` 已下载态：保留 `download_done` 角标，增加播放 IconButton；`detail_screen.onFileTap` 视频已下载时 `OpenFilex` 本地路径、不再强制走下载弹窗。
- `strings.dart` 新增文案；相关测试 + `flutter analyze` + `flutter build windows --release`。

**不包含：**
- 不迁移历史绝对路径、不改 DB schema（仍是 v3 `work_snapshots`）。
- 不做缓存配额设置/批量全选删除（单条删除即可）。
- 不改音频播放管线与 `playlistAudioExtensions`。

## 3. 验收标准（Acceptance）

- [x] 底部出现第 5 个 tab「本地缓存」，进入后列出已下载文件（有 `work_snapshots` 时显示作品名）。*
- [x] 过滤「视频」只显示视频扩展名/`media_type=video` 条目；视频播放走外部查看器。*
- [x] 删除条目后 DB 行与磁盘文件均消失（复用 DB-先行不变量）。*
- [x] 断网打开已下载过的作品详情：显示离线横幅 + 文件树来自快照；点「重试」走在线加载。*
- [x] 在线成功时**不显示**离线横幅（默认在线）。*
- [x] 详情页已下载文件 trailing 同时有绿色角标与播放按钮；已下载视频点击直接打开本地文件。*
- [x] `flutter analyze` 无新增 warning；下载相关测试通过；`flutter build windows --release` BUILD_RC=0。

> *UI 行为由实现保证，Windows 实机待用户点验。

## 4. 拆解步骤（Steps）

- [x] **Step 0**：建本 TODO。
- [x] **Step 1**：`DownloadService` 暴露 `listAllDownloads()` + `removeByEntry(DownloadEntry)`（DB 行先行，至少一行成功才删文件）。
  - 涉及：`lib/core/download/download_service.dart`
  - 验证：既有下载测试仍过；新逻辑与 `removeDownload` 同序。
- [x] **Step 2**：`strings.dart` 增加本地缓存/离线详情/播放相关文案。
  - 涉及：`lib/common/constants/strings.dart`
- [x] **Step 3**：`LocalCacheViewModel` + `LocalCacheContent` + 接入 `MainScreen` 第 5 tab。
  - 涉及：`lib/presentation/viewmodels/local_cache_viewmodel.dart`、`lib/screens/contents/local_cache_content.dart`、`lib/screens/main_screen.dart`
  - 验证：有/无下载、过滤切换、删除后列表刷新。
- [x] **Step 4**：详情离线降级 UI：`DetailViewModel.usingLocalDetail` + 重试；`detail_screen` 横幅。
  - 涉及：`lib/presentation/viewmodels/detail_viewmodel.dart`、`lib/screens/detail_screen.dart`
  - 验证：在线无横幅；快照回退有横幅；重试可恢复在线。
- [x] **Step 5**：已下载播放：`WorkFileItem` 播放按钮；`detail_screen.onFileTap` 视频本地优先。
  - 涉及：`lib/widgets/detail/work_file_item.dart`、`lib/screens/detail_screen.dart`（必要时 `work_files_list.dart`/`work_folder_item.dart` 传参）
  - 验证：已下载音频/视频点播放可播（视频外部打开）。
- [x] **Step 6**：验证 + 同步 AGENTS/CLAUDE + 归档。
  - 验证：`flutter test`（下载相关 43+4 新）、`flutter analyze`（仅 4 既有 warning）、杀进程后 `flutter build windows --release` BUILD_RC=0。

## 5. 风险与回滚（Risks）

- **风险**：底部 5 tab 在窄屏 label 挤压（`alwaysHide` 已缓解）。
- **风险**：`removeByEntry` 误删——严格复用「DB 行先行、至少一行成功才删文件」。
- **回滚**：revert 本 TODO 对应改动；`work_snapshots`/落盘布局未变，无数据迁移回滚。

## 6. 备注 / 决策记录

- 本地缓存页用 `IDownloadRepository.listAllOldestFirst` 语义（经 `DownloadService.listAllDownloads`），不扫盘做主数据源；文件缺失时删除路径仍 best-effort。
- 视频判定沿用扩展名优先（与 `WorkFileItem`/`DetailViewModel` 一致）。
- 队列/`playNow`/`loadSnapshot`/fileKey/磁盘回退等上一轮不变量**不得回退**。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-23 17:20
- 执行命令：`/init`（手动等价：AGENTS.md + CLAUDE.md 同步）
- CLAUDE.md 更新摘要：download 段补充本地缓存 tab/listAllDownloads/removeByEntry/详情离线横幅/已下载播放按钮；MainScreen 底栏 5 tab；测试段 local_cache_viewmodel_test。
- 关联 commit：（非 git 仓库，无 commit）

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

- 取消时间：
- 取消原因：
- 后续指向：
