# SmartSleep Alarm v0.2 MVP

SmartSleep Alarm v0.2 是一个 iOS + watchOS 技术可行性 MVP，用来验证 Apple Watch 起床确认型智能闹铃链路。

产品原则很保守：可靠性优先于智能感。只要系统无法确认用户已经醒来，闹铃就必须继续响，iPhone 兜底通道也必须保持可见。

## 产品定位

SmartSleep Alarm 不是睡眠报告 App，也不是医疗或睡眠阶段诊断工具。v0.2 只验证一条窄链路：

1. 用户在 iPhone 创建闹铃。
2. Apple Watch 收到配置后完成当晚或当次启用确认。
3. Watch 成功预约 runtime session 后，Smart Mode 才能显示 Ready。
4. 到点后 Watch 触觉/声音提醒，同时 iPhone 侧保留兜底通道。
5. Motion-first 逻辑判断高置信度清醒候选；心率只作为新鲜样本下的可选加分。
6. 不确定时继续响铃；自动静音和再睡检测只作为带 feature flag 的实验能力。
7. 所有状态、通道、传感器新鲜度、手势和结果写入本地日志，便于 dogfood 回放。

## 当前范围

已进入 v0.2 范围：

- 纯 Swift core models、状态机、评分、调度策略、日志和 payload 类型。
- Motion-first awake scoring，并拒绝 heart-rate-only 自动静音。
- 带响铃状态和冷却约束的手势贪睡检测。
- Append-only JSONL 事件存储。
- WatchConnectivity payload 类型和 mock outbox 行为。
- iOS / watchOS SwiftUI MVP 壳层，用于 dogfood 和技术 spike。
- iPhone 兜底策略建模：iOS 26+ AlarmKit 优先，其他情况降级为 Local Notification / 前台音频 / 明确用户提示。

不进入 v0.2：

- 睡眠报告、趋势图、睡眠阶段识别。
- 云同步、广告归因、跨用户模型训练。
- 机器学习个性化。
- 音频录制和夜间声音分析。
- Android 或 Wear OS 版本。
- 医疗诊断、治疗建议或健康结论。
- 复杂任务闹钟、订阅和商业化功能。

## 目录结构

```text
Apps/iOS/                  iPhone SwiftUI MVP 壳层
Apps/Watch/                Watch SwiftUI MVP 壳层
Packages/SmartSleepCore/   纯 Swift 模型、状态机、评分、日志、payload
docs/prd/                  v0.2 PRD 事实来源
docs/adr/                  工程决策记录
docs/spikes/               设备 spike 矩阵与验证记录
docs/qa/                   dogfood 和真机测试流程
docs/superpowers/          计划与执行文档
project.yml                XcodeGen 工程定义
```

## 本地开发

生成 Xcode 工程：

```bash
xcodegen generate
```

运行纯 Swift 单元测试：

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" \
  CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
  swift test --package-path Packages/SmartSleepCore
```

也可以直接运行：

```bash
swift test --package-path Packages/SmartSleepCore
```

使用 Xcode 或 XcodeBuildMCP 构建以下 scheme：

- `SmartSleepAlarm`：iOS App。
- `SmartSleepAlarmTests`：iOS 单元测试。
- `SmartSleepWatch`：watchOS App。
- `SmartSleepWatchTests`：watchOS 单元测试。

## Feature Flags

v0.2 默认保持保守配置：

```text
autoSilenceEnabled = false
reSleepDetectionEnabled = false
gestureSnoozeEnabled = true
heartRateBoostEnabled = true
maxReAlarmCount = 2
```

自动静音和再睡检测只能在命名的内部 dogfood 运行中启用，并且必须导出日志。HealthKit 心率只能在样本足够新鲜且 baseline 可信时增加置信度，绝不能单独触发自动静音。

## 日志要求

新增功能不得绕过日志。以下事件必须可记录、可导出、可回放：

- 状态机转换。
- Watch 启用确认和 runtime session 调度结果。
- 闹铃通道尝试、触发、失败和降级。
- Motion / heart rate 等传感器新鲜度。
- 手势贪睡事件。
- 自动静音、手动停止、重响、错判和最终 outcome。

日志用于验证“可靠性优先”。如果记录缺失，相关 dogfood 结果不应计入有效样本。

## 设备验证

Simulator 可以验证纯 Swift 逻辑、基础 UI 和部分 App 状态流，但以下能力需要 Apple Watch + iPhone 真机验证：

- Watch 端 runtime session 预约和唤醒时机。
- WatchConnectivity 真实收发和断连场景。
- CoreMotion 夜间佩戴采样质量。
- HealthKit 心率样本新鲜度。
- Watch 触觉/音频和 iPhone 兜底通道可靠性。
- AlarmKit 授权与触发行为。

dogfood 入口文档：`docs/qa/dogfood-runbook.md`。设备测试矩阵：`docs/qa/device-test-matrix.md`。

## 关键决策

- `docs/adr/ADR-0001-v02-scope-and-non-goals.md`：v0.2 范围与非目标。
- `docs/adr/ADR-0002-watch-arming-required.md`：Smart Mode Ready 必须依赖 Watch 启用确认和 runtime session 成功预约。
- `docs/adr/ADR-0003-motion-first-hr-optional.md`：Motion 是主信号，心率只是可选增强。
- `docs/adr/ADR-0004-fallback-channel-policy.md`：iPhone 兜底通道必须存在且记录日志。

## 开发约束

- 保持 v0.2 范围，不添加未批准的大功能。
- 纯 Swift 逻辑优先放进 `Packages/SmartSleepCore`，并补充单元测试。
- Apple API 行为如果无法在 Simulator 验证，必须留下手动真机测试说明。
- 不确定平台能力时，先写成 spike 或验证项，不要写成已保证能力。
- 提交前检查 `git diff`，确认只改了任务相关文件。
