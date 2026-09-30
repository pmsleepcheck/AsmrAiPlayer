# 任意一次 CI 运行都自动发布 GitHub Release（无需先打 tag）

- **创建时间**：2026-09-30
- **负责人**：pmsleepcheck
- **状态**：active <!-- active | done | cancelled -->
- **关联 Issue / PR**：无

---

## 1. 目标（Goal）

> 现在 `upload` job 里的 `Create Release` 有 `if: startsWith(github.ref, 'refs/tags/')`，
> 手动 `workflow_dispatch` 跑出来 4 个 artifact 只能手下载、手挂到 Release。
> 目标：**任何一次成功的 workflow 运行都自动创建/更新 GitHub Release**，
> 版本号自动取 `pubspec.yaml` 的 `version:`（tag 触发时仍用 tag 名），正文自动生成 changelog。

## 2. 范围（Scope）

**包含：**

- `.github/workflows/build.yml` 的 `upload` job：
  1. 新增 `Resolve release tag` 步骤（tag 触发 → `github.ref_name`；否则 → `pubspec.yaml` version 加 `v` 前缀）
  2. changelog 的终点由 `${GITHUB_REF#refs/tags/}` 改为 `$GITHUB_SHA`（两条触发路径都成立）
  3. `Create Release` 去掉 `if:`，补 `tag_name` / `target_commitish` / `overwrite_files: true`，
     版本展示与 `prerelease`（tag 含 `-`）改用解析出的 tag
  4. 删掉 `Upload artifacts if not release`（不再需要「非 tag 才传 artifact」的分支）
- `AGENTS.md` / `CLAUDE.md` 的 `## CI/CD` 段同步

**不包含：**

- 不在 push 到 `main` 时自动发版（会每次 push 都出 release，太吵）；触发器仍是 `v*` tag + 手动 dispatch
- 不改三个 build job、不改签名 secrets 逻辑
- 不在 CI 里 bump `pubspec.yaml` 版本

## 3. 验收标准（Acceptance）

- [x] YAML 解析通过，`upload` job 无 `if:` 残留（Create Release 恒执行）
- [ ] 手动 `workflow_dispatch` 跑成功后，Release 页出现 `v<pubspec 版本>`，带 4 个附件与自动生成正文
      （待下一次运行验证——本次改动只能本地校验 YAML 与解析逻辑）
- [ ] 同一版本重复运行 → **更新**同名 Release（assets 覆盖），不产生重复 Release（同上，待运行验证）
- [x] 推 `v*` tag 的老路径行为不变（tag 名即版本，含 `-` 仍是 prerelease）

## 4. 拆解步骤（Steps）

- [x] **Step 1**：改 `upload` job（Resolve tag / changelog 范围 / Create Release / 删 fallback）；YAML 校验
  - 涉及文件：`.github/workflows/build.yml`
  - 验证：`python -c "import yaml,io; yaml.safe_load(io.open('.github/workflows/build.yml',encoding='utf-8'))"`
- [x] **Step 2**：同步 `AGENTS.md` + `CLAUDE.md` 的 CI 段（手动运行也会发版、版本取 pubspec、重复运行覆盖）
  - 验证：两文件 CI 段描述与 workflow 实际一致
- [x] **Step 3**：勾选、填完成标记、移入 `done/`、commit；`v1.3.0` 重打到新提交
  - 验证：`git status` 干净，`git show v1.3.0 --no-patch` 指向新 HEAD

## 5. 风险与回滚（Risks）

- **风险**：CI 创建的 `v1.3.0` 是**轻量 tag**，而本地曾建过 **annotated tag** → 直接 `git push origin v1.3.0` 会被拒。
  - 缓解：发版后删本地 tag（`git tag -d v1.3.0`）或 `git push -f`；已在 AGENTS 记一句。
- **风险**：同一版本重跑会覆盖已发布 assets（下载链接变化）。
  - 缓解：这是期望行为（重新构建即替换）；要发新版本就 bump `pubspec.yaml` 的 `version:`。
- **风险**：`workflow_dispatch` 每跑一次都会写 Release（频繁跑会反复改同一 release）。
  - 缓解：`overwrite_files` 保证不堆积脏 assets；不想要时再把 `Create Release` 加回条件即可。
- **回滚**：revert 本 commit（`git revert <hash>`），`Create Release` 回到 tag-only。

## 6. 备注 / 决策记录

- 版本号来源二选一：tag 触发用 tag 名；手动触发读 `pubspec.yaml` → `v$VERSION`。**发新版 = 改 pubspec 的 `version:`**。
- `target_commitish: ${{ github.sha }}`：tag 不存在时 GitHub 用它在当前提交上建 tag（release API 原生行为，无需 CI 自己 `git tag && push`，避免 GITHUB_TOKEN 触发循环/权限问题）。
- `upload` 已有 `permissions: contents: write`，建 tag + release 够用。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `AGENTS.md`/`CLAUDE.md`，
> 然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-30
- 执行命令：`/init`（opencode 无 `/init`，手工同步 AGENTS.md + CLAUDE.md）
- CLAUDE.md 更新摘要：`## CI/CD` 段改为「tag **与手动 dispatch 都会自动发版**」，
  记录 `Resolve release tag` 的版本来源（tag 名 / `pubspec.yaml` `version:` → `v<version>`，
  去掉 `+build`）、同版本重跑 = 覆盖更新（`overwrite_files`）、changelog 终点固定 `GITHUB_SHA`、
  CI 建的是轻量 tag（本地 annotated tag 别再硬推）。
- 关联 commit：见本文件所在 commit
- 说明：验收项 2/3 需要一次真实运行确认（下一次 `workflow_dispatch` 或推 tag 即可）。

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

- 取消时间：<待填>
- 取消原因：<待填>
- 后续指向：<待填>
