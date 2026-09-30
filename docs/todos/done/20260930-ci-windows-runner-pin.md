# CI Windows job 钉回 windows-2022（规避 windows-latest 的 VS 2026 镜像）

- **创建时间**：2026-09-30
- **负责人**：pmsleepcheck
- **状态**：active <!-- active | done | cancelled -->
- **关联 Issue / PR**：无

---

## 1. 目标（Goal）

> 首次 `build-windows` 失败：`CMake Error ... Generator "Visual Studio 16 2019" could not
> find any instance of Visual Studio`。
> 根因：GitHub 自 2026-06-08~15 把 `windows-latest`/`windows-2025` 迁到
> **Windows Server 2025 + Visual Studio 2026（18.x）** 镜像（changelog: "GitHub Actions:
> Upcoming image migrations"），而 CI 固定的 **Flutter 3.27.0** 里
> `visual_studio.dart` 的生成器映射是 `17 → VS17 2022 / 18 或其他 → VS16 2019`，
> 遇到 18 就回落成不存在的 VS2019 → CMake 配置失败。
>
> 目标：让 Windows 构建稳定通过。

## 2. 范围（Scope）

**包含：**

- `.github/workflows/build.yml`：`build-windows.runs-on` 改为 **`windows-2022`**
  （自带 Visual Studio Enterprise 2022 17.x + C++ 工作负载 + CMake），并加注释说明原因。

**不包含：**

- 不升级 Flutter 版本（升级影响面大，属独立任务）。
- 不在 CI 里现装 VS Build Tools（+5~10 分钟且易碎）。
- 不改 Android / iOS / upload 三个 job。

## 3. 验收标准（Acceptance）

- [x] `build-windows` 使用 `runs-on: windows-2022`，YAML 解析通过。
- [x] 注释写明「windows-latest = VS2026 + Flutter 3.27 映射不到 → 回落 VS2019」的因果，
      防止后人手贱改回 `windows-latest`。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：改 `runs-on` + 注释；YAML 校验
- [x] **Step 2**：AGENTS/CLAUDE 的 CI 段补一句 runner 钉版原因
- [x] **Step 3**：勾选、完成标记、移入 `done/`、commit + `v1.3.0` 指到新提交

## 5. 风险与回滚（Risks）

- **风险**：`windows-2022` 镜像将来会被弃用（GitHub 通常在新镜像 GA 一年后退役）。
  - 缓解：届时升 Flutter 到支持 VS 2026 的版本，或临时改用 CI 内安装 VS2022 Build Tools。
- **风险**：pin 单一镜像会错过镜像更新带来的安全补丁。
  - 缓解：构建产物是应用而非系统镜像，可接受。
- **回滚**：改回 `runs-on: windows-latest`（会重新踩同一个坑）。

## 6. 备注 / 决策记录

- 官方规避路径（GitHub changelog 2026-05-14）：「If you want to remain on VS 2022,
  update the `runs-on:` target to `windows-2022`.」
- 另一条路是 `runs-on: windows-2025`（迁移期仍可能指向 VS2026 镜像，不可靠）或等
  Flutter 修复（flutter/flutter#176399，时间未知），故选 pin 2022。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `AGENTS.md`/`CLAUDE.md`，
> 然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-30
- 执行命令：`/init`（opencode 无 `/init`，手工同步 AGENTS.md + CLAUDE.md）
- CLAUDE.md 更新摘要：`## CI/CD` 段把 Windows job 的 runner 改写为 **`windows-2022`（有意钉版）**，
  记录 `windows-latest` = VS2026 镜像、Flutter 3.27 生成器回落 VS2019 的因果链与
  flutter/flutter#176399，防止被改回 `windows-latest`。
- 关联 commit：见本文件所在 commit

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：<待填>
- 后续指向：<待填>
