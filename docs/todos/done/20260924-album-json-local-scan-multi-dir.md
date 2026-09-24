# 下载写 album.json 专辑信息 + 本地缓存扫盘/多目录（Win & Android）

- **创建时间**：2026-09-24
- **负责人**：zouxin
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：（留空）

---

## 1. 目标（Goal）

> 1) 每次下载完成时在作品目录写入 `album.json`（专辑/作品元数据，复用 WorkSnapshot schema）；
> 2) 本地缓存列表改为「本地文件优先」——新增显式扫盘功能，把磁盘上存在但 DB 缺行的文件回填进 `downloads` 表；
> 3) 支持配置多个缓存/扫描目录（Windows 与 Android 同一代码路径），扫盘与磁盘回退覆盖所有已配置目录。

## 2. 范围（Scope）

**包含：**
- `DownloadService.download()` 新增可选 `work`/`files` 参数；success 与 alreadyExists 路径都 best-effort 写 `<workDir>/album.json`（tmp+rename 原子写，失败绝不影响下载结果）。
- `AlbumMetadataWriter`（payload = `WorkSnapshot.toJson()`，可 round-trip `WorkSnapshot.fromJson`）。
- `DownloadQueueService` 的 `QueueDownloadFn` 透传 `work`/`files`（`_runJob` 下载前 hydrate）；`DetailViewModel.downloadFile/downloadFolder` 直传 `work`/`files`。
- `AppSettingsService.downloadExtraDirs`（prefs key `download_extra_dirs`，StringList，默认空）。
- `DownloadService`：`downloadsRootPaths()`（默认根 + 附加目录）、`scanRoots(roots)` / `scanDownloadsRoots()`（扫盘回填 DB）、扫盘时若 work 目录有 `album.json` 则导入 `work_snapshots`（仅当更新或缺失）；`_recoverFromDisk`/`_recoverByFileName`/`_diskPathsForWork` 改为遍历全部根。
- 设置 → 存储：「附加缓存目录」对话框（列表 + 删除 + 手动输入添加 + FilePicker 浏览，浏览不可用时回退手动输入）。
- 本地缓存 Tab：路径头展示主目录（+N 附加数）；下拉刷新与「扫描」按钮触发 `scanDownloadsRoots()` 后 reload；扫描结果 SnackBar（新增 N 项）。
- 用户可见文案全部进 `Strings`。

**不包含：**
- 不改 DB schema、不引入 Freezed 新模型、不跑 build_runner。
- 不删除 `album.json`（删除作品最后一个文件后保留元数据，便于再次扫盘恢复标题）。
- 不做目录监听（watch）自动扫描——仅显式扫描 / 下拉刷新 / 进页首扫。
- 附加目录不作为新下载的写入目标（写入仍只落默认根 `_baseDir()`；附加目录是**只读扫描源**）。
- 不改容量 LRU 语义（仍按 DB 行的绝对路径回收）。

## 3. 验收标准（Acceptance）

- [x] 下载单文件成功后 `<downloads>/<workId>/album.json` 存在，内容 `WorkSnapshot.fromJson` 可解析出同名作品；alreadyExists 路径也会补写。
- [x] 写 album.json 抛 IO 异常时 `download()` 仍返回 success（best-effort）。
- [x] 手动把一个作品目录（含文件，无 DB 行）放进已配置的附加目录 → 点「扫描」→ 本地缓存列表出现该作品；组标题能从 album.json 导入的快照显示（若无快照则显示 workId）。
- [x] 同一 key 在 DB 已有有效行（文件在盘）时，扫盘不改其 `file_path`（路径稳定）。
- [x] Windows/Android 均能添加、持久化、删除附加目录；重复/空路径被拒绝。
- [x] 无附加目录时行为与现状完全一致（默认根单目录）。
- [x] `flutter analyze` 通过，无新增 warning。
- [x] 相关单元 / Widget 测试通过。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：文案 + 设置存储
  - 涉及文件：`lib/common/constants/strings.dart`、`lib/core/settings/app_settings_service.dart`
  - 验证：`downloadExtraDirs` 空默认 / setStringList 持久化（后续 Step 7 测试覆盖）
- [x] **Step 2**：AlbumMetadataWriter + DownloadService 写 album.json
  - 涉及文件：`lib/core/download/album_metadata_writer.dart`（新建）、`lib/core/download/download_service.dart`（ctor 加 `snapshots`、`download()` 加 `work`/`files`、`_writeAlbum` best-effort、成功/alreadyExists 两路调用）
  - 验证：analyze；work 与 snapshots 双路取数；失败仅 warning
- [x] **Step 3**：调用方透传 work/files
  - 涉及文件：`lib/core/download/download_queue_service.dart`（typedef + `_runJob` hydrate 后透传）、`lib/core/di/service_locator.dart`（闭包转发 + DownloadService 注入 snapshots）、`lib/presentation/viewmodels/detail_viewmodel.dart`（downloadFile/downloadFolder 直传）、`test/core/download/download_queue_service_test.dart`（假下载器补可选参数）
  - 验证：`flutter test test/core/download/` 全过
