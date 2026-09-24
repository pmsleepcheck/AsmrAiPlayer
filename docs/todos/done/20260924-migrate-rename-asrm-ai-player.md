# 迁移到 AsmrAiPlayer 仓库并全套改名（Dart 包 aaplay / 应用 ID com.aaplay）

- **创建时间**：2026-09-24
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：用户要求「把项目迁移到 AsmrAiPlayer 文件夹并改名为 AsmrAiPlayer，必要简称 aaplay/AAP」；目标文件夹已有 fork 克隆（origin=pmsleepcheck/AsmrAiPlayer, upstream=WuMe-sicx/Xuro），需保持可提交。

---

## 1. 目标（Goal）

> 项目整体落到 `F:\AS\AsmrAiPlayer`（保留其 `.git`），完成全套改名：文件夹/显示名 **AsmrAiPlayer**、Dart 包 **aaplay**、应用 ID **com.aaplay**、Windows exe **AsmrAiPlayer.exe**；analyze/test/build 全绿，git 状态可供后续提交。原 `F:\AS\Xuro-main` 冻结为备份不动。

## 2. 范围（Scope）

**包含：**
- 整树覆盖拷贝（排除 build/.dart_tool/ephemeral/local.properties 等生成物，**不动目标 .git**）。
- `package:xuro`→`package:aaplay`（lib/test 全部 import）、pubspec `name: aaplay`。
- Android：namespace/applicationId `com.aaplay`、kotlin 目录 `com/xuro`→`com/aaplay`、label `AsmrAiPlayer`。
- Windows：`BINARY_NAME/project` → `AsmrAiPlayer`，Runner.rc 产品信息；Linux：BINARY_NAME/APPLICATION_ID；iOS/macOS bundle id、web manifest、CI/ISSUE 模板、README 标题、About 文案与 repo/feedback 链接指向 fork。
- 验证：目标目录 `pub get` + analyze + test + build windows（产物 `AsmrAiPlayer.exe`）。

**不包含：**
- 不提交/不推送（留给用户）；不删原 Xuro-main；不改电报频道等上游归属链接（除 repo/feedback/update 检查指向 fork）。

## 3. 验收标准（Acceptance）

- [x] `F:\AS\AsmrAiPlayer` 下 `flutter analyze` 4 既有 warning 无新增；`flutter test` 210 全过。
- [x] `flutter build windows --release` 成功，产物 `AsmrAiPlayer.exe`；窗口标题/关于页显示 AsmrAiPlayer。
- [x] 源码 0 处 `package:xuro`/`com.xuro` 残留（生成物除外）；pubspec name=aaplay。
- [x] `git status` 差异清晰可提交；AGENTS/CLAUDE 已同步；TODO 归档到新仓库 `docs/todos/done/`。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：建本 TODO（源仓库）。
- [x] **Step 2**：整树覆盖拷贝到 `F:\AS\AsmrAiPlayer`（保留 .git，排除生成物）。
- [x] **Step 3**：批量改名（dart 包/应用 ID/exe/显示名/平台工程/文案链接）+ kotlin 目录迁移。
- [x] **Step 4**：目标目录 pub get / analyze / test / build windows。
- [x] **Step 5**：同步 AGENTS/CLAUDE、归档本 TODO（新仓库）、汇报 git status。

## 5. 风险与回滚（Risks）

- **数据库名 `xuro.db` 保持不变**：用户 Windows 端已有下载/快照数据，改名会丢 `work_snapshots` 标题（磁盘 fallback 虽可回填但标题降级）——刻意保留，见决策记录。
- `UpdateService` 的 GitHub 检查仓库改指 `pmsleepcheck/AsmrAiPlayer`（否则更新检查仍打上游）。
- 覆盖拷贝若目标存在源没有的文件→保留（git 会显示）；回滚 = `git -C F:\AS\AsmrAiPlayer reset --hard origin/main` + 删未跟踪文件（用户操作）。
- Windows 构建需等 flutter/MSBuild/xuro 进程清空；新目录首次构建较慢（media_kit 重新下载 mpv）。

## 6. 备注 / 决策记录

- 简称：Dart 包=`aaplay`；口头/文档缩写可用 **AAP**；显示名恒为 **AsmrAiPlayer**（用户 2026-09-24 确认「全套」+「简称必要且无歧义时用，可缩写 AAP」）。
- 应用 ID = `com.aaplay`（Android 视为全新应用，升级不保数据——用户已选全套）。
- fork 工作流：origin=pmsleepcheck/AsmrAiPlayer（用户推），upstream=WuMe-sicx/Xuro（同步上游）；迁移后改动以一个 rename+migration commit 提交（由用户执行）。
- `strings.aboutAppName`/Android label/Windows ProductName/web manifest 统一 AsmrAiPlayer；`feedbackUrl`/`repoUrl`/`update_service._repo` 指向 fork。

---

## ✅ 完成标记

- 完成时间：2026-09-24
- 执行命令：`robocopy` 整树覆盖（RC=3）；Python 两轮批量改名（223+10 文件，kotlin `com/xuro`→`com/aaplay` 目录迁移）；`E:\flutter\bin\flutter.bat pub get / analyze / test / build windows --release`（均 workdir=F:\AS\AsmrAiPlayer）
- CLAUDE.md 更新摘要：Project Overview 行改为 `package name: \`aaplay\`, app ID: \`com.aaplay\``（显示名 AsmrAiPlayer、exe AsmrAiPlayer.exe、简称 aaplay/AAP、DB 文件刻意仍为 `xuro.db` 以保磁盘连续性）；Issues 仓库链接改指 `pmsleepcheck/AsmrAiPlayer`；迁移/改名不变量随本文件记录。
- 验证结果：pub get OK；analyze 恰好 4 个基线 warning 无新增；`All tests passed!`（210）；`BUILD_EXIT=0` → `build\windows\x64\runner\Release\AsmrAiPlayer.exe`（含 `libmpv-2.dll`）。审计：源码 `package:xuro`/`com.xuro` 残留 0；裸 `xuro/Xuro` 仅剩 `database_service.dart` 的 `xuro.db`（刻意保留）。
- 关联 commit：（留给用户提交，未执行 commit/push）

---

## ⛔ 取消标记

- 取消时间：
- 取消原因：
- 后续指向：
