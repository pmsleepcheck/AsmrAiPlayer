# 字幕智能匹配：文件名优先级链 + 专辑内手工选择 + 结果记入 album.json

- **创建时间**：2026-09-24
- **负责人**：zouxin
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：（留空）

---

## 1. 目标（Goal）

> 播放时按「文件名全匹配 → 规范化全名 → 去字符模糊 → 已记录匹配(含手工选择) → 导入」自动找到字幕；自动/手工结果写入专辑 `album.json`；自动匹配失败时可在详情页/播放页从专辑文件夹内手工指定。

## 2. 范围（Scope）

**包含：**
- `SubtitleMatcher` 升级为优先级链（同目录优先 → 全作品树兜底）：
  1. 全文件名精确匹配（现有 Tier1，保留）
  2. 规范化全名匹配（小写、去扩展名、空白折叠、常见括号/书名号/连字符归一后全名相等）
  3. 去字符模糊匹配（仅保留字母/数字/CJK 后全名相等；否则 Levenshtein ≥ 0.6，替代现有裸前缀+相似度两层为同层内先精确去字符再模糊）
- 搜索范围：先同目录兄弟（现有语义），未命中再全作品树内所有 `.vtt/.lrc`。
- `album.json` 增加 sidecar-only 键 `subtitleMatches: { "<音频树路径>": "<字幕树路径>" }`（树路径 = `FilePath.getPath` 形如 `/folder/01.mp3`）。
- `AlbumMetadataWriter.write` 改为读-合并-写：重写 WorkSnapshot payload 时**保留**已有 `subtitleMatches`（否则下次下载会抹掉）。
- 播放解析顺序（`PlayerViewModel._loadSubtitleIfAvailable`，实现时定稿）：
  1. album.json 已记录匹配（手工/历史自动；避免每次重算覆盖用户手工指定）
  2. 自动链 ①②③（命中则补写 album.json，已有记录不覆盖）
  3. 用户导入 `user_subtitles`（现有，**降为最后**——用户决策）
  4. 无 → clearSubtitle
- 自动匹配成功即写 album.json（key 已存在且不同则**不覆盖**）；手工选择**可覆盖**已有记录（显式用户意图）。
- 手工选择 UI 两处：
  - 详情页：音频行操作（长按/菜单）→ 从专辑内 `.vtt/.lrc`（同目录优先列出）选择
  - 播放页：字幕弹出菜单加「从专辑选择字幕」
  - 选中即写 album.json + 立即加载
- 文案全部进 `Strings`；不改 DB schema、不跑 build_runner。

**不包含：**
- 不做 SRT 解析扩展（匹配/导入仍仅 `.vtt/.lrc`；预览 4 格式现状不动）。
- 批量下载配对 `collectAudioWithSubtitles` **保持仅同目录**（现有测试锁定的下载配对不变量；全树兜底只用于播放解析）。
- 不把 `subtitleMatches` 写入 SQLite `work_snapshots`（sidecar-only）。
- 导入文件（外部 file picker）不在作品树内，不写 subtitleMatches（仍只进 `user_subtitles`）。
- 不做字幕时间轴/翻译相关改动。

## 3. 验收标准（Acceptance）

- [x] 同目录下 `01.mp3` + `01.vtt` → ①命中；`【标题】01.mp3` + `【标题】01.vtt` 规范化后②命中；夹杂标点/空格差异仅去字符后相同 → ③命中。
- [x] 同目录无字幕、其他子目录有同名/可模糊命中字幕 → 全树兜底命中。
- [x] 自动命中后 `<downloads>/<workId>/album.json` 出现 `subtitleMatches["/.../01.mp3"]`；再次播放/下载不覆盖已有不同记录。
- [x] 手工选择覆盖已有自动记录并立即生效；下次播放优先用记录。
- [x] 手工选择入口：详情页音频行 + 播放页菜单均可选专辑内字幕。
- [x] 全自动失败且无记录时才回退到用户导入（导入仍可用）。
- [x] 下载重写 album.json 后 `subtitleMatches` 仍在（合并写）。
- [x] `flutter analyze` 通过，无新增 warning。
- [x] 相关单元 / Widget 测试通过。

## 4. 拆解步骤（Steps）

- [x] **Step 1**：文案
  - 涉及文件：`lib/common/constants/strings.dart`（选择字幕 / 专辑内无字幕 / 已匹配等）
  - 验证：analyze
