# 修复 Windows 下载报「文件写入错误」（sqflite 不支持桌面）

- **创建时间**：2026-09-23
- **负责人**：opencode
- **状态**：active <!-- active | done | cancelled -->
- **关联 Issue / PR**：用户实机反馈（Windows Release 编译产物）

---

## 1. 目标（Goal）

> Windows 端下载音频必现「下载失败，文件写入错误」——根因是 `sqflite` 无 Windows 实现，`DownloadService.download` 的前置 DB 查询（`findCompleted`）抛异常被收敛为 `ioError`。接入 `sqflite_common_ffi` 让桌面端 SQLite 可用，恢复下载/字幕导入/失效行清理等全部 DB 功能。

## 2. 范围（Scope）

**包含：**
- `pubspec.yaml` 新增 `sqflite_common_ffi` + `sqlite3_flutter_libs`（打包 `sqlite3.dll`）。
- 启动早期（任何 DB 访问前）在 Windows/Linux 设置 `databaseFactory = databaseFactoryFfi` 并 `sqfliteFfiInit()`。
- Android/iOS/macOS 行为不变（仍走 sqflite 原生实现）。
- 验证下载链路（`findCompleted` → 落盘 → upsert）在 Windows 可走通。

**不包含：**
- 下载目录改为用户可见位置（仍为 app 文档目录，属产品决策）。
- Web 平台 DB。
- `ioError` 文案细分（DB vs 文件系统）——可后续优化日志，不改 UI 文案。

## 3. 验收标准（Acceptance）

- [ ] Windows Release 启动无 DB 相关异常；设置/下载页无崩溃。
- [ ] Windows 下载音频成功（不再出现「文件写入错误」），生成 `downloads/<workId>/<fileKey>/<标题>` 且 DB 有行。
- [ ] 二次下载同一文件返回 alreadyExists（`findCompleted` 命中）。
- [ ] Android/macOS 路径不受影响（工厂仅在 Windows/Linux 覆盖）。
- [ ] `flutter analyze` 无新增 warning；相关测试通过。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：`pubspec.yaml` 加依赖 → `flutter pub get`
  - 涉及文件：`pubspec.yaml`（`sqflite_common_ffi: ^2.3.4`、`sqlite3_flutter_libs: ^0.5.29`）
  - 验证：pub get 成功，lock 解析到 `sqflite_common_ffi 2.3.4+4` / `sqlite3 2.9.4` / `sqlite3_flutter_libs 0.5.42`
- [x] **Step 2**：启动早期初始化 FFI 工厂（Windows/Linux only）
  - 涉及文件：`lib/core/di/service_locator.dart`（`setupServiceLocator` 最前：`sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi`，在 SharedPreferences/任何 DB 访问之前）
  - 验证：`flutter analyze` 0 新增问题（仍为既有 3 警告）
- [x] **Step 3**：Windows 实机验证下载成功 + 二次下载幂等
  - 涉及文件：—
  - 验证：✅ 用户确认「下载好用了」（2026-09-23）
- [x] **Step 4**：`flutter analyze` + `flutter test` + 重编 Release exe
  - 验证：analyze 通过；test 185 通过 / 2 失败为既有 `playlist_builder_test` Windows 路径分隔符问题（与本任务无关）；Release 构建已触发

## 5. 风险与回滚（Risks）

- **风险**：FFI 与原生 sqflite 打开同一 DB 文件不兼容（路径不同/锁差异）——桌面端此前根本打不开 DB，无存量 DB，无迁移负担。
- **回滚方案**：revert 依赖与初始化代码即可；`databaseFactory` 覆盖仅在桌面生效。

## 6. 备注 / 下载失败诊断链

`DownloadService.download` 把「缺 URL/文件名、DB 打开失败、目录创建失败、文件写入失败」全部收敛为 `DownloadStatus.ioError` → `Strings.downloadIoError`；`DioException` 才是 `networkError`。用户看到「文件写入错误」说明**不是网络问题**。Windows 上 `sqflite`（仅 android/darwin 实现）`openDatabase` 必抛 → 与症状完全吻合。字幕导入（同一 `DatabaseService`）在 Windows 同样会挂，本任务一并修复。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-23 13:45
- 执行命令：`/init`（本会话非 Claude Code，已手动同步 `AGENTS.md`/`CLAUDE.md` database 段：Desktop FFI invariant）
- CLAUDE.md 更新摘要：记录 Windows/Linux 必须在 `setupServiceLocator` 顶部 `sqfliteFfiInit` + FFI 工厂，否则 `openDatabase` 抛 → 下载/字幕 DB 收敛为 ioError
- 关联 commit：—（非 git 仓库）

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

> 任务取消时填写此块，**不需要执行 `/init`**，将文件移入 `docs/todos/cancelled/`。

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：<例如：方案被替换为 XYZ / 优先级下调 / 上游接口取消>
- 后续指向：<如有继任任务，写明对应的 TODO 路径；否则留空>
