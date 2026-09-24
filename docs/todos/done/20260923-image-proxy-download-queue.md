# 预览图走代理 + 下载后台队列/下载管理 + 编译脚本修复

- **创建时间**：2026-09-23
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：用户 Windows 实机反馈三连

---

## 1. 目标（Goal）

> ① 封面/预览图加载接入应用内代理（当前 `cached_network_image` 绕过代理，开了代理下载能用、图挂）；② 下载改为后台队列 + 侧边栏「下载管理」页；③ `build_exe.bat` 在中文 Windows 上 cmd 解析失败（LF-only + UTF-8 中文）→ 改为 CRLF + 纯 ASCII。

## 2. 范围（Scope）

**包含：**
- `ProxiedHttpFileService` → `ImageCacheManager` / `SubtitleCacheManager` 的 `HttpFileService` 换成带 `findProxy` 的 client。
- `DownloadQueueService`（串行后台队列，session 级）+ `DownloadManagementScreen` + 侧边栏入口。
- 单曲音频下载/批量下载入队；视频仍走阻塞弹窗（需下载完成即打开）。
- `build_exe.bat` 换行/编码修复。

**不包含：**
- just_audio 流式播放代理（仍不覆盖）。
- 队列跨重启持久化。
- 底部导航栏第 5 个 tab（入口放侧边栏）。

## 3. 验收标准（Acceptance）

- [x] 开代理后封面/详情页大图/字幕缓存请求走代理（图能加载）。
- [x] 点音频下载/下载全部 → 入队 + Snackbar，离开详情页后队列继续跑。
- [x] 侧边栏「下载管理」可见进度/状态，可取消/重试/清已完成。
- [x] 双击 `F:\AS\build_exe.bat` 无 cmd 解析错误，能走到 flutter build。
- [x] `flutter analyze` 无新增 warning；相关测试通过（队列单测 + 全量 196 通过，2 个既有 playlist_builder 失败）。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：修 `build_exe.bat`（CRLF + ASCII + 路径预检）
  - 涉及文件：`F:\AS\build_exe.bat`
  - 验证：`cmd /c build_exe.bat` 不再报「不是内部或外部命令」
- [x] **Step 2**：图片/字幕缓存走代理
  - 涉及文件：`lib/core/network/proxied_http_file_service.dart`（新）、`image_cache_manager.dart`、`subtitle_cache_manager.dart`、`proxy_config.dart` 注释
  - 验证：analyze；封面组件仍用 `ImageCacheManager.instance`
- [x] **Step 3**：`DownloadQueueService` + DI
  - 涉及文件：`lib/core/download/download_queue_service.dart`（新）、`service_locator.dart`
  - 验证：单测队列串行/状态机
- [x] **Step 4**：下载管理页 + 侧边栏 + 接入详情页
  - 涉及文件：`download_management_screen.dart`（新）、`sidebar_menu.dart`、`detail_viewmodel.dart`、`detail_screen.dart`、`batch_download_dialog.dart`、`strings.dart`
  - 验证：入队 Snackbar + 管理页可见任务
- [x] **Step 5**：analyze + test + 重编 exe
  - 验证：无新增 warning；新测试通过；`flutter build windows --release` RC=0（`Release\xuro.exe` 16:21:24）
- [x] **Step 6**：同步 AGENTS.md/CLAUDE.md（/init 等价）
  - 涉及文件：`AGENTS.md`、`CLAUDE.md`
  - 验证：network 段含 `ProxiedHttpFileService`；download 段含 `DownloadQueueService`/下载管理

## 5. 风险与回滚（Risks）

- **风险**：图片代理后若代理关，行为回退环境变量探测（与 Dio 一致）。
- **回滚**：删队列接入恢复原弹窗 await 路径（`downloadFile`/`downloadFolder` 保留给视频）。

## 6. 备注 / 决策记录

- 视频 `openOnDone` 必须等下载完成 → 保持阻塞 `MediaDownloadDialog`，不入队。
- 队列**串行**：维持 DownloadService 批量/容量 LRU「顺序下载」不变量。
- bat 必须 CRLF：cmd 解析 LF-only 的 `if (...)` 多行块会把后续行当独立命令执行。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-23 16:35
- 执行命令：`/init`（本会话手动同步 AGENTS.md/CLAUDE.md，无 /init 工具）
- CLAUDE.md 更新摘要：network 段将 `cached_network_image` 从「不覆盖」改为经 `ProxiedHttpFileService` 走代理；download 段补充 `DownloadQueueService`（串行/会话级/`playJob`）与下载管理页不变量。
- 关联 commit：（非 git 仓库）

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

> 任务取消时填写此块，**不需要执行 `/init`**，将文件移入 `docs/todos/cancelled/`。

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：<例如：方案被替换为 XYZ / 优先级下调 / 上游接口取消>
- 后续指向：<如有继任任务，写明对应的 TODO 路径；否则留空>
