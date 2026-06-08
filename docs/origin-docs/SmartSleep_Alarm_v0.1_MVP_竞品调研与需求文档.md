# SmartSleep Alarm v0.1 MVP 竞品调研与开发需求文档

版本：v0.1  
日期：2026-06-06  
范围：iOS + watchOS MVP

调研说明：联网检索日期为 2026-06-06。竞品信息以官方页面、Apple Support、Apple Developer 文档为主。

## 1. 结论摘要
- 市场上最接近的竞品是 AutoSleep、Pillow、SleepWatch、Sleep Cycle；它们主要解决“在浅睡窗口唤醒”，而不是“响铃后通过 Apple Watch 判断用户已醒并自动静音”。
- Alarmy 与 Sleep as Android 证明“防赖床/防再睡”是强需求，但主流解法是数学题、拍照、扫码、摇晃等强制任务，体验较重。SmartSleep 的机会在于用 Watch 做更自然、更低摩擦的闭环。
- SmartSleep 的差异化应定义为：睡着时持续响；检测到清醒后自动静音；静音后 5 分钟继续确认，疑似再睡自动重响；用户主动想赖床时可用手势贪睡。
- 最大技术风险不是单个算法阈值，而是 watchOS 后台生命周期、Smart Alarm 模式限制、HealthKit 心率实时性、音频/触觉在锁屏/静音/勿扰下的可靠性。v0.1 必须先做技术 spike。
- MVP 不建议做完整睡眠报告、语音播报、多模式、复杂手势库。全部资源应投入“闹铃链路可靠性 + 自动静音准确性 + 防再睡闭环”。

## 2. 竞品调研
### Apple 睡眠 / 闹钟（系统能力）
- 平台：watchOS / iOS
- 相似点：睡眠计划、Apple Watch 睡眠追踪、震动/铃声唤醒、睡眠阶段记录。
- 优点：原生信任度高；权限、低电量提示、Sleep Focus、闹钟可靠性强；用户教育成本低。
- 缺点/机会：未突出基于浅睡窗口的第三方 Smart Alarm；没有“醒了自动静音、再睡自动重响、手势贪睡”的闭环。
- 可借鉴：借鉴“低电量提醒、Sleep Focus 兼容、Break Through Silent Mode/响铃可靠性提示”。SmartSleep 不要挑战系统闹钟可靠性，应保留普通闹铃降级。

### AutoSleep Smart Alarm
- 平台：iOS + Apple Watch
- 相似点：Apple Watch 原生 Smart Alarm；浅睡唤醒；时间窗口；Early Wake；腕上触觉提醒；支持 iPhone 端周计划。
- 优点：与 SmartSleep 技术路线最接近；Watch 端可独立运行；提供 1–28 分钟唤醒窗口和逐分钟 arousal 触觉策略。
- 缺点/机会：主要目标是“在浅睡时叫醒”，不是“响铃后自动判断已醒并静音”；官方说明仍要求每天在 Watch 上启用一次，暴露系统限制。
- 可借鉴：重点参考 Watch 端 alarm-first 设计、时间窗口配置、arousal 触觉、Watch 表盘 complication 显示“已就绪”。同时把“每日启用/系统限制”作为 v0.1 必测风险。

### Pillow
- 平台：iOS + Apple Watch + iPad
- 相似点：通过动作和心率分析睡眠；在最浅睡眠阶段唤醒；睡眠趋势、音频记录、冥想/助眠。
- 优点：功能完整，睡眠分析叙事强；运动+心率路线可参考；数据展示和洞察成熟。
- 缺点/机会：功能面宽，MVP 复杂；核心不是防再睡闭环；音频/趋势会分散 SmartSleep 早期验证。
- 可借鉴：v0.1 只借鉴“动作+心率”信号组合；趋势、录音、冥想、睡眠报告全部后置。

### SleepWatch
- 平台：iOS + Apple Watch
- 相似点：Apple Watch Advanced Tracking + Smart Alarm；30 分钟唤醒窗口；轻度睡眠时用温和震动唤醒。
- 优点：设置路径清晰，Watch 端启动睡眠会话；30 分钟窗口符合用户认知。
- 缺点/机会：需要用户睡前主动从 Watch 端启动 Advanced Tracking；Smart Alarm 属于会员功能；不强调醒后自动静音与防再睡。
- 可借鉴：v0.1 应提供“今晚已就绪”的 Watch 端确认页；首次版本可以接受睡前/当天 Watch 端确认，以换取链路可靠性。

