# 已下载匹配修复（fileKey/磁盘回退）+ 详情页已下载标记 + 下载时持久化详情快照

- **创建时间**：2026-09-23
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：用户 Windows 实机反馈：不能匹配已下载内容 / 疑存储问题；建议下载时存详情快照

---

## 1. 目标（Goal）

> ① 修复「已下载无法匹配」：`fileKey` 在无 `hash` 时吃进预签名 URL 查询串会漂移；Windows 上 DB 行丢失/失效后无磁盘回退 → 首页「本地」角标、离线播放、alreadyExists 全挂。② 详情页文件列表增加「已下载」标记，可见即可确认匹配。③ 下载入队时持久化 work+files 详情快照，供自动播放/管理页播放在无 VM、无网络时仍可重建 `PlaybackContext`。

## 2. 范围（Scope）

**包含：**
- `fileKey`：无 hash 时用**去 query/fragment 的 URL** 作身份源（预签名 token 不进 key）。
- `localPathIfDownloaded` / `localPathsForWork` / `findCompleted`：DB 未命中时按 `downloads/<workId>/<fileKey>/` **磁盘目录回退**，并 best-effort 回写 DB 行（自愈）。
- 详情页 `WorkFileItem` 展示已下载标记（批量查 `localPathsForWork`）。
- 新表 `work_snapshots(work_id, payload, updated_at)`：入队时保存 `Work`+`Files` JSON；`playJob`/`playNow` 在 job 缺快照时从 DB 补。
- DB 迁移 v2→v3。

**不包含：**
- 队列跨重启持久化（任务列表仍会话级）。
- 改 Android 外部存储布局。
- 迁移「旧 fileKey 行」到新 key（磁盘回退按目录名=旧/新 key 均可命中）。

## 3. 验收标准（Acceptance）

- [x] 无 hash、URL 带变化 query 的同一文件 → 前后 `fileKey` 一致（单测）。
- [x] 人为删掉 downloads 行、文件仍在磁盘 → 磁盘回退路径（代码路径覆盖；Windows 实机待用户验证）。
- [x] 详情页已下载文件有可见标记（`download_done` trailing）。
- [x] 入队后 `work_snapshots` 有该 workId 行；job 缺 work/files 时 play 仍能播（`loadSnapshot` 单测）。
- [x] `flutter analyze` 无新增 warning（仅 4 既有）；下载相关测试 34 全过；exe 重编成功。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：TODO 文档（本文件）
- [x] **Step 2**：`fileKey` 稳定化 + 磁盘回退匹配
  - 涉及文件：`download_service.dart`、`download_service_test.dart`
- [x] **Step 3**：`work_snapshots` 表 + 入队持久化 + playJob 回补
  - 涉及文件：`database_service.dart`、`work_snapshot.dart`、`i_work_snapshot_repository.dart`、`work_snapshot_repository.dart`、`detail_viewmodel.dart`、`service_locator.dart`、`download_queue_service.dart`
- [x] **Step 4**：详情页已下载标记
  - 涉及文件：`detail_viewmodel.dart`、`work_file_item.dart`、`work_files_list.dart`、`work_folder_item.dart`、`strings.dart`、`detail_screen.dart`
- [x] **Step 5**：analyze + test + 重编 exe

## 5. 风险与回滚（Risks）

- **风险**：新 fileKey 与旧 DB 行不一致 → 已由磁盘按目录回退覆盖；回写 DB 时用新 key，旧 key 行可能残留（无害，LRU 仍按 path）。
- **风险**：磁盘回退多一次目录 IO → 仅 DB miss 时发生。
- **回滚**：去掉磁盘回退与 snapshot 读取即可；表迁移保留无害。

## 6. 备注 / 决策记录

- 预签名 `mediaDownloadUrl` 查询串每次签发可变，不能进身份。
- Windows 上 `sqflite` 曾完全不可用；FFI 后 DB 在 `getDatabasesPath()`，若该路径不稳则行丢失——磁盘回退不依赖 DB 路径，与「win 存储问题」假设对齐。
- 快照存整棵 `Files` 树（与 `PlaybackState` 同策略：playlist/index 不另存，恢复时派生）。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-23 16:57
- 执行命令：`/init`（手动等价：AGENTS.md + CLAUDE.md 同步）
- CLAUDE.md 更新摘要：download 段补充 query-stripped `fileKey`/`legacyFileKey`/磁盘回退/详情快照+已下载角标；database 段 v3 + `work_snapshots`；测试段 fileKey/queue loadSnapshot 覆盖。
- 关联 commit：（非 git 仓库，无 commit）

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

> 任务取消时填写此块，**不需要执行 `/init`**，将文件移入 `docs/todos/cancelled/`。

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：<例如：方案被替换为 XYZ / 优先级下调 / 上游接口取消>
- 后续指向：<如有继任任务，写明对应的 TODO 路径；否则留空>
