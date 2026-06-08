# SmartSleep Alarm 代理规则

本仓库当前目标是 SmartSleep Alarm v0.2。所有回答、提交说明和新增项目文档默认使用中文。

## 工作范围

- 只实现和维护 v0.2 范围内的 iOS + watchOS 技术可行性 MVP。
- 不要加入睡眠报告、云同步、机器学习个性化、音频录制、Android、医疗诊断、订阅、复杂任务闹钟或其他超出 v0.2 的功能。
- 保持改动范围收敛。不要顺手重构无关文件，不要改动与当前任务无关的产品边界。
- 文档、代码和测试必须区分“已实现”“模拟/占位”“需要真机 spike 验证”。

## 产品原则

- 可靠性优先于智能感。只要系统不确定，就继续响铃。
- Smart Mode 只有在 Watch 完成启用确认并且 runtime session 成功预约后，才能显示为 Ready。
- Motion 是主要信号。HealthKit 心率只能作为可选增强，绝不能单独触发自动静音。
- 自动静音和再睡检测属于 P0-Experiment，必须通过 feature flag 控制，默认保持保守。
- 不允许使用 workout session 伪装或绕过系统限制来强制获取高频心率。
- iPhone 兜底通道必须明确可见。不要暗示第三方 Watch 闹铃拥有 Apple 系统闹钟同等级可靠性。

## 日志与可回放性

以下事件必须记录，且新增路径不得绕过日志：

- 状态机转换。
- 闹铃通道事件和触发结果。
- 传感器新鲜度事件。
- Watch 启用确认、runtime session 调度和失败原因。
- 手势事件。
- 自动静音、贪睡、重响、手动停止、失败和最终 outcome。

日志优先服务 dogfood、真机 spike 和误判回放。新增判断逻辑必须能解释触发原因。

## 工程约束

- 纯 Swift 逻辑应放在 `Packages/SmartSleepCore`，并补充或更新单元测试。
- iOS 壳层位于 `Apps/iOS`，watchOS 壳层位于 `Apps/Watch`。
- Apple API 行为如果无法在 Simulator 验证，必须在相关文档、计划或变更说明中加入手动真机测试备注。
- WatchConnectivity、WKExtendedRuntimeSession、CoreMotion、HealthKit、AlarmKit 等集成应以保守降级为默认路径。
- 不确定平台行为时，不要把假设写成事实；先记录为 spike 或设备测试项。

## 验证要求

- 修改纯 Swift 逻辑后，至少运行 `swift test --package-path Packages/SmartSleepCore`。
- 修改 Xcode 工程结构后，运行 `xcodegen generate` 并确认相关 scheme 可构建。
- 修改 iOS/watchOS UI 或 Apple API 集成后，优先使用 Xcode 或 XcodeBuildMCP 做 Simulator 验证；Simulator 无法覆盖的行为需要补充真机测试说明。
- 完成任务前检查 `git diff`，确认没有无关文件变更。

## 主要事实来源

- v0.2 PRD：`docs/prd/SmartSleep_Alarm_v0.2.md`
- 范围与非目标：`docs/adr/ADR-0001-v02-scope-and-non-goals.md`
- Watch 启用确认要求：`docs/adr/ADR-0002-watch-arming-required.md`
- Motion-first 策略：`docs/adr/ADR-0003-motion-first-hr-optional.md`
- iPhone 兜底策略：`docs/adr/ADR-0004-fallback-channel-policy.md`
- Dogfood 流程：`docs/qa/dogfood-runbook.md`
- 设备测试矩阵：`docs/qa/device-test-matrix.md`
