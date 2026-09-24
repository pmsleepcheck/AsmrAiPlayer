# 修复播放无响应第二轮：Windows ready 挂起 + 点击无反馈

- **创建时间**：2026-09-23
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：用户反馈修复后「还是不能播放」

---

## 1. 目标（Goal）

> 点播放必须在有限时间内得到结果（MiniPlayer 更新或 SnackBar），不得因 `ready`/通知权限挂起而永久无反应。

## 2. 范围（Scope）

**包含：**
- `AudioNotificationService.init`（`AudioService.init`）加超时，失败/超时不拖垮 `_init`/`ready`。
- `resume()` 通知权限请求加超时，不阻塞 `play()`。
- 本地缓存/详情 `playWithContext` 调用加超时 + 点击即「正在启动播放…」SnackBar。
- 回答本地缓存 tab 入口（底部第 5 个）。

**不包含：**
- 不改 fileKey / 落盘 / DB。

## 3. 验收标准（Acceptance）

- [x] Windows 上点播放 ≤15s 内出声或出 SnackBar。
- [x] 通知栏初始化失败仍可播放。
- [x] analyze 无新增 warning；相关测试过；`build windows --release` 成功。

## 4. 拆解步骤（Steps）

- [x] **Step 0**：建本 TODO。
- [x] **Step 1**：通知 init/权限超时不阻塞 ready/resume。
- [x] **Step 2**：播放入口进度 SnackBar + playWithContext 超时。
- [x] **Step 3**：analyze/test/build + 同步文档 + 归档。

## 5. 风险与回滚（Risks）

- 超时后仍可能在后台完成 init——可接受（播放已给出反馈）。

## 6. 备注 / 决策记录

- 上一轮 candidateKeys/应用内播路径已合入但仍无反馈 → 最可疑是 `await ready` 卡在 `AudioService.init`。

---

## ✅ 完成标记

- 完成时间：2026-09-23 17:37
- 执行命令：`/init`
- CLAUDE.md 更新摘要：audio/download 段补 Play-no-response #2（通知 init 5s 超时不阻塞 ready、resume 权限 2s 超时、playWithContext 15s 硬超时 + AudioError、点击即 `Strings.playStarting`、超时后 `.ignore()` 被遗弃 Future）；CLAUDE 通知权限 bullet 补 2s-timeout-bounded。
- 关联 commit：（非 git 仓库）
- 验证：`flutter analyze` 4 既有 warning（无新增）；`flutter test` 209 全过；`flutter build windows --release` RC=0，`xuro.exe` TS=2026-09-23 17:36:51 LEN=91136。

---

## ⛔ 取消标记

- 取消时间：
- 取消原因：
- 后续指向：