### Sleep Cycle
- 平台：iOS / Android / Apple Watch 相关生态
- 相似点：浅睡阶段智能闹钟、睡眠分数、睡眠阶段、夜间声音、助眠内容。
- 优点：大众认知最强，定位清晰：“轻松醒来”；声音和睡眠洞察内容丰富。
- 缺点/机会：核心仍是浅睡窗口唤醒，不是响铃后自动静音；睡眠分析/内容生态不适合 v0.1 聚焦。
- 可借鉴：可学习一句话价值表达和 onboarding：不要先讲算法，先讲“醒来更顺、少打扰他人”。

### Alarmy
- 平台：iOS / Android
- 相似点：防赖床、任务闹钟、Prevent Falling Back Asleep、摇晃/数学题/拍照等任务关闭闹钟。
- 优点：重度赖床用户需求验证充分；任务机制有效防止用户随手关闭。
- 缺点/机会：体验强硬、打扰大；更多依赖手机操作，不是 Watch 无感体验；与“醒了自动静音”方向相反。
- 可借鉴：可作为 SmartSleep 的兜底策略：连续重响或高风险用户可选“必须站起/扫码/步数确认”。不要在 v0.1 做成主线。

### Sleep as Android
- 平台：Android + Wear OS / 其他可穿戴
- 相似点：手机或可穿戴传感器追踪睡眠；智能唤醒；CAPTCHA 任务；可穿戴心率唤醒检测。
- 优点：Android 生态功能纵深强；覆盖可穿戴、任务、灯光、健康服务集成。
- 缺点/机会：Android 生态碎片化，传感器/后台策略复杂；不是 Apple MVP 的优先验证对象。
- 可借鉴：为后续 Android 版本提供路线：Wear OS + 手机任务兜底 + CAPTCHA 可作为防再睡增强。

### Sleepwave / Sleepzy / Sleep Time 等
- 平台：iOS / Android
- 相似点：通过手机放床边或麦克风/动作推断睡眠周期，轻睡眠唤醒。
- 优点：不强依赖手表；上手门槛低。
- 缺点/机会：与 SmartSleep 的 Watch 实时腕上监测不同；手机床边方案更易受环境干扰。
- 可借鉴：后续可做“无 Watch 降级版”，但 v0.1 不建议纳入，以免稀释 Apple Watch MVP。

## 3. 深度分析：SmartSleep 的机会点
SmartSleep 不应定位为又一个“睡眠分析 App”，而应定位为“起床确认型智能闹钟”。差异化不是睡眠报告，而是响铃后的状态机：响铃、识别清醒、自动静音、继续监测、防止再睡、手势贪睡。

### 3.1 MVP 产品原则
- 不确定就继续响，不能为了“智能”牺牲防漏叫。
- 默认只需设置闹钟；高级配置后置。
- 闹铃触发时必须尽可能由 Watch 独立完成，不能依赖当时蓝牙连接。
- 每次自动静音/重响/降级都要有本地日志，方便早期实测。
- 只做起床状态辅助判断，不做医疗级睡眠诊断。

## 4. v0.1 MVP 产品需求文档
### 4.1 项目目标
v0.1 的目标是验证 Apple 生态内的完整闭环：用户在 iPhone 上设置闹铃，Apple Watch 在闹铃前进入监测，闹铃响起后根据动作/心率判断清醒并自动静音，静音后继续监测 5 分钟，用户疑似再睡则重响；响铃期间支持一个可靠的手势贪睡。

不在 v0.1 范围：睡眠/小憩模式区分、语音播报、天气新闻、完整睡眠报告、分享卡片、多手势库、多品牌手表、云同步、机器学习个性化模型。

### 4.2 功能需求
#### FR-1 iOS 闹铃管理
- 创建闹铃：时间、重复周期（按周）、标签、铃声、是否开启智能模式、贪睡间隔。P0。
- 编辑/删除/启用/禁用闹铃。P0。
- 闹铃列表：按下一次触发时间排序，展示重复标签、智能模式状态、Watch 就绪状态。P0。
- 权限引导：通知、HealthKit、Motion/传感器说明、Watch 安装状态检查。P0。

#### FR-2 Watch 端预监测与就绪
- 闹铃触发前 30 分钟进入预监测窗口。P0。
- Watch 端启动 WKExtendedRuntimeSession（Smart Alarm background mode）并记录启动结果。P0。
- 采集 CoreMotion 动作/旋转数据；在权限允许时读取心率相关数据。P0。
- 若 Watch 未佩戴、电量过低、权限缺失、session 启动失败或数据长时间缺失，进入普通闹铃兜底。P0。

#### FR-3 响铃与自动静音
- 到达闹铃时间后响铃/震动，并进入 RINGING 状态。P0。
- 检测到候选清醒信号后进入 3 秒确认窗口。P0。
- 确认窗口内若动作/旋转/心率变化综合得分持续达标，判定清醒，自动静音。P0。
- 若信号不确定，继续响铃，不自动静音。P0。

