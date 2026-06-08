# SmartSleep Alarm v0.2 MVP 竞品调研与开发需求文档

版本：v0.2  
日期：2026-06-07  
范围：iOS + watchOS 技术可行性 MVP / Spike-first PRD  
状态：可用于下一阶段技术 spike、工程拆解、内部 dogfood 设计  

调研说明：v0.2 基于 v0.1 文档、事实核验结论以及 Apple 官方文档/竞品官方信息修订。v0.2 的重点不是扩展功能，而是修正 v0.1 中过度乐观或不够工程化的假设，使文档能指导接下来的软件开发。

---

## 0. v0.2 修订摘要

v0.2 对 v0.1 的核心修订如下。

1. 将“iPhone 设置闹铃后 Apple Watch 自动进入监测”改为“iPhone 创建闹铃 + Watch 端当晚/当次启用确认 + Watch 端预约 Smart Alarm runtime session”。在 Watch 端未完成启用确认前，Smart Mode 不显示为 Ready。
2. 将“普通闹铃兜底”细化为明确通道：iOS 26+ 优先使用 AlarmKit 作为 iPhone 侧兜底；不满足条件时降级为 iOS Local Notification / 前台音频 / 用户明确风险提示。不得把第三方 Watch 闹铃写成系统闹钟同等级保证。
3. 将“动作 + 心率判断清醒”改为 motion-first。CoreMotion 动作/姿态是主信号；HealthKit 心率只作为机会性增强信号，并且只有在样本足够新鲜时才参与评分。心率不得单独触发自动静音。
4. 将“3 秒确认窗口自动静音”改为“两阶段确认”：短窗口进入 `AWAKE_CANDIDATE`，随后 10–20 秒高置信度确认。低置信度继续响铃或进入低扰确认，不自动静音。
5. 将“防再睡 = 判断用户又睡着”改为“再睡风险评分”。静音后 5 分钟只判断高概率回到静止卧床且无起床行为，不做睡眠阶段识别。
6. 将“快速翻转/快速旋转贪睡”改为高约束手势：仅在 `RINGING` 状态有效，响铃初始冷却后，在 1.5 秒内完成两次方向一致且幅度达标的腕部旋转，才触发贪睡。
7. 增加完整状态机、异常状态、数据日志模型、技术 spike 矩阵、工程验收标准、App Review 与隐私边界。
8. 将自动静音、5 分钟防再睡重响、心率增强从“稳定 P0 必达能力”降级为“P0-Experiment”。v0.2 仍实现，但必须以保守阈值、日志回放、用户反馈标注为前提。

---

## 1. 结论摘要

SmartSleep Alarm 的产品机会仍然成立：市场上大多数睡眠闹铃产品主打“浅睡窗口唤醒”或“睡眠分析报告”，而不是“响铃之后确认用户是否真的醒了”。SmartSleep 应定位为“起床确认型智能闹铃”，核心价值是：睡着时继续提醒，确认醒来后减少打扰，静音后若高概率睡回去再重响，用户主动想赖床时可用 Watch 手势贪睡。

v0.2 的工程判断是：SmartSleep 的难点不在 UI，也不在第一版算法有多复杂，而在 Apple 生态链路是否足够可靠。第一阶段必须先验证 Watch 端 runtime session、传感器采样、音频/触觉、iPhone 兜底闹铃、断连独立执行和日志回放。

v0.2 不把 SmartSleep 做成完整睡眠报告 App。睡眠趋势、录音、助眠内容、云同步、复杂任务闹钟、机器学习个性化模型、Android 版本都不进入本阶段主线。

v0.2 的最高产品原则是：不确定就继续响。自动静音是体验增强，不是可靠性优先级最高的能力。任何自动静音和重响判断都必须可解释、可回放、可被用户反馈纠正。

---

## 2. 事实与技术边界

### 2.1 Apple Watch 系统闹钟能力不能直接等同于第三方能力

Apple 自带睡眠/闹钟具备更强系统集成，例如 Sleep Focus、系统 Wake Up Alarm、低电量提醒等。SmartSleep 可以借鉴这些体验，但不能在 PRD 中承诺第三方 watchOS App 一定拥有同等级的静音模式突破、勿扰突破、锁屏可靠性或系统闹钟优先级。

产品文案和工程验收都必须区分：

- Apple 系统 Sleep/Wake Up Alarm 能力；
- 第三方 iOS AlarmKit 能力；
- 第三方 watchOS runtime session + 本地 haptic/audio 能力；
- 普通 iOS Local Notification 能力。

### 2.2 Watch 端必须显式启用确认，不默认全自动后台接管

v0.1 中“用户在 iPhone 上设置闹铃，Apple Watch 在闹铃前进入监测”的表达过于乐观。v0.2 改为：用户在 iPhone 创建闹铃后，Watch 端必须完成“今晚启用/已就绪”动作；Watch 端成功预约 runtime session 后，iPhone 和 Watch 才显示 `Smart Mode Ready`。

v0.2 的工程约束：

- iPhone 可以创建、编辑、同步闹铃；
- Watch 必须负责确认佩戴、权限、电量、session 预约结果；
- Watch 未完成启用确认时，不允许 UI 暗示智能监测已就绪；
- Watch session 未成功预约时，必须自动转入 iPhone 兜底通道；
- 重复闹铃每天/每次是否需要重新启用确认，必须通过 spike 验证后决定。

### 2.3 AlarmKit 是 iPhone 兜底，不是 Watch 实时睡眠监测方案

iOS 26+ 的 AlarmKit 可以用于 App 创建固定时间闹铃，并提供更接近系统闹铃的提醒体验。v0.2 将 AlarmKit 作为 iPhone 侧优先兜底方案，但它不解决 Watch 端实时传感器采集、自动静音判断和防再睡判断。

v0.2 的降级策略：

- iOS 26+ 且用户授权 AlarmKit：使用 `iOSAlarmKit` 作为主兜底；
- AlarmKit 未授权：明确提示“智能闹铃兜底不可用/可靠性下降”，并引导授权；
- 不支持 AlarmKit 的系统版本：使用 Local Notification / 前台音频 / 用户另设系统闹钟提示作为降级；
- 任何兜底通道触发都必须写入 `AlarmChannelLog`。

### 2.4 HealthKit 心率不能作为实时强依赖

Apple Watch 在 Workout 中会连续测量心率，但日常背景心率采样间隔会随用户活动状态变化。v0.2 不假设 HealthKit 心率具有秒级实时性，也不为提升心率频率而伪造 workout session。

