# 更新记录 / Changelog

记录 Xuro 自 v1.1.11 之后的所有用户可见与开发者可见改动。版本号遵循 [SemVer](https://semver.org/lang/zh-CN/) 与 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 风格。

---

## 未发布 / Unreleased

（暂无）

---

## [1.3.0] - 2026-09-30

> v1.2.0 之后的四个迭代合入：Windows 桌面适配 → 同声传译全链路 → 翻译音量自动对齐与
> 本地缓存改进 → Supertonic 默认 TTS + 智能耳侧。测试 470 → 490 全绿。

### 新增 / Added

- **同声传译（翻译 + 播放）**：按当前字幕逐句朗读并与主音轨混播；可调延迟
  （0/100/200/300/500/1000ms）、翻译轨音量、自动响度对齐；播放中随时开关与切换主耳。
- **双耳声道隔离**（桌面 Windows/Linux）：主轨与翻译轨硬分左右（mpv `lavfi pan`），
  Android/iOS 无 pan API 自动降级为音量强调混播。
- **多 TTS 引擎**：新增 **Supertonic**（本地 `supertonic serve`，`127.0.0.1:7788`，
  免费离线）作为**默认引擎**；**Fish Audio** 云端 API 保留，设置 → AI 翻译顶部
  「TTS 引擎」下拉切换，按引擎分区显示配置（Supertonic：地址/音色/语言 + 健康检测
  + 一键启动；Fish：Key / 音色预设 / 模型）。抽象出 `TtsSynthesizer` 接口，
  后续引擎（Edge / Azure 等）按「实现接口 + 枚举 + 路由分支」即可接入。
  本地服务未启动时给出明确文案与「启动服务」动作，不再静默失败。
- **智能耳侧（实验）**：本地分析 wav/mp3 得到逐窗左右声道时间轴，把翻译播到对侧耳；
  分析不就绪时自动回退固定耳侧。
- **翻译音量自动对齐**：两条轨实测 RMS 后把响的一侧压下来（下限 0.1），自动关时
  回退手动音量；手动音量作品级（`album.json translationVolume`）优先于全局。
- **Fish 多音色预设**：增删改 + 设当前，播放页音色键一键轮换；音色 ID 明文存 prefs，
  API Key 仍走安全存储。
- **本地缓存改版**：按作品分组的**文件夹树形视图**（默认）与「显示全部文件」双模式；
  下载目录改为可读的 `<作品标题>/<原文件名>` 平铺布局（旧的 md5 目录仍可读不迁移）；
  「附加缓存目录」可添加只读扫描根。
- **首页五宫格入口**（推荐/搜索/本地/定时关闭 + 热门）；**无图片模式**开关。
- **Windows 桌面适配**：`just_audio_media_kit` 播放后端、`sqflite_ffi` 数据库、
  下载与字幕路径可见可打开。

### 修复 / Fixed

- **不可播放文件不再给播放按钮**（字幕 / 视频 / `album.json` 被标成 audio 的场景）——
  否则 mpv 加载文本文件会卡死，连带之后所有播放都失败。
- **播放页布局**：小屏幕上封面溢出盖住底部控件的问题（封面尺寸按可用高度收敛，
  底部控件块限高可滚动）；睡眠定时行抽为独立组件。
- **列表错误态**：翻页失败不再整页替换成错误页（陈旧内容优先）；未登录时给
  「去登录」而不是无效的「重试」。
- **列表播放无响应**：本地路径解析改走新旧两套 fileKey 候选，过期的预签名 URL
  不再劫持本地播放。

### 文档 / Docs

- README（中英）：已实现的愿景项移入「特性」，「项目愿景」只保留未实现的
  语音识别（ASR）与日 → 中字幕机翻。
- `AGENTS.md` / `CLAUDE.md` 同步多 TTS 引擎、智能耳侧、音量对齐等不变量。

---

## [1.2.0] - 2026-08-13

> 本版含一次**完整的视觉语言替换**（Modernist）与一轮冷启动关键路径优化。
> 由于 v1.1.11 之后从未发版，5 月的若干中间态视觉决策也落在本版内，且其中一部分
> **在本版内被后续改动取代**（下方以 ⚠️ 标注）——升级用户看到的是取代之后的结果。

### 新增 / Added

- **Modernist 视觉语言（全局）**：零圆角、2px/1px 两级分隔线取代阴影与卡片、
  标题 800 字重、纸墨中性底色，随包 Archivo 字体（拉丁字母与数字；中日文回退系统字体）。
  视觉基准为 Claude Design 项目《Flutter ASMR播放器设计》。
- **第 4 主色调「红」**（`#EC3013`，设计稿的招牌色）。蓝 / 黑 / 绿保留，可随时切回。
- **首页改版**：按时段变化的问候语；「继续播放」卡片（有上次播放记录时才出现）；
  作品卡片新增「在线 / 本地」角标，一眼区分已下载与需联网的作品。
- **分类 / 社团 / 声优三屏改为编号列表**，条目数取接口真实值，接口未返回时不显示
  （不再兜底成 0）。
- **播放器改版**：方形大封面、2px 直条进度 + 方块滑块、大方块主播放键。
- **用户注册流程**（`POST /api/auth/reg`）：抽屉登录对话框新增「没有账号？去注册」入口；新对话框含用户名 / 密码 / 确认密码三字段，提交按钮按客户端校验状态自动启用。注册成功自动登录；服务端未返回 token 时回退到 `login` 兜底，账号创建成功但自动登录失败的边界场景通过 `RegisteredButNotLoggedInException` 单独提示。任务文档：[`done/20260515-user-registration.md`](docs/todos/done/20260515-user-registration.md)。
- **3 种主色调可切换**（蓝 / 黑 / 绿，默认蓝）：设置页「外观」之后新增「主色调」分组，三选一持久化到 `AppSettingsService.colorVariant`。`AppColors` 重构为 `lightSchemeFor(variant)` / `darkSchemeFor(variant)` 工厂，6 套手写 ColorScheme 不依赖 `fromSeed`。任务文档：[`done/20260515-color-palette-simplification.md`](docs/todos/done/20260515-color-palette-simplification.md)。
- ⚠️ **已被本版内后续改动取代** — **侧边抽屉视觉**（深色玻璃拟态）：深色蓝紫渐变 + 软光晕 + 半透明分组卡片 + 圆形资料卡。新增「最近播放」「排行榜」「深色模式」「关于我们」入口。宽度遵循 `ui-design-spec §5` 的 mobile/tablet 断点。任务文档：[`done/20260515-sidebar-glassmorphism-redesign.md`](docs/todos/done/20260515-sidebar-glassmorphism-redesign.md)。

### 变更 / Changed

- **冷启动只发一个内容请求**（原先并发 3 个，其中 2 个是当时看不见的标签页）。
  各标签页改为首次显形时才加载，切回不重复请求。
- **播放态恢复不再挡住第一次操作**：恢复挪到首帧之后，且不再排在播放器就绪闸门之前——
  此前恢复进行中按播放要排队等它做完。恢复时的逐轨数据库查询也收敛成一次批量查询。
- **通知权限改到首次播放时才请求**，冷启动不再弹系统权限框。
- **详情页与列表卡片的标签跟随主色调**（原先固定橙 / 绿 / 蓝，暗色下其中一处对比度
  不达 WCAG AA）。
- **侧边栏**：层级改由 2px（分组）/ 1px（行）分隔线表达，分组标题改用主色调，
  行标题加粗。⚠️ 取代 5 月的「深色玻璃拟态」与叶片水印装饰（见下方 ⚠️ 条目）。
- **搜索 / 收藏 / 相似作品三屏**改用与首页同一套列表实现，因此一并获得骨架加载、
  下拉刷新与统一的错误态。
- **`AuthService` 节点感知**：原硬编码 `https://api.asmr.one/api`，现注入 `AppSettingsService`、监听并同步 Dio baseUrl，登录与注册都会跟随用户在设置中选择的节点（主站 / 100 / 200 / 300）。
- **Surface 设计令牌中性化**：`AppColors.lightSurfaceL1/L2` 与 `darkSurfaceL1/L2` 之前略带紫调（`#F7F2FA` 等），现统一为无色相中性灰，避免与 mono/green 主色调撞色。
- ⚠️ **已被本版内后续改动取代** — **侧边抽屉「双色」简化**：抽屉内 9 处不同彩色的菜单图标背景统一为单一中性灰 `_kIconBgGray = #8E8E93`；唯一彩色 affordance 是 avatar / 圆形箭头 / footer 光点 / 渐变光晕 / 卡片阴影，全部从 `Theme.of(context).colorScheme.primary` 派生，随用户选的主色调动态切换。

### 修复 / Fixed

- **列表已有内容时翻页失败，整页内容被错误页盖掉**。现在陈旧内容优先于错误页。
- **收藏为空 / 无相似推荐时显示纯白屏**（旧列表实现的空态兜底是一个零尺寸组件）。
- **翻页时整屏被替换成转圈并丢失滚动位置**。现在只有首次空列表才显示加载态。
- **播放器初始化失败后整个使用周期内音频不可用**（不可重建的单例 + 一次性错误状态）。
  现在可重试。
- **错误提示直接显示 Dart 异常堆栈**（5 处），现在统一走可读文案。
- **播放时每个屏幕都在以每秒 5 次的频率重建迷你播放器**（含两处共享元素动画与网络
  封面图）。播放位置改走独立通道，只有两个进度组件订阅。
- **底部导航选中色不随主色调变化**：它默认取了一个从未被赋值的主题 token，因而在
  四种配色下恒为同一颜色。
- **侧边抽屉首次打开 256ms 卡顿**：PerfDog 真机数据证实由 `Stack` 顶层的 `BackdropFilter(blur 18)` 引起。该模糊在不透明渐变之上是视觉 no-op，但首次绘制触发 Impeller offscreen layer + shader 编译。已删除 `BackdropFilter`，原 18% 黑色 overlay 通过 `0.82` 折算严格等价地烘焙进渐变 RGB 与软光晕 RGB（保持 alpha 不变，源叠加数学等价）。任务文档：[`done/20260515-sidebar-first-open-jank.md`](docs/todos/done/20260515-sidebar-first-open-jank.md)。
- **小米 HyperOS 3 + Adreno + Vulkan 长会话型崩溃**（`ErrorDeviceLost` → `SIGSEGV in libvulkan.so::CmdEndRenderPass+4`）：Android 上禁用 Impeller 回退到 Skia 渲染器（`AndroidManifest.xml` 加 `io.flutter.embedding.android.EnableImpeller=false`）。iOS 继续使用 Impeller。任务文档：[`done/20260515-disable-impeller-android.md`](docs/todos/done/20260515-disable-impeller-android.md)；后续 SDK 升级跟踪：[`active/20260515-upgrade-flutter-sdk.md`](docs/todos/active/20260515-upgrade-flutter-sdk.md)。
- **登录/注册 dialog 切换泄漏旧错误**：`AuthViewModel.clearError()` 新增；`LoginDialog` ⇄ `RegisterDialog` 切换时调用。
- **退出登录概率不弹对话框 / 偶发闪退**：`SidebarHeader` 改为 `StatefulWidget` + `_dialogScheduled` 守卫；`Navigator.maybePop(drawer)` + `addPostFrameCallback` 把对话框开启推到下一帧，避免同帧 pop+push 在同一 navigator 上的 race。退出按钮恢复 `dialogContext.mounted` 守卫，避免 dialog 已被外部关闭时误 pop 底层页。任务文档：[`done/20260515-auth-flow-bugfix.md`](docs/todos/done/20260515-auth-flow-bugfix.md)。
- **抽屉内对话框继承暗色 Theme**：登录/退出对话框改用 `rootNavigator` 打开，与抽屉内本地 dark Theme 解耦。

### 移除 / Removed
- **注册表单的「推荐人 UUID」字段**：UI 输入框移除，服务层可选参数保留（未来若有深链解析需求可继续传值）。

### 工程 / Internal

- **设计令牌层重写**：`AppRadius` 全档归零、`AppColors` 换为纸墨 + 共享中性阶、
  `AppTextStyles` 换为 800 字重体系；`app_theme` 补齐 button / input / snackBar /
  bottomSheet / dialog / chip / navigationBar 主题——M3 这些组件的默认形状**不读
  `AppRadius`**，不显式覆盖则零圆角在它们身上整体失效。
- **净删代码**：合并两套 grid 栈（−180 行）、删三个零调用点原子（−173 行）、
  删四个死文件（`player_cover` / `player_progress` / `player_seek_controls` /
  `sidebar_decoration`）。全库绕过令牌的硬编码圆角由 25 处清零。
- **测试**：95 → 173 个用例，新增覆盖此前 0 覆盖的列表四态编排、播放位置订阅边界、
  多配色不变量。`design_tokens_test` 的圆角回归闸由「md 必须仍是 12」**刻意改写**
  为「四档必须为 0」。
- **发布策略**：`build.yml` 的 `prerelease` 由写死 `true` 改为按 tag 是否含 `-`
  判定，因此正式版打 `v1.2.0`、预览版打 `v1.3.0-rc.1` 即可，无需再改 workflow。
- **`docs/ui-design-spec.md` 重写为 v5.0**（Modernist），v4.0 的参考图内容整篇作废；
  新增 §8「已知缺口」表，登记交互反馈层、`disableAnimations` 无障碍守卫、真机验收
  等**已知未做**项，避免后续重复发现。
- **未完成的验收**：release/profile 冷启动毫秒未采集（debug 埋点为 JIT，不可代表
  release）；四配色 × 明暗未逐屏对照；播放器全屏未在真机上查看。三份任务文档
  保持 `active` 状态，未提前收口。
- **任务文档归档**：今日新增 5 个 `done/` 文档（注册流程 / 鉴权 bug 修复 / 抽屉首开卡顿 / Impeller 禁用 / 配色简化）+ 1 个 `cancelled/` 文档（[`flutter-performance-optimization.md`](docs/todos/cancelled/20260515-flutter-performance-optimization.md)，因审计基线过期 7/9 P0 已修，且剩余项需 profile 数据驱动）+ 1 个 `active/` 占位（Flutter SDK 升级，等 Skia 跑稳一周后启动）。
- **Codex 复审**：本会话所有 6 个独立 TODO 统一在 SESSION_ID `019e2873-2990-72e2-bc68-ba47328971b7` 下复审，全部走 ⚠️/❌ → ✅ PASS 闭环。
- **CLAUDE.md 反踩坑补丁**：标注侧边栏「Theme override 必须用 `darkSchemeFor(variant)` 而非只切 brightness」、「不要再加全屏 BackdropFilter」、「Android 已禁 Impeller」、「主题双轴 ThemeMode × ColorVariant」。
- **静态分析**：所有改动文件 `fvm flutter analyze` 零新增 warning（项目历史 33 条预存 `withOpacity` deprecation 维持不变）。

---

## v1.1.11 之前

历史版本变更记录见 git log 与 GitHub Releases（[releases](https://github.com/WuMe-sicx/Xuro/releases)）。
