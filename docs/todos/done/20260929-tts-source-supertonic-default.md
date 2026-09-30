# 集成 Supertonic 为默认 TTS（Fish API 保留为可切换引擎）+ README 校正

- **创建时间**：2026-09-29
- **负责人**：pmsleepcheck
- **状态**：active <!-- active | done | cancelled -->
- **关联 Issue / PR**：无

---

## 1. 目标（Goal）

> 翻译朗读的默认 TTS 换成本地离线的 Supertonic（免费、低延迟、无需 API Key），
> 同时保留 Fish Audio 云端引擎并提供「切换菜单」；抽象出可扩展的 TTS 源接口，
> 便于后续接入 Edge / Azure 等引擎。顺带把 README「项目愿景」里已实现的能力
> 移入「特性」，避免文档与实现脱节。

## 2. 范围（Scope）

**包含：**

- `TtsSynthesizer` 抽象接口 + `TtsSource` 枚举 + `TranslationTtsRouter`（按配置分发）。
- `SupertonicTtsService`：本地 `POST /v1/tts`（`supertonic serve`，默认 `127.0.0.1:7788`），
  磁盘缓存、健康检查、可选的一键启动。
- `FishTtsService` 实现同一接口，行为保持不变（含代理、缓存、在途去重）。
- `FishTtsConfigStore` 新增 `ttsSource`（默认 **supertonic**）+ Supertonic 的
  地址 / 音色 / 语言配置（pref `translation_tts_source` 等）。
- 设置 → AI 翻译：新增「TTS 引擎」下拉切换菜单；按引擎分区显示配置项
  （Supertonic：地址/音色/语言/检测/启动；Fish：Key/音色预设/模型）。
- `TranslationSessionController` 依赖改为 `TtsSynthesizer`；临时 clip 扩展名按
  音频内容识别（wav/mp3），不再假设 mp3。
- `README.md` / `README_en.md`：已实现的愿景项移入「特性」，愿景只留未实现项。
- 报告：仓库里未纳入版本控制但有提交价值的文件（一键提交可行性）。
- 口头说明 GitHub Releases 发布流程（打 tag → CI 自动出 Release）。

**不包含：**

- 真正的语音识别（ASR）与字幕机翻（日 → 中）——仍属愿景。
- 在 Android/iOS 上内置 Supertonic 运行时（只支持桌面端本机 HTTP 调用；
  移动端选中 Supertonic 时给出明确的「服务不可用」提示）。
- 除 Supertonic / Fish 外第三个引擎的实现（只留接口与枚举扩展位）。
- 改动 CI workflow / 新增 Windows 构建任务。

## 3. 验收标准（Acceptance）

- [x] 设置 → AI 翻译 顶部出现「TTS 引擎」下拉，含 Supertonic（默认）与 Fish Audio 两项；切换后持久化并仅在变更时通知。
- [x] 选 Supertonic 时显示地址/音色/语言 + 健康检测与启动入口，隐藏 Fish Key/预设/模型；选 Fish 时相反。
- [x] `TranslationTtsRouter` 在 supertonic/fish 间正确分发（单测），未知值回落 supertonic。
- [x] `SupertonicTtsService` 的请求体/缓存键/错误映射/离线失败有单测；测试保持网络无关（Dio 拦截器短路）。
- [x] 临时 clip 扩展名按内容（RIFF → `.wav`）判定，合成 mp3 仍为 `.mp3`。
- [x] README「特性」包含同声传译/开关翻译/声道与耳侧判断/多 TTS 引擎；「项目愿景」只剩未实现项（ASR、机翻）。
- [x] `flutter analyze` 通过，无新增 warning/info。
- [x] 相关单元 / Widget 测试通过。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：抽象层 —— `tts_synthesizer.dart`（`TtsSynthesizer` + `clipExtension(bytes)`）+ `TtsSource` 枚举（`fish_tts_config.dart` 加 `ttsSource`/`setTtsSource` 与 Supertonic 配置）
  - 涉及文件：`lib/core/audio/translation/tts_synthesizer.dart`、`fish_tts_config.dart`
  - 验证：`flutter analyze` 通过；config 单测（默认 supertonic / 持久化 / 仅变更 notify）
- [x] **Step 2**：`SupertonicTtsService`（POST `/v1/tts`、缓存、`health()`、`startServer()`）
  - 涉及文件：`lib/core/audio/translation/supertonic_tts_service.dart`
  - 验证：单测（body / cacheKey / 缓存命中 / 连接失败 → unavailable / health true/false）
