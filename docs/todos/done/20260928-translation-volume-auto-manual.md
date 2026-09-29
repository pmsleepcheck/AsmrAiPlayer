# 翻译音量自动对齐 + 手动调节（避免翻译轨与主轨音量差距过大）

- **创建时间**：2026-09-28
- **负责人**：zouxin
- **状态**：active <!-- active | done | cancelled -->
- **关联 Issue / PR**：（无）

---

## 1. 目标（Goal）

> 翻译 TTS 轨与主音轨的响度差距过大（ASMR 主轨很轻、TTS 归一化后很响），
> 现在是写死的「主 1.0 / 翻译 0.7」emphasis，无法适配具体作品。
> 增加**自动响度对齐**（实测两轨 RMS 后把响的一侧压下来）与**手动调节**
> （播放页滑杆，值按作品记进该作品文件夹的 `album.json`）。

## 2. 范围（Scope）

**包含：**
- 新增纯 Dart 响度测量（WAV 分窗随机读 + MP3 抽样解码，后台 isolate，按文件缓存）。
- 新增策略纯函数：`auto + 双方可测` → 对齐到较小响度；否则回退现有 emphasis。
- `FishTtsConfigStore.translationAutoVolume`（pref `translation_auto_volume`，**默认 true**）。
- 手动音量写入作品文件夹 `album.json`（sidecar 键 `translationVolume`，merge-on-write），
  全局 `translation_secondary_volume` 仅作兜底。
- 播放页 `TranslationControls` 音量面板（自动开关 + 手动滑杆），改动**立即生效**。
- 新增 pub 依赖 `glint_audio_pure: ^0.6.2`（MIT、纯 Dart mp3 编解码）。

**不包含：**
- 不改 TTS 输出格式（保持 `format:'mp3'`，不引入 wav 缓存翻倍；见决策记录）。
- 不动设置 → AI 翻译里的旧滑杆入口（只顺带变成保存即生效）。
- 不做闪避（ducking）、不做服务端 `prosody.normalize_loudness`。
- 不做 FLAC/在线流主轨的响度实测（无解码器 → 走回退比例）。
- Freezed 模型无改动 → 无需 build_runner。

## 3. 验收标准（Acceptance）

- [x] 自动开关默认开启；关闭后翻译轨音量 = 手动滑杆值（与今日行为一致）。
      —— `fish_auto_volume_config_test`（默认 true）+ `translation_session_controller_volume_test`
      「自动关 → 回退 emphasis，滑杆重新可用」。
- [x] 自动开启且主轨为本地 wav/mp3 时，日志/断言可见两轨被压到同一响度（响的一侧 volume < 1）。
      —— `debugApplyRms(main:0.4, tts:0.1)` → `IAudioPlayerService.setVolume == 0.25`；
      真实测量路径由 `loudness_meter_test`（合成+真实文件 spike）覆盖，
      运行时日志 `主轨响度: …`（`AppLogger.debug`）。
- [x] 自动开启但主轨不可测（在线流）→ 回退到手动值比例，不崩、不静音。
      —— policy `usable()` 分支单测 + controller「切曲后…TTS 未测到前仍回退 emphasis（main=1.0）」。
- [x] 播放页滑杆拖动时**当帧生效**（无需重开会话）；值写进当前作品 `<作品目录>/album.json`
      的 `translationVolume`，且再次 `AlbumMetadataWriter.write()` **不丢该键**。
      —— `album_metadata_test` 4 例；controller「手动音量：写全局配置 + 记到当前作品 + 立即生效」；
      widget test「拖滑杆 → 手动音量变化」。
