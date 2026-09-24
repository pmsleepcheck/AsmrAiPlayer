# 本地缓存列表默认按作品文件夹折叠

- **创建时间**：2026-09-24
- **负责人**：opencode
- **状态**：active <!-- active | done | cancelled -->
- **关联 Issue / PR**：用户口头需求「本地内容默认按文件夹折叠」

---

## 1. 目标（Goal）

> 本地缓存 Tab 的作品分组默认**全部折叠**（只显示标题/数量，不展开文件行）；点组头可展开/收起，展开态仅本会话保留。

## 2. 范围（Scope）

**包含：**

- `LocalCacheContent` 分组头改为可点（chevron + 条数），子文件行仅在展开时渲染。
- 默认折叠：`_expandedWorkIds` 初始为空集；新出现的分组默认折叠。
- 文案：组头条数走 `Strings`（如 `localCacheGroupCount(n)`）。

**不包含：**

- 不改 `LocalCacheViewModel` 分组/过滤/删除逻辑。
- 不持久化展开态（不进 SharedPreferences）。
- 不做「全部展开/收起」工具条（除非实现中顺带零成本）。
- freezed/build_runner；提交/推送。

## 3. 验收标准（Acceptance）

- [ ] 进入本地缓存：所有作品组默认折叠，仅见组标题 + 条数 + chevron。
- [ ] 点组头 → 展开该组文件行；再点 → 折叠；多组可各自独立展开。
- [ ] 过滤切换/扫描刷新后：已展开组保持展开（同 workId），新组默认折叠。
- [ ] `flutter analyze` 恰 4 既有 warning、无新增。
- [ ] `flutter test` 全过（含新增折叠行为测试或既有 local_cache 测试）。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：建本 TODO。
  - 验证：位于 `docs/todos/active/`。
- [x] **Step 2**：`Strings` 增加组头条数文案；`LocalCacheContent` 实现默认折叠 + 组头点击展开。
  - 涉及文件：`lib/common/constants/strings.dart`、`lib/screens/contents/local_cache_content.dart`
  - 验证：grep `_expandedWorkIds` / chevron 接线齐全；analyze 无新 warning。
- [ ] **Step 3**：单测/回归（本地缓存相关测试全过）。
  - 验证：`flutter test` 相关文件通过。
- [ ] **Step 4**：清进程 → analyze（4 warning）→ test 全过。
  - 验证：两门通过。
- [ ] **Step 5**：同步 AGENTS.md/CLAUDE.md（本地缓存列表「默认按作品折叠」不变量）、勾完步骤、填完成标记、TODO 移 `done/`、汇报 `git status`（不 commit）。

## 5. 风险与回滚（Risks）

- **风险**：用户找不到文件（不知道要点开）→ 组头必须有明显 chevron + 条数。
- **回滚**：去掉 `_expandedWorkIds` 门控恢复全展开即可。

## 6. 备注 / 决策记录

- 「文件夹」= 既有作品分组（`LocalCacheWorkGroup.workId`，对应磁盘标题目录），不是再拆一层目录树。
- 折叠状态放 `State`（`AutomaticKeepAliveClientMixin`），不进 ViewModel，避免与数据 load 耦合。
- 视觉参照 `DownloadQueuePanel` 组头（InkWell + expand_less/more）。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，手动同步根目录 `AGENTS.md`/`CLAUDE.md`（不跑 `/init`），然后把本文件移入 `docs/todos/done/`。

- 完成时间：YYYY-MM-DD HH:mm
- 执行命令：手动同步 AGENTS.md / CLAUDE.md
- CLAUDE.md 更新摘要：
- 关联 commit：未 commit（git status 见会话汇报）
