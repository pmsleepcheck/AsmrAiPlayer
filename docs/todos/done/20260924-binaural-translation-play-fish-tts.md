# 第一阶段.1：双耳「翻译+播放」——左右耳检测 + fish TTS 混播 + 播放器翻译开关/方向切换

- **创建时间**：2026-09-24
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：`F:\AS\todo.txt` 第一阶段.1；用户确认：含 fish API 全流程（文档自行查 fish 官网）；音频路由为**简化混播模式**

---

## 1. 目标（Goal）

> 为已有汉化字幕的作品提供「翻译+播放」入口：检测/标记主耳侧，列表一键以翻译混播模式播放，播放中可随时开关翻译并切换主次方向；翻译语音由 Fish Audio TTS 按当前字幕行生成并与主音轨混播。

## 2. 范围（Scope）

**包含：**

- **左右耳检测链**：文件名含 左/右/left/right → 本地立体声 WAV 左右声道 RMS 强度 → 弹窗用户选择；用户标记按 `fileKey` 持久化（SharedPreferences）。
- **Fish Audio TTS 全流程**：设置页配置（API Key、reference_id 音色、model）；`POST https://api.fish.audio/v1/tts` 调用；按 `hash(text+voice+model)` 磁盘缓存生成结果。
- **翻译混播会话**：`TranslationSessionController`（GetIt 单例）——第二 `AudioPlayer` 与主音轨同时输出；随字幕行变更拉取/生成 TTS 播放；与主播放 pause/play/seek/切曲/stop 同步。
- **列表入口**：详情页 `WorkFileItem`、本地缓存 `local_cache_content` 的播放按钮**左侧**增加「翻译+播放」图标（仅音频）；点击 = 解析耳侧（含必要弹窗）→ 开翻译会话 → 按原路径播放。
- **播放器两按钮**：开关翻译、切换方向。混播下「方向」= `mainEar` 左右交换 + 主/次音量 emphasis 交换（主音量 1.0 / 次音量默认 0.7，可设置）。
- **设置 UI**：设置页新增「AI 翻译」分组（Key/音色/模型/次音量/连通性提示文案）。
- **文案**：`strings.dart` 全部新增用户可见文案。
- **测试**：耳侧文件名检测、WAV 波形 RMS、fish 请求构造/缓存键、会话状态机（音量交换/开关）等纯逻辑单测。

**不包含：**

- 真左右声道隔离/pan（用户已确认简化为混播）。
- todo.txt 第一阶段.2/3/4（日语字幕→中文翻译、生成字幕、智能来回切换耳判定）。
- Fish 翻译类接口（仅 TTS）；不做实时 WebSocket 流式 TTS（用同步 REST + 缓存）。
- 提交 / 推送（留给用户）。

## 3. 验收标准（Acceptance）

- [x] 文件名含 `左|右|left|right`（不区分大小写、全半角常见形态）可解析主耳并跳过弹窗。
- [x] 文件名解析不出时：已下载的立体声 `.wav` 走左右 RMS；仍失败或非 WAV → 弹窗 左耳/右耳（取消则不进入翻译播放）。
- [x] 用户耳侧选择按 `fileKey` 持久化，下次同文件直接复用；可在弹窗中强制重选（入口再次检测到已有标记时直接用标记）。
- [x] 未配置 Fish API Key 时点「翻译+播放」→ 明确 SnackBar/引导设置，不静默失败。
- [x] 配置 Key 后，字幕行变更 → 生成/命中缓存 → 第二播放器与主音轨混播出声；关闭翻译立即静音。
- [x] 详情页与本地缓存音频行：播放按钮左侧存在翻译+播放图标；点击走翻译模式；普通播放行为不变。
- [x] 播放页两按钮：翻译开关（有/无字幕均有反馈）、方向切换（ear + 主次音量对调，按钮状态可见）。
- [x] 主播放 pause/resume/seek/next/prev/stop/切曲时翻译轨行为正确（暂停同停、seek 丢弃过期行、切曲重置队列）。
- [x] 无字幕/无 Key 时开翻译：Snack 提示，不崩溃、不影响主音轨。
- [x] `flutter analyze` 恰为 4 个既有 warning；`flutter test` 全过（210+新增）；`flutter build windows --release` 成功。
- [x] 涉及 `lib/data/models/` Freezed 改动时已跑 build_runner（本任务预期**不改** freezed 模型）。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：建本 TODO（本文件）。
  - 验证：位于 `docs/todos/active/`。
- [x] **Step 2**：耳侧检测 + 标记仓储 + WAV 波形工具 + 单测。
  - 涉及文件：`lib/core/audio/translation/ear_side.dart`、`ear_side_filename_detector.dart`、`wav_stereo_rms.dart`、`ear_mark_repository.dart`、`ear_side_detector.dart`；`test/core/audio/translation/ear_side_test.dart`、`ear_mark_repository_test.dart`
  - 验证：translation 单测组全过。
- [x] **Step 3**：Fish 配置 + TTS 客户端 + 磁盘缓存 + 单测。
  - 涉及文件：`lib/core/audio/translation/fish_tts_config.dart`、`fish_tts_service.dart`；`test/core/audio/translation/fish_tts_service_test.dart`
  - 验证：buildBody/cacheKey/401/缓存命中单测全过。
