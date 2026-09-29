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

- [ ] 播放页在**很小的可用高度**（封面区 < 内容自然高度、底部控件超过半屏）下
      不出现 RenderFlex overflow，也不出现封面/标题压在底部控件上的重叠。
- [ ] 封面区内容高于可用高度时可**纵向滚动**露出作品信息；能放下时保持垂直居中（与现状一致）。
- [ ] 底部控件区（波形 + 字幕模式 + 翻译两行 + 播放键 + 睡眠倒计时）超出半屏时可滚动，不再溢出。
- [ ] 当前字幕行开始朗读后，**下一句**在后台被合成（日志/断言可见），轮到它时直接命中磁盘缓存。
- [ ] 睡眠倒计时整行（图标 + 文案 + 右侧按钮）任意位置点击都打开定时对话框；视觉与现在一致。
- [ ] `flutter analyze` 通过，无新增 warning。
- [ ] 相关单元 / Widget 测试通过。

## 4. 拆解步骤（Steps）

- [ ] **Step 1**：播放页布局防溢出
  - 涉及文件：`lib/screens/player_screen.dart`（`_buildContent` 封面分支 + body 底部块）
  - 内容：
    1. body 外层改 `LayoutBuilder`：底部控件块 `ConstrainedBox(maxHeight: 总高*0.55)` +
       `SingleChildScrollView`（放得下时尺寸即内容高度，行为不变；放不下时滚动而不是溢出）。
    2. 封面分支去掉 `Spacer()`（滚动容器内无界高度会炸），改
       `SingleChildScrollView + ConstrainedBox(minHeight: 可用高)` +
       `Column(mainAxisSize.min, mainAxisAlignment.center)`，内容自然高时仍居中。
    3. 封面边长按可用高自适应：`coverSide = min(宽-64, max(可用高 - 固定信息预算, 120))`，
       预算取不到就退到 120 下限，绝不为负；纯函数抽出来单测。
    4. 标题 `maxLines:2 + ellipsis`、kicker `maxLines:1 + ellipsis`（长日文标题不再把布局撑爆）。
  - 验证：`test/screens/player_layout_test.dart`（coverSideFor 纯函数边界）+
    `flutter analyze`；肉眼/手测小窗高不重叠。
- [ ] **Step 2**：睡眠倒计时整行可点
  - 涉及文件：`lib/screens/player_screen.dart` (`_buildSleepTimerFooter`)
  - 内容：把现有 `GestureDetector`（仅右侧文案）换成包住整个 `Row` 的 `InkWell`，
    padding/字号/颜色全不动。
  - 验证：`test/screens/player_sleep_footer_test.dart`（点行内左侧图标也能打开对话框）。
- [ ] **Step 3**：翻译朗读预合成下一句
  - 涉及文件：`lib/core/audio/translation/translation_session_controller.dart`
  - 内容：`_speak` 起播当前句后（epoch 门控），取 `_subtitleService.subtitleList`
    中**下一条非空**字幕 → `unawaited(_tts.synthesize(text))`（只预热磁盘缓存，
    结果丢弃）；`_preloadedIndex` 防重复；`!enabled` 不预取；换曲/seek 用 epoch 作废。
  - 验证：`test/core/audio/translation/translation_preload_test.dart`
    （假 tts 记录调用：起播后收到「下一句」、不预取空行、切换后作废）。
- [ ] **Step 4**：收尾
  - `flutter analyze` 无新增；`flutter test` 全绿；同步 `AGENTS.md` / `CLAUDE.md`
    （player_screen 布局不变量 + 翻译预取一段）；完成块 + 移入 `done/`。

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

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：YYYY-MM-DD HH:mm
- 执行命令：`/init`
- CLAUDE.md 更新摘要：<一两句话说明 CLAUDE.md 的变化>
- 关联 commit：<commit hash>

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

> 任务取消时填写此块，**不需要执行 `/init`**，将文件移入 `docs/todos/cancelled/`。

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：<例如：方案被替换为 XYZ / 优先级下调 / 上游接口取消>
- 后续指向：<如有继任任务，写明对应的 TODO 路径；否则留空>