- [x] **Step 3**：接线 —— `FishTtsService implements TtsSynthesizer`、`TranslationTtsRouter`、controller 依赖改接口 + clip 扩展名按内容判定、DI 注册
  - 涉及文件：`translation_session_controller.dart`、`service_locator.dart`
  - 验证：既有 470 例全绿；`clipExtension` 单测
- [x] **Step 4**：UI —— 设置对话框「TTS 引擎」下拉 + 分区显示 + 检测/启动；`Strings` 新增文案；播放页失败 SnackBar 覆盖「本地服务未启动」
  - 涉及文件：`fish_tts_settings_dialog.dart`、`strings.dart`、`translation_controls.dart`
  - 验证：widget 测试（下拉两项、按引擎显示分区、文案）；`flutter analyze`
- [x] **Step 5**：README 中英校正（愿景 → 特性）+ 许可证段措辞
  - 涉及文件：`README.md`、`README_en.md`
  - 验证：目视 + grep「尚未实现」只留 ASR/机翻
- [x] **Step 6**：全量 `flutter test` + `flutter analyze`；勾选本文件、填完成标记、同步 AGENTS/CLAUDE、移入 `done/`
  - 验证：测试数不降、analyze = 既有基线

## 5. 风险与回滚（Risks）

- **风险**：默认引擎改为 Supertonic 后，未部署本地服务的既有用户翻译朗读会失败。
  - 缓解：失败映射为明确文案「本地 TTS 服务未启动」+ 一键启动/安装指引；设置里可随时切回 Fish。
- **风险**：`Process` 启动子进程在移动端不可用 / 在打包桌面端可能找不到 `supertonic`。
  - 缓解：仅桌面端尝试，失败只提示、不抛错；健康检测按钮可独立判断。
- **风险**：依赖接口化改动触及播放热路径。
  - 缓解：`TtsSynthesizer` 只暴露 `synthesize`，Fish 实现零改动；既有 470 例做回归网。
- **回滚方案**：revert 该任务 commit；或把 `translation_tts_source` 置为 `fish` 即回到原行为。

## 6. 备注 / 决策记录

- **Supertonic 调用方式**：用户态 `pip install 'supertonic[serve]'` + `supertonic serve`
  （默认 `127.0.0.1:7788`），App 只做 HTTP 客户端 —— 不把 ~400MB ONNX 模型塞进 App，
  也不引入 ONNX 运行时依赖。
- **响应格式**：Supertonic `/v1/tts` 支持 `wav/flac/ogg`，取 `wav`；因此临时 clip
  不能再硬编码 `.mp3` → 改为按文件头（`RIFF`/`ID3`/`0xFFEx`）判定。
- **代理**：Supertonic 走 127.0.0.1 回环，**不接 `ProxyConfig`**（走代理反而连不上）；
  Fish 仍接代理，行为不变。
- **异常类型**：复用 `FishTtsException`/`FishTtsError`（新增 `unavailable`）作为
  统一 TTS 异常，避免波及既有测试与 `_lastError` 分支；类名保留 Fish 前缀是历史包袱，
  只加文档说明，不改名（改名收益低、回归面大）。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `AGENTS.md`/`CLAUDE.md`，
> 然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-29（本次会话）
- 执行命令：`/init`（opencode 无 `/init`，手工同步 AGENTS.md + CLAUDE.md）
- CLAUDE.md 更新摘要：
  1. `audio/translation/` 段末追加 **Multi-engine TTS — Supertonic default (2026-09-29)** 段：`TtsSynthesizer`/`TtsSource`/`clipExtension` 抽象与「按文件头定扩展名」、`TranslationTtsRouter` 分发、config 新 pref 与默认 supertonic、`SupertonicTtsService`（HTTP + 缓存 + health + startServer + **不接 ProxyConfig**）、复用 `FishTtsException`/`FishTtsError.unavailable`、设置对话框引擎下拉与分区、`TranslationPlayFlow.ensureTtsReady` 前置闸门、扩展点说明（移动端无本地服务）。
  2. `## Tests` 段追加 **Multi-TTS tests (2026-09-29, suite 470 → 490)**：`tts_source_test` / `supertonic_tts_service_test`（Dio 拦截器短路、网络无关）/ `translation_tts_router_test` / `tts_source_settings_dialog_test`。
- 关联 commit：未提交（`git add -A && git commit` 可一键纳入：新增 21 个文件 + 修改 18 个）

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：<待填>
- 后续指向：<待填>
