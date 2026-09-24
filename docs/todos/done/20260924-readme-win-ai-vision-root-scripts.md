# README 增补（Windows 支持 + AI 愿景 + 许可证叠加）并切换根目录快捷方式/编译脚本到新仓

- **创建时间**：2026-09-24
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：用户要求「修改 README：叠加我们的许可证，在保证原来内容基础上增加 a) Windows 平台支持 b) AI 增强播放（同声传译/翻译/识别，均为 TODO 项目愿景）；在新仓基础上修改根目录的快捷方式和编译脚本」。

---

## 1. 目标（Goal）

> 在不动 README 原有内容的前提下叠加本仓许可证说明并增补 Windows 支持与 AI 愿景章节；把 `F:\AS` 根目录的 `Xuro.lnk`/`build_exe.bat` 切到 `F:\AS\AsmrAiPlayer` + `AsmrAiPlayer.exe`。

## 2. 范围（Scope）

**包含：**
- `README.md` + `README_en.md`：特性/环境/构建命令补 Windows；新增「项目愿景（规划中/TODO）」含同声传译、翻译、识别；许可证段叠加本仓 CC BY-NC-SA 与原项目署名（原文行保留）。
- `F:\AS\build_exe.bat`：PROJECT/EXE/文案 → AsmrAiPlayer。
- `F:\AS\Xuro.lnk`：重定向到新仓 Release 的 `AsmrAiPlayer.exe` 并更名为 `AsmrAiPlayer.lnk`。

**不包含：**
- 不实现任何 AI 功能本体；不改 `lib/` 代码；不动 LICENSE 文件本体；不提交/不推送。

## 3. 验收标准（Acceptance）

- [x] README 中英文原句均保留（原项目作者行逐字不动）。
- [x] README 含 Windows 支持（特性+环境+构建命令）与 AI 愿景三件套且标注 TODO/愿景。
- [x] 许可证段明确本仓 CC BY-NC-SA（链接 LICENSE）+ 原项目署名叠加。
- [x] `build_exe.bat` 指向 `F:\AS\AsmrAiPlayer` 且产物为 `AsmrAiPlayer.exe`。
- [x] `AsmrAiPlayer.lnk` 指向新 Release exe；`Xuro.lnk` 不再存在。
- [x] 无 `lib/` 改动 → 无需 analyze/test/build（若改了则全套重跑）。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：建本 TODO。
- [x] **Step 2**：改 `README.md` / `README_en.md`。
  - 验证：diff 可见新增段，原句仍在。
- [x] **Step 3**：改 `F:\AS\build_exe.bat`；重定向/更名快捷方式。
  - 验证：bat 内路径 = 新仓；lnk TargetPath = AsmrAiPlayer.exe。
- [x] **Step 4**：填完成标记、归档到新仓 `done/`、汇报 git status。

## 5. 风险与回滚（Risks）

- 快捷方式更名后旧 `Xuro.lnk` 消失——回滚：重建指向旧 xuro.exe 的 lnk。
- README 误删原句——回滚：`git -C F:\AS\AsmrAiPlayer checkout -- README.md README_en.md`。

## 6. 备注 / 决策记录

- 「叠加许可证」= README 许可证段写清本仓 CC BY-NC-SA + ShareAlike/NonCommercial 要点，并保留原项目署名行；LICENSE 文件不动。
- AI 三件套（同声传译/翻译/识别）仅愿景，不进「特性」实装清单；与 `F:\AS\todo.txt` 第一阶段方向一致。
- 根目录 = `F:\AS\`（bat/lnk 现存位置），不复制进仓库（保持为本机快捷入口）。

---

## ✅ 完成标记

- 完成时间：2026-09-24
- 执行命令：Edit `README.md`/`README_en.md`；Write `F:\AS\build_exe.bat`；COM 重定向 `Xuro.lnk`→`AsmrAiPlayer.lnk`。无 flutter 命令（零 `lib/` 改动）。
- CLAUDE.md 更新摘要：README 中英增补 Windows 支持（特性/环境/构建命令）+「项目愿景（AI 增强播放 · 规划中 TODO）」章节（同声传译/翻译/识别）+ 许可证段叠加（CC BY-NC-SA 叠加许可、署名链 AsmrAiPlayer→Xuro→Yuro、原句保留）；根目录 `build_exe.bat`/快捷方式切到新仓。CLAUDE.md 本身无需变更（无新架构不变量）。
- 关联 commit：（留给用户提交，未执行 commit/push）

---

## ⛔ 取消标记

- 取消时间：
- 取消原因：
- 后续指向：