- [x] **Step 4**：多根目录 + 扫盘
  - 涉及文件：`lib/core/download/download_service.dart`（`downloadsRootPaths`/`scanRoots`/`scanDownloadsRoots`/`_importAlbumIfNewer`；三处磁盘回退改多根遍历；路径归一化去重）
  - 验证：单测 `scanRoots`（临时目录 + 内存假 repo）：新文件回填、有效行不改 path、album.json 导入快照
- [x] **Step 5**：设置 UI——附加缓存目录对话框
  - 涉及文件：`lib/screens/settings/download_dirs_dialog.dart`（新建）、`lib/screens/settings/settings_screen.dart`（`_storageSection` 加 tile）
  - 验证：analyze；settings_d1 不变量（leading 中性 `folder_copy_outlined`）
- [x] **Step 6**：本地缓存 Tab 接扫描
  - 涉及文件：`lib/presentation/viewmodels/local_cache_viewmodel.dart`（`load(scan:)`、`scanAndLoad()`、`lastScanAdded`）、`lib/screens/contents/local_cache_content.dart`（首扫、下拉刷新扫、扫描按钮 + SnackBar、路径头多目录展示）
  - 验证：analyze；手动/测试验证扫描触发路径
- [x] **Step 7**：测试
  - 涉及文件：`test/core/settings/app_settings_download_dirs_test.dart`、`test/core/download/album_metadata_test.dart`、`test/core/download/download_scan_test.dart`（含内存假 repository/snapshot repo）、`test/presentation/viewmodels/local_cache_viewmodel_scan_test.dart`
  - 验证：`flutter test` 全过
- [x] **Step 8**：全量验证 + 文档同步 + 归档
  - `flutter analyze`（恰 4 既有 warning）、`flutter test`（251+新增 全过）、`flutter build windows --release`
  - 手动同步 `AGENTS.md`/`CLAUDE.md`（download 段：album.json / 多根 / 扫盘；settings 段：downloadExtraDirs）；勾完步骤填 ✅ 完成标记；移 `done/`；汇报 `git status`（不 commit）

## 5. 风险与回滚（Risks）

- **风险**：扫盘对超大目录树慢 → 扫描仅显式触发（进页首扫 + 下拉 + 按钮），不进播放热路径；`scanRoots` 深度固定两层（workId/fileKey），不递归全树。
- **风险**：queue typedef 变更破坏既有假实现 → Step 3 同步改测试假下载器（可选参数，编译期即暴露）。
- **风险**：FilePicker `getDirectoryPath` 在部分平台（Android）不可用 → 对话框始终保留手动输入，浏览失败仅提示。
- **风险**：扫盘 upsert 改写有效行路径导致播放路径漂移 → 已有有效行（文件在盘）一律跳过，仅回填缺行/失效行。
- **回滚**：revert 单次 commit；`download_extra_dirs` 空列表 = 旧行为，无迁移负担。

## 6. 备注 / 决策记录

- album.json 位置：`downloads/<workId>/album.json`（workId 根一层，不在 `<fileKey>/` 内）——既有 fileKey 层扫描只进子目录，不会把 album.json 误当媒体行；workId 层列目录时它是 File，被 `is! Directory` 跳过。
- payload 复用 `WorkSnapshot.toJson()`（`{work, files?, updatedAt}`），与 SQLite 快照同 schema，`WorkSnapshot.fromJson` 直接 round-trip；文件名固定 `album.json`。
- `mediaType` 扫盘回填为 `''`（与 `_recoverFromDisk` 一致）——列表视频/音频分类本就扩展名优先。
- 附加目录 = **只读扫描源**（下载仍写默认根）；DB `file_path` 绝对路径不变量不动，无迁移。
- DI 顺序：`IWorkSnapshotRepository` 注册先于 `DownloadService`，可安全注入。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-24
- 执行命令：手动同步 `AGENTS.md`/`CLAUDE.md`（未跑 `/init`——已按手册直接编辑对应段落，效果等价）
- CLAUDE.md 更新摘要：
  - `core/download/` 段：album.json sidecar（`AlbumMetadataWriter` best-effort、tmp→rename、queue hydrate）、多根 `downloadsRootPaths`/`scanRoots`（只读附加目录、路径稳定不变量、album.json 导入、仅显式扫盘）、`local_cache` VM 扫描入口、`DownloadDirsDialog`。
  - `core/settings/` 段：`downloadExtraDirs`（prefs `download_extra_dirs`、只读扫描源语义）。
  - Tests 段：补 `album_metadata_test` / `download_scan_test` / `app_settings_download_dirs_test` / `local_cache_viewmodel_scan_test` 覆盖说明。
- 关联 commit：（未 commit，按工作流仅汇报 `git status`）

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：
- 后续指向：
