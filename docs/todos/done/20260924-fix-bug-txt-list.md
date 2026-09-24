# 按 bug.txt 依次修复（字幕模式/控件常显/翻译文案与延迟/睡眠倒计时）

- **创建时间**：2026-09-24
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：（可留空）

---

## 1. 目标（Goal）

> 按 `F:\AS\bug.txt` 列出的 6 条依次修复：字幕 Win 兼容与三模式、播放页控件常显、朗读方位文案、同传延迟下拉、睡眠定时剩余时间。

## 2. 范围（Scope）

**包含：**
1. 字幕功能 Windows 平台兼容性问题（排查修复） ✅ 完成
2. 字幕三模式：关闭 / 应用内显示 / 弹窗（Windows 常见系统级字幕样式） ✅ 完成
3. 无论何种播放方式，始终显示：字幕开关、模式切换、朗诵开关、左右耳 ✅ 完成
4. 朗读说明改为「主耳：右　同声传译：左」式描述 ✅ 完成
5. 同声传译延迟：界面下拉选择 ✅ 完成
6. 睡眠定时自动关闭显示**剩余时间**（非固定总时长） ✅ 完成

**不包含：**
- 文件夹可读化（另一 TODO：`20260924-readable-flatten-download-dirs.md`，须先完成）
- 音色预设

## 3. 验收标准（Acceptance）

- [x] bug.txt 1–6 各有可验证行为/文案变更
- [x] 字幕三模式可切换且 Win 下模式 3 可用（或明确降级路径）
- [x] 播放页控件在所有播放模式下可见
- [x] 睡眠定时 UI 每秒（或合适节拍）刷新剩余 mm:ss/分钟
- [x] `flutter analyze` 恰 4 既有 warning、无新增
- [x] 相关测试通过 + `flutter build windows --release` 成功
- [x] AGENTS/CLAUDE 手动同步，TODO 移 `done/`，汇报 `git status`

## 4. 拆解步骤（Steps）

- [x] **Step 1**：排查并修复字幕 Win 兼容（bug 1）
  - 涉及文件：`i_lyric_overlay_controller.dart`（新增 `isSupported`）、`dummy_lyric_overlay_controller.dart`（false）、`lyric_overlay_controller.dart`（true）、`lyric_overlay_manager.dart`（无能力平台不订阅/不 show/不谎报）、`player_screen.dart`（`_LyricOverlayAction` 无能力时 shrink）、`settings_screen.dart`（悬浮歌词整段隐藏）
  - 验证：Win 构建下字幕路径不崩、可显示（字幕条降级）
- [x] **Step 2**：字幕三模式状态 + UI 切换 + Win 弹窗模式（bug 2）
  - 涉及文件：`app_settings_service.dart`（`SubtitleDisplayMode` + prefs `subtitle_display_mode`）、`subtitle_mode_controls.dart`（新开关+下拉）、`subtitle_caption_band.dart`（应用内/Win 弹窗样式字幕条）、`player_screen.dart`（popup↔系统悬浮同步）
  - 验证：三模式切换持久化；模式 3 在 Windows 有可见表现（半透明底白字描边字幕条）
- [x] **Step 3**：播放页控件常显（bug 3）
  - 涉及文件：`player_screen.dart`（`SubtitleModeControls` 常显）、`translation_controls.dart`（耳侧文案常显 + swap 始终可点）
  - 验证：普通/翻译等播放模式下四类控件均可见
- [x] **Step 4**：朗读方位文案（bug 4）
  - 涉及文件：`strings.dart`（`translationEarDesc`）、`translation_controls.dart`、`translation_session_controller.dart`（swap 未开会话时补默认右耳）
  - 验证：文案为「主耳：右　同声传译：左」风格并随 swap 更新
- [x] **Step 5**：同传延迟下拉（bug 5）
  - 涉及文件：`fish_tts_config.dart`（`delayMs` + `delayOptionsMs`）、`translation_session_controller.dart`（epoch 门控延迟后 play）、`fish_tts_settings_dialog.dart`（下拉）
  - 验证：可选延迟档位（0/100/200/300/500/1000ms），TTS 轨按延迟启动
- [x] **Step 6**：睡眠定时剩余时间（bug 6）
  - 涉及文件：`sleep_timer_controller.dart`（`remaining` + 1s ticker）、`strings.dart`（`sleepTimerRemaining`/`playerSleepTimerActive(Duration)`）、player/settings/home/sleep dialog UI
  - 验证：激活时显示倒计时并周期刷新；到点仍 pause 一次（fake_async 测试覆盖）
- [x] **Step 7**：全量验证 + 同步文档 + 归档 + `git status`
  - 验证：analyze 恰 4 warning；`flutter test` **314 全过**（原 301 + 新增）；`flutter build windows --release` 成功

## 5. 风险与回滚（Risks）

- **风险**：Win 弹窗字幕无现成组件，可能需 TopLevelWindow/自绘 overlay；延迟档位改变翻译时序
- **回滚**：revert 对应 Step 提交；sleep timer 不变量（不持久化、pause 不 stop）不得破坏

## 6. 备注 / 决策记录

- 源文本：`F:\AS\bug.txt`（7 行，第 6 行空）。
- 排序：**严格按 bug.txt 1→6**；文件夹任务优先（用户确认）。

---

## ✅ 完成标记

> 全部步骤勾选后填写，手动同步 AGENTS/CLAUDE（不跑 `/init`），移入 `done/`。

- 完成时间：2026-09-24
- 执行命令：手动同步 AGENTS/CLAUDE（不跑 `/init`）
- CLAUDE.md 更新摘要：补充 `ILyricOverlayController.isSupported` 门控、`SubtitleDisplayMode` 三模式与 Win 弹窗降级字幕条、播放页四类控件常显、`translationEarDesc` 文案、`FishTtsConfigStore.delayMs` 下拉、`SleepTimerController.remaining` 1s ticker；Sleep-timer 不变量改为「到点 pause 一次 + UI 显示剩余时间」。
- 关联 commit：（不 commit，留空）
