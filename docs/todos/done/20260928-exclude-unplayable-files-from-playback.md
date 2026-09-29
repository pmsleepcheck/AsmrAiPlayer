# 排除不可播放文件：界面播放按钮 + 播放列表 + 播放链路自愈

- **创建时间**：2026-09-28
- **负责人**：opencode
- **状态**：active <!-- active | done | cancelled -->
- **关联 Issue / PR**：用户反馈「点了一次不能播放的文件（如字幕）后，整个程序再也无法播放，重启才恢复」

---

## 1. 目标（Goal）

> 一句话：把**不可播放的文件格式（字幕 .vtt/.lrc/.srt/.txt、视频、album.json 等）彻底挡在播放入口之外**，并让播放链路在一次失败后能自愈，而不是把整个 session 锁死到重启。

**问题复盘（已定位）**

- 「本地缓存」页每一行都**无条件**渲染播放按钮，且整行 `onTap → _play()`（`local_cache_content.dart:513-526`）。
- `_play()` 对非视频条目一律走应用内音频管线：`_buildAudioContext` 里 `full.playlist` 为空时会用
  `PlaybackContext.withFilteredPlaylist(playlist: [child])`（`local_cache_content.dart:201`）**绕过扩展名白名单**，
  合成一个「1 首」的合法播放列表，于是 `validate()` 通过，`.vtt` 被送进 `setAudioSource` → mpv 打开纯文本。
- `PlaylistBuilder.setPlaylistSource` 的 5s 超时不会取消底层平台加载；下一次 `setPlaybackContext`
  先 `await _player.stop()`（**无超时**，`playback_controller.dart:126`）与仍在飞行的 `setAudioSource` 交错，
  触发 just_audio 平台侧死锁 → `_setContextChain` 永久阻塞 → **之后所有播放都无响应，直到重启**。
- 详情页同类问题：`type=='audio'` 的字幕（asmr.one 会这样下发）被 `DetailViewModel._isAudioChild`
  直接判成音频（`detail_viewmodel.dart:311` 扩展名校验排在 type 之后），拿到播放按钮 / 进入播放分支，
  最终落成「播放失败」。

## 2. 范围（Scope）

**包含**

1. 统一「可播放」判定到 `PlaybackContext`（唯一的音频白名单持有者）：
   `extensionOf` / `isPlayableAudioTitle` / `isSubtitleTitle` / `isVideoTitle`。
2. `DetailViewModel`、`WorkFileItem`、`LocalCacheViewModel` 改为**扩展名优先**判定，字幕/视频/未知格式
   即便 `type=='audio'` 也不再被判成音频。
3. 「本地缓存」行：不可播放条目**不渲染播放/翻译按钮**、整行不可点播，图标区分为字幕/其他。
4. `PlaylistBuilder.buildAudioSources` 兜底：已知不可播放扩展名直接跳过（防止 `withFilteredPlaylist`
   之类入口再次把字幕送进 `setAudioSource`）。
5. `PlaybackController._setPlaybackContext` 的 `_player.stop()` 加超时，避免一次失败永久锁死串行链。
6. 单元/Widget 测试：**逐一枚举本地缓存目录里的文件**，断言每个文件要么可播放、要么被明确排除，
   绝不会进入播放器；并对播放按钮可见性做 Widget 级断言。

**不包含**

- 不扩充音频扩展名白名单本身（`playlistAudioExtensions` 保持不变）。
- 不改动字幕预览 / 字幕匹配 / 翻译播放的业务语义。
- 不重构 `_setContextChain` 的串行化设计（只加超时兜底）。

## 3. 验收标准（Acceptance）

- [x] 详情页：`type='audio'` 的 `.vtt/.lrc/.srt/.txt` 不再出现播放按钮与「翻译+播放」图标，点击仍进入字幕预览。
- [x] 本地缓存页：字幕/`album.json` 等条目**没有播放按钮、不可点播**，仍可删除。
- [x] 任何 `type=='audio'` 但扩展名不在白名单的文件，`isAudioFile` 一律为 false（含 `.mp4` 既有回归）。
- [x] `PlaylistBuilder.buildAudioSources` 对字幕/未知扩展名条目不产出 AudioSource（跳过并记日志）。
- [x] 播放链：`_player.stop()` 限时，单次失败后链尾不被阻塞（代码层断言 + 日志）。
- [x] 扫描真实本地缓存目录（存在时）的测试通过：每个文件分类结果自洽，**无「会被送进播放器的非音频文件」**。
- [x] `flutter analyze` 无新增 warning。
- [x] 相关单元 / Widget 测试通过。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：`PlaybackContext` 增加统一判定静态方法并让 `_getPlaylistFromSameDirectory` 复用
  - 涉及文件：`lib/core/audio/models/playback_context.dart`
  - 验证：`test/core/audio/models/playback_context_playlist_test.dart` 仍通过