v0.2 的算法约束：

- `motion` 是清醒候选的主触发；
- `heartRate` 只在 `hrAgeSec <= 120` 且 `baselineHRConfidence` 足够时参与加分；
- 心率不得单独触发自动静音；
- HealthKit 未授权时，保留 motion-only Smart Mode；
- 只有 CoreMotion 不可用、Watch 未佩戴或 session 不可用时，才降级为普通兜底闹铃。

### 2.5 只做起床状态辅助判断，不做医疗或睡眠诊断

SmartSleep 不声明识别睡眠阶段，不输出医学判断，不提供诊断或治疗建议。App Store 文案、权限说明、隐私政策和 onboarding 都必须明确：采集动作、心率等数据仅用于闹铃体验和起床状态辅助判断。

健康、动作、健身数据默认本地处理。v0.2 不做广告归因，不做第三方数据出售，不做跨用户模型训练，不做云端健康画像。

---

## 3. 竞品调研

### 3.1 Apple 睡眠 / 闹钟（系统能力）

平台：watchOS / iOS。

相似点：睡眠计划、Apple Watch 睡眠追踪、震动/铃声唤醒、Sleep Focus、Wake Up Alarm、低电量提醒。

优点：原生信任度高，系统权限和提醒链路强，用户教育成本低。

缺点/机会：系统闹钟没有突出“响铃后通过 Watch 判断用户已醒并自动静音”“静音后疑似再睡自动重响”“手势贪睡”的完整闭环。

v0.2 借鉴方式：借鉴低电量提醒、就绪状态、Sleep Focus 兼容提示、Wake Up 体验，但不承诺第三方 App 具备系统闹钟全部能力。

### 3.2 AutoSleep Smart Alarm

平台：iOS + Apple Watch。

相似点：Apple Watch Smart Alarm、浅睡唤醒、时间窗口、Early Wake、腕上触觉提醒、iPhone 周计划。

优点：与 SmartSleep 的 Apple Watch alarm-first 路线最接近。其 Watch 端启用和表盘 complication 显示就绪状态值得参考。

缺点/机会：主要目标是“在浅睡时叫醒”，不是“响铃后确认是否醒来并自动静音/防再睡”。官方使用方式也提示 Watch 端启用链路存在系统约束。

v0.2 借鉴方式：参考 Watch 端“今晚已就绪”确认页、表盘 complication、唤醒窗口和渐进式 haptic，但 SmartSleep 的差异点放在响铃后的状态机。

### 3.3 Pillow

平台：iOS + Apple Watch + iPad。

相似点：动作 + 心率睡眠分析，浅睡阶段唤醒，睡眠趋势和音频记录。

优点：睡眠分析叙事完整，权限引导和数据展示成熟。

缺点/机会：功能宽，MVP 重，核心不是防再睡闭环。

v0.2 借鉴方式：只借鉴 motion + HR 的信号组合和权限解释方式；睡眠报告、录音、冥想、趋势分析全部后置。

### 3.4 SleepWatch

平台：iOS + Apple Watch。

相似点：Advanced Tracking、Smart Alarm、轻度睡眠阶段温和震动。

优点：Watch 端启动睡眠会话的路径清晰，30 分钟窗口符合用户认知。

缺点/机会：仍偏睡眠追踪/浅睡唤醒，不强调响铃后自动静音和防再睡。

v0.2 借鉴方式：参考 Watch 端启动/就绪确认，不在 v0.2 做会员功能、趋势图和完整睡眠洞察。

### 3.5 Sleep Cycle

平台：iOS / Android / Apple Watch 相关生态。

相似点：浅睡阶段智能闹钟、睡眠分数、睡眠阶段、夜间声音。

优点：大众认知强，价值表达清晰。

缺点/机会：核心仍是浅睡窗口唤醒和睡眠报告，不是起床确认闭环。

v0.2 借鉴方式：学习 onboarding 语言：少讲算法，多讲“醒来更顺、少打扰身边人、不怕睡回去”。

### 3.6 Alarmy

平台：iOS / Android。

相似点：防赖床、任务闹钟、摇晃、数学题、拍照、扫码、Prevent Falling Back Asleep。

优点：证明“防赖床/防再睡”是强需求，任务式机制有效。

缺点/机会：体验强硬，用户负担大，和 SmartSleep 的低摩擦方向不同。

v0.2 借鉴方式：任务机制只作为未来高风险用户或连续失败后的 P2 兜底，不进入 v0.2 主线。

### 3.7 Sleep as Android

平台：Android + Wear OS / 其他可穿戴。

相似点：手机/可穿戴传感器追踪、智能唤醒、CAPTCHA、心率唤醒检测。

优点：Android 生态能力纵深强。

缺点/机会：Android 后台策略、传感器、设备碎片化复杂，不适合作为 Apple MVP 的首要验证对象。

v0.2 借鉴方式：记录为 Android 后续路线参考：Wear OS + 手机任务兜底 + CAPTCHA。

### 3.8 Sleepwave / Sleepzy / Sleep Time 等

平台：iOS / Android。

相似点：手机放床边或使用麦克风/动作推断睡眠周期，轻睡眠唤醒。

优点：不依赖手表，启动门槛低。

缺点/机会：与 SmartSleep 的 Watch 腕上监测路线不同，环境干扰更大。

v0.2 借鉴方式：不进入 v0.2。未来可作为“无 Watch 降级版”探索。

---

## 4. 产品定位与用户价值

### 4.1 定位

SmartSleep Alarm 是一款 Apple Watch 起床确认型智能闹铃。

一句话：不是判断你睡得怎么样，而是确认你真的醒了。

### 4.2 核心体验

1. 用户在 iPhone 上设置闹铃。
2. Watch 提醒用户当晚/当次完成智能闹铃启用确认。
3. Watch 在闹铃前进入预监测窗口，采集动作和姿态，心率仅作辅助。
4. 到点响铃/震动；iPhone 侧设置兜底闹铃。
5. 用户仍睡着或无法确认已醒时，闹铃继续。
6. Watch 高置信度判断用户已醒时，自动静音。
7. 静音后 5 分钟监测再睡风险；高风险才重响。
8. 用户主动想贪睡时，可用高约束手势触发贪睡。

### 4.3 目标用户

优先用户：

- 佩戴 Apple Watch 睡觉的人；
- 轻度或中度赖床，需要“不要随手关掉后又睡回去”的用户；
- 与伴侣/室友同住，希望醒来后快速减少铃声打扰的用户；
- 需要早起但不想做数学题、扫码、拍照等强任务的用户。