- [x] 换曲/换作品时自动读回该作品已记的音量。 —— controller「换作品：album.json 记录优先于全局；无记录回退全局」。
- [x] `flutter analyze` 通过，无新增 warning。 —— 仅剩 4 个基线 warning + 3 个既有 info（0 新增）。
- [x] 相关单元测试通过（策略、响度测量、album.json 保留、配置默认值）。 —— `flutter test` **423 passed**。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：响度测量器 + 依赖
  - 涉及文件：`pubspec.yaml`；新建 `lib/core/audio/translation/loudness_meter.dart`；
    既有 `lib/core/audio/translation/wav_stereo_rms.dart`（抽取共用 WAV 头解析，`analyze` 行为不变）
  - 内容：`LoudnessMeter.wavRms(RandomAccessFile)`（fmt 头解析后按 10%/50%/90% 三窗随机读，
    mono/stereo/N 声道、PCM16/float32，抽样 ≤200k 帧）；`LoudnessMeter.mp3Rms(bytes)`（帧同步
    后 `mp3Decode` 整段/窗口）；`LoudnessMeter.fileRms(path)` 按扩展名分派；`LoudnessCache`
    （`path|size|mtime` → rms，LRU ≤64）；mp3 解码走 `Isolate.run`。
  - 验证：`test/core/audio/translation/loudness_meter_test.dart` —— 合成 WAV 与
    `mp3EncodeMono` 正弦 fixture 的 RMS 落在期望区间；窗口抽样与整段解码差 < 10%。
- [x] **Step 1b**：真实文件 spike
  - 结果：`C:\Users\zouxin\Documents\downloads` 35 个 wav 中 **28 个 24-bit**（13 个 fmt 前有 JUNK）→ 必须支持 24-bit（已支持）；
    wav 8–36ms（rms 0.0133–0.1002）、mp3 0.7–1.0s（rms 0.0178–0.1002），同作品 wav/mp3 量级吻合（0.0595 vs 0.0478）→ 通过，未触发失败处置。
    （临时 spike 测试 `test/spike_real_loudness_test.dart` 实跑后已删除。）
  - 验证：用 `C:\Users\zouxin\Documents\downloads` 下真实 mp3/wav 打印 RMS，
    量级应同处 0.01~0.5 区间且同作品 mp3/wav 接近；解码耗时（isolate）< 1s/文件。
  - 失败处置：退回「mp3 主轨不实测，仅测 TTS + 回退比例」，其余步骤不变。
- [x] **Step 2**：策略纯函数
  - 涉及文件：新建 `lib/core/audio/translation/translation_volume_policy.dart`
  - 内容：`compute({state, autoVolume, mainRms, ttsRms}) → VolumePlan(main, tts, aligned)`
    —— auto && 双方 >1e-4 时 `mainVol=clamp(ttsRms/mainRms, 0.1, 1)`、
    `ttsVol=clamp(mainRms/ttsRms, 0.1, 1)`；否则复用 `state.mainVolume/state.translationVolume`。
  - 验证：`test/core/audio/translation/translation_volume_policy_test.dart`（对齐双向/回退/关闭/下限）。
- [x] **Step 3**：配置项
  - 涉及文件：`lib/core/audio/translation/fish_tts_config.dart`
  - 内容：`translationAutoVolume` getter/setter（pref `translation_auto_volume`，默认 `true`，
    仅变更时 `notifyListeners`）。
  - 验证：`test/core/audio/translation/fish_auto_volume_config_test.dart`（默认值/persist/notify）。
- [x] **Step 4**：作品文件夹 json
  - 涉及文件：`lib/core/download/album_metadata_writer.dart`、`lib/core/download/download_service.dart`
  - 内容：`translationVolumeKey = 'translationVolume'`、`readTranslationVolume(workDir)`、
    `recordTranslationVolume(workDir, v)`；`write()` **保留**该键（与 subtitleMatches/fileKeys 同法）；
    `DownloadService.readTranslationVolume(workId)` / `recordTranslationVolume(workId, v)` best-effort。
  - 验证：`test/core/download/album_metadata_test.dart` 增补（round-trip + write 不丢键 + 损坏容错）。
