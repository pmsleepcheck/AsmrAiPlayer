# Fish TTS 多音色预设：命名列表 + 播放页一键切换（预留按角色分配）

- **创建时间**：2026-09-24
- **负责人**：zouxin
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：（留空）

---

## 1. 目标（Goal）

> 音色 Reference ID 支持维护多个命名预设、播放页一键切换；数据结构预留未来「不同角色使用不同音色翻译」的扩展位（本次不做角色映射 UI）。

## 2. 范围（Scope）

**包含：**
- `FishTtsConfigStore` 扩展：
  - prefs `fish_voice_presets`：JSON 数组 `[{id, name, referenceId}]`（id = 短 uuid/时间戳字符串）
  - prefs `fish_active_voice_id`：当前选中预设 id；`referenceId` getter 解析为当前预设的 referenceId（空预设/未命中 → 兼容旧 `fish_reference_id` 单值，一次性迁移进预设列表或保留为 fallback）
  - `setActiveVoiceId`、`upsertPreset`/`removePreset`（ChangeNotifier 供播放页 Listenable 刷新）
  - 结构预留：preset 对象可后续加 `role` 字段而不破坏解析（fromJson 忽略未知字段）
- 设置 AI 翻译对话框：管理列表（增/改名/删/设为当前），保留「留空默认音色」语义（列表可为空）
- 播放页 `TranslationControls`：一键循环/下拉切换当前音色（**仅播放页**做切换入口——用户决策）
- 请求与缓存：`FishTtsService` 继续每次读 `config.referenceId`；cacheKey 已含 referenceId，切换天然隔离
- 文案进 `Strings`；不跑 build_runner（无 Freezed）

**不包含：**
- 不做按角色/耳/说话人自动分配音色（未来任务；仅数据结构预留）
- 不改 Fish TTS HTTP 协议、模型列表、API key 安全存储
- 不做音色试听（需网络合成）

## 3. 验收标准（Acceptance）

- [x] 可添加多个命名音色、改名、删除、一键切换；切换后下次 `synthesize` 用新 referenceId。
- [x] 旧 `fish_reference_id` 单值用户升级后行为不回归（仍能发出正确 voice）。
- [x] 播放页 TranslationControls 可切换；设置对话框可管理列表。
- [x] 缓存按 (model, ref, text) 隔离，切换不串音。
- [x] `flutter analyze` 通过，无新增 warning。
- [x] 相关单元 / Widget 测试通过。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：文案（`strings.dart`）— 17 个 `voicePreset*` 常量（section/desc/add/edit/name/nameHint/reference/default/empty/switch/nameRequired/nameDuplicate/deleteConfirm('%s')/setActive/active/delete/noPresets）
- [x] **Step 2**：`fish_tts_config.dart` 预设模型 + prefs 读写 + 旧值迁移
  - 验证：单测（默认/迁移/切换/增删）— `test/core/audio/translation/fish_voice_preset_test.dart` 全过
- [x] **Step 3**：设置对话框列表管理 UI（参考 `download_dirs_dialog` 校验模式）
- [x] **Step 4**：播放页 `TranslationControls` 一键切换（`_cycleVoice` 循环切换 + `Listenable.merge` 刷新）
- [x] **Step 5**：测试全量 + `flutter analyze` + build windows
  - 验证：analyze 恰 4 既有 warning、0 error；`flutter test` **323 全过**（原 314 + 新增 9）；`flutter build windows --release` 成功
- [x] **Step 6**：同步 AGENTS/CLAUDE → 归档 → git status

## 5. 风险与回滚（Risks）

- **风险**：迁移把旧单值弄丢 → 迁移只在 presets 为空且旧值非空时写入；getter 保留旧 key fallback。
- **回滚**：revert；新 prefs key 多余无害。

## 6. 备注 / 决策记录

- 用户决策：先做预设列表（不做角色映射）；切换 UI **仅播放页**；设置页管列表。
- 音色 ID 非敏感 → 普通 SharedPreferences（API key 仍 secure storage）。
- 排期：字幕智能匹配 TODO（`20260924-smart-subtitle-matching-album-json.md`）先做完再做本任务。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-24 17:15
- 执行命令：手动同步 AGENTS/CLAUDE（不跑 `/init`）
- CLAUDE.md 更新摘要：补充 `FishVoicePreset` 多音色预设（prefs `fish_voice_presets`/`fish_active_voice_id`、旧 `fish_reference_id` 一次性迁移与 fallback、`upsertPreset`/`removePreset`/`setActiveVoiceId`、fromJson 忽略未知字段预留 `role`）、设置对话框列表管理、播放页 `TranslationControls._cycleVoice` 一键切换、cacheKey 含 referenceId 切换天然隔离。
- 关联 commit：（不 commit，留空）