非优先用户：

- 不戴 Apple Watch 睡觉的人；
- 只需要系统闹钟的人；
- 需要完整睡眠医学分析的人；
- 重度迟到风险且必须用强任务关闭闹钟的人。

---

## 5. MVP 产品原则

1. 可靠性优先于智能感。不能漏叫。
2. 不确定就继续响。自动静音必须保守。
3. Watch 独立执行优先。闹铃触发时不能依赖蓝牙连接。
4. iPhone 兜底必须明确。任何 Smart Mode 都必须有 backup channel。
5. 自动判断必须可解释。每次自动静音、重响、降级、失败都必须有日志。
6. 心率只作增强，不作硬依赖。
7. 再睡判断不是睡眠阶段识别，只做风险监测。
8. v0.2 不追求功能丰富，追求链路可验证。
9. 权限不足时不误导用户。UI 必须明确“智能模式不可用/可靠性下降”的具体原因。
10. 本地优先、非医疗、少采集、可删除。

---

## 6. v0.2 MVP 目标与范围

### 6.1 项目目标

v0.2 的目标是验证 Apple 生态下的智能闹铃链路可行性：用户在 iPhone 创建闹铃后，需要在 Watch 端完成当晚/当次“已就绪”；Watch 通过 runtime session 预约预监测窗口，motion-first 采集腕部动作与姿态，到点触发 Watch haptic/audio，同时 iPhone 侧通过 AlarmKit 或降级通道作为兜底。只有在高置信度清醒时才自动静音；低置信度继续响。静音后 5 分钟进行再睡风险监测，高风险才重响。所有状态转换、传感器新鲜度、闹铃通道和用户结果都写入本地日志。

### 6.2 v0.2 要验证的核心假设

H1：用户可以接受“iPhone 创建 + Watch 当晚/当次启用确认”的轻量流程，只要 UI 明确显示已就绪。
H2：Watch runtime session 能在足够多的真实场景下按时进入预监测。  
H3：motion-first 足以识别一部分高置信度醒来场景，从而安全自动静音。  
H4：自动静音误判率可以控制在内部 dogfood 可接受范围内。  
H5：静音后 5 分钟再睡风险监测能减少“关了又睡”的情况，同时不造成过多误重响。  
H6：iPhone 兜底通道能覆盖 Watch session 未启动、Watch 未佩戴、Watch 电量不足、Watch 与 iPhone 断连等失败场景。

### 6.3 v0.2 不做的事情

- 不做完整睡眠报告。
- 不做睡眠阶段识别展示。
- 不做医学、健康诊断或治疗建议。
- 不做夜间录音、打鼾检测、助眠内容。
- 不做云同步、多设备云端画像、跨用户训练。
- 不做复杂任务关闭闹钟，如扫码、拍照、数学题、步数任务。
- 不做复杂手势库。
- 不做 Android / Wear OS 版本。
- 不做机器学习个性化模型。
- 不伪造 Workout session 来获得高频心率。

---

## 7. 系统架构

### 7.1 模块拆分

#### iOS App

职责：

- 闹铃创建、编辑、删除、启用/禁用；
- 权限引导：通知、AlarmKit、HealthKit、Motion、Watch 安装检查；
- 将闹铃配置同步到 Watch；
- 创建 iPhone 侧兜底闹铃；
- 展示 Smart Mode 状态：未设置、需 Watch 启用确认、已就绪、兜底中、失败；
- 展示运行日志和用户反馈入口；
- 提供导出日志能力，供内部测试使用。

#### watchOS App

职责：

- 接收 iOS 闹铃配置；
- Watch 端“今晚启用/启用确认”确认；
- 预约 runtime session；
- 进入预监测窗口；
- 采集 CoreMotion 动作/旋转/姿态信号；
- 在授权且样本新鲜时读取 HealthKit 心率；
- 到点响铃/震动；
- 执行自动静音、手势贪睡、防再睡风险监测状态机；
- 记录本地日志，网络可用时同步给 iPhone。

#### WatchConnectivity

职责：

- iPhone -> Watch：同步闹铃配置、删除/禁用状态、铃声/震动配置、贪睡间隔；
- Watch -> iPhone：同步启用确认结果、session 结果、运行日志、最终 outcome；
- 断连场景：Watch 必须能独立响铃/震动；iPhone 必须能独立触发兜底闹铃。

### 7.2 闹铃通道定义

`watchRuntimeHapticAudio`：Watch runtime session 内的 haptic/audio。  
`iOSAlarmKit`：iOS 26+ AlarmKit 兜底。  
`iOSLocalNotification`：不支持 AlarmKit 或未授权时的降级提醒。  
`watchLocalNotification`：Watch 本地提醒，作为补充，不作为唯一可靠通道。  
`foregroundAudio`：App 前台时的音频补充。  
`manualFallbackPrompt`：提示用户另设系统闹钟，作为低系统版本/无授权时的人工兜底。

v0.2 不允许使用含糊的“普通闹铃兜底”说法，必须记录具体通道。

---

## 8. 功能需求

优先级定义：

- P0：v0.2 必须实现，否则无法验证链路。
- P0-Experiment：必须实现实验路径，但不能默认承诺稳定体验；需保守阈值、日志回放、用户反馈。
- P1：若 P0 顺利可实现；不阻塞 v0.2。
- P2：后续版本。

### FR-1 iOS 闹铃管理

优先级：P0。

需求：

- 创建闹铃：时间、重复周期、标签、是否开启 Smart Mode、贪睡间隔、兜底通道偏好。
- 编辑/删除/启用/禁用闹铃。
- 闹铃列表按下一次触发时间排序。
- 列表中展示：下一次时间、Smart Mode 状态、Watch 就绪状态、iPhone 兜底状态。
- 若 Smart Mode 开启但 Watch 未完成启用确认，显示 `需在 Watch 上启用`，不得显示 `Ready`。
- 若 AlarmKit 未授权或系统不支持，显示兜底风险提示。
- 创建闹铃后立即尝试同步到 Watch；同步失败时保留 iPhone 兜底。

验收标准：

- 用户能在 iPhone 完成闹铃 CRUD。
- UI 能准确区分 `Smart Off`、`需在 Watch 上启用`、`Ready`、`Fallback Only`、`Failed`。
- 删除/禁用闹铃时，iOS 兜底和 Watch 配置都被取消或标记无效。

### FR-2 Watch 端启用确认与就绪确认