#### FR-4 防再睡监测与重响
- 自动静音后进入 5 分钟防再睡监测。P0。
- 若连续一段时间出现“动作消失 + 心率回落/稳定接近睡眠基线 + 未发生站立/走动”等信号，判定疑似再睡并重响。P0。
- 重响后重新执行自动静音判断；记录 reAlarmCount，并允许用户手动关闭。P0。

#### FR-5 手势贪睡
- v0.1 只实现一种手势：佩戴 Watch 的手腕快速翻转/快速旋转。P0。
- 手势仅在 RINGING 状态有效；检测成功后立即静音，并进入 SNOOZED 状态。P0。
- 贪睡倒计时按闹铃设置执行，默认 5 分钟，范围 1–30 分钟。P0/P1。
- 触发后 Watch 给出短震动或小图标反馈。P1。

#### FR-6 降级与异常处理
- HealthKit 未授权：普通闹铃 + 解释提示；不阻塞闹铃响铃。
- 通知未授权：设置页强提醒，闹铃创建时给出风险提示。
- Watch 未安装/未连接：iPhone 普通闹铃兜底。
- 传感器数据 stale：继续响铃，不自动静音；若 CoreMotion 仍可用，手势贪睡可继续有效。

### 4.3 核心状态机
IDLE -> SCHEDULED -> PRE_MONITORING -> RINGING -> AWAKE_CONFIRMING -> SILENCED_MONITORING -> COMPLETED。手势路径为 RINGING -> SNOOZED -> RINGING。异常路径为 FALLBACK_ALARM。

### 4.4 MVP 算法建议
- v0.1 不建议上机器学习模型。使用可解释的启发式评分，重点是采集高质量日志，为 v0.2 个性化阈值做准备。
- 输入信号：加速度模长、旋转角速度、姿态变化、心率/心率变化、传感器时间戳、Watch 佩戴状态、用户手动操作。
- 清醒候选：出现明显手腕/身体动作、连续姿态变化、腕部抬起/翻转、心率相对睡眠基线升高。
- 确认窗口：默认 3 秒；至少满足“动作持续”或“动作 + 心率变化”组合条件。单次心率跳变不能单独触发静音。
- 置信度低时不做自动静音；优先保持响铃。

### 4.5 数据模型
- `Alarm(id, time, repeatDays, label, soundId, isEnabled, smartEnabled, snoozeInterval, createdAt, updatedAt)`
- `AlarmRun(id, alarmId, scheduledAt, preMonitorStartedAt, ringStartedAt, silenceReason, snoozeCount, reAlarmCount, outcome)`
- `SensorSummary(runId, baselineHR, baselineMotion, sensorConfidence, missingDataDuration, batteryDelta)`
- `StateTransitionLog(runId, fromState, toState, timestamp, reason, confidence)`

## 5. 技术验证计划
1. 验证 WKExtendedRuntimeSession Smart Alarm 模式能否在闹铃前稳定启动、屏幕关闭后是否继续采集。
2. 验证 Watch 独立响铃/震动在静音模式、Sleep Focus、低电量、锁屏、蓝牙断开、飞行模式下的表现。
3. 验证 HealthKit 心率实时性；若不足，v0.1 改为 motion-first。
4. 验证 CoreMotion 手势识别在不同睡姿、左右手、表带松紧、夜间翻身、响铃震动干扰下的表现。
5. 验证 iPhone-Watch 同步与断连独立执行。
6. 验证 App Review 风险：背景模式、健康数据说明、非医疗声明、隐私文案。

## 6. 信息来源
- Apple Support - Track your sleep with Apple Watch: https://support.apple.com/guide/watch/track-your-sleep-apd830528336/watchos
- Apple Developer - WKExtendedRuntimeSession: https://developer.apple.com/documentation/watchkit/wkextendedruntimesession
- Apple Developer - Using extended runtime sessions: https://developer.apple.com/documentation/watchkit/using-extended-runtime-sessions
- Apple Developer - WatchConnectivity: https://developer.apple.com/documentation/watchconnectivity
- Apple Developer - CoreMotion CMMotionManager: https://developer.apple.com/documentation/coremotion/cmmotionmanager
- Apple Developer - HealthKit heartRate: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartrate
- AutoSleep - Smart Alarm: https://autosleepapp.tantsissa.com/watch-use/smart-alarm
- Pillow - Sleep Tracker, Monitor & Alarm Clock: https://pillow.app/
- SleepWatch - Advanced Tracking with Smart Alarm: https://www.sleepwatchapp.com/blog/sleepwatch-feature-advanced-tracking/
- Sleep Cycle - Product Features: https://sleepcycle.com/
- Alarmy - Not Just an Alarm Clock, Your Morning Upgrade: https://alar.my/en
- Sleep as Android - Sleep phase tracking & smart alarm: https://sleep.urbandroid.org/