# 智能左右耳（实验）：按音频内容实时路由翻译耳 + 提前分析

- **创建时间**：2026-09-28
- **负责人**：zouxin
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：（用户 2026-09-28 口述需求，接 `20260924-translation-ear-channel-isolation.md`）

---

## 1. 目标（Goal）

> 现在的分耳是**整首固定一侧**（`mainEar`），对「声音在左右耳之间来回切换」的
> 双耳 ASMR 无效。新增**智能耳（实验）模式**：提前分析本地音频，得到随时间变化的
> 「当前内容在哪只耳」，逐句把翻译路由到**内容的对侧耳**；判定为左右等响的段落
> 则**一句左一句右轮播**。主轨保持原始立体声不动（用户决策），只路由翻译。

## 2. 范围（Scope）

**包含：**
- `SmartEarAnalyzer`：本地 wav/mp3 的**逐窗左右 RMS 分析** → `EarTimeline`
  （wav 1s 窗随机读；mp3 扫帧头定位 + 抽样窗解码），结果按
  `path|size|mtime` 落盘缓存（`ear_analysis/<hash>.json`），isolate 解码不卡 UI。
- 判定：`|L-R|/max(L,R) > 5%` → 内容耳；`≤5%` 或近静音 → **等响**（null）。
- `translationSmartEar` 配置（pref `translation_smart_ear`，**默认 false**，UI 标「实验」）。
- 逐句路由纯函数 `SmartEarRouter.resolve(...)`：
  内容耳 → 对侧；等响 → `lineIndex` 奇偶轮播（偶数句左 / 奇数句右）；
  分析未就绪 → 回退 `mainEar` 对侧（既有行为的耳侧结论）。
- `EarChannelRouter.apply` 扩成 `apply({mainEar, ttsEar})`：
  **智能模式下主轨不 pan（null）**，翻译轨单独指定耳。
- 播放页 `TranslationControls`：「智能(实验)」开关 + 状态（分析中/已就绪/不支持/失败）。

**不包含：**
- 不做实时/播放中重分析（只做开播前 + 缓存命中）。
- 不做 Android/iOS 的分耳（原生 just_audio 无 pan，沿用既有 no-op 降级）。
- 不做 flac/ogg 等其它容器（无解码器 → 状态「不支持」，回退固定耳）。
- 不改 `EarSideDetector`（文件级左右耳检测，仍是固定模式的取数口）。
- 不引入服务端分析、不写数据库（纯文件缓存）。

## 3. 验收标准（Acceptance）

- [x] 合成「左 30s → 右 30s → 等响 30s」的立体声 wav，分析结果逐窗判定正确
      （等响窗 `side == null`），同一文件二次调用命中磁盘缓存。
- [x] 合成左右不等响的立体声 mp3（`mp3EncodeStereo`），能扫出帧并得到正确时长/分窗判定。
- [x] 智能模式开启且分析就绪：主轨 `af` 不再 pan（main 清空），翻译轨按内容对侧耳
      /等响轮播逐句切换（纯函数断言）。
- [x] 智能模式开启但分析未就绪/不支持：翻译耳 = `mainEar` 对侧（与现在一致），不崩。
- [x] 智能模式关闭：行为与当前完全一致（主 pan mainEar、TTS 对侧）。
- [x] UI：开关文案带「实验」，状态三态可见（分析中 / 已就绪 / 不支持）。
- [x] `flutter analyze` 通过，无新增 warning。
- [x] 相关单元 / Widget 测试通过。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：时间线模型 + WAV 分析
  - 涉及文件：新建 `lib/core/audio/translation/smart_ear_analyzer.dart`
  - 内容：`EarWindow{startMs, EarSide? side}` / `EarTimeline{windowMs, durationMs, sides}`
    + `sideAt(int ms)`；`SmartEarAnalyzer.analyzeWav(path)` 用 `WavHeader` +
    每窗随机读（1s 窗、抽样 ≤4096 帧，只求**分声道**平方和）→ 5% 阈值分类。
  - 验证：`test/core/audio/translation/smart_ear_analyzer_test.dart`
    合成左/右/等响三段 wav，断言逐窗结果 + `sideAt` 边界。