优先级：P0。

需求：

- Watch 收到 iPhone 闹铃配置后，展示“今晚启用/启用确认”入口。
- 用户在 Watch 端确认后，App 检查：电量、佩戴状态、权限、下一次闹铃时间、session 可预约性。
- Watch 成功预约 runtime session 后，状态进入 `SESSION_SCHEDULED`。
- Watch 端显示下一次闹铃时间和 `Smart Mode Ready`。
- iPhone 收到 Watch 启用确认成功回执后，列表状态更新为 `Ready`。
- 若预约失败，进入 `SESSION_NOT_SCHEDULED`，并启用 iPhone 兜底。
- 是否允许一次确认多个闹铃、重复闹铃是否每天需重新启用确认，列入 spike，不在 v0.2 预设。

验收标准：

- Watch 启用确认成功后，iPhone 和 Watch 状态一致。
- Watch 未完成启用确认时，iPhone 不误导用户 Smart Mode 已就绪。
- Watch session 失败时，iPhone 兜底通道状态可见且日志可查。

### FR-3 Watch 端预监测

优先级：P0。

需求：

- 闹铃触发前默认 30 分钟进入 `PRE_MONITORING`。
- 预监测采集 motion 信号：加速度模长、旋转角速度、姿态变化、静止/活动窗口、腕部抬起/旋转特征。
- 预监测读取 HealthKit 心率仅作为机会性增强。
- 记录传感器新鲜度：`motionLastSampleAgeSec`、`hrLastSampleAgeSec`、`motionSampleCount`、`hrSampleCount`。
- 若 motion 流中断或 Watch 未佩戴，不执行自动静音和手势贪睡。
- 若 HealthKit 未授权或心率 stale，不影响 motion-only 智能模式。

验收标准：

- 预监测开始时间、实际开始延迟、采样数量可记录。
- motion-only 模式可独立运行。
- HealthKit 不授权时，Smart Mode 不直接降级为普通闹铃。

### FR-4 响铃/震动与 iPhone 兜底

优先级：P0。

需求：

- 到达闹铃时间时，Watch 进入 `RINGING` 并触发 haptic/audio。
- iPhone 侧兜底闹铃必须提前创建，并在约定时间触发。
- 若 Watch 已确认响铃并可与 iPhone 通信，可根据 spike 结果决定是否取消或降低 iPhone 兜底；v0.2 默认不取消兜底，先记录多通道表现。
- 用户可在 Watch 手动停止、手动贪睡。
- 用户可在 iPhone 兜底提示中停止或贪睡。
- 任一通道触发、停止、贪睡都写入 `AlarmChannelLog`。

验收标准：

- 内部测试中不得出现“所有通道都未触发”的 missed alarm。
- Watch 与 iPhone 断连时，两端各自按已配置通道执行。
- Silent Mode、Sleep Focus、低电量、锁屏等场景结果必须被记录，不得用假设替代测试。

### FR-5 自动静音

优先级：P0-Experiment。

需求：

- 自动静音只在 `RINGING` 状态有效。
- motion 出现候选清醒信号后，进入 `AWAKE_CANDIDATE`。
- 第一阶段：3 秒候选窗口，用于捕获明显动作/姿态变化，但不直接静音。
- 第二阶段：10–20 秒确认窗口，判断持续动作、姿态变化、抬腕、屏幕交互、步数增量、用户按钮/表冠操作等。
- HealthKit 心率在样本足够新鲜时加分，但不能单独触发自动静音。
- 只有达到高置信度阈值时，才自动静音。
- 低置信度时继续响铃；可进入低扰确认，但不静音。
- 自动静音后，Watch 显示短反馈，例如“已检测到你醒来，继续监测 5 分钟”。
- 用户可在 iPhone 日志中标注“误静音/我还没醒”。

验收标准：

- 自动静音每次都有 `confidence`、`reason`、`features`、`sensorFreshness` 日志。
- 单次大幅翻身不得直接静音。
- 心率单独升高不得触发静音。
- motion stale 时不得自动静音。

### FR-6 防再睡风险监测与重响

优先级：P0-Experiment。

需求：

- 自动静音后进入 `SILENCED_MONITORING`，默认持续 5 分钟。
- 静音后前 30 秒为 grace period，不触发重响。
- grace period 后计算再睡风险评分。
- 高风险条件可包含：连续 90–180 秒低 motion、无步数增量、无屏幕交互、腕部姿态稳定、未手动确认已醒、心率样本新鲜且回落接近基线。
- 不依赖 Activity/Stand Ring 作为秒级起床判断。
- 达到高风险阈值时进入 `RE_RINGING` 或回到 `RINGING`。
- 重响后重新执行自动静音判断。
- 用户可手动关闭重响，并反馈“误重响/我已经醒了”。

验收标准：

- 防再睡逻辑不使用“已睡着”文案，只使用“疑似又躺回去/再睡风险”。
- 每次重响记录 `reAlarmReason`、`riskScore`、`lowMotionDurationSec`、`stepDelta`、`interactionCount`。
- 重响最多次数可配置；v0.2 默认最多 2 次，避免无限骚扰。

### FR-7 手势贪睡

优先级：P0。

需求：

- v0.2 只实现一种高约束 Watch 手势。
- 手势仅在 `RINGING` / `RE_RINGING` 状态有效。
- 响铃开始后前 1–2 秒忽略 gesture 输入，避免 haptic/audio 启动造成误判。
- 默认手势：1.5 秒内完成两次方向一致的腕部旋转，旋转幅度和角速度均超过阈值。
- 阈值可以在内部测试中通过配置文件调整。
- 触发成功后进入 `SNOOZED`，Watch 给出短 haptic 反馈，iPhone 同步状态。
- 手势触发失败不弹错误，不打断响铃。

验收标准：

- 翻身、抓被子、挠痒、拿手机等常见夜间动作不得高频误触发。
- 每次手势检测记录 `gestureConfidence`、`rotationPeak`、`directionConsistency`、`cooldownPassed`。

### FR-8 降级与异常处理

优先级：P0。

需求：

- HealthKit 未授权：禁用心率增强，保留 motion-only Smart Mode。
- Motion/CoreMotion 不可用：禁用自动静音和手势贪睡，保留 Watch/iPhone 普通响铃。
- 通知未授权：iOS 设置页强提醒；创建闹铃时提示兜底风险。
- AlarmKit 未授权：引导授权；若用户拒绝，改用 Local Notification 并显示可靠性下降。
- Watch 未安装：Smart Mode 不可用，iPhone 兜底。
- Watch 未佩戴：Smart Mode 不可用，iPhone 兜底。
- Watch 电量低：提示用户充电；仍可启用 iPhone 兜底。
- Watch session 未启动/被系统终止：记录原因，iPhone 兜底。
- iPhone-Watch 断连：两端各自执行已预约任务，不等待对方。
- 用户 force quit App 的影响必须通过 spike 验证，不做可靠承诺。

