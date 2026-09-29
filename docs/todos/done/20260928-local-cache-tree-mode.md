# 本地缓存页：树形 / 全部文件 视图开关（默认树形）+ 出包（exe / APK）

- **建立时间**：2026-09-28
- **负责人**：opencode
- **状态**：active <!-- active | done | cancelled -->
- **关联 Issue / PR**：无

---

## 1. 目标（Goal）

> 一句话：本地缓存页新增一个视图开关，在「树形模式（完全按磁盘真实文件夹树）」与「显示全部文件（现行按作品分组的扁平列表）」之间切换，**默认树形**；完成后再分别出 Windows exe 与 Android APK。
> 为什么：真实数据里既有 `<作品>/01_通常/MP3/xx.mp3`、`<作品>/LRC or Script/CN/xx.lrc` 这种多级目录，也有 `<workId>/<md5>/xx.mp3` 旧布局，现行扁平列表把目录抹平后用户无法区分来源/格式/字幕分组；树形视图所见即资源管理器所见。

## 2. 范围（Scope）

**包含**
- `AppSettingsService.localCacheTreeMode`（prefs `local_cache_tree_mode`，默认 `true` = 树形）持久化开关。
- 纯逻辑树构建器 `LocalCacheTree.build(entries)`：按 `filePath` 真实层级建树（剥掉公共父目录前缀，保留组内相对结构），文件夹在前、文件在后，各自保持原顺序。
- 本地缓存页头部新增两个互斥 chip：`文件夹树形` / `显示全部文件`；树形态下每个作品分组内渲染可折叠文件夹节点（默认展开，折叠态跨分组收起/展开保持）。
- 文件行沿用现行 `_entryRow`（可播放才出播放/翻译按钮），仅加缩进。

**不包含**
- 不改扫描/DB/下载落盘逻辑（树只读 `DownloadEntry.filePath`，不新建目录、不迁移文件）。
- 不改 `DownloadService` 目录布局（仍为 `downloads/<标题>/<原文件名>` 扁平 + 旧 `<workId>/<fileKey>/`）。
- 不给树形视图加「打开文件夹 / 新建目录」等文件管理能力（仅浏览 + 现有播放/删除）。
- 不动 Android `AndroidManifest` / 签名配置。

## 3. 验收标准（Acceptance）

- [ ] 新装/清空 prefs 进本地缓存页 → 默认为**树形**视图；多级目录作品（如 `01_通常/MP3`）能逐级展开/收起，文件夹显示真实目录名与条目数。
- [ ] 点「显示全部文件」→ 与改动前完全一致的按作品分组扁平列表；重启 app 后选择保持（prefs 生效）。
- [ ] 树形态下播放/翻译/删除按钮行为与扁平态一致（字幕/`album.json` 仍无播放按钮，只留删除）。
- [ ] 分组头折叠再展开，文件夹的展开/收起状态不丢失（按路径记忆）。
- [x] `flutter analyze` 通过，无新增 warning（历史遗留 7 条不计；本次实际仅 3 条既有 warning）。
- [x] 涉及 `lib/data/models/` 的 Freezed/json_serializable 改动时才需跑 build_runner（本次不涉及）。
- [x] 新增单测通过：树构建器（扁平 / 多级 / 旧 md5 布局 / 混合 / 空 / 跨盘符）+ `localCacheTreeMode` 持久化默认值。
- [x] `flutter build windows --release` 成功产出 `build\windows\x64\runner\Release\AsmrAiPlayer.exe`。
- [x] `flutter build apk --release` 成功产出 `build\app\outputs\flutter-apk\app-release.apk`。

## 4. 步骤（Steps）

- [x] **Step 1**：建本 TODO 文档（先于任何代码改动）
  - 涉及文件：`docs/todos/active/20260928-local-cache-tree-mode.md`
  - 验证：文档存在且含范围/验收/步骤。
- [x] **Step 2**：`AppSettingsService` 增加 `localCacheTreeMode`（默认 true + setter notify）
  - 涉及文件：`lib/core/settings/app_settings_service.dart`
  - 验证：`test/core/settings/app_settings_local_cache_tree_test.dart`（默认 true / 写入后 reload 保持 / setter 触发 notify）。
- [x] **Step 3**：新增纯逻辑树构建器 `LocalCacheTree`
  - 涉及文件：`lib/presentation/models/local_cache_tree.dart`
  - 验证：`test/presentation/models/local_cache_tree_test.dart` 覆盖：空输入、扁平（无文件夹节点）、多级目录（文件夹在前 + `fileCount`）、旧 md5 布局、同一作品扁平+md5 混合、跨盘符不崩、`entry` 指回原 `DownloadEntry`。
- [x] **Step 4**：`Strings` 增加开关文案
  - 涉及文件：`lib/common/constants/strings.dart`（`localCacheTreeMode` / `localCacheFlatMode`）
  - 验证：无硬编码中文新增在 UI 里。
