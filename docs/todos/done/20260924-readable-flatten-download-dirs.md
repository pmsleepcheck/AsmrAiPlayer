# 下载目录改为可读标题拍平布局（数据源以盘为准）

- **创建时间**：2026-09-24
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：（可留空）

---

## 1. 目标（Goal）

> 放弃 `downloads/<数字workId>/<md5fileKey>/` 编码目录，改为纯可读 `downloads/<作品标题>/<文件名>`（同名文件加 ` (2)` 序号），扫描/回填时**以磁盘内容为准**修复 DB 行；旧布局继续可扫可播、不迁移。

## 2. 范围（Scope）

**包含：**
- 新下载落盘：`downloads/<sanitize(标题)>/<sanitize(文件名)>`，同名冲突加序号 ` (2)`、` (3)`…
- workId ↔ 标题目录：靠 `album.json` 的 `work.id` 反查；`findWorkDir` 支持 legacy 数字目录 + sidecar + 快照标题回退
- 扫盘/回退双布局：拍平（作品根下直接文件）+ 旧 `<fileKey>/` 子目录；路径稳定不变量保留
- `album.json` sidecar 增 `fileKeys: {落盘文件名: fileKey}`，供盘→DB 身份回填
- 「盘为准」：扫描时以绝对 `file_path` 对齐既有行；缺行按 sidecar/文件名回填；失效行清理
- 单测覆盖：序号分配、标题目录解析、双布局 scan、旧布局回归

**不包含：**
- 不迁移旧目录（不改已有 `file_path`）
- 不改 DB `file_key` 语义（仍 md5 `candidateKeys`）
- 不改本地缓存 Tab UI（仍 DB 分组列表）
- 音色预设 / bug.txt 任务（另建 TODO）

## 3. 验收标准（Acceptance）

- [ ] 新下载在默认根下生成 `<标题>/<原文件名>`，无 md5 中间层；同名第二文件为 `名 (2).ext`
- [x] 旧 `downloads/<workId>/<fileKey>/` 扫盘/播放/徽章行为与改前一致（回归测试绿）
- [x] `findWorkDir(workId)` 能定位标题目录（album.json `work.id`）与 legacy 数字目录
- [x] 扫盘对拍平布局：有行路径稳定；无行回填且 `file_key` 与下载时一致（经 `fileKeys` sidecar）
- [x] `removeDownload` 不把标题目录名误当 fileKey 删行
- [x] `flutter analyze` 恰 4 既有 warning、无新增
- [x] 相关单元测试通过（新增 + 既有 download/playlist 全绿）
- [x] `flutter build windows --release` 成功
- [x] AGENTS.md / CLAUDE.md 手动同步（不跑 `/init`）

## 4. 拆解步骤（Steps）

- [x] **Step 1**：纯函数与 sidecar —— `workDirName`/`uniqueDiskName`/`fileKeys` 读写合并
  - 涉及文件：`lib/core/download/download_service.dart`、`lib/core/download/album_metadata_writer.dart`
  - 验证：新增单测绿
- [x] **Step 2**：写路径 —— `_workDir`/`_destPath` 标题拍平 + 序号；`download`/`_writeAlbum` 传 `work`；落盘后写 `fileKeys`
  - 涉及文件：`download_service.dart`
  - 验验：单测 + 既有 identity 测试绿
- [x] **Step 3**：读路径 —— `findWorkDir` 双布局；`scanRoots` 拍平+旧布局；`_recoverFromDisk`/`_recoverByFileName`/`_diskPathsForWork` 兼容；`removeDownload` dirname 守卫
  - 涉及文件：`download_service.dart`
  - 验证：`download_scan_test` 旧用例全绿 + 新拍平用例绿
- [x] **Step 4**：全量验证 —— analyze / test / build windows
  - 验证：见验收标准
- [x] **Step 5**：同步 AGENTS/CLAUDE（手动），勾选本 TODO，移入 `done/`，汇报 `git status`
  - 验证：文档含新布局描述；不 commit

## 5. 风险与回滚（Risks）

- **风险**：同名作品标题目录撞车；sidecar 缺失时拍平文件无法还原 md5 fileKey（徽章/去重退化为文件名回退）
- **回滚**：revert 代码即可；新目录与旧目录并存互不破坏（扫描双布局）

## 6. 备注 / 决策记录

- 用户决策（2026-09-24）：布局=**纯标题拍平+序号**；「内容优先」=**仅数据源以盘为准**（列表 UI 不变）；任务拆分=两份 TODO、先文件夹。
- AGENTS 旧句「Don't flatten back to `<workId>/<name>`」指禁止去掉 fileKey 子目录且仍用数字 workId；本次为**产品决策改为标题根**，完成后改写该段，不是静默违反。
- workId 解析优先级：album.json `work.id` → 目录名（legacy 数字/无 sidecar 用户目录）→ 快照标题反查。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，**手动**同步 AGENTS.md/CLAUDE.md（不执行 `/init`），然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-24
- 执行命令：手动同步 `AGENTS.md`/`CLAUDE.md`（不跑 `/init`）；`flutter analyze`（恰 4 warning）；`flutter test`（301 passed）；`flutter build windows --release` 成功
- CLAUDE.md 更新摘要：
  - `core/download/` 段：磁盘布局改为 `downloads/<标题>/<原文件名>` 拍平 + ` (n)` 序号；legacy `<workId>/<fileKey>/` 双布局扫描/回退；`fileKeys` sidecar；`findWorkDir`/`removeDownload` md5 守卫；改写旧「Don't flatten」句。
  - Tests 段：`download_service_test` 纯函数 / `album_metadata_test` fileKeys / `download_scan_test` 拍平+album work.id 用例。
- 关联 commit：（不 commit，按工作流仅汇报 `git status`）
