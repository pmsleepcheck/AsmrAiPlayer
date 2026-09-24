# 同声传译真左右耳声道隔离（主轨/翻译轨分耳输出）

- **创建时间**：2026-09-24
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：用户报障「同声传译左右耳有问题 现在是双耳播放」；推翻原 `20260924-binaural-translation-play-fish-tts` 的「简化混播、无声道路由」决策

---

## 1. 目标（Goal）

> 同声传译开启时，主轨只进 mainEar、翻译轨只进对侧耳（真 mpv `af` 声道路由），不再是双耳双轨混播；关闭翻译恢复全立体声。

## 2. 范围（Scope）

**包含：**

- Vendor `just_audio_media_kit-2.1.0` → `third_party/just_audio_media_kit/`（`dependency_overrides` path）。
- Fork 内：`MediaKitPlayer.setAudioFilter`（mpv `af`）；`JustAudioMediaKit` 角色注册表（`expectMainPlayer`/`expectTtsPlayer`、`id→role`、role→player、desired filter 在 init/re-init 时补写）。
- `EarChannelRouter`：lavfi pan 滤镜字符串生成 + `apply(EarSide? mainEar)`（null=清除）；仅 `JustAudioPlatform.instance is JustAudioMediaKit` 时生效（Android no-op）。
- `AudioPlayerService` 构造主轨前 `expectMainPlayer()`；`TranslationSessionController` 创建 `_ttsPlayer` 前 `expectTtsPlayer()`；`_applyVolumes` 顺带 `_applyEarRouting`（enabled→`mainEar` 分耳，否则清 af）。
- 纯逻辑单测：左右滤镜字符串 + 对侧关系。
- 同步 AGENTS.md/CLAUDE.md（撤销「无真声道路由」不变量，注明 Android 降级与 main-first init 前提）。

**不包含：**

- Android/iOS just_audio 原生 pan（no-op 降级，保持音量 mix）。
- 改音量 emphasis 模型（secondary 0.7 仍用于两耳响度平衡）。
- freezed/build_runner；提交/推送。

## 3. 验收标准（Acceptance）

- [x] `third_party/just_audio_media_kit` 经 path override 生效，`flutter build windows --release` 成功。
- [x] 翻译开启时主轨 af → mainEar 单耳、TTS af → 对侧单耳；关闭/`endSession` 清 af。
- [x] swap/ toggle 路由跟随 `mainEar`/`enabled`（经 `_applyVolumes`）。
- [x] Android 路径 `EarChannelRouter.apply` 不抛、不改行为。
- [x] 滤镜字符串单测通过；`flutter analyze` 恰 4 既有 warning；`flutter test` 全过（323+新增 = 327）。
- [x] AGENTS.md/CLAUDE.md 不再声称「无真声道隔离」。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：建本 TODO。
  - 验证：位于 `docs/todos/active/`。
- [x] **Step 2**：Vendor fork + pubspec `dependency_overrides`。
  - 涉及文件：`third_party/just_audio_media_kit/**`、`pubspec.yaml`
  - 验证：`flutter pub get` 成功；override 解析到 path（`pubspec.lock` → `path: "third_party/just_audio_media_kit"`）；`analysis_options.yaml` exclude `third_party/**`；`just_audio_platform_interface: ^4.5.0` 直接依赖。
- [x] **Step 3**：`EarChannelRouter` + 主/TTS expect 接线 + 会话 `_applyEarRouting`。
  - 涉及文件：`lib/core/audio/translation/ear_channel_router.dart`、`audio_player_service.dart`、`translation_session_controller.dart`、`translation_mix_state.dart`（注释）
  - 验证：grep 接线点齐全；analyze 无新 warning。
- [x] **Step 4**：单测滤镜字符串。
  - 涉及文件：`test/core/audio/translation/ear_channel_router_test.dart`
  - 验证：4 例全过。
- [x] **Step 5**：清进程 → analyze（4 warning）→ test 全过 → `build windows --release`。
  - 验证：三门通过——analyze 恰 4 既有 warning、0 error；`flutter test` 327 全过；`build windows --release` 成功（`build\windows\x64\runner\Release\AsmrAiPlayer.exe`，71.0s）。
- [x] **Step 6**：同步 AGENTS.md/CLAUDE.md、勾完步骤、填完成标记、TODO 移 `done/`、汇报 `git status`（不 commit）。

## 5. 风险与回滚（Risks）

- **mpv `af` 语法**：lavfi pan 链错误会静默无声或双声道未隔离 → 用标准 `lavfi=[aformat=…,pan=…]`；失败仅 warning，不阻塞播放。
- **角色认领顺序**：依赖 main 先 init（字幕/翻译均在主轨播放后）→ 文档写明；错序则路由可能装错轨，回滚 = 去掉 override + 删 router 接线。
- **path override 锁版本**：上游 just_audio_media_kit 升级需手动同步 fork → README/AGENTS 注明。
- **回滚**：revert 本次改动即可恢复双耳混播。

## 6. 备注 / 决策记录

- 用户 2026-09-24 推翻原「简化混播」确认：要求真分耳。
- mpv `balance` 不可用（-1 会把 L 映射双声道）；必须 `af` + lavfi pan。
- 滤镜：先 `aformat=channel_layouts=stereo` 再 `pan`，主轨 downmix 到单耳（不丢对侧内容）；TTS 同链。
- 角色：`InitRequest.id` 无公开于 `AudioPlayer` 侧 → fork 内 pending role 队列 + `id→role` 持久（dispose 不删 id 映射，支持 stop→play 同 id re-init）。
- 音量 model 不变；`mainEar` 仍是唯一路由源，swap 已翻 mainEar。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，手动同步根目录 `AGENTS.md`/`CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-24
- 执行命令：手动同步 AGENTS.md / CLAUDE.md（等价 /init）；`flutter pub get` / `flutter analyze`（恰 4 warning）/ `flutter test`（327）/ `flutter build windows --release`（成功）
- CLAUDE.md 更新摘要：`audio/translation/` 段撤销「simplified mix / 无真声道隔离」不变量，改述为真 `af` 分耳路由（media_kit only、Android no-op 降级、`third_party/just_audio_media_kit` fork + path override 手动同步、expect 队列与 main-first init 前提、lavfi pan 滤镜、禁 mpv `balance`、`_applyVolumes`→`_applyEarRouting` 推送、`disposePlayer` 保留 id→role）；Tests 段补 `ear_channel_router_test`；Code Generation 段注明 `third_party/**` analyze exclude。AGENTS.md 同步同等变更。
- 关联 commit：未 commit（git status 见会话汇报）
