# 首页热门卡片 + 下载/本地缓存合并 + 无图片模式

- **创建时间**：2026-09-24
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：用户口头需求三条（首页热门入口卡片 / 下载管理与本地缓存合并页 / 设置无图片模式）

---

## 1. 目标（Goal）

> 三项体验优化：① 首页入口网格增加「热门」卡片；② 侧栏「下载管理」与底部「本地缓存」合并为一页（上：可折叠下载队列，默认仅在有进行中任务时展开；下：本地文件）；③ 新增「无图片模式」设置，开启后列表/播放器/详情页均不加载封面图。

## 2. 范围（Scope）

**包含：**
- 首页 `HomeContent` 网格新增「热门」入口卡片 → `onNavigateToTab(3)`。
- 合并页：本地缓存 Tab（index 4）作为唯一载体 —— 顶部 `DownloadQueuePanel`（可折叠，初始展开 iff `DownloadQueueService.pendingCount > 0`），下方现有本地文件区（路径头/筛选/chips/列表/播放/删除逻辑不动）。
- 侧栏「下载管理」改为切到本地缓存 Tab（不再 push 独立 `DownloadManagementScreen`）；若无其他引用则删除该独立页。
- `AppSettingsService.noImageMode`（默认 false，SharedPreferences 持久化）+ 设置页开关（外观或内容分组）。
- 四个封面渲染点接入：`WorkCoverImage`（全部网格/列表）、`WorkCover`（详情）、`SquareCover`（播放页）、`MiniPlayerCover`（迷你条）—— 开启后不发起网络图片请求，显示主题色占位。
- 全部新文案进 `strings.dart`。

**不包含：**
- 移除底部导航「热门」Tab（保留；卡片是**额外**入口）。
- 通知栏 artUri / 悬浮歌词封面逻辑。
- 下载队列持久化、并行下载策略改动。
- Freezed 模型变更（无需 build_runner）。
- 提交 / 推送（留给用户）。

## 3. 验收标准（Acceptance）

- [x] 首页出现第 5 张「热门」卡片，点击切到热门 Tab（index 3）；原四卡行为不变。
- [x] 本地缓存 Tab 顶部为下载队列区：有 queued/running 任务时默认展开；无则默认折叠；点头部可随时折叠/展开，折叠后仍能看到进行中数量角标/摘要。
- [x] 队列区任务行为与原下载管理一致：进度、取消、重试、播放、清除已完成可用。
- [x] 下方本地文件区行为不变（分组、筛选、播放、翻译播放、删除、打开目录）。
- [x] 侧栏「下载管理」进入合并页（切 Tab 4），不再进入独立页；无残留死代码引用。
- [x] 设置页出现「无图片模式」开关，重启后状态保持。
- [x] 开启后：作品网格、详情页封面、播放页封面、迷你播放条封面均不加载网络图（占位可见）；关闭后立即恢复。
- [x] `flutter analyze` 恰为 4 个既有 warning；`flutter test` 全过；`flutter build windows --release` 成功。
- [x] 本任务不改 `lib/data/models/` Freezed。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：建本 TODO。
  - 验证：位于 `docs/todos/active/`。
- [x] **Step 2**：首页「热门」卡片。
  - 涉及文件：`lib/screens/contents/home_content.dart`、`strings.dart`（如需）
  - 验证：第 5 卡渲染；`onNavigateToTab(3)`。
- [x] **Step 3**：`AppSettingsService.noImageMode` + 设置开关 + 文案。
  - 涉及文件：`app_settings_service.dart`、`settings_screen.dart`、`strings.dart`
  - 验证：开关读写 prefs；ListenableBuilder 实时生效；leading 中性（settings_d1 不破）。
- [x] **Step 4**：四个封面组件接入无图片模式。
  - 涉及文件：`work_cover_image.dart`、`work_cover.dart`、`square_cover.dart`、`mini_player_cover.dart`
  - 验证：on → 占位不发请求；off → 原样；三配色无硬编码色。