- [x] **Step 5**：本地缓存页接线（开关 + 树渲染 + 折叠态）
  - 涉及文件：`lib/screens/contents/local_cache_content.dart`
  - 验证：analyze 通过；手工点验树形/扁平切换、播放/删除可用、分组折叠再展开状态保持。
- [x] **Step 6**：全量 `flutter analyze` + `flutter test`
  - 验证：analyze 仅历史 7 条；test 全绿（364 + 新增）。
- [x] **Step 7**：出 Windows exe
  - 命令：`flutter build windows --release`
  - 验证：`build\windows\x64\runner\Release\AsmrAiPlayer.exe` 存在且时间戳为本次。
- [x] **Step 8**：出 Android APK
  - 命令：`flutter build apk --release`
  - 验证：`build\app\outputs\flutter-apk\app-release.apk` 存在且时间戳为本次。

## 5. 风险与回滚（Risks）

- **风险**：树形为默认视图，若构建器把路径算错（公共前缀取错/分隔符混用），会出现「文件看不到了」的回归——用单测覆盖多布局锁定；扁平分支一行开关即可回退。
- **回滚**：`AppSettingsService.localCacheTreeMode` 关掉即回到现行扁平视图；更彻底则 revert `local_cache_content.dart` 的树渲染分支。

## 6. 备注 / 决策记录

- 树的根 = 组内所有条目 `filePath` 父目录的**公共前缀**：扁平布局（`<标题>/<文件>`）剥完前缀后没有文件夹节点 → 与扁平视图一致；多级目录作品则保留 `01_通常/MP3` 这类真实结构；旧布局保留 `<md5>` 层。这是「完全根据实际的文件夹树形」的直接实现。
- 文件夹默认展开（只记 `collapsed` 集合），文件夹在前、文件在后，各自按原顺序（不重排 → 音轨 01/02 顺序不被字典序打乱）。
- 开关持久化走 `AppSettingsService`（而非 VM 自持 prefs），与 `noImageMode`/`smartPath` 同款写法，避免 VM dispose 回写陈旧值。

---

## ✅ 完成标记

- 完成时间：2026-09-28 15:20
- 执行命令：`/init` —— 当前会话为 opencode，**无该 slash 命令**；已手工同步根 `AGENTS.md` 与 `CLAUDE.md` 各三处：
  1. Build 命令块后补「本地 release 签名」段（根目录 `upload-keystore.jks` + `android/key.properties`，均 gitignored；与 CI 签名不同源）；
  2. 本地缓存 VM 段后补「树形/扁平视图开关」（`localCacheTreeMode` 默认树形、`LocalCacheTree.build` 公共前缀剥除、文件夹在前、默认展开、`_entryRow(indent:)` 复用）；
  3. Tests 段补 `test/presentation/models/local_cache_tree_test.dart`、`test/core/settings/app_settings_local_cache_tree_test.dart`。
- 产物：
  - Windows exe：`build\windows\x64\runner\Release\AsmrAiPlayer.exe`（0.1MB loader，**整个 `Release\` 目录一起分发**，含 `data\`）
  - Android APK：`build\app\outputs\flutter-apk\app-release.apk`（28.3 MB；`apksigner verify --print-certs` 通过，证书 SHA-256 `1c0644a00617010644c566997fb96a870ac1a89f8d98e937df9b89e183af4382`）
- 验证结果：`flutter analyze` 仅 3 条历史遗留 warning（0 新增）；`flutter test` **378 全部通过**（较上一任务 364 新增 14）。
- 待人工点验（UI）：进页默认树形；多级目录作品（如 `01_通常/MP3`）逐级展开/收起；切「显示全部文件」与旧版一致且重启保持；分组折叠再展开保留文件夹收起状态；树形下播放/翻译/删除与扁平态一致（字幕仍无播放按钮）。
- 本地 Android 工具链（**本机专属，未入库**）：
  - JDK 17 = `E:\android-toolchain\jdk17`（Temurin 17.0.20.1）；SDK = `E:\android-toolchain\sdk`（cmdline-tools 11076708 + platform-tools + `platforms;android-35` + `build-tools;35.0.0`，license 已接受）。已 `flutter config --jdk-dir` / `--android-sdk` 注册。
  - `services.gradle.org` 在本网络不可达：Gradle 8.11.1 发行包改由 `mirrors.cloud.tencent.com` 下载，手工放进 `%USERPROFILE%\.gradle\wrapper\dists\gradle-8.11.1-all\2qik7nd48slq1ooc2496ixf4i\gradle-8.11.1-all.zip`（wrapper 会自行解压）。再遇到 wrapper 卡在下载，就重放这一步。
  - 签名：根目录 `upload-keystore.jks`（alias `upload`，密码已单独告知，**不写入本文件**）+ `android/key.properties`；两者都在 `.gitignore`。CI 用的是另一把密钥 → 本地包与 CI 包**签名不同**，不能互相覆盖升级。
  - 构建时 `wakelock_plus` 等插件会刷出 Kotlin incremental cache 的 "different roots"（pub cache 在 C:、工程在 F:）警告，**非致命**，可忽略。
- 关联 commit：未提交（本仓库无 git）
