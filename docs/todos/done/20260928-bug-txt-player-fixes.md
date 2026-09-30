# bug.txt 三条播放页问题修复（布局重叠 / 翻译预加载 / 睡眠倒计时整行可点）

- **创建时间**：2026-09-28
- **负责人**：zouxin
- **状态**：active <!-- active | done | cancelled -->
- **关联 Issue / PR**：`F:\AS\bug.txt`（2026-09-28 15:30 版，致命 1 条 + 逻辑 1 条 + 友好性 1 条）

---

## 1. 目标（Goal）

> 按用户「依次修复」要求处理 `bug.txt` 三条：
> ① 安卓播放页（封面 + 底部控件区）各种糊/叠在一起；② 翻译朗读要预加载以避免延迟；
> ③ 底部睡眠倒计时整行都该可点（样式不动）。

## 2. 范围（Scope）

**包含：**
- 播放页布局：任何屏高下封面区与底部控件区**都不再溢出重叠**（超出可滚动）。
- `TranslationSessionController` 预合成**下一句**（当前句在播时后台合成下一句，
  走 `FishTtsService.synthesize` 的磁盘缓存，轮到时命中即播）。
- 底部睡眠倒计时整行 `InkWell` 打开同一个 `SleepTimerDialog`（视觉不变）。

**不包含：**
- 不做时间窗预取（提前 N 秒合成后续多句）—— 用户选了「预合成下一句」档。
- 不重设计睡眠倒计时样式（用户选了「样式不动」）。
- 不改迷你播放器 / 详情页 / 歌词页布局（bug 定位在播放页）。
- 不做安卓原生 pan（既有平台限制，见 `ear_channel_router.dart`）。

## 3. 验收标准（Acceptance）

- [x] 播放页在**很小的可用高度**（封面区 < 内容自然高度、底部控件超过半屏）下
      不出现 RenderFlex overflow，也不出现封面/标题压在底部控件上的重叠。
- [x] 封面区内容高于可用高度时可**纵向滚动**露出作品信息；能放下时保持垂直居中（与现状一致）。
- [x] 底部控件区（波形 + 字幕模式 + 翻译两行 + 播放键 + 睡眠倒计时）超出半屏时可滚动，不再溢出。
- [x] 当前字幕行开始朗读后，**下一句**在后台被合成（日志/断言可见），轮到它时直接命中磁盘缓存。
- [x] 睡眠倒计时整行（图标 + 文案 + 右侧按钮）任意位置点击都打开定时对话框；视觉与现在一致。
- [x] `flutter analyze` 通过，无新增 warning。
- [x] 相关单元 / Widget 测试通过。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：播放页布局防溢出
  - 涉及文件：`lib/screens/player_screen.dart`（`_buildContent` 封面分支 + body 底部块）
  - 内容：
    1. body 外层改 `LayoutBuilder`：底部控件块 `ConstrainedBox(maxHeight: 总高*0.55)` +
       `SingleChildScrollView`（放得下时尺寸即内容高度，行为不变；放不下时滚动而不是溢出）。
    2. 封面分支去掉 `Spacer()`（滚动容器内无界高度会炸），改
       `SingleChildScrollView + ConstrainedBox(minHeight: 可用高)` +
       `Column(mainAxisSize.min, mainAxisAlignment.center)`，内容自然高时仍居中。
    3. 封面边长按可用高自适应：`playerCoverSideFor(width, height, hasKicker)` 纯函数
       （`maxSide=320`、矮屏保底 120、极窄不越宽、异常宽返 0）。
    4. 标题 `maxLines:2 + ellipsis`、kicker `maxLines:1 + ellipsis`。
  - 验证：`test/screens/player_layout_test.dart` 7 例全绿；`flutter analyze` 无新增。
  - 落地注记：**`LayoutBuilder` 必须在 body Column 外层**——`RenderFlex` 给非 flex
    子项的是无界主轴约束（`flex.dart:339`），放在内层拿到的 `maxHeight` 是 `∞`。
- [x] **Step 2**：睡眠倒计时整行可点
  - 涉及文件：`lib/widgets/player/sleep_timer_footer.dart`（新，从 player_screen 抽出
    `PlayerSleepTimerFooter`）、`lib/screens/player_screen.dart`
  - 内容：整行 `InkWell`（含上下各 `space4` 命中 padding）包住图标/文案/「修改」，
    打开同一个 `SleepTimerDialog`；配色/字号/分隔线不动。
  - 验证：`test/widgets/player/sleep_timer_footer_test.dart` 4 例（点图标 / 点行内
    最左空白 / 点右侧文案 / 结构不变）。
