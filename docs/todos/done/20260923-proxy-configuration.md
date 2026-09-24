# 增加代理配置功能（Windows 桌面端优先）

- **创建时间**：2026-09-23
- **负责人**：opencode
- **状态**：active <!-- active | done | cancelled -->
- **关联 Issue / PR**：根目录 `todo.txt` 前置任务 1

---

## 1. 目标（Goal）

> 为应用增加可配置的 HTTP 代理（如 `127.0.0.1:7890`），让 Windows 桌面端用户在仅开系统代理（非 TUN）时也能让应用内网络请求走代理，正常访问 asmr 节点与 GitHub 更新接口。

## 2. 范围（Scope）

**包含：**
- `AppSettingsService` 新增持久化项：`proxy_enabled`（默认关）、`proxy_url`（默认 `127.0.0.1:7890`）。
- 新建 `lib/core/network/proxy_config.dart`：地址规范化/校验（纯逻辑，可单测）+ 对 `Dio` 的 `IOHttpClientAdapter.findProxy` 挂载（每次请求实时读设置，无需监听重挂）。
- 5 个 Dio 客户端全部接入：`ApiService`、`AuthService`、`UpdateService`、`DownloadService`、`SubtitleLoader`（DI 内创建的 Dio）。
- 设置 →「网络」分组新增：代理开关 toggle + 开启后显示「代理地址」导航项（弹窗编辑，校验 `主机:端口`）。
- 文案集中入 `Strings`。
- 单元测试：`ProxyConfig.normalize` / `resolve` 边界。

**不包含：**
- 音频流式播放（`LockCachingAudioSource`，just_audio 自有 HTTP 栈）与 `cached_network_image` 图片加载的代理 —— 本期不覆盖，文档注明。
- SOCKS5 代理（dart:io `HttpClient` 仅支持 HTTP 代理）。
- 仅 Windows 显示的平台门控：设置项对全平台可见（Android 代理模式同样可用），不引入 UI 层平台分支。
- 代理认证（用户名/密码）。

## 3. 验收标准（Acceptance）

- [ ] 开启代理并填入合法地址后，`ApiService`/`AuthService`/`UpdateService`/`DownloadService`/`SubtitleLoader` 的 Dio `findProxy` 返回 `PROXY host:port`；关闭后回退 `HttpClient.findProxyFromEnvironment`。
- [ ] 地址校验拒绝空串、无端口、端口越界、非法字符；接受 `127.0.0.1:7890`、`http://127.0.0.1:7890/`、`[::1]:7890` 并规范化。
- [ ] 设置页「网络」分组显示代理开关；开启后出现地址项；弹窗输入非法地址显示错误文案且不保存。
- [ ] 代理设置持久化：重启后恢复开关与地址。
- [ ] `flutter analyze` 通过，无新增 warning。
- [ ] `test/core/network/proxy_config_test.dart` 通过。

## 4. 拆解步骤（Steps）

按依赖顺序排列，每步注明「验证方法」。

- [x] **Step 1**：`Strings` 新增代理文案分区
  - 涉及文件：`lib/common/constants/strings.dart`
  - 验证：`flutter analyze lib/common/constants/strings.dart`
- [x] **Step 2**：`AppSettingsService` 新增 `proxyEnabled`/`proxyUrl` 持久化字段与 setter（沿用 判等短路 → notifyListeners → 落盘 模式）
  - 涉及文件：`lib/core/settings/app_settings_service.dart`
  - 验证：analyze；字段默认值符合 Scope
- [x] **Step 3**：新建 `ProxyConfig`（`normalize`/`resolve`/`apply`）
  - 涉及文件：`lib/core/network/proxy_config.dart`（新建）
  - 验证：analyze
- [x] **Step 4**：5 处 Dio 接入 `ProxyConfig.apply`（UpdateService 注入 `AppSettingsService` 仅用于传输层代理，baseUrl 仍硬编码不随节点轮换；DownloadService 的 `settings` 为可选参以兼容既有测试构造）
  - 涉及文件：`lib/data/services/api_service.dart`、`auth_service.dart`、`update_service.dart`、`lib/core/download/download_service.dart`、`lib/core/di/service_locator.dart`
  - 验证：analyze + 既有测试仍绿
- [x] **Step 5**：设置页网络分组 UI + 代理地址编辑弹窗
  - 涉及文件：`lib/screens/settings/settings_screen.dart`、`lib/screens/settings/proxy_address_dialog.dart`（新建）
  - 验证：analyze；手动路径：设置 → 网络 → 代理开关/地址
- [x] **Step 6**：单元测试 `normalize`/`resolve`/`apply` + 设置持久化
  - 涉及文件：`test/core/network/proxy_config_test.dart`（新建）
  - 验证：`flutter test test/core/network/proxy_config_test.dart`
- [x] **Step 7**：全量 `flutter analyze` + `flutter test`
  - 验证：无新增 warning（仅剩 AGENTS.md 已记录的 3 个既有 unused 警告）；测试 185 通过，2 个失败均为 `playlist_builder_test` 的 Windows 路径分隔符既有环境问题（`Uri.toFilePath()` 返回 `\`），与本任务无关

## 5. 风险与回滚（Risks）

- **风险**：`UpdateService` 构造签名变化影响 DI/测试；非法代理地址导致全部请求失败。
- **回滚方案**：`proxy_enabled` 默认 false，关闭即回退环境变量代理行为；revert 本任务提交即可整体回滚。DownloadService `settings` 可选，既有测试不受影响。

## 6. 备注 / 决策记录

- `findProxy` 是 Dio 在**每次请求时**回调的，闭包内实时读 `AppSettingsService` 当前值即可生效，无需 listener 重挂 —— 比 `_onSettingsChanged` 旋转 baseUrl 的模式更简单且无一致性风险。
- 关闭代理或地址非法时回退 `HttpClient.findProxyFromEnvironment`（尊重 `HTTP_PROXY` 等环境变量），不写死 `DIRECT`。
- 音频播放走 just_audio 自有 HTTP 栈、图片走 cached_network_image，均不经过 Dio —— 本期明确不覆盖。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-23 10:30
- 执行命令：`/init`（本会话非 Claude Code 环境，无 `/init` 命令可用 —— 已**手动**按 §3.3 等价刷新 `AGENTS.md` 与 `CLAUDE.md`：新增 `core/network/` 层说明、settings 代理字段、API 段 Proxy 不变量、settings 树 network 含代理、测试清单补 `proxy_config_test`）
- CLAUDE.md 更新摘要：记录 `ProxyConfig` 五 Dio 接入方式（createHttpClient 每连接实时读设置、无 listener）、代理不覆盖音频流/图片、`UpdateService` 仅注入 settings 挂代理、`DownloadService.settings` 可选参
- 关联 commit：无（`Xuro-main/Xuro-main` 非 git 仓库，用户未要求初始化/提交）

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）

> 任务取消时填写此块，**不需要执行 `/init`**，将文件移入 `docs/todos/cancelled/`。

- 取消时间：YYYY-MM-DD HH:mm
- 取消原因：<例如：方案被替换为 XYZ / 优先级下调 / 上游接口取消>
- 后续指向：<如有继任任务，写明对应的 TODO 路径；否则留空>