- [x] **Step 2**：Matcher 优先级链 + 树路径工具复用
  - 涉及文件：`lib/core/subtitle/utils/subtitle_matcher.dart`（规范化/去字符层；`findMatchingSubtitle` 重构为 ①②③）、`lib/core/subtitle/subtitle_loader.dart`（同目录 → 全树两段候选）、`lib/core/audio/models/file_path.dart`（`childByPath`）
  - 验证：新增 `test/core/subtitle/subtitle_matcher_test.dart`、`test/core/audio/file_path_child_by_path_test.dart`
- [x] **Step 3**：album.json `subtitleMatches` 合并写
  - 涉及文件：`lib/core/download/album_metadata_writer.dart`（merge-on-write、`readSubtitleMatches`/`recordSubtitleMatch`）、`lib/core/download/download_service.dart`（`findWorkDir`/`readSubtitleMatches`/`recordSubtitleMatch`）
  - 验证：`album_metadata_test` 补合并/不覆盖/手工覆盖用例
- [x] **Step 4**：播放解析链重排 + 自动补写
  - 涉及文件：`lib/presentation/viewmodels/player_viewmodel.dart`（记录→①②③→导入；`assignSubtitleFromAlbum`）
  - 验证：analyze
- [x] **Step 5**：手工选择 UI
  - 涉及文件：`lib/widgets/detail/subtitle_pick_dialog.dart`、`work_file_item.dart`（长按）、`work_files_list.dart`/`work_folder_item.dart`（透传）、`detail_screen.dart`、`player_screen.dart` 菜单
  - 验证：analyze；两入口可选
- [x] **Step 6**：测试全量
  - 涉及文件：`test/core/subtitle/subtitle_matcher_test.dart`、album 合并写、`file_path_child_by_path_test`
  - 验证：`flutter test` 291 全过
- [x] **Step 7**：全量验证 + 文档同步 + 归档
  - `flutter analyze` 恰 4 既有 warning、`flutter test` 291 全过、`flutter build windows --release` 成功
  - 手动同步 `AGENTS.md`/`CLAUDE.md`（subtitle 段匹配链、download 段 subtitleMatches 合并写、Tests 段）；勾步骤填 ✅；移 `done/`；汇报 `git status`（不 commit）

## 5. 风险与回滚（Risks）

- **风险**：导入从「最优先」降为最后，老用户导入的字幕若自动链也命中同名文件会改用自动结果 → 决策已确认；导入仍可用且 `user_subtitles` 不动，revert 解析顺序即可。
- **风险**：全树模糊匹配误配对 → ①②③仍要求同名/高相似；先同目录再全树；threshold 0.6 不降低。
- **风险**：合并写与并发下载写 album.json 竞态 → 写路径单线程（队列串行）+ tmp rename；best-effort。
- **回滚**：revert commit；album.json 多余键 `WorkSnapshot.fromJson` 忽略，无迁移。

## 6. 备注 / 决策记录

- 用户决策：播放时实时匹配；手工选择两处都加；匹配范围同目录→全作品树；album.json key=树路径；手工仅写 album.json 不复制进 user_subtitles；自动成功即写、已有不覆盖（手工可覆盖）。
- 实现定稿：已记录匹配（含手工）**优先于**自动链——否则自动每次重跑会盖过用户手工指定；首次无记录时走①②③并补写。
- 树路径用现成 `FilePath.getPath`（title+url+type+size 定位）。
- 批量下载配对保持同目录（`detail_viewmodel_collect_test` 不变量）；全树仅播放解析。
- 顺带答疑：数字文件夹名对 Android/iOS 兼容**无必要**——私有目录无命名格式要求，可读名只要过 `sanitizeFileName` 即可。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-24
- 执行命令：手动同步 `AGENTS.md`/`CLAUDE.md`（未跑 `/init`，按手册直接编辑）
- CLAUDE.md 更新摘要：
  - `core/subtitle/` 段：Matcher ①②③ 优先级链、`findSubtitleFile` 同目录→全树、播放解析顺序（记录→自动→导入）、双入口手工选择、批量配对仍同目录。
  - `core/download/` 段：album.json `subtitleMatches` sidecar + merge-on-write + `DownloadService` 读写 API + `FilePath.childByPath`。
  - Tests 段：`subtitle_matcher_test` / `file_path_child_by_path_test` / album `subtitleMatches` 用例。
- 关联 commit：（未 commit，按工作流仅汇报 `git status`）

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：
- 后续指向：
