# CI 增加 Windows 构建产物（windows-latest job）

- **创建时间**：2026-09-30
- **负责人**：pmsleepcheck
- **状态**：active <!-- active | done | cancelled -->
- **关联 Issue / PR**：无

---

## 1. 目标（Goal）

> `.github/workflows/build.yml` 目前只出 Android(APK/AAB) 与 iOS(IPA)，桌面端用户拿不到
> 安装包。补一个 `windows-latest` job，让 `v*` tag 的 Release 里同时带上 Windows x64 压缩包。

## 2. 范围（Scope）

**包含：**

- 新增 `build-windows` job：`windows-latest` + Flutter 3.27.0 → `flutter build windows --release`
  → 打 zip → `actions/upload-artifact`。
- `upload` job 的 `needs` 加入该 job；`softprops/action-gh-release` 的 `files` 与
  Release 正文的 Distribution 表加 Windows 行。

**不包含：**

- 不改 Android/iOS 两个既有 job 的构建与签名方式（secrets 缺失问题另行处理）。
- 不做 MSIX / 安装器，只出便携 zip。
- 不给 `workflow_dispatch` 增加分支条件（与既有 job 保持一致：始终构建、仅 tag 发 Release）。

## 3. 验收标准（Acceptance）

- [x] `build.yml` YAML 语法可被解析，`build-windows` job 定义完整（checkout → Flutter → pub get → build → zip → upload）。
- [x] `upload.needs` 含 `build-windows`，`files:` 含 `dist/app-release-windows-x64.zip`。
- [x] Release 正文的文件表包含 `.zip` 行。
- [x] 既有 Android/iOS job 未被改动（diff 只新增 job + 两处引用）。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：新增 `build-windows` job（缓存与 Android job 同 key 规则）
- [x] **Step 2**：接线 `upload`（needs / files / 正文表格）
- [x] **Step 3**：YAML 解析校验 + diff 自检（只动预期位置）
- [x] **Step 4**：勾选本文件、填完成标记、同步 AGENTS/CLAUDE、移入 `done/`

## 5. 风险与回滚（Risks）

- **风险**：`windows-latest` 缺 C++ 桌面工作负载 / CMake → 构建失败。
  - 缓解：runner 镜像自带 VS2022 C++ 工具集；显式 `flutter config --enable-windows-desktop`。
- **风险**：`media_kit_libs_windows_audio` 走 `third_party/` 本地 override，第三方构建脚本拉不到外网资源。
  - 缓解：该包为 vendored 源码（已入版本库），构建期不需要再下载。
- **风险**：Windows job 失败会让 `upload`（连带 Android/iOS 发布）一起挂。
  - 缓解：先在 `workflow_dispatch` 上验证；真出问题可把 `needs` 回退为 `[build-android, build-ios]`。
- **回滚**：revert 本任务 commit 即恢复原 workflow。

## 6. 备注 / 决策记录

- **产物形态**：`build/windows/x64/runner/Release/*` 整目录压成 `app-release-windows-x64.zip`
  （便携版，解压即用），不引入 MSIX/Inno 打包器。
- **命名带 `x64`**：将来若加 arm64 需要区分。
- **不配 secrets**：Windows 构建不需要 Android 签名 secrets，与签名问题解耦。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `AGENTS.md`/`CLAUDE.md`，
> 然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-30
- 执行命令：`/init`（opencode 无 `/init`，手工同步 AGENTS.md + CLAUDE.md）
- CLAUDE.md 更新摘要：`## CI/CD` 段改为「Android APK/AAB + iOS IPA + Windows x64 便携 zip」，
  并记录 `build-windows` 的四步、`upload.needs` 依赖关系与「Windows 挂掉会连带发布失败，
  回退方式是从 `needs` 里摘掉」的回滚说明。
- 关联 commit：见本文件所在 commit（`docs/todos/done/20260930-ci-windows-job.md`）

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：<待填>
- 后续指向：<待填>
