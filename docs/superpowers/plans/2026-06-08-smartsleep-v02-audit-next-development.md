# SmartSleep v0.2 Audit-Based Next Development Plan Index

原始单体计划已按审核结论拆分。不要把本文件当作实现计划执行。

## 拆分后的执行顺序

1. `docs/superpowers/plans/2026-06-08-smartsleep-v02-watch-ios-connectivity-run-summary.md`
2. `docs/superpowers/plans/2026-06-08-smartsleep-v02-watch-sensor-preflight.md`
3. `docs/superpowers/plans/2026-06-08-smartsleep-v02-experimental-auto-silence-resleep.md`

## 当前执行策略

- 不采用多分支并行开发，改为严格串行。
- `codex/smartsleep-v02-audit-next-development` 只负责计划输入、执行清单、验收汇总，不承担产品代码改动。
- 串行基线顺序固定为：
  1. `codex/smartsleep-v02-audit-next-development`
  2. `codex/smartsleep-v02-watch-ios-connectivity-run-summary`
  3. `codex/smartsleep-v02-watch-sensor-preflight`
  4. `codex/smartsleep-v02-experimental-auto-silence-resleep`
  5. 回到 `codex/smartsleep-v02-audit-next-development` 收口

## 修订原则

- 不再用 `WatchArmingStatus(isArmed: true, sessionScheduled: false)` 覆盖 runtime failure。Watch arming 与 session result 分开保存和展示。
- iOS 端不能只保存一个 `latestRunSummary` 作为产品事实源；session result 需要按 `alarmId` 合并到卡片，run summary 需要按 `runId` 保存，调试区只显示 latest 摘要。
- Watch run summary 的 `eventCount` 必须来自 logger 计数 API，不由 `WatchAppModel` 手写估算。
- `WatchAlarmRunLogging` 必须先补 `recordSummary(_:)` 和 `eventCount(runId:)`，再接传感器 summary。
- 新增 preflight 后，现有 Watch 测试不得继续依赖 `Date(timeIntervalSince1970: 3_600)` 作为“未来时间”；测试要么使用 `Date.now.addingTimeInterval(...)`，要么显式注入通过的 fake preflight。
- `FakeWatchPreflightChecker`、`FakeWatchHeartRateSampler` 等测试替身不得进入生产 Watch target；放在 `Apps/Watch/Tests`，或用 `#if DEBUG` 明确隔离。
- preflight failure、runtime invalidation、用户 stop/snooze 都必须有可回放日志；不得只发 arming result。
- HealthKit 授权检查从 Watch arming preflight 中移出；HealthKit denied 只禁用 HR boost，不阻塞 motion-only Smart Mode。
- HealthKit 本轮只交付 mapper、协议和保守查询 adapter；真机数据质量、授权体验和 AlarmKit 真实 API 都作为独立 spike。真实 API 签名必须以当前官方 SDK/文档为准。
- 修改 `Apps/iOS/Info.plist` 或 `Apps/Watch/Info.plist` 后必须运行 `xcodegen generate`，并确认生成工程仍包含对应 usage description。
- 自动静音必须记录两阶段状态、confidence、channel stoppedAt、outcome，以及同一 runId 下触发决策前的 `SensorFreshness` 和 `SensorSummary`；candidate rejected 要回到进入 candidate 前的原状态。
- 再睡重响必须记录 risk score/reason，并确保同一 runId 的 summary/freshness 能回放出 `stillnessDurationSec`、`stepDelta`、`interactionCount` 等触发特征。
- 测试和构建命令必须先确认本机 scheme 与 simulator。当前 XcodeBuildMCP 可见 scheme 为 `SmartSleepAlarm`、`SmartSleepCore`、`SmartSleepWatch`，默认 session 未配置；当前可用 iOS 示例设备为 `iPhone 16 Pro`，当前可用 watchOS 示例设备为 `Apple Watch Series 10 (46mm)`。所有固定 simulatorId 都只是当前机器示例，执行前必须重新确认设备存在并按需 boot。

## 当前基线

- `Packages/SmartSleepCore` 纯 Swift 测试最近一次验证为 27 tests，0 failures。
- 已实现：核心模型、状态机、motion-first awake scoring、再睡风险评分、手势贪睡检测、feature flags、JSONL 日志、iOS CRUD/本地通知兜底/日志导出/反馈入口、Watch 启用确认/runtime session 调度/CoreMotion freshness/手动停止与贪睡。
- 未实现：iOS 消费 Watch session/run summary、真实 AlarmKit、Watch arming preflight、CoreMotion summary 聚合、HealthKit freshness adapter、feature-flagged 自动静音真实链路、feature-flagged 再睡检测真实链路、真机 P0 gate。

## 全局验证前置

每份计划执行前先确认工程状态：

```bash
git status --short
xcodegen generate
```

使用 XcodeBuildMCP 时先运行：

```text
session_show_defaults()
list_schemes(projectPath: "/Users/lzc/TNTprojectZ/AprojectZ/SmartSleepAlarm/SmartSleepAlarm.xcodeproj")
list_sims(enabled: true)
```

如没有 session defaults，构建或运行时显式传入 `projectPath`、`scheme` 和 `simulatorId`。不要使用固定设备名作为唯一验证路径；示例命令只用于当前这台机器。

当前示例 simulatorId：

```text
iOS: FD770DCA-02E9-4FE8-A924-2AC0C699A2DE  iPhone 16 Pro  iOS 18.6
watchOS: 2AC7F432-233D-42C0-8F88-9041EE6CE231  Apple Watch Series 10 (46mm)  watchOS 11.5
```
