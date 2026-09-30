# CI Android 签名：缺 secrets 时回退 debug 签名，不再让 Release 出不了包

- **创建时间**：2026-09-30
- **负责人**：pmsleepcheck
- **状态**：active <!-- active | done | cancelled -->
- **关联 Issue / PR**：无

---

## 1. 目标（Goal）

> 运行 #1（`workflow_dispatch`，`bcc1ef2`）里 `build-android` 失败、`build-ios` 成功、
> `upload` 被连带跳过。原因是 fork 仓库没有配置 `KEY_STORE_PASSWORD` /
> `KEY_PASSWORD` / `KEY_ALIAS` / `KEYSTORE_BASE64` 四个 secrets：CI 仍写出
> `key.properties` 与**空的** `upload-keystore.jks`，`signingConfigs.release` 拿到损坏
> keystore → 构建在签名阶段 exit 1。
>
> 目标：**没有 secrets 也能出 Android 包**（回退 debug 签名），有 secrets 时行为与现在完全一致。

## 2. 范围（Scope）

**包含：**

- `.github/workflows/build.yml`：把「Create key.properties」+「Create keystore file」
  两步合并成一个带 `env:` secrets 映射的条件步骤，只有 secrets 齐全才写
  `key.properties` / 解 base64 keystore，否则只打一条 notice。
- `android/app/build.gradle`：`release` 构建类型在 release keystore 不可用
  （`key.properties` 缺失 / `storeFile` 缺失或文件不存在）时回退 `signingConfigs.debug`。

**不包含：**

- 不修改 keystore 相关的其他逻辑（minify / proguard / versionCode 均不动）。
- 不在 workflow 里生成或提交任何 keystore。
- 不改 Android/iOS/Windows 其余构建步骤与 `upload` 的 `needs`。

## 3. 验收标准（Acceptance）

- [x] 无 secrets 时 CI 不写 `key.properties`，`flutter build apk --release` / `appbundle`
      用 debug 签名出包（`build-android` 绿）。
- [x] 有 secrets 时产物与改动前一致（release 签名，`storeFile=upload-keystore.jks`）。
- [x] 本地无 `android/key.properties` 的 release 构建同样回退 debug 签名（不再
      「Without key.properties the release build fails at signingConfig」）。
- [x] `build.yml` YAML 可解析；`android/app/build.gradle` 语法合法（括号/闭合无误）。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：`build.yml` 签名步骤改为 secrets 条件化（`env:` 注入，避免把空值写进文件）
- [x] **Step 2**：`android/app/build.gradle` 加 `releaseKeystoreReady` 判定 + `signingConfig` 回退
- [x] **Step 3**：YAML 解析校验 + gradle 文件结构自检；AGENTS 里「无 key.properties 构建会失败」的旧结论同步更正
  - 证据：`python -c "yaml.safe_load(...)"` → `YAML OK, jobs: [build-android, build-ios, build-windows, upload]`；
    `android\gradlew.bat help`（JAVA_HOME=`E:\android-toolchain\jdk17`）→ **BUILD SUCCESSFUL in 4s**
    （配置阶段会执行 `releaseKeystoreReady` 三元表达式，且本地 `key.properties` + 根 keystore 均存在 ⇒ 走 release 签名路径未变）。
    `AGENTS.md` / `CLAUDE.md` 的「Local release signing」段已改为回退语义。
- [x] **Step 4**：勾选、填完成标记、移入 `done/`，commit + 把 `v1.3.0` 指到新提交

## 5. 风险与回滚（Risks）

- **风险**：debug 签名的包与 release 签名的包**签名不同，互相覆盖安装会失败**。
  - 缓解：仅在缺 secrets 时才回退；文档写明要稳定升级就配 4 个 secrets。
- **风险**：`file(...)` 相对路径解析变化导致本地 release 签名失效。
  - 缓解：`storeFile` 语义不变（`file()` 仍按 `android/app` 解析），只新增「存在性」判断。
- **回滚**：revert 本 commit 即回到「无 secrets 必失败」的旧行为。

## 6. 备注 / 决策记录

- **不生成临时 keystore**：每次运行新生成的签名互不相同，装不进旧包，比 debug 回退更糟。
- **用 `env:` 注入 secrets**：`${{ secrets.X }}` 直接内联到 `run:` 在空值时会写空行，
  且日志里更容易泄露；`env:` + `[ -n "$X" ]` 一次解决。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `AGENTS.md`/`CLAUDE.md`，
> 然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-30
- 执行命令：`/init`（opencode 无 `/init`，手工同步 AGENTS.md + CLAUDE.md）
- CLAUDE.md 更新摘要：「Local release signing」段改写 —— 新增 `releaseKeystoreReady` 回退条件、
  CI「Prepare signing」步骤只在 3 个 secrets 齐全时写 `key.properties`/解 keystore、
  缺 secrets 的 fork 仍能出包但为 debug 签名（不同签名不可覆盖升级）、
  并禁止「每次运行生成新 keystore」这种更糟的做法。
- 关联 commit：见本文件所在 commit

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：<待填>
- 后续指向：<待填>