验收标准：

- 每种异常都有明确 UI 状态和日志状态。
- 不出现“智能模式看似开启但实际没有任何可靠通道”的状态。

### FR-9 本地日志、回放与用户反馈

优先级：P0。

需求：

- 每次闹铃运行生成 `AlarmRun`。
- 记录状态转换、传感器新鲜度、通道触发、自动静音原因、重响原因、手势事件、用户操作。
- iPhone 提供内部测试日志页。
- 用户可以对结果标注：醒了、误静音、误重响、没响、没戴表、已手动关闭。
- 日志默认本地存储；内部测试可手动导出 JSON。

验收标准：

- 任一次失败都能判断是 session 问题、传感器问题、通道问题、算法问题还是用户操作。
- 自动静音和重响结果可离线回放。

### FR-10 隐私、权限与合规

优先级：P0。

需求：

- 权限文案必须说明具体用途：动作和心率只用于起床状态辅助判断。
- 不声明医疗用途。
- 不将 HealthKit / Motion 数据用于广告、营销、数据经纪、画像或无关分析。
- v0.2 默认本地处理和本地存储。
- 用户可删除本地历史数据。
- TestFlight 版本隐私文案与 App Store 文案一致。

验收标准：

- 首次启动权限说明可被非技术用户理解。
- 隐私政策不包含超出实际功能的数据用途。

---

## 9. 核心状态机

### 9.1 主路径

```text
IDLE
  -> CREATED_ON_PHONE
  -> NEEDS_WATCH_ARMING
  -> ARMED_ON_WATCH
  -> SESSION_SCHEDULED
  -> PRE_MONITORING
  -> RINGING
  -> AWAKE_CANDIDATE
  -> SILENCED_MONITORING
  -> COMPLETED
```

### 9.2 贪睡路径

```text
RINGING
  -> SNOOZED
  -> SESSION_SCHEDULED 或 RINGING
```

说明：若贪睡间隔足够长，重新预约或进入等待；若很短，可直接保留当前 runtime 上下文并等待重响。具体实现由 spike 决定。

### 9.3 防再睡路径

```text
SILENCED_MONITORING
  -> RE_SLEEP_RISK_DETECTED
  -> RE_RINGING
  -> AWAKE_CANDIDATE
  -> SILENCED_MONITORING
  -> COMPLETED
```

### 9.4 异常路径

```text
NEEDS_WATCH_ARMING -> FALLBACK_PHONE_ALARM
SESSION_SCHEDULED -> SESSION_INVALIDATED -> FALLBACK_PHONE_ALARM
PRE_MONITORING -> MOTION_STALE -> FALLBACK_PHONE_ALARM 或 RINGING_NO_SMART
PRE_MONITORING -> WATCH_NOT_WORN -> FALLBACK_PHONE_ALARM
PRE_MONITORING -> LOW_BATTERY -> FALLBACK_PHONE_ALARM
RINGING -> USER_STOPPED -> COMPLETED
RINGING -> USER_SNOOZED -> SNOOZED
SILENCED_MONITORING -> FALSE_SILENCE_REPORTED -> RINGING 或 COMPLETED_WITH_FEEDBACK
```

### 9.5 状态定义

`IDLE`：无待执行闹铃。  
`CREATED_ON_PHONE`：iPhone 已创建闹铃。  
`NEEDS_WATCH_ARMING`：需要 Watch 当晚/当次确认。  
`ARMED_ON_WATCH`：Watch 用户已确认启用。  
`SESSION_SCHEDULED`：Watch runtime session 已预约。  
`PRE_MONITORING`：闹铃前预监测，采集 motion/HR。  
`RINGING`：响铃/震动中。  
`AWAKE_CANDIDATE`：检测到清醒候选信号，但尚未确认。  
`SILENCED_MONITORING`：已静音，监测再睡风险。  
`RE_SLEEP_RISK_DETECTED`：达到再睡风险阈值。  
`RE_RINGING`：防再睡重响。  
`SNOOZED`：用户手动或手势贪睡。  
`COMPLETED`：本次闹铃结束。  
`FALLBACK_PHONE_ALARM`：Watch 智能链路不可用，使用 iPhone 兜底。  
`RINGING_NO_SMART`：可以响铃，但不能自动静音或手势识别。  

---

## 10. MVP 算法设计

### 10.1 总体策略

v0.2 不使用机器学习模型。使用可解释的启发式评分，目标是收集高质量运行数据，为 v0.3/v0.4 的个性化阈值或轻量模型做准备。

算法目标不是识别完整睡眠阶段，而是识别三个闹铃相关事件：

1. 高置信度醒来；
2. 用户主动贪睡手势；
3. 静音后高再睡风险。

### 10.2 输入信号

主信号：

- `accelMagnitudeMean`：加速度模长均值；
- `accelMagnitudeStd`：加速度模长波动；
- `gyroMagnitudeMean`：旋转角速度均值；
- `gyroPeak`：旋转峰值；
- `postureDelta`：姿态变化幅度；
- `motionContinuitySec`：持续动作时长；
- `stillnessDurationSec`：静止时长；
- `wristRaiseLikeEvent`：疑似抬腕事件；
- `stepDelta`：步数增量或 pedometer 增量；
- `screenWakeCount`：屏幕唤醒/交互次数；
- `buttonOrCrownInteraction`：按钮/表冠/屏幕操作。

辅助信号：

- `heartRate`：心率样本；
- `hrAgeSec`：心率样本年龄；
- `hrDeltaFromBaseline`：相对睡前/预监测基线变化；
- `baselineHRConfidence`：心率基线可信度；
- `watchWornConfidence`：佩戴可信度；
- `batteryLevel`：电量；
- `lowPowerMode`：低电量模式状态。

### 10.3 传感器新鲜度规则

- `motionLastSampleAgeSec <= 2`：motion 可用于实时判断。
- `motionLastSampleAgeSec > 2`：禁止自动静音和手势贪睡。
- `hrAgeSec <= 120` 且 `baselineHRConfidence >= medium`：心率可参与加分。
- `hrAgeSec > 120`：心率仅记录，不参与判断。
- `watchWornConfidence < medium`：禁止 Smart Mode，进入兜底。

