# ADR-0002: Watch 启用确认必需

## 状态

已接受，进入 MVP 实现范围。

## 决策

iPhone 创建闹铃并不足以让 Smart Mode 显示 Ready。Watch 必须先收到配置、通过就绪检查，并成功预约 runtime session，iPhone 和 Watch 才能显示 Ready。

## 影响

如果 Watch 尚未完成启用确认，UI 必须显示“需在 Watch 上启用”。如果 runtime session 预约失败，系统必须显示 Fallback Only，并保持 iPhone 兜底通道可见。
