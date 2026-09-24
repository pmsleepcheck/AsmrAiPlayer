# 覆盖 Dio 5.11 新增的 transformTimeout，修复 Windows release 构建

- **创建时间**：2026-09-23
- **负责人**：opencode
- **状态**：done <!-- active | done | cancelled -->
- **关联 Issue / PR**：（留空）

---

## 1. 目标（Goal）

> 本地 `flutter pub get` 将 dio 解析到 5.11.1，新增 `DioExceptionType.transformTimeout` 导致两处穷尽 switch 编译失败，补全 case 以恢复 `flutter build windows --release`。

## 2. 范围（Scope）

**包含：**
- `lib/data/services/exceptions/network_exception.dart`：`transformTimeout` 归入 timeout 分支
- `lib/data/services/exceptions/update_exception.dart`：`transformTimeout` 归入 network 分支
- 完成 Windows release 构建验证

**不包含：**
- 不改动 pubspec 依赖约束（仍为 `dio: ^5.4.0`）
- 不涉及其它 Dio 错误分类语义调整
- 不执行 `/init`（本任务不改架构/模块文档；完成标记中注明跳过原因）

## 3. 验收标准（Acceptance）

- [x] 两处 switch 对 `DioExceptionType` 穷尽，无 G42E56F65 错误
- [x] `flutter analyze lib/data/services/exceptions/` 无新增 warning
- [x] `flutter build windows --release` 成功产出 exe（`build\windows\x64\runner\Release\xuro.exe`）
- [x] 相关单元测试通过（`update_version_compare_test` + `update_release_parse_test`：21 passed；含 `UpdateException.fromDioException` 分类用例）

## 4. 拆解步骤（Steps）

- [x] **Step 1**：定位编译失败点与 dio 版本
  - 涉及文件：`pubspec.lock`（dio 5.11.1）、两个 exception 文件
  - 验证：构建日志 `G42E56F65 ... transformTimeout` × 2
- [x] **Step 2**：补全 switch case
  - 涉及文件：`lib/data/services/exceptions/network_exception.dart`、`update_exception.dart`
  - 验证：`flutter analyze` 对应目录无该错误
- [x] **Step 3**：Windows release 构建
  - 验证：`build/windows/x64/runner/Release/xuro.exe` 存在（90624 bytes，Release 目录共 5 文件 / 17.9MB）

## 5. 风险与回滚（Risks）

- **风险**：`transformTimeout` 被归为超时类，若实际语义更接近 unknown 则错误文案略偏
- **回滚方案**：revert 两个文件的 case 增补即可

## 6. 备注 / 决策记录

- dio 5.11 新增 `transformTimeout`（transformer/拦截器内超时），语义仍是超时 → 归入既有 timeout/network 分支，不新增 `NetworkErrorType`/`UpdateErrorType` 枚举值。
- 本次为 Windows 构建环境打通的一部分；环境侧（Flutter SDK VS18 生成器映射、VS 2026 组件）改动不在仓库内。

---

## ✅ 完成标记

> 全部步骤勾选完毕后填写此块，并实际执行 `/init` 刷新根目录 `CLAUDE.md`，然后把本文件移入 `docs/todos/done/`。

- 完成时间：2026-09-23 09:55
- 执行命令：无需 `/init`（仅补两个 switch case，无新增/重命名服务/VM/Screen，CLAUDE.md 不描述 Dio 异常分类内部——与 `20260515-fix-inapp-pause-toggle-lock` / `20260515-fix-lyric-overlay-bg-start` 先例一致）
- CLAUDE.md 更新摘要：不涉及（无结构性变更）
- 关联 commit：（仓库无 `.git`，留空）

---

## ⛔ 取消标记（仅 cancelled 任务填写，与上方完成标记互斥）