- [x] **Step 2**：MP3 分析 + 磁盘缓存
  - 涉及文件：同上（+ 把 `LoudnessMeter._id3v2End` 提为 public 复用）
  - 内容：两遍法 —— ① 顺序扫帧头（`mp3FrameSize`/`kMp3SampleRates`，MPEG-1 L3）
    累加时长、记下每个 5s 窗的字节偏移；② 按偏移读 12KB 抽样片 →
    `Isolate.run(mp3Decode)` 分批解码（≤32 片/批）算分声道 RMS。
    缓存：`getApplicationSupportDirectory()/ear_analysis/<sha1(path|size|mtime)>.json`
    （`{v,windowMs,durationMs,sides:'LR.EE…'}`，损坏即重算）。
  - 验证：单测用 `mp3EncodeStereo` 合成左右不等响 mp3 → 分窗判定正确；
    同 key 二次调用命中磁盘缓存（不重扫）。
- [x] **Step 3**：路由纯函数 + 配置 + 声道路由扩展
  - 涉及文件：新建 `lib/core/audio/translation/smart_ear_router.dart`、
    `fish_tts_config.dart`、`ear_channel_router.dart`
  - 内容：`SmartEarRouter.resolve({smart, mainEar, timeline, positionMs, lineIndex})`
    （纯函数，见范围）；`translationSmartEar` getter/setter（仅变更 notify）；
    `EarChannelRouter.apply({EarSide? mainEar, EarSide? ttsEar})`
    （`ttsEar` 缺省 = `mainEar?.flipped`；两者都 null = 清 af；
    现有调用点改成具名参数）。
  - 验证：`translation_smart_ear_config_test` + `ear_channel_router_test`
    增补 apply 具名参数语义（纯 `filterFor` 断言不变）。
- [x] **Step 4**：会话控制器接线
  - 涉及文件：`translation_session_controller.dart`
  - 内容：
    - 状态机：`SmartEarStatus{idle, analyzing, ready, unsupported, failed}` +
      `smartStatus`/`smartEar` getter；智能开 + 曲目已知 → 后台 `analyze()`，
      完成后 `_applyVolumes()`（重推耳路由）；换曲/关掉开关 → 作废在途分析（序号守卫）。
    - `_onSubtitle` → `_speak(Subtitle)`，起播前按 `SmartEarRouter.resolve`
      算本句耳侧并 `_applyEarRouting(ttsEar: ...)`；智能开时 main 恒 null。
    - 智能关时行为与现在完全一致。
  - 验证：`translation_session_controller_volume_test` 不回归 +
    新增「智能开 → 主轨清 pan / 分析就绪前用 mainEar 对侧」用例（`debugApplyRms` 同款测试钩子）。
- [x] **Step 5**：UI + 文案
  - 涉及文件：`translation_controls.dart`、`strings.dart`
  - 内容：音量行旁边加「智能(实验)」开关（tooltip 说明实验性质与限制）；
    状态文本（分析中… / 已就绪 / 该格式不支持 / 分析失败）；空闲时不占位或显示「关」。
  - 验证：`translation_controls_volume_test` 增补开关渲染/点击用例；`flutter analyze`。
- [x] **Step 6**：收尾
  - `flutter analyze` 无新增；`flutter test` 全绿；同步 `AGENTS.md`/`CLAUDE.md`
    （`audio/translation/` 智能耳小节 + Tests）；完成块 + 移入 `done/`。

## 5. 风险与回滚（Risks）

- **风险**：大 mp3 扫描 + 抽样解码耗时（60 分钟文件估计十几秒～几十秒，后台）。
  **缓解**：磁盘缓存（同文件只算一次）+ 分批 isolate + 状态可见；未就绪时按固定耳播。
- **风险**：mp3 是 VBR 时「帧头 → 时间」映射误差（我们的帧扫描是逐帧累加，
  时间轴准确；抽样片只是采样点，不影响时间轴）。
