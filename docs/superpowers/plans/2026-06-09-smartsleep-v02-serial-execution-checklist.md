# SmartSleep v0.2 Serial Execution Checklist

> 说明：本清单约束的是提交内容的集成顺序，不等价于 Git 分支已经整理成逐级派生的严格链式拓扑。当前 3 个实现分支与 `codex/p0-reliability-chain` 的共同基线仍为 `9ed6b93851c6258b592e4a27fc697a9ce66df29d`；收口时必须按“串行叠加、非串行派生”解释 merge/rebase 风险。

## 分支 1: `codex/smartsleep-v02-audit-next-development`

- 目标：固定 4 份计划文档，记录串行执行策略与验收框架。
- 前置条件：
  - 当前基线来自 `codex/p0-reliability-chain`
  - 4 份计划文档已在 Git 中可见
- 验证命令：
  - `git status --short`
- 完成标准：
  - 4 份计划文档已提交
  - 本清单文档已提交
  - 不包含 `Apps/iOS`、`Apps/Watch`、`Packages/SmartSleepCore` 产品代码改动

## 分支 2: `codex/smartsleep-v02-watch-ios-connectivity-run-summary`

- 目标：接通 iOS 消费 Watch session result / run summary，补齐 Watch logger 真实 event count 与 run summary 发送链路。
- 前置条件：
  - audit 文档基线提交已完成
  - `git status --short` 为空
- 验证命令：
  - `swift test --package-path Packages/SmartSleepCore`
  - `xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepAlarm -destination 'platform=iOS Simulator,id=FD770DCA-02E9-4FE8-A924-2AC0C699A2DE'`
- 真机 / spike 备注：
  - WatchConnectivity 真机可达性与后台时序仍需设备验证
- 完成标准：
  - `PhoneConnectivityClient` 可接收 `SessionResultPayload`、`RunLogSummaryPayload`
  - iOS 卡片状态不再用 arming 状态覆盖 runtime failure
  - `WatchAlarmRunLogging` 具备 `recordSummary(_:)` 与 `eventCount(runId:)`
  - Watch 在 stop/snooze/runtime invalidation 等终态路径发送 run summary

## 分支 3: `codex/smartsleep-v02-watch-sensor-preflight`

- 目标：补齐 Watch arming preflight、CoreMotion summary 聚合、HealthKit HR freshness mapper/adapter。
- 前置条件：
  - connectivity 分支已完成并作为当前开发基线
  - `git status --short` 为空
- 验证命令：
  - `swift test --package-path Packages/SmartSleepCore`
  - `xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,id=2AC7F432-233D-42C0-8F88-9041EE6CE231'`
- 真机 / spike 备注：
  - HealthKit 授权体验、真实心率样本质量、WKExtendedRuntimeSession 行为需要真机验证
- 完成标准：
  - preflight failure 不调 runtime scheduler，但会记录日志并发送 session result / run summary
  - summary 聚合结果能写入 logger 并被后续 run summary 使用
  - HealthKit denied 只影响 HR boost，不阻断 motion-only Smart Mode

## 分支 4: `codex/smartsleep-v02-experimental-auto-silence-resleep`

- 目标：在 feature flag 保护下接通自动静音与再睡检测真实链路。
- 前置条件：
  - preflight 分支已完成并作为当前开发基线
  - `git status --short` 为空
- 验证命令：
  - `swift test --package-path Packages/SmartSleepCore`
  - `xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,id=2AC7F432-233D-42C0-8F88-9041EE6CE231'`
- 真机 / spike 备注：
  - 自动静音误判、再睡重响阈值与运动噪声容忍度需要真机 dogfood 验证
- 完成标准：
  - 自动静音为两阶段状态机，candidate rejected 可恢复原状态
  - 再睡重响记录 risk score / reason，并保留同一 runId 的 freshness / summary 回放证据
  - `FeatureFlags.v02Default.autoSilenceEnabled == false`
  - `FeatureFlags.v02Default.reSleepDetectionEnabled == false`

## 收口: `codex/smartsleep-v02-audit-next-development`

- 汇总每个分支的完成提交、验证命令、真机未覆盖项、剩余风险。
- 只更新文档，不补产品代码。
