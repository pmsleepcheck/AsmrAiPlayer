# 首页改为四宫格入口（推荐/搜索/本地/定时关闭）

- **创建时间**：2026-09-23
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：用户要求「首页不要立刻显示推荐 而是显示一个四宫格 推荐 搜索 本地 定时关闭」——完成。

---

## 1. 目标（Goal）

> 首页 Tab 打开即见 2×2 四宫格：推荐、搜索、本地、定时关闭；不再自动加载/展示推荐作品网格。

## 2. 范围（Scope）

**包含：**
- 重写 `HomeContent`：零网络请求的四宫格入口页。
- Tab 切换回调注入（`onNavigateToTab`）；AppBar 筛选按钮仅推荐/热门显示。
- 文案 `Strings.homeGrid*`；定时关闭 tile 跟随 `SleepTimerController` 会话状态。

**不包含：**
- 不删 RecommendContent/tab、不改底部导航结构、不改 HomeViewModel 加载逻辑（首页不再触发即可）。

## 3. 验收标准（Acceptance）

- [x] 进入首页 Tab 即见四宫格，无推荐网格/无立即推荐请求（`ensureFirstLoad` 调用已移除）。
- [x] 推荐→index 2；本地→index 4；搜索→SearchScreen；定时关闭→SleepTimerDialog（可设/取消，开启时 tile accent+倒计时文案）。
- [x] analyze 4 既有 warning 无新增；210 测试过；`build windows --release` 成功。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：建本 TODO。
- [x] **Step 2**：读 `home_content.dart`/`main_screen.dart`/`sleep_timer_dialog.dart`，实现回调 + 四宫格 + 文案。
- [x] **Step 3**：analyze/test/build + 同步 AGENTS/CLAUDE + 归档。

## 5. 风险与回滚（Risks）

- 回滚：还原 `home_content.dart` + `main_screen.dart` + `strings.dart` 三文件即可。
- `HomeGreeting`/`ContinuePlayingCard`/`AppSearchField`(首页用法) 自此无调用方但保留（公开组件 + 各有单测，如 `home_greeting_test`/`continue_playing_card_test` 仍绿）。
- 一次性踩坑：首版 `HomeContent.build` 留了未用的 `cs` 局部变量 → analyze 第 5 个 warning，已删。

## 6. 备注 / 决策记录

- 首页问候语/继续播放卡片/只读搜索框整体移除（用户指令=显示一个四宫格）；搜索入口收敛为宫格内一格。
- Tab 回调用构造参数注入而非新全局状态；`_pages` const 列表改为 build 内联构造。
- 标题栏计数：首页不再加载 → `pagination?.totalCount` 为 null → 标题显示纯「主页」。
- 定时关闭文案复用 `Strings.playerSleepTimerActive(m)`（与播放页一致）。

---

## ✅ 完成标记

- 完成时间：2026-09-24 09:30
- 执行命令：`/init`（手动等价：已同步 AGENTS.md + CLAUDE.md）
- CLAUDE.md 更新摘要：screens 段追加「Home four-grid entries」——首页=2×2 入口宫格（推荐/搜索/本地/定时关闭）、进页零网络加载、`onNavigateToTab` 回调注入、AppBar 筛选仅 2/3、定时 tile 跟随 SleepTimerController、`Strings.homeGrid*`；勿把推荐自动加载加回首页。
- 关联 commit：无（非 git 仓库）

---

## ⛔ 取消标记

- 取消时间：
- 取消原因：
- 后续指向：