- **风险**：等响阈值 5% 对某些「近似单耳」素材误判成等响 → 频繁轮播。
  **缓解**：阈值收敛成常量 + 单测锁定；不行再调（改一个常量）。
- **风险**：改 `EarChannelRouter.apply` 签名影响固定模式。
  **回滚**：具名参数保持缺省语义等价，revert 即回原状；配置默认 false，开关即回原行为。
- **风险**：Android/iOS 上智能模式无声变化（本就没有分耳）。
  **缓解**：状态文本照常显示，tooltip 注明「需 Windows/Linux 分耳支持」。

## 6. 备注 / 决策记录

- **用户 2026-09-28 决策**：① 标「实验功能」、翻译里可开；② 支持「提前对音频进行分析」；
  ③ 双耳等响段 → **一句左一句右**轮播；④ **主轨不动，只路由翻译**（不跟随 pan）。
- 分析只对**本地文件**做（在线流拿不到字节）→ 与翻译音量对齐同一套
  `resolveLocalPath` 回调；拿不到路径 = 状态「不支持」。
- 等响（含近静音）记 `side == null`：查询时与「未知」同义，都走轮播 —— 简化模型，
  因为两者对用户的表现都是「左右轮流」。
- 轮播用 `lineIndex` 奇偶（偶数句左），不依赖计时器：seek 后仍然稳定、可复现。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-29 11:45
- 执行命令：**opencode 环境无 `/init`** → 手工同步 `AGENTS.md` + `CLAUDE.md`（两文件各追加
  `audio/translation/` 智能耳小节 + Tests 段的新测试文件名），并在下方注明。
- CLAUDE.md 更新摘要：`audio/translation/` bullet 追加「智能耳（实验）」——
  `SmartEarAnalyzer`（wav 1s 窗分块读 / mp3 两遍法 + `Isolate.run` 批解码、
  `sha1(path|size|mtime)` 磁盘缓存 + 进程内 LRU + 在途去重）、`SmartEarRouter.resolve`
  （内容对侧 / 等响按 `lineIndex` 奇偶轮播 / 无时间线回落 `mainEar` 对侧）、
  `translationSmartEar`（pref `translation_smart_ear`，默认 false）、
  `EarChannelRouter.apply({mainEar, ttsEar})` 具名参数（智能就绪时 main 恒 null = 主轨不 pan）、
  控制器 `_syncSmartEar`/`_computeTtsEar`/`_speak(start:)`、`TranslationControls` 智能行；
  Tests 段追加 `smart_ear_analyzer_test` / `smart_ear_router_test` /
  `fish_smart_ear_config_test` / `translation_session_controller_smart_ear_test` /
  `translation_controls_smart_ear_test`。
- 验证：`flutter analyze` = **7 issues（全部既有基线，无新增）**；
  `flutter test` = **470 passed**（441 → 470，新增 29 例）。
- 关联 commit：未提交（用户未要求提交）。

### 与计划的偏差

- `EarWindow` 未单列类型：`EarTimeline.sides` 直接是 `List<EarSide?>`（等价且更省）。
- WAV 每窗抽样 **1024 帧**（计划写 ≤4096，实测 1024 足够定方向，读取更省）；
  每次 IO 合并 **8 个窗**（`wavWindowsPerRead`）。
- mp3 解码分批 **24 片/批**（计划 ≤32）；帧扫描返回 `({durationMs, offsets})`，
  测试钩子 `debugScanMp3`。
- `WavHeader` 新增 `sampleRate` 字段（WAV 分窗需要）；`LoudnessMeter._id3v2End`
  → 公开 `id3v2End`（mp3 扫描跳 ID3v2 复用）。
- 路由入参命名 `fallbackEar`（计划写 `mainEar`），语义一致 = 固定模式的主耳。

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

> 任务取消时填写此块，**不需要执行 `/init`**，将文件移入 `docs/todos/cancelled/`。

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：<例如：方案被替换为 XYZ / 优先级下调 / 上游接口取消>
- 后续指向：<如有继任任务，写明对应的 TODO 路径；否则留空>