- [x] **Step 3**：翻译朗读预合成下一句
  - 涉及文件：`translation_session_controller.dart`、`fish_tts_service.dart`
  - 内容：`_onSubtitle` 在 `_speak` 后 `unawaited(_preloadNextLine(sub))`；取
    `subtitleService.subtitleList` 的下一条非空字幕；`_preloadedIndex` 同行去重、
    `_resetSpeech` 清位、失败只 `AppLogger.debug`。顺带给 `FishTtsService` 加
    `_inflight` 同文本在途去重（预取与当前句撞同一句时共享 future，避免重复计费），
    空文本改返回 `Future.error`。
  - 验证：`test/core/audio/translation/translation_preload_test.dart` 7 例全绿
    （含字幕流接线：`_speak` + 预取同时发生）。
- [x] **Step 4**：收尾
  - `flutter analyze` = 7 issues，**全是既有基线**（4 warning + 3 info）；
    `flutter test` **441 passed**（423 + 7 布局 + 4 footer + 7 预取）。
  - `AGENTS.md` / `CLAUDE.md` 各追加三段（translation 预取 / PlayerScreen 布局不变量 /
    bug.txt 测试清单）；完成块已填。

## 5. 风险与回滚（Risks）

- **风险**：滚动化改变播放页手感（桌面高屏原本不用滚）。 **缓解**：只有「内容高于可用高」
  才滚；高屏下 `minHeight` 保证视觉与现在一致（居中、无滚动条感知）。
- **风险**：预取多打一次 TTS 请求（费用/限流）。 **缓解**：只预取**一句**、只在会话开启时、
  已在缓存时 `synthesize` 直接命中不发网络；失败只 log 不影响当前句。
- **风险**：底部限高 0.55 在极小窗口压掉封面。 **回滚**：常量收敛在一处，可调回原样
  （去掉 `ConstrainedBox` 即恢复旧行为）。

## 6. 备注 / 决策记录

- **用户 2026-09-28 四问四答**：① bug1 定位「播放页（封面 + 底部控件区）」；
  ② bug2 取「预合成下一句」档；③ bug3「整行可点，样式不动」。
- bug1 根因判断：封面是**按宽度**取正方形（360dp 屏 → 296dp 高），叠加 kicker/标题/
  作品信息后固定高度 > `Expanded` 分配到的高度 → `RenderFlex` 溢出且**不裁剪**，
  子节点画到下方控件上（＝「各种叠在一起」）。底部再高一点只会更糟
  （本次还给 `TranslationControls` 加了音量第二行）。
- 底部限高 0.55 是「封面至少拿到 45%」的下限保证，不是视觉设计。
- 封面区从「顶部对齐 + Spacer 把作品信息压到底」改为**整块居中**（滚动容器里
  没有 flex 可用）；作品信息紧跟曲名而不是贴底 —— 属于本次允许的布局调整。
- footer 抽成 `PlayerSleepTimerFooter` 是为了可测（原 `_buildSleepTimerFooter`
  是私有方法，widget 测试无法单独构造）。
- 预取只预「下一句」而不是时间窗（用户 2026-09-28 四问答：取「预合成下一句」档）。
- 顺带修的隐患：`FishTtsService.synthesize` 同文本在途去重 —— 预取与当前句撞
  同一句时共享一个 future（否则会重复 POST、重复计费）。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-29 11:05
- 执行命令：本环境（opencode）**无 `/init`** → 手工同步：`AGENTS.md` + `CLAUDE.md`
  各追加三段（translation 预取小节 / PlayerScreen 布局不变量 / bug.txt 测试清单）。
- CLAUDE.md 更新摘要：播放页布局不变量（LayoutBuilder 在 Column 外层、底部 55% 封顶、
  `playerCoverSideFor`）、`PlayerSleepTimerFooter` 整行可点、翻译预合成下一句 +
  `FishTtsService._inflight` 去重，以及 18 个新测试的清单。
- 关联 commit：<未提交，等用户指令>
- 验证：`flutter analyze` 7 issues（全为既有基线）；`flutter test` **441 passed**。

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

> 任务取消时填写此块，**不需要执行 `/init`**，将文件移入 `docs/todos/cancelled/`。

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：<例如：方案被替换为 XYZ / 优先级下调 / 上游接口取消>
- 后续指向：<如有继任任务，写明对应的 TODO 路径；否则留空>