- [x] **Step 5**：会话控制器接线
  - 涉及文件：`lib/core/audio/translation/translation_session_controller.dart`、
    `lib/core/di/service_locator.dart`
  - 内容：
    - DI 注入可选 `resolveLocalPath(workId, file)`（接 `DownloadService.localPathIfDownloaded`，单测可空）。
    - 订阅 `contextChange`/`trackChange` → 更新当前 workId、异步读作品音量、
      （仅 `enabled && autoVolume` 时）测主轨 RMS；epoch/序号守卫避免串台。
    - 订阅 `FishTtsConfigStore`（ChangeNotifier）→ 音量/开关变化立即 `_applyVolumes()`。
    - `_speak` 写完临时 mp3 后测该段 RMS → `_applyVolumes()` → 再 play。
    - `_applyVolumes` 改走 `TranslationVolumePolicy.compute`；公开
      `autoVolume` / `manualVolume` / `setAutoVolume(bool)` / `setManualVolume(double)`
      （后者写 config + 作品 album.json，best-effort）。
  - 验证：`flutter analyze` + 既有翻译测试不回归；新增策略应用的行为用 Step 2 单测覆盖。
- [x] **Step 6**：UI
  - 实现与原计划的两处出入（见 §6 决策记录）：面板做成**常显第二行**（非 volume_up 弹层）；
    滑杆**仅在对齐真正生效时**置灰（自动开但任一轨不可测时仍可拖）。
  - 涉及文件：`lib/widgets/player/translation_controls.dart`、`lib/common/constants/strings.dart`
  - 内容：`TranslationControls` 加 `volume_up` IconButton → 面板（`自动音量` Switch +
    `手动音量` Slider + 百分比；auto 开启时滑杆禁用并提示「回退比例」）；
    onChangeEnd 提交（拖动过程中实时 apply）。
  - 验证：`flutter analyze`；手测（见验收 1~4）。
- [x] **Step 7**：收尾
  - `flutter analyze` 7 issues（4 warning + 3 info，全为既有基线，0 新增）；`flutter test` **423 passed**；
    已同步 `AGENTS.md` / `CLAUDE.md`（`audio/translation/` 段 + `download/` album.json 段 + Tests 段）。
  - `flutter analyze` 无新增；`flutter test` 全绿；同步 `AGENTS.md` / `CLAUDE.md`
    （`audio/translation/` 段 + Tests 段）；必要时补 `docs/audio_architecture.md`。
  - 验证：完成块 + 移入 `docs/todos/done/`。

## 5. 风险与回滚（Risks）

- **风险**：`glint_audio_pure` 版本新、下载量小，mp3 解码正确性/性能未知。
  **回滚**：Step 1b spike 不过 → 关闭「mp3 主轨实测」，保留 wav 实测 + 回退比例；
  最坏情况移除依赖（Step 1 单独可 revert），策略/配置/UI 不受影响。
- **风险**：纯 Dart 解码卡顿主线程。 **缓解**：mp3 解码一律 `Isolate.run`，
  主轨只读 3 个 512KB 窗口，结果按 `path|size|mtime` 缓存。
- **风险**：音量被压得过小听不清。 **缓解**：对齐下限 0.1；自动关即回到手动值。
- **风险**：改动集中在 `TranslationSessionController`（现有翻译功能的中枢）。
  **回滚**：全部新逻辑经 `translationAutoVolume` 开关与 `_applyVolumes` 单点进入，
  关掉开关 = 回到现状 emphasis 行为。

## 6. 备注 / 决策记录

- **用户决策（2026-09-28 四问四答）**：① 自动=实测响度对齐（并要求「mp3 也想想办法」）；
  ② 手动滑杆**仅播放页**；③ 默认开启自动音量开关，手动调节后**记录到作品文件夹 album.json**；
  ④ mp3 解码用**纯 Dart 包**。
- **与用户选项的唯一偏离**：TTS 侧**不**改成 wav 输出，仍用 mp3 —— 因为纯 Dart 解码器
  反正要装（主轨 mp3 必须它），TTS 同样可整段测 RMS；改 wav 还要动缓存键、磁盘占用 ×5。
  如用户否决可改为 wav（Fish `format:'wav'` 已确认支持，注意其 WAV 头是占位值，
  `data` chunk size 读到 4294967040，解析必须 `min(chunkSize, 剩余字节)` —— 现有
  `WavStereoRms` 已如此处理）。