阈值是 v0.2 初始建议，必须通过真实设备测试调整。

### 10.4 清醒候选规则

进入 `AWAKE_CANDIDATE` 的条件必须由 motion 触发。示例：

- 3 秒内出现连续腕部动作；
- 出现明显姿态变化；
- 出现抬腕/旋转事件；
- 出现步数增量；
- 用户触摸屏幕、按按钮或转动表冠。

禁止条件：

- 单次心率升高不得触发候选；
- 单次加速度尖峰不得直接静音；
- motion stale 时不得进入候选。

### 10.5 自动静音两阶段确认

第一阶段：候选捕获。

- 默认 3 秒。
- 目标：判断是否值得进入确认。
- 结果：进入 `AWAKE_CANDIDATE`，但不直接静音。

第二阶段：高置信度确认。

- 默认 10–20 秒。
- 目标：识别持续动作、姿态变化、交互、步数等起床迹象。
- 达到阈值：自动静音，进入 `SILENCED_MONITORING`。
- 未达到阈值：回到 `RINGING`，继续响铃。

建议评分项：

```text
awakeScore =
  motionContinuityScore
  + postureChangeScore
  + wristRaiseScore
  + interactionScore
  + stepDeltaScore
  + optionalHeartRateScore
  - singleSpikePenalty
  - staleSensorPenalty
```

自动静音条件：

```text
awakeScore >= highConfidenceThreshold
AND motionFresh == true
AND watchWornConfidence >= medium
AND notOnlyHeartRate == true
```

### 10.6 再睡风险评分

`SILENCED_MONITORING` 默认持续 5 分钟。

规则：

- 静音后 0–30 秒：grace period，不重响。
- 30 秒后：开始计算风险。
- 连续 90–180 秒低 motion，且无步数、无屏幕交互、腕部姿态稳定，则风险上升。
- 心率样本新鲜且回落接近睡眠基线，只能加分，不能单独触发。
- 达到高风险阈值才重响。

建议评分项：

```text
reSleepRiskScore =
  lowMotionDurationScore
  + postureStabilityScore
  + noInteractionScore
  + noStepDeltaScore
  + optionalHrReturnScore
  - recentManualAwakeConfirmationPenalty
  - recentMovementPenalty
```

重响条件：

```text
reSleepRiskScore >= highRiskThreshold
AND gracePeriodPassed == true
AND reAlarmCount < maxReAlarmCount
```

v0.2 默认 `maxReAlarmCount = 2`。

### 10.7 手势贪睡规则

有效状态：`RINGING`、`RE_RINGING`。

冷却：响铃开始后 1–2 秒内忽略手势。

候选：1.5 秒内两次方向一致的腕部旋转。

触发条件：

```text
gestureCooldownPassed == true
AND rotationCountWithinWindow >= 2
AND directionConsistency >= threshold
AND gyroPeak >= threshold
AND postureDelta >= threshold
AND motionFresh == true
```

触发结果：

- 当前响铃静音；
- 进入 `SNOOZED`；
- 按用户设置的贪睡间隔重响；
- 记录 `GestureEvent`。

---

## 11. 数据模型

### 11.1 Alarm

```text
Alarm(
  id,
  timeOfDay,
  repeatDays,
  timezonePolicy,
  label,
  soundId,
  isEnabled,
  smartEnabled,
  requiresWatchArming,
  snoozeIntervalMin,
  maxSnoozeCount,
  maxReAlarmCount,
  backupChannelPreferred,
  createdAt,
  updatedAt
)
```

### 11.2 AlarmRun

```text
AlarmRun(
  id,
  alarmId,
  scheduledAt,
  createdOnPhoneAt,
  watchArmedAt,
  sessionScheduledAt,
  preMonitorTargetStartAt,
  preMonitorActualStartAt,
  ringStartedAt,
  firstSilencedAt,
  completedAt,
  silenceReason,
  snoozeCount,
  reAlarmCount,
  fallbackUsed,
  outcome
)
```

### 11.3 DeviceContext

```text
DeviceContext(
  runId,
  iPhoneModel,
  watchModel,
  iOSVersion,
  watchOSVersion,
  watchBatteryAtArm,
  watchBatteryAtRing,
  phoneBatteryAtRing,
  wristSide,
  watchLocked,
  watchWornConfidence,
  silentMode,
  sleepFocus,
  lowPowerMode,
  bluetoothConnected,
  wifiConnected,
  cellularAvailable,
  airplaneMode
)
```

### 11.4 RuntimeSessionLog

```text
RuntimeSessionLog(
  runId,
  sessionType,
  scheduledAt,
  targetStartAt,
  actualStartAt,
  invalidatedAt,
  invalidationReason,
  startLatencySec,
  didStartBeforeAlarm,
  didReachRingTime,
  errorCode,
  errorMessage
)
```

### 11.5 AlarmChannelLog

```text
AlarmChannelLog(
  runId,
  channel,
  scheduledAt,
  firedAt,
  stoppedAt,
  snoozedAt,
  cancelledAt,
  authorizationState,
  failureReason,
  userVisibleState
)
```

`channel` 枚举：

```text
watchRuntimeHapticAudio
iOSAlarmKit
iOSLocalNotification
watchLocalNotification
foregroundAudio
manualFallbackPrompt
```

### 11.6 SensorFreshness

```text
SensorFreshness(
  runId,
  timestamp,
  motionSampleCount,
  motionLastSampleAgeSec,
  hrSampleCount,
  hrLastSampleAgeSec,
  baselineHRConfidence,
  baselineMotionConfidence,
  watchWornConfidence,
  sensorConfidence
)
```

### 11.7 SensorSummary

```text
SensorSummary(
  runId,
  windowStart,
  windowEnd,
  baselineHR,
  baselineMotion,
  accelMagnitudeMean,
  accelMagnitudeStd,
  gyroMagnitudeMean,
  gyroPeak,
  postureDelta,
  motionContinuitySec,
  stillnessDurationSec,
  stepDelta,
  screenWakeCount,
  interactionCount,
  missingDataDurationSec,
  batteryDelta
)
```

### 11.8 StateTransitionLog

```text
StateTransitionLog(
  runId,
  fromState,
  toState,
  timestamp,
  reason,
  confidence,
  featureSnapshotId,
  errorCode
)
```

### 11.9 GestureEvent

