# 增加返回按钮（Windows 桌面端）

- **创建时间**：2026-09-23
- **负责人**：opencode
- **状态**：active <!-- active | done | cancelled -->
- **关联 Issue / PR**：根目录 `todo.txt` 前置任务 2

---

## 1. 目标（Goal）

> Android/iOS 有系统返回手势/按键，Windows 桌面没有 —— 为被 push 打开、当前在 Windows 上「无返回出口」的页面补上可见返回按钮，保证桌面端每个二级页都能一键返回。

## 2. 范围（Scope）

**包含：**
- `SearchScreen`：当前**完全没有 AppBar、没有任何返回控件**（Windows 端唯一真正卡死的页面）——在搜索框行左侧加返回 `IconButton`（`tooltip` 走 `Strings.back`，全平台可见，符合搜索页惯例）。
- `FavoritesScreen`：自带 `drawer`，框架自动 leading 被 `DrawerButton`（汉堡）抢占，Windows 上没有返回 ——桌面平台（win/mac/linux）显式 `leading` 返回按钮；移动端保持现状（汉堡 + 系统返回）。
- `Strings` 新增 `back = '返回'`。

**不包含：**
- 已有 AppBar 且被 push 的页面（Settings / About / CacheManager / Detail / SimilarWorks / SubtitlePreview / browse 三页 / Player）——框架 `automaticallyImplyLeading` 已在 Windows 显示 `BackButton`，不改为显式（避免无谓 churn）。
- 键盘快捷返回（Esc / Alt+Left）。
- 播放器 `expand_more` 收起按钮与播放列表二级页 `arrow_back`（已有，不动）。
- `MainScreen` 根页面（抽屉汉堡是正确语义，不动）。

## 3. 验收标准（Acceptance）

- [ ] Windows 打开搜索页后，左上角有返回按钮，点击可回到上一页（6 个入口一致）。
- [ ] Windows 打开收藏页后，左上角是返回箭头而非汉堡；点击返回上一页；抽屉仍可通过返回后的主界面打开。
- [ ] Android/iOS 收藏页行为不变（仍为汉堡 + 系统返回）。
- [ ] `flutter analyze` 通过，无新增 warning。
- [ ] 新增/改动的 Widget 断言通过（如为纯逻辑部分）。

## 4. 拆解步骤（Steps）

按依赖顺序排列，每步注明「验证方法」。

- [x] **Step 1**：`Strings` 新增 `back`
  - 涉及文件：`lib/common/constants/strings.dart`
  - 验证：analyze
- [x] **Step 2**：`SearchScreen` 搜索框行左侧加返回 `IconButton`（`Navigator.maybePop`）
  - 涉及文件：`lib/screens/search_screen.dart`
  - 验证：analyze；Windows 运行点搜索入口可见返回键
- [x] **Step 3**：`FavoritesScreen` 桌面平台显式 `leading` 返回按钮（`defaultTargetPlatform` 判定 win/mac/linux），移动端保持 `null` 走框架自动推断（drawer → 汉堡）
  - 涉及文件：`lib/screens/favorites_screen.dart`
  - 验证：analyze；Windows 上左上角为返回箭头
- [x] **Step 4**：全量 `flutter analyze` + `flutter test`
  - 验证：无新增 warning（仅剩 AGENTS.md 已记录的 3 个既有 unused 警告）；测试 185 通过，2 个失败为 `playlist_builder_test` 既有 Windows 环境问题，与本任务无关

## 5. 风险与回滚（Risks）

- **风险**：桌面端收藏页失去汉堡入口（该页 `drawer` 在桌面不可再打开）——用户可返回主界面开抽屉，影响可接受。
- **回滚方案**：revert 本任务提交；移动端行为零变化，回滚无回归面。

## 6. 备注 / 决策记录

- 项目 UI 层此前 **0 处**平台分支；本任务因目标平台（win 无系统返回）而必须引入 —— 用 `defaultTargetPlatform`（可测试覆盖）而非 `dart:io Platform`。
- 其余 push 页面的自动 `BackButton` 是框架行为且不区分平台，Windows 上本就可见 —— 故真正缺口仅 Search（无 AppBar）与 Favorites（drawer 抢占 leading）两处，已逐一核实全部 13 个 `Scaffold(`。
- 项目无统一返回组件；沿用既有两处写法之一（`playlist_works_view.dart` 的 `IconButton(Icons.arrow_back)` 风格）+ `tooltip`。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-23 10:30
- 执行命令：`/init`（本会话非 Claude Code 环境，无 `/init` 命令可用 —— 已**手动**按 §3.3 等价刷新 `AGENTS.md` 与 `CLAUDE.md`：screens 段新增 Windows 返回按钮不变量）
- CLAUDE.md 更新摘要：记录 SearchScreen 唯一出口、FavoritesScreen 桌面显式 leading / 移动保持汉堡、其余页面依赖框架自动 BackButton 勿 churn
- 关联 commit：无（`Xuro-main/Xuro-main` 非 git 仓库，用户未要求初始化/提交）

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

> 任务取消时填写此块，**不需要执行 `/init`**，将文件移入 `docs/todos/cancelled/`。

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：<例如：方案被替换为 XYZ / 优先级下调 / 上游接口取消>
- 后续指向：<如有继任任务，写明对应的 TODO 路径；否则留空>