- [x] **Step 5**：可折叠 `DownloadQueuePanel` + 并入 `LocalCacheContent` 顶部。
  - 涉及文件：新 `download_queue_panel.dart`（或 widgets/ 下）、`local_cache_content.dart`、`strings.dart`
  - 验证：初始展开规则 = pendingCount>0；折叠状态本地 State；队列操作齐全。
- [x] **Step 6**：侧栏「下载管理」改切 Tab 4；清理 `DownloadManagementScreen` 引用（无引用则删文件）。
  - 涉及文件：`sidebar_menu.dart`、`main_screen.dart`（如需传 onNavigateToTab）、`download_management_screen.dart`
  - 验证：侧栏点击落到合并页；`grep DownloadManagementScreen` 无残留。
- [x] **Step 7**：单测（如适合：noImageMode 持久化 / 面板初始展开逻辑纯函数）。
  - 涉及文件：`test/...`
  - 验证：`flutter test` 全过。
- [x] **Step 8**：串行验证：等 flutter/MSBuild 进程清空 → `analyze`（恰 4 warning）→ `test` 全过 → `build windows --release`。
- [x] **Step 9**：完成标记 + 手动同步 AGENTS.md/CLAUDE.md + 移入 `done/` + 汇报 `git status`（不 commit）。

## 5. 风险与回滚（Risks）

- **Tab 指标/索引**：合并只动 Tab 4 内容与侧栏入口，不改底部 5 个 destination 的 index 契约（0收藏/1主页/2推荐/3热门/4本地）。
- **侧栏导航模式**：侧栏目前是 push 路由；改切 Tab 需要 MainScreen 注入回调，避免做成「弹抽屉后再 push 一个假页面」。
- **无图片模式**：占位需保留 RJ/时长/已下载角标与 Hero 结构，避免 Hero tag 断裂（`work-cover-<id>` / `mini-player-cover` 契约不动）。
- **DownloadManagementScreen 删除**：先 grep 全部引用；有未预期引用则保留文件仅去侧栏入口。
- **回滚**：按 Step 独立 revert；`noImageMode` 默认 false 对旧行为零影响。

## 6. 备注 / 决策记录

- 用户原话：「1把原来的首页（热门）也做成首页上的一个卡片 2下载管理功能和本地缓存功能合并上面是下载列表（如果有正在下载内容 否则折叠） 下载中区域有折叠功能 下面是本地文件区域 3 新增设置 无图片模式开启 此模式不显示封面图片（包含列表和播放器 详情页）」。
- 「也做成」= 追加入口，不删除底部热门 Tab。
- 合并页载体选底部本地缓存 Tab（高频、已有列表基建）；侧栏下载管理改道，不再维护两套列表 UI。
- 下载队列仍是 session-only（`DownloadQueueService`），本地文件仍来自 `DownloadService.listAllDownloads()`，数据源不合并、只合并展示。
- 无图片模式读点在四个封面 widget（可直达 `GetIt.I<AppSettingsService>()`）；通知栏 art 不在本次范围。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-24 11:25
- 执行命令：`/init`（本次为手动同步 AGENTS.md/CLAUDE.md 对应章节，未跑 `/init`）
- CLAUDE.md 更新摘要：Home 四宫格改为含「热门」的 5 入口；下载管理并入本地缓存 Tab（`DownloadQueuePanel`，侧栏/详情 SnackBar 经 `MainScreen.pendingTab` 切 Tab 4，`DownloadManagementScreen` 已删）；新增 `AppSettingsService.noImageMode` 与四封面占位读点。
- 关联 commit：（未提交，留给用户）

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

> 任务取消时填写此块，**不需要执行 `/init`**，将文件移入 `docs/todos/cancelled/`。

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：<例如：方案被替换为 XYZ / 优先级下调 / 上游接口取消>
- 后续指向：<如有继任任务，写明对应的 TODO 路径；否则留空>