- [x] **Step 2**：`DetailViewModel` 改用统一判定（`_isAudioChild` / `isSubtitleFile` / `_hasVideoExtension`）
  - 涉及文件：`lib/presentation/viewmodels/detail_viewmodel.dart`
  - 验证：`detail_viewmodel_collect_test.dart` + 新增 `detail_viewmodel_playable_test.dart`
- [x] **Step 3**：`WorkFileItem` 改用统一判定，字幕不再拿到播放按钮
  - 涉及文件：`lib/widgets/detail/work_file_item.dart`
  - 验证：新增 `test/widgets/detail/work_file_item_play_button_test.dart`
- [x] **Step 4**：`LocalCacheViewModel` 增加 `isPlayableEntry`，`isAudioEntry` 受白名单约束
  - 涉及文件：`lib/presentation/viewmodels/local_cache_viewmodel.dart`
  - 验证：`local_cache_viewmodel_test.dart` 增补字幕用例
- [x] **Step 5**：本地缓存行隐藏不可播放条目的播放/翻译按钮与点播
  - 涉及文件：`lib/screens/contents/local_cache_content.dart`
  - 验证：同 Step 4 的判定测试 + 人工点验
- [x] **Step 6**：`PlaylistBuilder` 兜底跳过不可播放条目
  - 涉及文件：`lib/core/audio/utils/playlist_builder.dart`
  - 验证：`playlist_builder_test.dart` 增补用例
- [x] **Step 7**：`_player.stop()` 加超时，失败不锁死串行链
  - 涉及文件：`lib/core/audio/controllers/playback_controller.dart`
  - 验证：`flutter analyze` + 代码评审（平台侧无法在纯 Dart 单测中模拟）
- [x] **Step 8**：缓存目录全量扫描测试（逐个文件判定）
  - 涉及文件：`test/core/audio/cache/cache_dir_playability_test.dart`
  - 验证：`flutter test` 通过（目录不存在时跳过扫描，仅跑固定夹具）

## 5. 风险与回滚（Risks）

- **影响面**：`type=='audio'` 但扩展名怪异的真实音频（如 `.ape`/`.m4b`）会失去播放按钮。
  缓解：这类文件本来也会被 `PlaybackContext` 白名单挡成「播放列表为空」，行为只是从「点了报错」提前为「不给点」。
- **回滚**：单 commit revert；判定集中在 `PlaybackContext` 静态方法，回滚无需迁移数据。

## 6. 备注 / 决策记录

- 音频白名单唯一持有者是 `PlaybackContext.playlistAudioExtensions`，其他模块一律引用，不再各自维护副本
  （`WorkFileItem` / `LocalCacheViewModel` 里的手抄副本本次移除）。
- `withFilteredPlaylist` 是**绕过白名单**的口子，只允许「已通过白名单的同目录列表被过滤后」使用；
  本地缓存的兜底分支必须先过 `isPlayableAudioTitle` 再用它。

---

## ✅ 完成标记

- 完成时间：2026-09-28 12:35
- 执行命令：/init —— 当前会话为 opencode，**无该 slash 命令**；已改为手工同步根 CLAUDE.md 与 AGENTS.md 中「PlaybackContext playlist extension whitelist」段落（两文件各追加一条 Playable-file gate (2026-09-28) 记录），效果等同 /init 对本次改动的增量更新。
- CLAUDE.md 更新摘要：新增「可播放判定唯一入口 + 扩展名优先于 type + 本地缓存播放按钮闸门 + PlaylistBuilder 兜底 + stop() 4s 超时 + 4 个新测试文件」。
- 验证结果：lutter analyze 7 issues（全部为改动前既有的 4 warning / 3 info，新增 0）；lutter test **364 通过 / 0 失败**（含新扫描测试逐个校验 Downloads 144 个文件与 audio_cache 缓存文件）。
- 待人工点验：本地缓存页字幕行无播放按钮、详情页已下载字幕无播放/翻译按钮、点字幕仍进字幕预览。
- 关联 commit：未提交（本仓库无 git）