- [x] **Step 4**：`TranslationSessionController`（双 player 混播 + 字幕驱动 + 与主事件同步）+ DI 注册 + `IAudioPlayerService.setVolume`。
  - 涉及文件：`translation_mix_state.dart`、`translation_session_controller.dart`、`translation_play_flow.dart`、`service_locator.dart`、`i_audio_player_service.dart`、`audio_player_service.dart`、`player_viewmodel.dart`（seek→notifySeek）
  - 验证：`translation_mix_state_test` 全过；analyze 无新增 warning。
- [x] **Step 5**：列表翻译+播放入口（详情 + 本地缓存 + folder 透传）。
  - 涉及文件：`work_file_item.dart`、`work_folder_item.dart`、`work_files_list.dart`、`detail_screen.dart`、`local_cache_content.dart`、`widgets/translation/ear_side_prompt_dialog.dart`
  - 验证：analyze 通过；仅音频显示图标。
- [x] **Step 6**：播放页两按钮（开关翻译 / 切换方向）。
  - 涉及文件：`widgets/player/translation_controls.dart`、`player_screen.dart`
  - 验证：WaveformProgress 与 PlayerControls 之间插入 TranslationControls。
- [x] **Step 7**：设置页「AI 翻译」配置界面 + 全部 `strings.dart` 文案。
  - 涉及文件：`settings_screen.dart`、`fish_tts_settings_dialog.dart`、`strings.dart`
  - 验证：AI 翻译分组入口 + 弹窗可读写 Key/音色/模型/音量。
- [x] **Step 8**：串行验证：等 flutter/MSBuild 进程清空 → `flutter analyze`（恰 4 warning）→ `flutter test` 全过 → `flutter build windows --release`。
  - 验证：analyze ✅ 恰 4 既有 warning；test ✅ 235 全过（新增 translation 组 25）；build ✅ `AsmrAiPlayer.exe` 出包。
- [x] **Step 9**：填完成标记、手动同步 AGENTS.md/CLAUDE.md、TODO 移入 `done/`、汇报 `git status`（不 commit）。

## 5. 风险与回滚（Risks）

- **双 AudioPlayer**：Windows 走 media_kit；第二实例可能与 audio_session/通知栏交互异常 → 翻译轨初始化失败仅降级为「仅状态+提示」，不拖垮主播放；回滚 = 注销 DI 中的 controller。
- **TTS 网络延迟**：行播完才生成 → 跳过已过期字幕行；磁盘缓存热行秒出。缓存目录纳入存储设置说明（可后续挂 CacheCoordinator）。
- **混播音量**：主次 emphasis 可能不讨好 → 次音量做成设置项（默认 0.7）。
- **API Key 明文**：进 `flutter_secure_storage`（同 AuthRepository 模式），不落 SharedPreferences。
- **范围蔓延**：严格不含 .2/.3/.4；fish 仅 TTS。
- **回滚**：整任务单分支/单提交 revert；各 Step 无破坏既有播放主路径（普通播放不经过翻译会话）。

## 6. 备注 / 决策记录

- **fish API（官网 docs.fish.audio 查证）**：`POST https://api.fish.audio/v1/tts`，头 `Authorization: Bearer <key>`、`Content-Type: application/json`、`model: s2.1-pro|s2-pro|s1|s2.1-pro-free`；体 `{text, reference_id?, format: 'mp3', sample_rate?, ...}`；响应为音频字节流。免费档可用 `s2.1-pro-free`。
- **混播模式（用户 2026-09-24 确认）**：不做单耳隔离；主音轨正常播 + 翻译语音第二 AudioPlayer 同时混播；按钮控两路开关与哪路为主。
- **全流程含 fish（用户 2026-09-24 确认）**：配置界面 + 生成 + 播放本任务内完成；文档已从 fish 官网取得，无需再向用户要。
- **TTS 文本源**：当前已加载字幕的**当前行**（「已有汉化字幕」前提）；无字幕时开翻译仅提示，不朗读标题。
- **方向映射**：`mainEar` left↔right 交换，同时 primary/secondary 音量对象对调（默认主音轨 primary=1.0、翻译 secondary=0.7）。
- **普通播放不自动开翻译**；只有翻译+播放入口或播放页手动打开开关才进入混播。
- 既有 `TranslationInfo` 模型是 asmr.one API 的翻译声明字段，与本功能无关，勿混用。

---

## ✅ 完成标记

- 完成时间：2026-09-24 11:05
- 执行命令：`/init`（手动等价同步 AGENTS.md / CLAUDE.md——新增 `lib/core/audio/translation/` 子系统说明与 translation 单测引用）
- CLAUDE.md 更新摘要：audio 层补充翻译混播会话（ear 检测链 / Fish TTS 缓存 / `TranslationSessionController` 双 player 与主轨同步）与 Settings「AI 翻译」入口；Tests 段补 `test/core/audio/translation/`。
- 关联 commit：未 commit（按约定留给用户；`git status` 见会话汇报）

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

> 任务取消时填写此块，**不需要执行 `/init`**，将文件移入 `docs/todos/cancelled/`。

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：<例如：方案被替换为 XYZ / 优先级下调 / 上游接口取消>
- 后续指向：<如有继任任务，写明对应的 TODO 路径；否则留空>