```text
GestureEvent(
  runId,
  timestamp,
  state,
  gestureType,
  gestureConfidence,
  rotationPeak,
  directionConsistency,
  cooldownPassed,
  accepted,
  rejectionReason
)
```

### 11.10 OutcomeLabel

```text
OutcomeLabel(
  runId,
  manualStop,
  manualSnooze,
  gestureSnooze,
  autoSilenceAccepted,
  falseSilenceReported,
  falseReAlarmReported,
  missedAlarmReported,
  fallbackUsed,
  userReportedStillAsleep,
  userReportedAwake,
  notes,
  labeledAt
)
```

---

## 12. 技术 Spike 计划

### Spike A：Watch 端启用确认与 runtime session

目标：验证 Watch 端当晚/当次启用确认是否能稳定预约并按时进入预监测。

测试项：

- 单个闹铃；
- 多个闹铃；
- 重复闹铃；
- 距离闹铃 5 分钟、30 分钟、8 小时、24 小时；
- Watch App 前台完成启用确认后退出；
- Watch 锁屏；
- Watch 重启；
- App 被用户 force quit；
- Watch 低电量；
- 蓝牙断开；
- iPhone 不在身边；
- Watch 未佩戴；
- Watch 正在充电。

退出标准：

- 明确哪些场景可支持、哪些必须降级；
- 明确是否支持多个并发/排队闹铃；
- 明确重复闹铃是否每天需要 Watch 重新确认；
- 所有失败原因可被日志捕获。

### Spike B：闹铃通道可靠性

目标：验证 Watch haptic/audio、iOS AlarmKit、iOS Local Notification 在真实模式下的表现。

测试项：

- Silent Mode；
- Sleep Focus；
- Do Not Disturb；
- 锁屏；
- 低电量；
- 飞行模式；
- 蓝牙断开；
- iPhone 不在身边；
- Watch 未佩戴；
- Watch 正在充电；
- App 后台；
- App 被终止。

退出标准：

- 得到通道可靠性矩阵；
- 明确默认兜底通道；
- 明确哪些条件下必须提示用户另设系统闹钟；
- v0.2 内部 dogfood 不出现所有通道都未响的情况。

### Spike C：motion 采样与清醒候选

目标：验证 motion-first 是否能区分高置信度醒来动作与普通翻身。

测试项：

- 仰睡、侧睡、趴睡；
- 左手佩戴、右手佩戴；
- 表带松紧；
- 翻身；
- 抬腕看表；
- 拿手机；
- 起身下床；
- 抓被子；
- 挠痒；
- 闹铃震动干扰；
- 被子压住 Watch。

退出标准：

- 确定第一版 motion 特征和阈值；
- 确定自动静音保守阈值；
- 单次翻身不触发自动静音；
- 起身/持续活动能进入高置信度候选。

### Spike D：HealthKit 心率新鲜度

目标：量化闹铃前后心率样本可用性。

测试项：

- 闹铃前 30 分钟心率样本年龄分布；
- 响铃瞬间样本年龄；
- 响铃后 5 分钟样本年龄；
- 不同 Watch 型号；
- 不同表带松紧；
- Wrist Detection 开/关；
- Sleep Focus 开/关；
- 低电量模式。

退出标准：

- 得到 `hrAgeSec` p50/p90/p95；
- 决定 `hrAgeSec` 参与评分的阈值；
- 若心率实时性不足，正式确认 motion-only 为 v0.2 默认模式；
- 不使用 workout session 伪装方案。

### Spike E：手势贪睡误触

目标：验证高约束手势是否足够低误触。

测试项：

- 两次快速旋转；
- 单次翻身；
- 抬腕；
- 拿手机；
- 抓被子；
- 挠痒；
- 震动开始后的 1–2 秒；
- 左右手；
- 表带松紧。

退出标准：

- 明确手势阈值；
- 明确冷却时间；
- false snooze 低于内部可接受阈值；
- 手势日志能解释每次接受/拒绝。

### Spike F：App Review 与隐私

目标：降低审核和隐私风险。

测试项：

- 权限文案；
- HealthKit 使用说明；
- Motion/Fitness 使用说明；
- 非医疗声明；
- 本地日志导出；
- 数据删除；
- TestFlight 描述；
- App Store 元数据。

退出标准：

- 不使用医疗诊断语言；
- 不把健康/动作数据用于广告或无关用途；
- 用户能理解为什么需要 Watch、motion、heart rate、notification、AlarmKit 权限。

---

## 13. QA 测试矩阵

### 13.1 设备与系统

- iPhone：至少覆盖一台支持 iOS 26+ 的主测设备，一台较旧设备。
- Apple Watch：至少覆盖一台新型号和一台旧型号。
- watchOS：当前稳定版；如可行，覆盖最新 beta。
- 佩戴：左手、右手、表带紧、表带松。

### 13.2 场景矩阵

| 场景 | Watch Smart | iPhone 兜底 | 自动静音 | 手势贪睡 | 必须记录 |
|---|---|---|---|---|---|
| 正常佩戴，蓝牙连接 | 是 | 是 | 是 | 是 | 全链路 |
| 蓝牙断开 | 是 | 是 | 是 | 是 | 两端独立执行 |
| Watch 未佩戴 | 否 | 是 | 否 | 否 | watchWornConfidence |
| Watch 低电量 | 视 spike | 是 | 视情况 | 视情况 | battery + fallback |
| Sleep Focus | 视通道 | 是 | 是 | 是 | channel result |
| Silent Mode | 视通道 | 是 | 是 | 是 | channel result |
| App 被终止 | 视 spike | 是 | 视 spike | 视 spike | session result |
| HealthKit 未授权 | 是 | 是 | motion-only | 是 | HR disabled |
| Motion 不可用 | 否 | 是 | 否 | 否 | motion unavailable |
| AlarmKit 未授权 | 是 | 降级 | 是 | 是 | fallback risk |

---

## 14. 工程验收标准

### 14.1 闹铃可靠性

- 内部 100 次 dogfood 闹铃中，`missedAlarm` 必须为 0。
- Watch session 未按时启动时，iPhone 兜底必须触发。
- 任一 fallback 都必须在日志中可追溯。
- 任何“没有响”的报告必须能定位到通道、权限、系统状态或用户操作。

### 14.2 自动静音

- 自动静音只在高置信度下触发。
- 内部 dogfood 目标：`falseSilenceReported < 3–5%`。
- 每次 false silence 必须能通过日志解释。
- motion stale 或 Watch 未佩戴时 false silence 必须为 0。

### 14.3 防再睡重响

