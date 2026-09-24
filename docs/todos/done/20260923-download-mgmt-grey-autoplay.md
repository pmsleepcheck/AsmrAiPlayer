# 下载管理灰屏 + 下完不自动播放修复

- **创建时间**：2026-09-23
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：用户 Windows 实机反馈

---

## 1. 目标（Goal）

> ① 侧边栏/SnackBar 打开「下载管理」整页灰屏（Provider 未注入 `DownloadQueueService`，`context.read` 抛 ProviderNotFound → release ErrorWidget）；② 单曲下载完成后仍不自动播放——`alreadyExists` 不算 success 不触发 `playJob`，且管理页无法对已完成任务手动播放。

## 2. 范围（Scope）

**包含：**
- `DownloadManagementScreen` 改用 `getIt<DownloadQueueService>()` 提供 Provider（不再依赖祖先树）。
- 队列：`alreadyExists` 也触发 `playJob`；拆 `canPlay` / `canAutoPlay`；暴露 `playNow(job)` 供管理页手动播放。
- 下载管理已完成任务增加「播放」按钮（有 work/files 快照时）。

**不包含：**
- 改 Windows 落盘路径。
- 队列持久化。
- 批量下载自动连播。

## 3. 验收标准（Acceptance）

- [x] 从侧边栏 / Snackbar「查看」打开下载管理不再灰屏，能见空态或任务列表。
- [x] 单曲入队（含文件已存在 → alreadyExists）下完后自动播放。
- [x] 下载管理已完成且有快照的任务可点播放。
- [x] `flutter analyze` 无新增 warning；队列测试通过。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：TODO 文档（本文件）
- [x] **Step 2**：修 Provider 灰屏
  - 涉及文件：`download_management_screen.dart`（改用 `getIt<DownloadQueueService>()`）
  - 验证：analyze；页面可渲染
- [x] **Step 3**：队列 `alreadyExists` 自动播放 + `playNow`
  - 涉及文件：`download_queue_service.dart`（`canPlay`/`playNow`/`completed` 含 alreadyExists）
  - 验证：单测 11 个全过（含 alreadyExists、playNow）
- [x] **Step 4**：管理页已完成任务播放按钮
  - 涉及文件：`download_management_screen.dart`、`strings.dart`（`downloadJobPlay`）
  - 验证：有快照时显示播放；无快照不显示
- [x] **Step 5**：analyze + test + 重编 exe
  - 验证：analyze 仅 4 个既有 warning；`flutter build windows --release` RC=0（16:40:25）

## 5. 风险与回滚（Risks）

- **风险**：已存在文件重复入队即播，可能打断用户手动播放 → 仅 playOnComplete 单曲路径已确认。
- **回滚**：去掉 playJob 的 alreadyExists 分支与 playNow 按钮即可。

## 6. 备注 / 决策记录

- 灰屏根因：`ChangeNotifierProvider.value(context.read<DownloadQueueService>())` 但 GetIt 单例从未挂到 Provider 树。
- `completed` 原仅 `success`：预检 `findCompleted` 命中 → `alreadyExists` → 永不 `playJob`。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-23 16:41
- 执行命令：`/init`（本会话手动同步 AGENTS.md/CLAUDE.md，无 /init 工具）
- CLAUDE.md 更新摘要：download 段补充下载管理页 Provider 必须 `getIt` 注入（禁止 `context.read`）、`alreadyExists` 也触发自动播放、管理页 `playNow` 手动播放按钮。
- 关联 commit：（非 git 仓库）

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

> 任务取消时填写此块，**不需要执行 `/init`**，将文件移入 `docs/todos/cancelled/`。

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：<例如：方案被替换为 XYZ / 优先级下调 / 上游接口取消>
- 后续指向：<如有继任任务，写明对应的 TODO 路径；否则留空>