- 主轨**在线流**不可测（无本地字节）→ 回退手动比例，这是设计内的降级，不是缺陷。
- `TranslationMixState` 保持不动（现有测试锁定）；对齐逻辑全在新策略文件里。
- swap（切换主次方向）在自动对齐下不再改变音量差（只翻耳侧），手动模式下语义不变。

**实现期补充（2026-09-28，均在验收口径内）：**
- **UI 形态**：`TranslationControls` 不做 `volume_up` 弹层，而是常显第二行
  （自动音量 Switch + 滑杆 + 百分比）——播放页控件本就只有两行，弹层多一次点击。
- **滑杆何时可拖**：不是「auto 开就禁用」，而是 `manualVolumeEffective`
  （自动关 / 会话关 / 任一轨不可测 → 可拖；两轨已对齐 → 置灰 + `translationVolumeAlignedHint`）。
  原因：对齐生效时手动值确实不参与音量，**拖了不会变**才是真陷阱；而在线流主轨下
  auto 开着却测不到，若一并禁用会让用户无从调节。
- **手动音量优先级**：作品 `album.json` > 全局 `translation_secondary_volume`。
  播放页滑杆同时写两者（作品级保证换回该作品仍是这个值）；设置页旧滑杆只写全局，
  当前作品已有记录时以作品记录为准（作品是「这一部怎么响」的记忆）。
- **测量不挡出声**：`_speak` 先按回退音量起播，再异步测该段 mp3 并补一次 `setVolume`；
  主轨在 `trackChange`/`contextChange` 异步测（`_measureSeq` 换曲作废）。
  由此**对齐生效前后音量会变一次**（首句 TTS 测完），属预期。
- **测试钩子**：`@visibleForTesting TranslationSessionController.debugApplyRms(main:, tts:)`
  —— 合成 TTS 需要网络/第二 AudioPlayer（测试环境不可用），用它直接喂响度断言
  「policy → `IAudioPlayerService.setVolume`」全链路（0.4/0.1 → 0.25）。
- 顺手修：`FishTtsConfigStore.setSecondaryVolume` 改为**值变化即 notifyListeners**
  （原来只有落盘不通知，设置页改音量要等保存才生效）。
- 依赖：新增 `glint_audio_pure: ^0.6.2`（MIT，纯 Dart mp3）；`wav_stereo_rms.dart` 改为
  共用 `LoudnessMeter` 的 `WavHeader.parse`/`readSample`（顺带让耳检测支持 24-bit WAV）。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-28 17:10
- 执行命令：手工同步（本环境 opencode 无 `/init` 命令）—— 已手动在 `AGENTS.md` 与
  `CLAUDE.md` 各追加三段：`audio/translation/` 音量对齐/手动音量不变量、
  `download/` 的 album.json `translationVolume` sidecar 键、Tests 段新增测试清单。
- CLAUDE.md 更新摘要：翻译轨音量「自动响度对齐 + 按作品记住的手动音量」的策略/测量/
  优先级/滑杆置灰规则，与对应单测清单。
- AGENTS.md 更新摘要：同上（AGENTS.md 与 CLAUDE.md 各自维护，内容一致）。
- 关联 commit：未提交（本次会话未做 git 提交；`flutter analyze` 0 新增、`flutter test` 423 passed）
- 新增/改动文件：
  - 新建 `lib/core/audio/translation/loudness_meter.dart`、`translation_volume_policy.dart`、
    `test/core/audio/translation/{loudness_meter,translation_volume_policy,fish_auto_volume_config,translation_session_controller_volume}_test.dart`、
    `test/widgets/player/translation_controls_volume_test.dart`
  - 改 `pubspec.yaml`（+`glint_audio_pure`）、`fish_tts_config.dart`、`wav_stereo_rms.dart`、
    `translation_session_controller.dart`、`service_locator.dart`、`album_metadata_writer.dart`、
    `download_service.dart`、`translation_controls.dart`、`strings.dart`、`album_metadata_test.dart`

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

> 任务取消时填写此块，**不需要执行 `/init`**，将文件移入 `docs/todos/cancelled/`。

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：<例如：方案被替换为 XYZ / 优先级下调 / 上游接口取消>
- 后续指向：<如有继任任务，写明对应的 TODO 路径；否则留空>