- 内部 dogfood 目标：`falseReAlarmReported < 10–15%`。
- 重响最多次数默认 2 次。
- 用户可一键反馈误重响。
- 重响原因必须可解释。

### 14.4 手势贪睡

- 手势宁可略难触发，也不能频繁误触发。
- 翻身/抓被子/拿手机不应高频触发。
- 所有 gesture accept/reject 事件可回放。

### 14.5 权限与降级

- HealthKit 未授权不应关闭 motion-only Smart Mode。
- Motion 不可用必须关闭自动静音和手势贪睡。
- AlarmKit 未授权必须显示兜底风险。
- Watch 未完成启用确认不允许显示 Smart Mode Ready。

---

## 15. 版本路线

### v0.2：技术可行性 MVP

目标：完成 iOS + watchOS 链路、Watch 启用确认、runtime session、motion-first 自动静音实验、再睡风险实验、手势贪睡、iPhone 兜底、日志回放。

发布对象：内部 dogfood / 极小范围 TestFlight。

### v0.3：稳定性与阈值调优

目标：基于 v0.2 日志调优阈值；改善 Watch 启用确认体验；优化低扰提醒；完善误判反馈闭环。

可新增：更细的 complication、就寝前提醒、简单结果页。

### v0.4：个性化与用户体验

目标：引入用户级阈值、起床习惯偏好、更多兜底策略。

可新增：轻量个性化模型、任务式高风险兜底、睡眠报告摘要。

### Android 后续路线

只有在 Apple 链路验证成立后，再评估 Android：Wear OS 传感器、后台限制、手机端任务兜底、权限碎片化。

---

## 16. 风险清单与应对

### R1：Watch runtime session 无法稳定按时启动

影响：Smart Mode 不可靠。  
应对：Watch 端启用确认、session 日志、iPhone AlarmKit 兜底、用户风险提示。

### R2：第三方 Watch 音频/触觉在部分模式下不可靠

影响：Watch 端可能漏响或提醒弱。  
应对：多通道闹铃、通道矩阵测试、iPhone 兜底默认开启。

### R3：HealthKit 心率不够实时

影响：心率无法作为自动静音关键依据。  
应对：motion-first；心率只作新鲜样本加分；不使用 workout 伪装。

### R4：自动静音误判

影响：严重损害用户信任。  
应对：高置信度阈值、两阶段确认、低置信度继续响、false silence 反馈、日志回放。

### R5：防再睡误重响

影响：用户被多次打扰。  
应对：30 秒 grace period、90–180 秒持续静止条件、最多重响 2 次、误重响反馈。

### R6：手势误触发贪睡

影响：用户翻身后闹铃被贪睡，导致漏起。  
应对：两次方向一致旋转、冷却时间、阈值、gesture 日志。

### R7：App Review / 隐私风险

影响：审核失败或用户不信任。  
应对：非医疗定位、本地优先、明确权限用途、不做广告/画像/数据售卖。

---

## 17. 信息来源

- Apple Developer - WKExtendedRuntimeSession: https://developer.apple.com/documentation/watchkit/wkextendedruntimesession
- Apple Developer - Using extended runtime sessions: https://developer.apple.com/documentation/watchkit/using-extended-runtime-sessions
- Apple Developer - AlarmKit: https://developer.apple.com/documentation/AlarmKit
- Apple Developer - Scheduling an alarm with AlarmKit: https://developer.apple.com/documentation/AlarmKit/scheduling-an-alarm-with-alarmkit
- Apple Developer - Wake up to the AlarmKit API - WWDC25: https://developer.apple.com/videos/play/wwdc2025/230/
- Apple Support - Monitor your heart rate with Apple Watch: https://support.apple.com/en-us/120277
- Apple Support - Get the most accurate measurements using your Apple Watch: https://support.apple.com/en-us/105002
- Apple Support - Track your sleep with Apple Watch: https://support.apple.com/guide/watch/track-your-sleep-apd830528336/watchos
- Apple Developer - App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Apple Developer Program License Agreement - HealthKit APIs; Motion & Fitness APIs: https://developer.apple.com/support/terms/apple-developer-program-license-agreement/
- AutoSleep - Smart Alarm: https://autosleepapp.tantsissa.com/watch-use/smart-alarm
- Pillow - Sleep Tracker, Monitor & Alarm Clock: https://pillow.app/
- SleepWatch - Advanced Tracking with Smart Alarm: https://www.sleepwatchapp.com/blog/sleepwatch-feature-advanced-tracking/
- Sleep Cycle - Product Features: https://www.sleepcycle.com/features/
- Alarmy - Not Just an Alarm Clock, Your Morning Upgrade: https://alar.my/en
- Sleep as Android - Sleep phase tracking & smart alarm: https://sleep.urbandroid.org/

---

## 18. 附录：v0.1 -> v0.2 主要改动对照

| v0.1 表述/问题 | v0.2 修订 |
|---|---|
| iPhone 设置后 Watch 自动进入监测 | iPhone 创建 + Watch 当晚/当次启用确认 + session 预约成功后才 Ready |
| 普通闹铃兜底 | 拆分为 iOSAlarmKit、iOSLocalNotification、watchLocalNotification、foregroundAudio、manualFallbackPrompt |
| HealthKit 未授权则普通闹铃 | HealthKit 未授权只禁用心率增强，保留 motion-only Smart Mode |
| 心率参与清醒判断 | 心率只作机会性增强，样本 stale 时不参与，不能单独触发 |
| 3 秒确认窗口后自动静音 | 3 秒候选 + 10–20 秒确认，两阶段高置信度静音 |
| 防再睡用“动作消失 + 心率回落 + 未站立/走动” | 改为再睡风险评分，不依赖 Activity/Stand Ring，不做睡眠阶段判断 |
| 快速翻转/快速旋转手势 | 改为 1.5 秒内两次方向一致旋转 + 冷却 + 阈值 |
| 状态机较粗 | 增加 NEEDS_WATCH_ARMING、SESSION_SCHEDULED、AWAKE_CANDIDATE、异常状态等 |
| 数据模型偏少 | 增加 DeviceContext、RuntimeSessionLog、AlarmChannelLog、SensorFreshness、GestureEvent、OutcomeLabel |
| 自动静音/重响写成稳定 P0 | 改为 P0-Experiment，必须配日志、反馈和保守阈值 |
| Break Through Silent Mode 可借鉴但易误读 | 明确不能把 Apple 系统闹钟能力写成第三方 Watch App 保证 |
